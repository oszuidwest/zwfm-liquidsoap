#!/bin/sh

# Check if the file to write to is specified
if [ -z "$2" ]
then
    # Print an error message and exit with a non-zero exit code if no file is specified
    echo "Error: No file specified."
    exit 1
fi

# Use the file specified as the second argument
file="$2"

# Create the file if it doesn't exist
touch "$file"

# Make the file world readable and writeable
chmod 777 "$file"

# Get the current date and time in 24-hour format
now=$(date -R)

# Check the value of the first argument
if [ "$1" = "disconnect" ]
then
    # Log the date and time with DISCONNECTED ON: in front of it
    echo "DISCONNECTED ON: $now" >> "$file"
elif [ "$1" = "connect" ]
then
    # Log the date and time with CONNECTED ON: in front of it
    echo "CONNECTED ON: $now" >> "$file"
else
    # Print an error message and exit with a non-zero exit code
    echo "Error: Invalid argument. Must be 'disconnect' or 'connect'."
    exit 1
fi