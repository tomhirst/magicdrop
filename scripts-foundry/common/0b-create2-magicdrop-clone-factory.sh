#!/bin/bash

get_magicdrop_factory_address() {
    local INITIAL_OWNER="$1"
    local REGISTRY_ADDRESS="$2"
    
    if [ -z "$INITIAL_OWNER" ] || [ -z "$REGISTRY_ADDRESS" ]; then
        echo "Usage: get_magicdrop_factory_address <initial-owner-address> <registry-address>" >&2
        return 1
    fi

    # NOTE: If you change the number of optimizer runs, you must also change the number in the deploy script,
    # otherwise the CREATE2 address will be different.
    local factoryByteCode
    factoryByteCode="$(forge inspect contracts/factory/MagicDropCloneFactory.sol:MagicDropCloneFactory bytecode --optimizer-runs 777 --via-ir)"

    # # Encode the constructor arguments
    # local constructorArgs
    # constructorArgs="$(cast abi-encode "constructor(address,address)" "$INITIAL_OWNER" "$REGISTRY_ADDRESS")"
    # # Remove the '0x' prefix from the encoded constructor arguments
    # local constructorArgsNoPrefix=${constructorArgs#0x}

    # Concatenate the bytecode and constructor arguments to construct the init code
    # local factoryInitCode
    # factoryInitCode="$(cast concat-hex "$factoryByteCode" "$constructorArgsNoPrefix")"

    # Compute the expected CREATE2 address and parse the output
    local create2_output
    create2_output="$(cast create2 --starts-with 0000 --case-sensitive --init-code "$factoryByteCode")"
    
    # Extract salt and address using regex and set them as global variables
    if [[ $create2_output =~ Address:\ (0x[0-9a-fA-F]+).*Salt:\ (0x[0-9a-fA-F]+) ]]; then
        FACTORY_ADDRESS="${BASH_REMATCH[1]}"
        FACTORY_SALT="${BASH_REMATCH[2]}"
    else
        echo "Error: Failed to parse CREATE2 output: $create2_output" >&2
        return 1
    fi
}

# Function to display usage information
usage() {
    echo "Usage: $0 --run --initial-owner <initial owner address> --registry-address <registry address>"
    exit 1
}

# Main run function that processes arguments and calls get_magicdrop_factory_address
run() {
    local INITIAL_OWNER=""
    local REGISTRY_ADDRESS=""
    # Declare global variables
    FACTORY_SALT=""
    FACTORY_ADDRESS=""

    # Process arguments for run function
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --initial-owner)
                INITIAL_OWNER="$2"
                shift ;;
            --registry-address)
                REGISTRY_ADDRESS="$2"
                shift ;;
            *)
                usage ;;
        esac
        shift
    done

    if [ -z "$INITIAL_OWNER" ] || [ -z "$REGISTRY_ADDRESS" ]; then
        usage
    fi

    if ! get_magicdrop_factory_address "$INITIAL_OWNER" "$REGISTRY_ADDRESS"; then
        echo "Error: Failed to compute factory address" >&2
        exit 1
    fi
    
    # Now you can use FACTORY_SALT and FACTORY_ADDRESS here
    echo ""
    echo "MagicDropCloneFactory"
    echo "Salt: $FACTORY_SALT"
    echo "Address: $FACTORY_ADDRESS"
    echo ""
}

# When running this script directly with --run, invoke the run function.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$1" == "--run" ]]; then
        shift
        run "$@"
    fi
fi
