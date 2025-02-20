#!/usr/bin/env bash
BASE_ROOT_FACTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$BASE_ROOT_FACTORY/utils"

# Function to deploy the MagicDrop Clone Factory
deploy_magicdrop_factory() {
    local CHAIN_ID="$1"
    local FACTORY_SALT="$2"
    local FACTORY_EXPECTED_ADDRESS="$3"
    local REGISTRY_ADDRESS="$4"
    local INITIAL_OWNER="$5"
    local RESUME="$6"
    local DRY_RUN="$7"
    local MAX_RETRIES=3
    local RETRY_DELAY=10
    
    # Set the RPC URL based on chain ID
    set_rpc_url "$CHAIN_ID"

    # Set the ETHERSCAN API KEY based on chain ID
    set_etherscan_api_key "$CHAIN_ID"

    # Build the forge command
    local FORGE_CMD="forge script \"$BASE_ROOT_FACTORY/DeployMagicDropCloneFactory.s.sol:DeployMagicDropCloneFactory\" \
        --rpc-url \"$RPC_URL\" \
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
           FACTORY_SALT=$FACTORY_SALT \
           FACTORY_EXPECTED_ADDRESS=$FACTORY_EXPECTED_ADDRESS \
           INITIAL_OWNER=$INITIAL_OWNER \
           REGISTRY_ADDRESS=$REGISTRY_ADDRESS \
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
    echo "Usage: $0 --run --chain-id <chain id> --salt <salt> --expected-address <expected address> --initial-owner <initial owner> --registry-address <registry address> [--resume] [--dry-run]"
    exit 1
}

# Main run function
run() {
    local CHAIN_ID=""
    local FACTORY_SALT=""
    local FACTORY_EXPECTED_ADDRESS=""
    local INITIAL_OWNER=""
    local REGISTRY_ADDRESS=""
    local RESUME=""
    local DRY_RUN="false"

    # Process arguments for run function
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --chain-id) CHAIN_ID="$2"; shift ;;
            --salt) FACTORY_SALT="$2"; shift ;;
            --expected-address) FACTORY_EXPECTED_ADDRESS="$2"; shift ;;
            --initial-owner) INITIAL_OWNER="$2"; shift ;;
            --registry-address) REGISTRY_ADDRESS="$2"; shift ;;
            --resume) RESUME="--resume" ;;
            --dry-run) DRY_RUN="true" ;;
            *) usage ;;
        esac
        shift
    done

    # Check if all parameters are set
    if [ -z "$CHAIN_ID" ] || [ -z "$FACTORY_SALT" ] || [ -z "$FACTORY_EXPECTED_ADDRESS" ] || [ -z "$INITIAL_OWNER" ] || [ -z "$REGISTRY_ADDRESS" ]; then
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
    echo "============= DEPLOYING MAGICDROP CLONE FACTORY ============="
    echo "Chain ID: $CHAIN_ID"
    echo "RPC URL: $RPC_URL"
    echo "SALT: $FACTORY_SALT"
    echo "EXPECTED ADDRESS: $FACTORY_EXPECTED_ADDRESS"
    echo "INITIAL OWNER: $INITIAL_OWNER"
    echo "REGISTRY ADDRESS: $REGISTRY_ADDRESS"
    echo "Dry Run: ${DRY_RUN:-false}"
    echo "Resume: ${RESUME:-false}"
    read -p "Do you want to proceed? (yes/no) " yn

    case $yn in 
        yes ) echo "ok, we will proceed";;
        no ) echo "exiting..."; exit 1;;
        * ) echo "invalid response"; exit 1;;
    esac

    deploy_magicdrop_factory "$CHAIN_ID" "$FACTORY_SALT" "$FACTORY_EXPECTED_ADDRESS" "$INITIAL_OWNER" "$REGISTRY_ADDRESS" "$RESUME" "$DRY_RUN"
}

# When running this script directly with --run, invoke the run function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$1" == "--run" ]]; then
        shift
        run "$@"
    fi
fi
