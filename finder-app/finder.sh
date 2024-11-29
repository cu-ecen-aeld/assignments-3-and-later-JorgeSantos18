#!/bin/sh 

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



grep_output=$(grep -R "$1" -e "$2" -c)
file_count=0
line_count=0

IFS=$'\n' # Set IFS to handle multiline input
for line in $grep_output; do
    file=$(echo "$line" | cut -d ':' -f 1)
    number=$(echo "$line" | cut -d ':' -f 2)
    if [ "$number" -ne 0 ]; then
        file_count=$((file_count + 1))
        line_count=$((line_count + number))
    fi
done

echo  "The number of files are $file_count and the number of matching lines are $line_count" 