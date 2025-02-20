#!/usr/bin/env bash
BASE_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$BASE_ROOT/utils"

# Function to deploy the MagicDrop Implementation
deploy_magicdrop_impl() {
    local CHAIN_ID="$1"
    local USECASE="$2"
    local IMPL_EXPECTED_ADDRESS="$3"
    local IMPL_SALT="$4"
    local RESUME="$5"
    local DRY_RUN="$6"
    local MAX_RETRIES=3
    local RETRY_DELAY=10

    # Validate usecase
    case $USECASE in
        ERC721_LP|ERC1155_LP|ERC721_SS|ERC1155_SS) ;;
        *) echo "Invalid usecase. Must be one of: ERC721_LP, ERC1155_LP, ERC721_SS, ERC1155_SS"; exit 1;;
    esac

    echo "$DRY_RUN" "IS DRY RUN"

    # Set the RPC URL based on chain ID
    set_rpc_url "$CHAIN_ID"

    # Set the ETHERSCAN API KEY based on chain ID
    set_etherscan_api_key "$CHAIN_ID"

    # Build the forge command
    local FORGE_CMD="forge script \"$BASE_ROOT/DeployMagicDropImplementation.s.sol:DeployMagicDropImplementation\" \
        --rpc-url \"$RPC_URL\" \
        --optimizer-runs 777 \
        --via-ir \
        -v"

    # Add --broadcast and --verify only if not a dry run
    if [ "$DRY_RUN" != "true" ]; then
        FORGE_CMD="$FORGE_CMD --broadcast --verify"
    fi

    # Add resume if specified
    if [ -n "$RESUME" ]; then
        FORGE_CMD="$FORGE_CMD $RESUME"
    fi

    # Execute the command with retries
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        echo "Attempt $attempt of $MAX_RETRIES"
        if CHAIN_ID=$CHAIN_ID \
           RPC_URL=$RPC_URL \
           TOKEN_STANDARD=$USECASE \
           IMPL_EXPECTED_ADDRESS=$IMPL_EXPECTED_ADDRESS \
           IMPL_SALT=$IMPL_SALT \
           eval "$FORGE_CMD"; then
            echo "Deployment successful!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $MAX_RETRIES ]; then
            echo "Deployment failed. Retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        else
            echo "Deployment failed after $MAX_RETRIES attempts."
            return 1
        fi
    done
}

# Function to display usage
usage() {
    echo "Usage: $0 --run --chain-id <chain id> --usecase <usecase> --expected-address <expected address> --salt <salt> [--resume] [--dry-run]"
    echo "Valid usecases: ERC721_LP, ERC1155_LP, ERC721_SS, ERC1155_SS"
    exit 1
}

# Main run function
run() {
    local CHAIN_ID=""
    local USECASE=""
    local IMPL_EXPECTED_ADDRESS=""
    local IMPL_SALT=""
    local RESUME=""
    local DRY_RUN="false"

    # Process arguments for run function
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --chain-id) CHAIN_ID="$2"; shift ;;
            --usecase) USECASE="$2"; shift ;;
            --expected-address) IMPL_EXPECTED_ADDRESS="$2"; shift ;;
            --salt) IMPL_SALT="$2"; shift ;;
            --resume) RESUME="--resume" ;;
            --dry-run) DRY_RUN="true" ;;
            *) usage ;;
        esac
        shift
    done

    # Check if all parameters are set
    if [ -z "$CHAIN_ID" ] || [ -z "$USECASE" ] || [ -z "$IMPL_EXPECTED_ADDRESS" ] || [ -z "$IMPL_SALT" ]; then
        usage
    fi

    # Load environment variables
    if [ -f "$ROOT/.env" ]; then
        export $(grep -v '^#' "$ROOT/.env" | xargs)
    else
        echo "Please set your .env file"
        exit 1
    fi

    echo ""
    echo "============= DEPLOYING MAGICDROP IMPLEMENTATION ============="
    echo "Chain ID: $CHAIN_ID"
    echo "RPC URL: $RPC_URL"
    echo "Usecase: $USECASE"
    echo "Expected Address: $IMPL_EXPECTED_ADDRESS"
    echo "Salt: $IMPL_SALT"
    echo "Dry Run: ${DRY_RUN:-false}"
    echo "Resume: ${RESUME:-false}"
    read -p "Do you want to proceed? (yes/no) " yn

    case $yn in 
        yes ) echo "ok, we will proceed";;
        no ) echo "exiting..."; exit 1;;
        * ) echo "invalid response"; exit 1;;
    esac

    deploy_magicdrop_impl "$CHAIN_ID" "$USECASE" "$IMPL_EXPECTED_ADDRESS" "$IMPL_SALT" "$RESUME" "$DRY_RUN"
}

# When running this script directly with --run, invoke the run function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$1" == "--run" ]]; then
        shift
        run "$@"
    fi
fi
