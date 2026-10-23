#!/bin/bash

# Script per installare e rimuovere i kernel, e getire i link simbolici per i kernel.
# Naturalmente in Slackware

set -euo pipefail

### CONFIGURAZIONE

# Sono le mie directory al momento

MIRROR="/mnt/hd/mirror/slackware/slackware64-current/slackware64"
TESTING_BASE="/mnt/hd/mirror/slackware/slackware64-current/testing"

# Diretory dei pacchetti in Slackware
PKGDB="/var/lib/pkgtools/packages"

# Comandi in Slackware
REMOVEBIN="/sbin/removepkg"
GRBBIN="/usr/sbin/grub-mkconfig"
GENINITRD="/usr/sbin/geninitrd"

# Specificare qui directory di testing particolari, se necessario.
# Esempio: TESTING_KERNEL_DIRS=("linux-6.18.x")
TESTING_KERNEL_DIRS=()

DRY_RUN=false
ACTION=""

PROTECTED_VERSIONS=()
KERNEL_CHANGED=false

usage() {
  cat << EOF
Uso:
  ${0##*/} install [opzioni]
  ${0##*/} remove [versione] [opzioni]
  ${0##*/} update-boot [opzioni]

Azioni:
  install              Installa i kernel nuovi presenti nel mirror (main e testing)
  remove               Rimuove i kernel non protetti
                       (quello in uso, l'ultimo e penultimo solitamente,
                       a meno di varie versioni in testing)
  remove VERSIONE      Rimuove la versione indicata, se non protetta
  update-boot          Aggiorna i link simbolici e la configurazione GRUB

Opzioni:
  -n, --dry-run        Mostra cosa verrebbe fatto senza modificare il sistema
  -h, --help           Mostra questo messaggio

Esempi:
  ${0##*/} install
  ${0##*/} install --dry-run
  ${0##*/} remove
  ${0##*/} remove 7.2.7
  ${0##*/} remove 7.2.7 --dry-run
  ${0##*/} update-boot
  ${0##*/} update-boot --dry-run
EOF
}

### PARSING ARGOMENTI

while [[ $# -gt 0 ]]; do
  case "$1" in
    install | remove | update-boot)
      if [[ -n $ACTION ]]; then
        echo "Errore: specificare una sola azione." >&2
        exit 1
      fi
      ACTION="$1"
      ;;
    -n | --dry-run)
      DRY_RUN=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Opzione sconosciuta: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ $ACTION == "remove" && -z ${REMOVE_VERSION:-} ]]; then
        REMOVE_VERSION="$1"
      else
        echo "Argomento inatteso: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z $ACTION ]]; then
  usage
  exit 1
fi

### CONTROLLO ROOT

if [[ $EUID -ne 0 ]]; then
  echo "Questo script deve essere eseguito come root." >&2
  exit 1
fi

#### FUNZIONI PRINCIPALI CON DEBUG/DRYRUN

run_installpkg() {
  local file="$1"

  if $DRY_RUN; then
    echo "(dry-run) installpkg -- $file"
  else
    installpkg "$file"
  fi
}

run_upgradepkg() {
  local file="$1"

  if $DRY_RUN; then
    echo "(dry-run) upgradepkg --install-new -- $file"
  else
    upgradepkg --install-new "$file"
  fi
}

run_removepkg() {
  local pkg="$1"

  if $DRY_RUN; then
    echo "(dry-run) $REMOVEBIN -- $pkg"
  else
    "$REMOVEBIN" "$pkg"
  fi
}

### PREPARAZIONE MIRROR

check_mirror() {
  if [[ ! -d $MIRROR ]]; then
    mount /mnt/hd || true
    sleep 2

    if [[ ! -d $MIRROR ]]; then
      echo "Errore: mirror non raggiungibile in $MIRROR" >&2
      exit 1
    fi
  fi
}

### VERSIONI INSTALLATE

get_installed_versions() {
  local versions=()
  local pkg
  local version

  while IFS= read -r pkg; do
    [[ -n $pkg ]] || continue

    version=$(basename "$pkg" | cut -d- -f3)
    versions+=("$version")
  done < <(
    find "$PKGDB" -maxdepth 1 -type f \
      -name 'kernel-generic-*-x86_64-*' \
      -printf '%f\n'
  )

  if [[ ${#versions[@]} -gt 0 ]]; then
    printf '%s\n' "${versions[@]}" | sort -uV
  fi
}

### RACCOLTA KERNEL PROTETTI

collect_protected_versions() {
  PROTECTED_VERSIONS=()

  local installed_versions=()
  local count
  local v
  local f

  mapfile -t installed_versions < <(get_installed_versions)

  # Ultimo e penultimo kernel installato
  count=${#installed_versions[@]}

  if [[ $count -ge 1 ]]; then
    PROTECTED_VERSIONS+=("${installed_versions[$((count - 1))]}")
  fi

  if [[ $count -ge 2 ]]; then
    PROTECTED_VERSIONS+=("${installed_versions[$((count - 2))]}")
  fi

  # Kernel presenti nel mirror ufficiale
  for f in "$MIRROR/a"/kernel-generic-*-x86_64-*.txz; do
    [[ -e $f ]] || continue

    v=$(basename "$f" | cut -d- -f3)
    PROTECTED_VERSIONS+=("$v")
  done

  # Kernel presenti in testing
  if [[ -d $TESTING_BASE ]]; then
    while IFS= read -r f; do
      v=$(basename "$f" | cut -d- -f3)
      PROTECTED_VERSIONS+=("$v")
    done < <(
      find "$TESTING_BASE" \
        -maxdepth 2 \
        -type f \
        -name 'kernel-generic-*-x86_64-*.txz'
    )
  fi

  # Kernel attualmente in uso
  PROTECTED_VERSIONS+=("$(uname -r)")

  if [[ ${#PROTECTED_VERSIONS[@]} -gt 0 ]]; then
    mapfile -t PROTECTED_VERSIONS < <(
      printf '%s\n' "${PROTECTED_VERSIONS[@]}" | sort -uV
    )
  fi

  echo "Versioni protette:"
  printf ' - %s\n' "${PROTECTED_VERSIONS[@]}"
  echo "-------------------------------------------------------"
}

is_protected() {
  local version="$1"
  local p

  for p in "${PROTECTED_VERSIONS[@]}"; do
    [[ $version == "$p" ]] && return 0
  done

  return 1
}

### AGGIORNAMENTO LINK in /boot

update_boot_links() {
  echo "Aggiornamento link simbolici in /boot..."

  local latest_kernel
  local latest_entry
  local target
  local kv
  local initrd

  # Raccoglie i kernel reali nei due formati supportati.
  # Ordina per versione numerica, non per nome del file.
  latest_entry=$(
    find /boot -maxdepth 1 -type f \
      \( -name 'vmlinuz-[0-9]*' -o -name 'vmlinuz-generic-[0-9]*' \) \
      -printf '%f\n' \
      | while IFS= read -r f; do
        case "$f" in
          vmlinuz-generic-*)
            version=${f#vmlinuz-generic-}
            ;;
          vmlinuz-*)
            version=${f#vmlinuz-}
            ;;
        esac

        printf '%s\t%s\n' "$version" "$f"
      done \
      | sort -t $'\t' -k1,1V \
      | tail -n 1
  )

  if [[ -z $latest_entry ]]; then
    echo "Attenzione: nessun kernel reale trovato in /boot."
    return 0
  fi

  latest_kernel=${latest_entry#*$'\t'}
  target=$latest_kernel

  case "$target" in
    vmlinuz-generic-*)
      kv=${target#vmlinuz-generic-}
      ;;
    vmlinuz-*)
      kv=${target#vmlinuz-}
      ;;
  esac

  echo "Kernel più recente: $target"

  if $DRY_RUN; then
    echo "(dry-run) cd /boot && ln -sfn -- $target vmlinuz"
    echo "(dry-run) cd /boot && ln -sfn -- $target vmlinuz-generic"
  else
    (
      cd /boot
      ln -sfn -- "$target" vmlinuz
      ln -sfn -- "$target" vmlinuz-generic
    )
  fi

  # Aggiorna il link initrd se il file corrispondente esiste.
  initrd="/boot/initrd-$kv.img"

  if [[ -f $initrd ]]; then
    if $DRY_RUN; then
      echo "(dry-run) cd /boot && ln -sfn -- initrd-$kv.img initrd-generic.img"
    else
      (
        cd /boot
        ln -sfn -- "initrd-$kv.img" initrd-generic.img
      )
    fi
  fi
}

### AGGIORNAMENTO /boot DOPO MODIFICHE AI KERNEL

update_boot_files() {
  if ! $KERNEL_CHANGED; then
    echo "Nessuna modifica ai kernel: /boot non necessita aggiornamenti."
    return 0
  fi

  echo "-------------------------------------------------------"
  echo "Aggiornamento initrd..."

  if $DRY_RUN; then
    echo "(dry-run) $GENINITRD"
  else
    "$GENINITRD"
  fi

  update_boot_links

  echo "-------------------------------------------------------"
  echo "Aggiornamento configurazione GRUB..."

  if $DRY_RUN; then
    echo "(dry-run) $GRBBIN -o /boot/grub/grub.cfg"
  else
    "$GRBBIN" -o /boot/grub/grub.cfg
  fi

  echo "GRUB aggiornato."
}

### AGGIORNAMENTO /boot MANUALE

update_boot_only() {
  echo "======================================================="
  echo " AGGIORNAMENTO LINK BOOT E GRUB"
  echo "======================================================="

  update_boot_links

  echo "-------------------------------------------------------"
  echo "Aggiornamento configurazione GRUB..."

  if $DRY_RUN; then
    echo "(dry-run) $GRBBIN -o /boot/grub/grub.cfg"
  else
    "$GRBBIN" -o /boot/grub/grub.cfg
  fi

  echo "GRUB aggiornato."
}

### INSTALLAZIONE KERNEL

install_kernel_generic() {
  local file="$1"
  local basefile

  basefile=$(basename "$file" .txz)

  if [[ -f "$PKGDB/$basefile" ]]; then
    echo "Kernel generic $basefile già installato, salto."
    return 0
  fi

  echo "Installo nuovo kernel generic: $basefile"

  run_installpkg "$file"

  KERNEL_CHANGED=true
}

process_install() {
  local search_paths=()
  local subdir
  local f
  local kernel
  local k

  # Mirror ufficiale
  search_paths+=("$MIRROR/a")

  # Testing
  if [[ -d "$TESTING_BASE/packages" ]]; then
    while IFS= read -r subdir; do
      search_paths+=("$subdir")
    done < <(
      find "$TESTING_BASE/packages" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d
    )
  fi

  # Directory testing specificate manualmente
  for k in "${TESTING_KERNEL_DIRS[@]}"; do
    search_paths+=("$TESTING_BASE/packages/$k")
  done

  # Rimuovi duplicati
  mapfile -t search_paths < <(
    printf '%s\n' "${search_paths[@]}" | sort -u
  )

  echo "Ricerca kernel nei repository..."

  for f in "${search_paths[@]}"; do
    [[ -d $f ]] || continue

    while IFS= read -r kernel; do
      install_kernel_generic "$kernel"
    done < <(
      find "$f" \
        -maxdepth 1 \
        -type f \
        -name 'kernel-generic-*-x86_64-*.txz' \
        | sort -V
    )
  done
}

### RIMOZIONE KERNEL

remove_kernel_version() {
  local pkg="$1"
  local kv
  local arch
  local rev
  local full_pkg
  local initrd

  kv=$(echo "$pkg" | cut -d- -f3)
  arch=$(echo "$pkg" | cut -d- -f4)
  rev=$(echo "$pkg" | cut -d- -f5)

  if [[ -n ${REMOVE_VERSION:-} && $kv != "$REMOVE_VERSION" ]]; then
    return 0
  fi

  if is_protected "$kv"; then
    echo "Tenendo: $pkg (versione protetta)"
    return 0
  fi

  echo "-------------------------------------------------------"
  echo "PROCESSO RIMOZIONE: versione $kv"

  # Generic
  full_pkg="kernel-generic-${kv}-${arch}-${rev}"

  if [[ -f "$PKGDB/$full_pkg" ]]; then
    run_removepkg "$full_pkg"
  fi

  # Modules
  full_pkg="kernel-modules-${kv}-${arch}-${rev}"

  if [[ -f "$PKGDB/$full_pkg" ]]; then
    run_removepkg "$full_pkg"
  fi

  # Initrd residui
  for initrd in \
    "/boot/initrd-$kv.img" \
    "/boot/initrd-$kv-generic.img"; do
    if [[ -f $initrd || -L $initrd ]]; then
      echo "Cancellazione initrd: $initrd"

      if $DRY_RUN; then
        echo "(dry-run) rm -f -- $initrd"
      else
        rm -f -- "$initrd"
      fi
    fi
  done

  KERNEL_CHANGED=true
}

process_remove() {
  local pkg

  collect_protected_versions

  cd -- "$PKGDB"

  for pkg in kernel-generic-*-x86_64-*; do
    [[ -e $pkg ]] || continue

    remove_kernel_version "$pkg"
  done

  if [[ -n ${REMOVE_VERSION:-} && ! $KERNEL_CHANGED ]]; then
    echo "Nessuna rimozione effettuata per la versione $REMOVE_VERSION."
  fi
}

### SBBDEP

run_sbbdep() {
  if ! $KERNEL_CHANGED; then
    return 0
  fi

  if command -v sbbdep > /dev/null 2>&1; then
    echo "Aggiornamento sbbdep..."

    if $DRY_RUN; then
      echo "(dry-run) sbbdep"
    else
      sbbdep
    fi
  fi
}

### MAIN

case "$ACTION" in
  install)
    check_mirror

    echo "======================================================="
    echo " INSTALLAZIONE KERNEL"
    echo "======================================================="

    process_install
    ;;

  remove)
    check_mirror

    echo "======================================================="
    echo " RIMOZIONE KERNEL"
    echo "======================================================="

    process_remove
    ;;

  update-boot)
    update_boot_only
    ;;
esac

if [[ $ACTION != "update-boot" ]]; then
  if $KERNEL_CHANGED; then
    update_boot_files
    run_sbbdep
  else
    echo "-------------------------------------------------------"
    echo "Nessuna modifica ai kernel effettuata."
  fi
fi

echo "======================================================="
echo "Operazione completata."
echo "======================================================="
