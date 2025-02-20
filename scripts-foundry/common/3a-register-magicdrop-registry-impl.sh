#!/usr/bin/env bash
BASE_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$BASE_ROOT/utils"

# Function to register MagicDrop implementation
register_magicdrop_impl() {
    local CHAIN_ID="$1"
    local REGISTRY_ADDRESS="$2"
    local IMPL_ADDRESS="$3"
    local TOKEN_STANDARD="$4"
    local IS_DEFAULT="$5"
    local MINT_FEE="$6"
    local DEPLOYMENT_FEE="$7"
    local RESUME="$8"
    local DRY_RUN="$9"
    local MAX_RETRIES=3
    local RETRY_DELAY=10

    # Set the RPC URL based on chain ID
    set_rpc_url "$CHAIN_ID"

    # Set the ETHERSCAN API KEY based on chain ID
    set_etherscan_api_key "$CHAIN_ID"

    # Build the forge command
    local FORGE_CMD="forge script \"$BASE_ROOT/RegisterMagicDropImpl.s.sol:RegisterMagicDropImpl\" \
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
           REGISTRY_ADDRESS=$REGISTRY_ADDRESS \
           IMPL_ADDRESS=$IMPL_ADDRESS \
           TOKEN_STANDARD=$TOKEN_STANDARD \
           IS_DEFAULT=$IS_DEFAULT \
           MINT_FEE=$MINT_FEE \
           DEPLOYMENT_FEE=$DEPLOYMENT_FEE \
           eval "$FORGE_CMD"; then
            echo "Registration successful!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $MAX_RETRIES ]; then
            echo "Registration failed. Retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        else
            echo "Registration failed after $MAX_RETRIES attempts."
            return 1
        fi
    done
}

# Function to display usage
usage() {
    echo "Usage: $0 --run --chain-id <chain id> --registry-address <registry address> --impl-address <impl address> --token-standard <token standard> --is-default <true/false> --fee <fee> [--resume] [--dry-run]"
    exit 1
}

# Main run function
run() {
    local CHAIN_ID=""
    local REGISTRY_ADDRESS=""
    local IMPL_ADDRESS=""
    local TOKEN_STANDARD=""
    local IS_DEFAULT=""
    local DEPLOYMENT_FEE=""
    local MINT_FEE=""
    local RESUME=""
    local DRY_RUN="false"

    # Process arguments for run function
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --chain-id) CHAIN_ID="$2"; shift ;;
            --registry-address) REGISTRY_ADDRESS="$2"; shift ;;
            --impl-address) IMPL_ADDRESS="$2"; shift ;;
            --token-standard) TOKEN_STANDARD="$2"; shift ;;
            --is-default) IS_DEFAULT="$2"; shift ;;
            --deployment-fee) DEPLOYMENT_FEE="$2"; shift ;;
            --mint-fee) MINT_FEE="$2"; shift ;;
            --resume) RESUME="--resume" ;;
            --dry-run) DRY_RUN="true" ;;
            *) usage ;;
        esac
        shift
    done

    # Check if all parameters are set
    if [ -z "$CHAIN_ID" ] || [ -z "$REGISTRY_ADDRESS" ] || [ -z "$IMPL_ADDRESS" ] || [ -z "$TOKEN_STANDARD" ] || [ -z "$IS_DEFAULT" ] || [ -z "$DEPLOYMENT_FEE" ] || [ -z "$MINT_FEE" ]; then
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
    echo "==================== REGISTRATION DETAILS ===================="
    echo "Chain ID: $CHAIN_ID"
    echo "RPC URL: $RPC_URL"
    echo "Registry Address: $REGISTRY_ADDRESS"
    echo "Implementation Address: $IMPL_ADDRESS"
    echo "Token Standard: $TOKEN_STANDARD"
    echo "Is Default: $IS_DEFAULT"
    echo "Deployment Fee: $DEPLOYMENT_FEE"
    echo "Mint Fee: $MINT_FEE"
    echo "Dry Run: ${DRY_RUN:-false}"
    echo "Resume: ${RESUME:-false}"
    echo "============================================================="
    read -p "Do you want to proceed? (yes/no) " yn

    case $yn in 
        yes ) echo "ok, we will proceed";;
        no ) echo "exiting..."; exit 1;;
        * ) echo "invalid response"; exit 1;;
    esac

    register_magicdrop_impl "$CHAIN_ID" "$REGISTRY_ADDRESS" "$IMPL_ADDRESS" "$TOKEN_STANDARD" "$IS_DEFAULT" "$MINT_FEE" "$DEPLOYMENT_FEE" "$RESUME" "$DRY_RUN"
}

# When running this script directly with --run, invoke the run function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$1" == "--run" ]]; then
        shift
        run "$@"
    fi
fi
