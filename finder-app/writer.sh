#!/bin/bash

if [ "$#" -lt 2 ]; then
    echo "No enough args were provided."
    exit 1
fi


mkdir -p $(dirname "$1") && touch "$1"


echo "$2" > "$1"