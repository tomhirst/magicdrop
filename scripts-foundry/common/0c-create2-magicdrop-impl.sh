#!/bin/bash
BASE_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$BASE_ROOT/utils"

# Function to get implementation CREATE2 address and salt
get_magicdrop_impl_address() {
    local STANDARD="$1"
    local IMPL_PATH="$2"
    local SALT_KEY="$3"

    # Determine the implementation path based on standard
    if [ -z "$IMPL_PATH" ]; then
        case $STANDARD in
            "ERC721_LP")
                IMPL_PATH="contracts/nft/erc721m/ERC721MInitializableV1_0_2.sol:ERC721MInitializableV1_0_2"
                ;;
            "ERC1155_LP")
                IMPL_PATH="contracts/nft/erc1155m/ERC1155MInitializableV1_0_2.sol:ERC1155MInitializableV1_0_2"
                ;;
            "ERC721_SS")
                IMPL_PATH="contracts/nft/erc721m/clones/ERC721MagicDropCloneable.sol:ERC721MagicDropCloneable"
                ;;
            "ERC1155_SS")
                IMPL_PATH="contracts/nft/erc1155m/clones/ERC1155MagicDropCloneable.sol:ERC1155MagicDropCloneable"
                ;;
            *)
                echo "Unsupported token standard: $STANDARD"
                echo "Supported standards: ERC721_LP, ERC1155_LP, ERC721_SS, ERC1155_SS"
                return 1
                ;;
        esac
    fi

    echo "Computing CREATE2 address for $STANDARD implementation..."
    
    # Get the bytecode
    local IMPL_CODE=$(forge inspect $IMPL_PATH bytecode --optimizer-runs 777 --via-ir)
    if [ -z "$IMPL_CODE" ]; then
        echo "Failed to get bytecode for $IMPL_PATH"
        return 1
    fi
    
    # Get CREATE2 address
    local CREATE2_OUTPUT=$(cast create2 --starts-with 0000 --case-sensitive --init-code $IMPL_CODE)
    local IMPL_ADDRESS=$(echo "$CREATE2_OUTPUT" | grep "Address:" | awk '{print $2}')
    local IMPL_SALT=$(echo "$CREATE2_OUTPUT" | grep "Salt:" | awk '{print $2}')
    
    if [ -z "$IMPL_ADDRESS" ]; then
        echo "Failed to compute CREATE2 address"
        return 1
    fi

    echo "Implementation salt: $IMPL_SALT"
    echo "Implementation address: $IMPL_ADDRESS"
}

# Function to display usage
usage() {
    echo "Usage: $0 --run --standard <token standard> [--impl <implementation path>] --salt-key <salt key>"
    exit 1
}

# Main run function
run() {
    local STANDARD=""
    local IMPL_PATH=""
    local SALT_KEY=""

    # Process arguments for run function
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --standard) STANDARD="$2"; shift ;;
            --impl) IMPL_PATH="$2"; shift ;;
            --salt-key) SALT_KEY="$2"; shift ;;
            *) usage ;;
        esac
        shift
    done

    # Check if required parameters are set
    if [ -z "$STANDARD" ] || [ -z "$SALT_KEY" ]; then
        usage
    fi

    # Load environment variables
    if [ -f "$ROOT/.env" ]; then
        export $(grep -v '^#' "$ROOT/.env" | xargs)
    else
        echo "Please set your .env file"
        exit 1
    fi

    get_magicdrop_impl_address "$STANDARD" "$IMPL_PATH" "$SALT_KEY"
}

# When running this script directly with --run, invoke the run function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$1" == "--run" ]]; then
        shift
        run "$@"
    fi
fi
