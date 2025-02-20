#!/bin/bash

get_erc1967_address() {
    local implementation_address="$1"

    if [ -z "$implementation_address" ]; then
        echo "Usage: get_erc1967_address <implementation address>" >&2
        return 1
    fi

    out=$(ADDRESS=$implementation_address forge script "$ROOT/common/ERC1967InitCode.s.sol:ERC1967InitCode")
    init_code=$(echo "$out" | grep -o "0x[0-9a-f]\{1,\}")
    echo "Extracted init code: $init_code"

    # Compute the expected CREATE2 address and parse the output
    local create2_output
    create2_output="$(cast create2 --starts-with 0000 --case-sensitive --init-code "$init_code")"

    echo "ERC1967 CODE: $init_code"
    
    # Extract salt and address using regex and set them as global variables
    if [[ $create2_output =~ Address:\ (0x[0-9a-fA-F]+).*Salt:\ (0x[0-9a-fA-F]+) ]]; then
        ADDRESS="${BASH_REMATCH[1]}"
        SALT="${BASH_REMATCH[2]}"
    else
        echo "Error: Failed to parse CREATE2 output: $create2_output" >&2
        return 1
    fi
}

# Function to display usage information
usage() {
    echo "Usage: $0 --run --initial-owner <initial owner address>"
    exit 1
}
