#!/bin/bash

#ENV_LIST
if [[ -z "$ENV_LIST" ]]; then
    echo "Environment variable 'ENV_LIST' is not set"
    exit 1
fi

echo "Checking env list: $ENV_LIST"
RC=0
for var in $ENV_LIST; do
    if [[ -z ${var+x} ]]; then
        echo "Environment variable '$var' is not set"
        RC=1
    fi
done
if [[ $RC -ne 0 ]]; then
    echo "Some environment variables are not set, review logs for details"
    exit $RC
else
    echo "All environment variables are set"
    exit $RC
fi