#!/usr/bin/env python3

# Sort the sections of the all.ini file alphabetically,
# with __config__ as the first entry,
# by first making a backup of all.ini and then overwriting it.
#
# python-toml package is needed

import toml
import shutil

file_name = 'all.ini'
backup_name = f'{file_name}.bak'

shutil.copy(file_name, backup_name)
print(f"Backup created:: {backup_name}")

with open(file_name, 'r') as file:
    data = toml.load(file)

sorted_sections = sorted(data)
if "__config__" in sorted_sections:
    sorted_sections.remove("__config__")
    sorted_sections.insert(0, "__config__")

sorted_data = {key: data[key] for key in sorted_sections}

with open(file_name, 'w') as file:
    toml.dump(sorted_data, file)

print(f"Sorted and overwritten file: {file_name}")

