#!/bin/bash

if [ "$#" -lt 2 ]; then
    echo "No enough args were provided."
    exit 1
fi

# Check if the first argument is a directory
if [ ! -d "$1" ]; then
    echo "$1 is not a directory."
    exit 1
fi

file_count=0
line_count=0



while IFS=":" read -r file number; do
    if [ "$number" -ne 0 ]; then
        file_count=$((file_count + 1))
        line_count=$((line_count + "$number"))
    fi
done < <(grep -R "$1" -e "$2" -c)

echo  "The number of files are $file_count and the number of matching lines are $line_count" 