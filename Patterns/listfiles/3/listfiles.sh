#!/bin/bash

# Output file
OUTPUT="listfiles.txt"

# Create or clear the output file
echo "=== Python Files in main/ ===" > $OUTPUT
echo "Date: $(date)" >> $OUTPUT
echo "=========================" >> $OUTPUT

# List each .py file and its contents
for file in *.py; do
    if [[ -f "$file" && "$file" != *"__pycache__"* ]]; then
        echo -e "\n\n=== $file ===" >> $OUTPUT
        echo "Lines: $(wc -l < "$file")" >> $OUTPUT
        echo "=========================" >> $OUTPUT
        cat "$file" >> $OUTPUT
        echo -e "\n\n" >> $OUTPUT
    fi
done 