#!/bin/bash

# listfiles.sh (V3) — generate a consolidated listing of code and text files
# Output file lives next to this script.

OUTPUT="listfiles.txt"

# Create or clear the output file
{
  echo "=== Core Code and Text Files ==="
  echo "Date: $(date)"
  echo "========================="
} > "$OUTPUT"

# Function to append a file with a header and line count
add_file() {
  local file="$1"
  echo -e "\n\n=== $file ===" >> "$OUTPUT"
  if [[ -f "$file" ]]; then
    echo "Lines: $(wc -l < "$file")" >> "$OUTPUT"
  else
    echo "Lines: 0 (missing)" >> "$OUTPUT"
  fi
  echo "=========================" >> "$OUTPUT"
  [[ -f "$file" ]] && cat "$file" >> "$OUTPUT"
  echo -e "\n\n" >> "$OUTPUT"
}

# Core code file extensions (same set as V2)
CODE_EXTENSIONS=("*.cpp" "*.h" "*.swift" "*.c" "*.mm" "*.py" "*.sh")

# Find and add core code files (skip build artifacts and git)
for ext in "${CODE_EXTENSIONS[@]}"; do
  find . -name "$ext" -type f \
    ! -path "./build/*" \
    ! -path "./.build/*" \
    ! -path "./.git/*" \
    ! -path "./**/*.dSYM/*" \
    ! -name "listfiles.txt" \
    | sort | while read -r file; do
      add_file "$file"
    done
done

# Add .txt files (excluding the output)
find . -name "*.txt" -type f \
  ! -path "./build/*" \
  ! -path "./.build/*" \
  ! -path "./.git/*" \
  ! -name "listfiles.txt" \
  | sort | while read -r file; do
    add_file "$file"
  done

# Add CMakeLists.txt files
find . -name "CMakeLists.txt" -type f \
  ! -path "./build/*" \
  ! -path "./.build/*" \
  ! -path "./.git/*" \
  | sort | while read -r file; do
    add_file "$file"
  done

# Add entitlements files
find . -name "*.entitlements" -type f \
  ! -path "./build/*" \
  ! -path "./.build/*" \
  ! -path "./.git/*" \
  | sort | while read -r file; do
    add_file "$file"
  done

echo "File listing complete. Output written to $OUTPUT"
