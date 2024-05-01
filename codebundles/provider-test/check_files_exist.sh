#!/bin/bash

#FILE_LIST
if [[ -z "$FILE_LIST" ]]; then
    echo "Environment variable 'FILE_LIST' is not set"
    exit 1
fi

# Check if any files are missing
missing=0
for file in $FILE_LIST; do
    if [ ! -f "$file" ]; then
        echo "File $file is missing"
        missing=1
        break
    fi
done
if [[ $missing -ne 0 ]]; then
    echo "Some files are missing, review logs for details"
    exit $missing
else
    echo "All files present"
    exit $missing
fi