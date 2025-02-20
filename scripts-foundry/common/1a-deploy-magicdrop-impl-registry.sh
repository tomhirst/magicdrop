#!/usr/bin/env bash
BASE_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$BASE_ROOT/utils"

# Function to deploy the MagicDrop Implementation Registry
deploy_magicdrop_registry() {
    local CHAIN_ID="$1"
    local REGISTRY_SALT="$2"
    local REGISTRY_EXPECTED_ADDRESS="$3"
    local INITIAL_OWNER="$4"
    local RESUME="$5"
    local DRY_RUN="$6"
    local MAX_RETRIES=3
    local RETRY_DELAY=10

    # Set the RPC URL based on chain ID
    set_rpc_url "$CHAIN_ID"

    # Set the ETHERSCAN API KEY based on chain ID
    set_etherscan_api_key "$CHAIN_ID"

    # Build the forge command
    local FORGE_CMD="forge script \"$BASE_ROOT/DeployMagicDropTokenImplRegistry.s.sol:DeployMagicDropTokenImplRegistry\" \
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
           REGISTRY_SALT=$REGISTRY_SALT \
           REGISTRY_EXPECTED_ADDRESS=$REGISTRY_EXPECTED_ADDRESS \
           INITIAL_OWNER=$INITIAL_OWNER \
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
    echo "Usage: $0 --run --chain-id <chain id> --salt <salt> --expected-address <expected address> --initial-owner <initial owner> [--resume] [--dry-run]"
    exit 1
}

# Main run function
run() {
    local CHAIN_ID=""
    local REGISTRY_SALT=""
    local REGISTRY_EXPECTED_ADDRESS=""
    local INITIAL_OWNER=""
    local RESUME=""
    local DRY_RUN="false"

    # Process arguments for run function
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --chain-id) CHAIN_ID="$2"; shift ;;
            --salt) REGISTRY_SALT="$2"; shift ;;
            --expected-address) REGISTRY_EXPECTED_ADDRESS="$2"; shift ;;
            --initial-owner) INITIAL_OWNER="$2"; shift ;;
            --resume) RESUME="--resume" ;;
            --dry-run) DRY_RUN="true" ;;
            *) usage ;;
        esac
        shift
    done

    # Check if all parameters are set
    if [ -z "$CHAIN_ID" ] || [ -z "$REGISTRY_SALT" ] || [ -z "$REGISTRY_EXPECTED_ADDRESS" ] || [ -z "$INITIAL_OWNER" ]; then
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
    echo "============= DEPLOYING MAGICDROP IMPL REGISTRY ============="
    echo "Chain ID: $CHAIN_ID"
    echo "RPC URL: $RPC_URL"
    echo "SALT: $REGISTRY_SALT"
    echo "EXPECTED ADDRESS: $REGISTRY_EXPECTED_ADDRESS"
    echo "Dry Run: ${DRY_RUN:-false}"
    echo "Resume: ${RESUME:-false}"
    read -p "Do you want to proceed? (yes/no) " yn

    case $yn in 
        yes ) echo "ok, we will proceed";;
        no ) echo "exiting..."; exit 1;;
        * ) echo "invalid response"; exit 1;;
    esac

    deploy_magicdrop_registry "$CHAIN_ID" "$REGISTRY_SALT" "$REGISTRY_EXPECTED_ADDRESS" "$INITIAL_OWNER" "$RESUME" "$DRY_RUN"
}

# When running this script directly with --run, invoke the run function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$1" == "--run" ]]; then
        shift
        run "$@"
    fi
fi
