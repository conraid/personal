#!/usr/bin/env python3

# Sort the sections of the all.ini file alphabetically,
# with __config__ as the first entry,
# by first making a backup of all.ini and then overwriting it.
#
# python-tomlikit package is needed

import shutil
import tomlkit
import re

file_name = 'all.ini'
backup_name = f'{file_name}.bak'

# Backup
shutil.copy(file_name, backup_name)
print(f"Backup created: {backup_name}")

# Load file all.ini
with open(file_name, 'r', encoding='utf-8') as file:
    doc = tomlkit.parse(file.read())

# Sort sections
sorted_keys = sorted(doc.keys())
if "__config__" in sorted_keys:
    sorted_keys.remove("__config__")
    sorted_keys.insert(0, "__config__")

sorted_doc = tomlkit.document()
for key in sorted_keys:
    sorted_doc[key] = doc[key]

# Convert the document into a string
content = tomlkit.dumps(sorted_doc)

# Use a regex to replace 3 or more consecutive newlines with only 2.
# This ensures a maximum of ONE empty line between sections.
clean_content = re.sub(r'\n{3,}', '\n\n', content)

# Write the cleaned file
with open(file_name, 'w', encoding='utf-8') as file:
    file.write(clean_content)
# --------------------

print(f"Sorted and cleaned file: {file_name}")
