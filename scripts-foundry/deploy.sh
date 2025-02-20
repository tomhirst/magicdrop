#!/usr/bin/env bash 

# Start time tracking
START_TIME=$(date +%s)

# Check for bash version 4 or higher for associative arrays
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
    echo "This script requires bash version 4 or higher"
    echo "Current bash version: $BASH_VERSION"
    exit 1
fi

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to display usage - define this before argument parsing
usage() {
    echo "Usage: $0 --owner <initial owner address> [--resume] [--dry-run]"
    exit 1
}

# Source all dependencies - escape spaces in path
source "${ROOT}/common/utils"
source "${ROOT}/common/0a-create2-magicdrop-impl-registry.sh"
source "${ROOT}/common/0b-create2-magicdrop-clone-factory.sh"
source "${ROOT}/common/0c-create2-magicdrop-impl.sh"
source "${ROOT}/common/1a-deploy-magicdrop-impl-registry.sh"
source "${ROOT}/common/1b-deploy-magicdrop-clone-factory.sh"
source "${ROOT}/common/2a-deploy-magicdrop-impl.sh"
source "${ROOT}/common/3a-register-magicdrop-registry-impl.sh"

# List of network names and their RPC endpoints
DEPLOYMENT_CHAINS=(1 137 56 8453 42161 1329 33139)

# Update the standards array to match the new usecase naming
IMPL_STANDARDS=(ERC1155_LP ERC721_LP ERC1155_SS ERC721_SS)

# Load environment variables
if [ -f "$ROOT/.env" ]; then
    export $(grep -v '^#' "$ROOT/.env" | xargs)
else
    echo "Please set your .env file"
    exit 1
fi

# Initialize variables
OWNER="$OWNER"
RESUME="false"
DRY_RUN="false"
PROXY_SALT=$(cast keccak "$SALT_KEY")

# Declare associative arrays
declare -A IMPL_ADDRESSES
declare -A IMPL_SALTS
declare -A REGISTRY_ADDRESSES
declare -A FACTORY_ADDRESSES
declare -A IMPL_DEPLOYED_ADDRESSES

# Add state file path
STATE_FILE="$ROOT/.deployment-state"

# Process command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --owner)
            OWNER="$2"
            shift ;;
        --dry-run)
            DRY_RUN="true"
            shift ;;
        --resume)
            RESUME="true"
            shift ;;
        *)
            usage ;;
    esac
    shift
done

if [ -z "$OWNER" ]; then
    usage
fi

# Function to save state
save_state() {
    local chain_id="$1"
    local type="$2"
    local address="$3"
    local salt="$4"
    local standard="${5:-}"  # Optional parameter for implementations

    # Create state directory if it doesn't exist
    mkdir -p "$(dirname "$STATE_FILE")"

    if [ -n "$standard" ]; then
        echo "${chain_id}:${type}:${standard}:${address}:${salt}" >> "$STATE_FILE"
    else
        echo "${chain_id}:${type}:${address}:${salt}" >> "$STATE_FILE"
    fi
}

# Function to check if something is deployed
is_deployed() {
    local chain_id="$1"
    local address="$2"
    set_rpc_url $chain_id
    # Call eth_getCode to check if contract is deployed
    local code=$(cast code $address --rpc-url "$RPC_URL")
    
    # If code length is more than 2 (0x), contract is deployed
    [ "${#code}" -gt 2 ]
}

# Function to load state
load_state() {
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi

    while IFS=: read -r chain_id type address salt standard; do
        case "$type" in
            "registry")
                REGISTRY_ADDRESSES[$chain_id]=$address
                REGISTRY_SALT=$salt  # Load registry salt
                ;;
            "factory")
                FACTORY_ADDRESSES[$chain_id]=$address
                FACTORY_SALT=$salt  # Load factory salt
                ;;
            "implementation")
                IMPL_DEPLOYED_ADDRESSES["${chain_id}_${standard}"]=$address
                IMPL_SALTS[$standard]=$salt  # Load implementation salt
                ;;
        esac
    done < "$STATE_FILE"
}

# Load state before generating addresses
load_state

# Only generate salts if not already loaded from state
if [ -z "$REGISTRY_SALT" ]; then
    REGISTRY_SALT=$(cast keccak "$SALT_KEY")
fi

if [ -z "$FACTORY_SALT" ]; then
    FACTORY_SALT=$(cast keccak "$SALT_KEY")
fi

# Generate addresses only if not already deployed
if [ -z "${REGISTRY_ADDRESSES[1]}" ]; then
    echo "Generating registry address..."
    get_magicdrop_registry_address $OWNER
else
    echo "Using existing registry address: ${REGISTRY_ADDRESSES[1]}"
    REGISTRY_ADDRESS="${REGISTRY_ADDRESSES[1]}"
fi

if [ -z "${FACTORY_ADDRESSES[1]}" ]; then
    echo "Generating factory address..."
    get_magicdrop_factory_address $OWNER $REGISTRY_ADDRESS
else
    echo "Using existing factory address: ${FACTORY_ADDRESSES[1]}"
    FACTORY_ADDRESS="${FACTORY_ADDRESSES[1]}"
fi

# Only generate implementation addresses if not already deployed
generate_impl_addresses() {
    for STANDARD in "${IMPL_STANDARDS[@]}"; do
        # Check if implementation is already deployed on any chain
        local already_deployed=false
        for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
            if [ -n "${IMPL_DEPLOYED_ADDRESSES[${CHAIN_ID}_${STANDARD}]}" ]; then
                already_deployed=true
                IMPL_ADDRESSES[$STANDARD]="${IMPL_DEPLOYED_ADDRESSES[${CHAIN_ID}_${STANDARD}]}"
                echo "Using existing $STANDARD implementation address: ${IMPL_ADDRESSES[$STANDARD]}"
                break
            fi
        done

        if [ "$already_deployed" = false ]; then
            echo "Generating for $STANDARD..."
            local DEPLOY_OUTPUT
            DEPLOY_OUTPUT=$(get_magicdrop_impl_address "$STANDARD" "" "${SALT_KEY}")
            
            local IMPL_ADDRESS
            local IMPL_SALT
            IMPL_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "Implementation address:" | awk '{print $3}')
            IMPL_SALT=$(echo "$DEPLOY_OUTPUT" | grep "Implementation salt:" | awk '{print $3}')
            
            if [ -z "$IMPL_ADDRESS" ] || [ -z "$IMPL_SALT" ]; then
                echo "Failed to get implementation details for $STANDARD. Exiting."
                echo "Output was: $DEPLOY_OUTPUT"
                exit 1
            fi
            
            IMPL_ADDRESSES[$STANDARD]=$IMPL_ADDRESS
            IMPL_SALTS[$STANDARD]=$IMPL_SALT
        fi
    done
}

echo "Building..."
forge build
if [ $? -ne 0 ]; then
  echo "Build failed. Skipping or handling error."
  exit 1
fi

if ! command -v gum &> /dev/null
then
    echo "gum could not be found, installing..."
    brew install gum
    if [ $? -ne 0 ]; then
        echo "Failed to install gum. Exiting."
        exit 1
    fi
fi

echo "Formatting..."
forge fmt

generate_impl_addresses

deploy_registry() {
    local -A pids
    local -A results
    local all_succeeded=true

    # Create a temporary directory to store our results
    local tmp_dir=$(mktemp -d)

    # Start deployments in parallel
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        (   # Use subshell instead of command group
            local temp_file="$tmp_dir/result_${CHAIN_ID}"
            
            # Check if already deployed
            if [ -n "${REGISTRY_ADDRESSES[$CHAIN_ID]}" ] && is_deployed "$CHAIN_ID" "${REGISTRY_ADDRESSES[$CHAIN_ID]}"; then
                echo "Registry already deployed on chain $CHAIN_ID at ${REGISTRY_ADDRESSES[$CHAIN_ID]}"
                echo "success:${REGISTRY_ADDRESSES[$CHAIN_ID]}" > "$temp_file"
                exit 0  # Exit the subshell
            fi

            if DEPLOY_OUTPUT=$(deploy_magicdrop_registry $CHAIN_ID $REGISTRY_SALT $REGISTRY_ADDRESS $OWNER $RESUME $DRY_RUN 2>&1); then
                REGISTRY_PROXY_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "Proxy deployed:" | awk '{print $3}')
                if [ -n "$REGISTRY_PROXY_ADDRESS" ]; then
                    save_state "$CHAIN_ID" "registry" "$REGISTRY_PROXY_ADDRESS" "$REGISTRY_SALT"
                    echo "success:$REGISTRY_PROXY_ADDRESS" > "$temp_file"
                else
                    echo "error:Failed to get proxy address" > "$temp_file"
                fi
            else
                echo "error:$DEPLOY_OUTPUT" > "$temp_file"
            fi
        ) &  # End subshell and background it
        pids[$CHAIN_ID]=$!
    done

    # Wait for all deployments to complete and collect results
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        wait ${pids[$CHAIN_ID]}
        
        if [ -f "$tmp_dir/result_${CHAIN_ID}" ]; then
            result=$(cat "$tmp_dir/result_${CHAIN_ID}")
            
            if [[ $result == success:* ]]; then
                REGISTRY_PROXY_ADDRESS=${result#success:}
                echo "Deployed registry to address: $REGISTRY_PROXY_ADDRESS on chain $CHAIN_ID"
                results[$CHAIN_ID]=$REGISTRY_PROXY_ADDRESS
            else
                error_msg=${result#error:}
                echo "Deployment failed on chain $CHAIN_ID: $error_msg"
                all_succeeded=false
            fi
        else
            echo "Deployment failed on chain $CHAIN_ID: No result file found"
            all_succeeded=false
        fi
    done

    # Cleanup
    rm -rf "$tmp_dir"

    # If any deployment failed, exit with error
    if [ "$all_succeeded" = false ]; then
        echo "One or more deployments failed. Exiting."
        exit 1
    fi

    return 0
}

deploy_factory() {
    local -A pids
    local -A results
    local all_succeeded=true

    # Create a temporary directory to store our results
    local tmp_dir=$(mktemp -d)

    # Start deployments in parallel
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        (   # Use subshell instead of command group
            local temp_file="$tmp_dir/result_${CHAIN_ID}"
            
            # Check if already deployed
            if [ -n "${FACTORY_ADDRESSES[$CHAIN_ID]}" ] && is_deployed "$CHAIN_ID" "${FACTORY_ADDRESSES[$CHAIN_ID]}"; then
                echo "Factory already deployed on chain $CHAIN_ID at ${FACTORY_ADDRESSES[$CHAIN_ID]}"
                echo "success:${FACTORY_ADDRESSES[$CHAIN_ID]}" > "$temp_file"
                exit 0  # Exit the subshell
            fi
            
            if DEPLOY_OUTPUT=$(deploy_magicdrop_factory "$CHAIN_ID" "$FACTORY_SALT" "$FACTORY_ADDRESS" "$REGISTRY_PROXY_ADDRESS" "$OWNER" "$RESUME" "$DRY_RUN" 2>&1); then
                FACTORY_PROXY_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "Proxy deployed:" | awk '{print $3}')
                if [ -n "$FACTORY_PROXY_ADDRESS" ]; then
                    save_state "$CHAIN_ID" "factory" "$FACTORY_PROXY_ADDRESS" "$FACTORY_SALT"
                    echo "success:$FACTORY_PROXY_ADDRESS" > "$temp_file"
                else
                    echo "error:Failed to get proxy address" > "$temp_file"
                fi
            else
                echo "error:$DEPLOY_OUTPUT" > "$temp_file"
            fi
        ) &  # End subshell and background it
        pids[$CHAIN_ID]=$!
    done

    # Wait for all deployments to complete and collect results
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        wait ${pids[$CHAIN_ID]}
        
        if [ -f "$tmp_dir/result_${CHAIN_ID}" ]; then
            result=$(cat "$tmp_dir/result_${CHAIN_ID}")
            
            if [[ $result == success:* ]]; then
                FACTORY_PROXY_ADDRESS=${result#success:}
                echo "Deployed factory to address: $FACTORY_PROXY_ADDRESS on chain $CHAIN_ID"
                results[$CHAIN_ID]=$FACTORY_PROXY_ADDRESS
            else
                error_msg=${result#error:}
                echo "Deployment failed on chain $CHAIN_ID: $error_msg"
                all_succeeded=false
            fi
        else
            echo "Deployment failed on chain $CHAIN_ID: No result file found"
            all_succeeded=false
        fi
    done

    # Cleanup
    rm -rf "$tmp_dir"

    # If any deployment failed, exit with error
    if [ "$all_succeeded" = false ]; then
        echo "One or more deployments failed. Exiting."
        exit 1
    fi

    return 0
}

deploy_impls() {
    local -A pids
    local -A results
    local all_succeeded=true

    # Create a temporary directory to store our results
    local tmp_dir=$(mktemp -d)

    # Start deployments in parallel
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        for STANDARD in "${IMPL_STANDARDS[@]}"; do
            (   # Use subshell instead of command group
                local temp_file="$tmp_dir/result_${CHAIN_ID}_${STANDARD}"
                
                # Check if already deployed
                if [ -n "${IMPL_DEPLOYED_ADDRESSES[${CHAIN_ID}_${STANDARD}]}" ] && \
                   is_deployed "$CHAIN_ID" "${IMPL_DEPLOYED_ADDRESSES[${CHAIN_ID}_${STANDARD}]}"; then
                    echo "$STANDARD implementation already deployed on chain $CHAIN_ID"
                    echo "success:${IMPL_DEPLOYED_ADDRESSES[${CHAIN_ID}_${STANDARD}]}" > "$temp_file"
                    exit 0  # Exit the subshell
                fi
                
                if DEPLOY_OUTPUT=$(deploy_magicdrop_impl $CHAIN_ID $STANDARD ${IMPL_ADDRESSES[$STANDARD]} ${IMPL_SALTS[$STANDARD]} $RESUME $DRY_RUN 2>&1); then
                    local DEPLOYED_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "Implementation deployed:" | awk '{print $3}')
                    if [ -n "$DEPLOYED_ADDRESS" ]; then
                        save_state "$CHAIN_ID" "implementation" "$DEPLOYED_ADDRESS" "${IMPL_SALTS[$STANDARD]}" "$STANDARD"
                        echo "success:$DEPLOYED_ADDRESS" > "$temp_file"
                    else
                        echo "error:Failed to get deployed address" > "$temp_file"
                    fi
                else
                    echo "error:$DEPLOY_OUTPUT" > "$temp_file"
                fi
            ) &  # End subshell and background it
            pids["${CHAIN_ID}_${STANDARD}"]=$!
        done
    done

    # Wait for all deployments to complete and collect results
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        for STANDARD in "${IMPL_STANDARDS[@]}"; do
            wait ${pids["${CHAIN_ID}_${STANDARD}"]}
            
            if [ -f "$tmp_dir/result_${CHAIN_ID}_${STANDARD}" ]; then
                result=$(cat "$tmp_dir/result_${CHAIN_ID}_${STANDARD}")
                
                if [[ $result == success:* ]]; then
                    DEPLOYED_ADDRESS=${result#success:}
                    echo "Deployed $STANDARD implementation to address: $DEPLOYED_ADDRESS on chain $CHAIN_ID"
                    results["${CHAIN_ID}_${STANDARD}"]=$DEPLOYED_ADDRESS
                else
                    error_msg=${result#error:}
                    echo "Deployment failed for $STANDARD on chain $CHAIN_ID: $error_msg"
                    all_succeeded=false
                fi
            else
                echo "Deployment failed for $STANDARD on chain $CHAIN_ID: No result file found"
                all_succeeded=false
            fi
        done
    done

    # Cleanup
    rm -rf "$tmp_dir"

    # If any deployment failed, exit with error
    if [ "$all_succeeded" = false ]; then
        echo "One or more deployments failed. Exiting."
        exit 1
    fi

    return 0
}

register_impls() {
    local -A pids
    local -A results
    local all_succeeded=true

    # Create a temporary directory to store our results
    local tmp_dir=$(mktemp -d)

    # Start registrations in parallel
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        for STANDARD in "${IMPL_STANDARDS[@]}"; do
            (   # Use subshell instead of command group
                local temp_file="$tmp_dir/result_${CHAIN_ID}_${STANDARD}"
                
                echo "Registering $STANDARD implementation on chain $CHAIN_ID..."
                
                # Set default flag based on standard type
                local IS_DEFAULT="false"
                if [[ "$STANDARD" == *"_LP" ]]; then
                    IS_DEFAULT="true"
                fi

                # Remove _LP or _SS suffix from standard for registration
                local CLEAN_STANDARD=${STANDARD%_LP}
                CLEAN_STANDARD=${CLEAN_STANDARD%_SS}

                # Set fees
                local DEPLOYMENT_FEE="0"
                local MINT_FEE="0"

                if DEPLOY_OUTPUT=$(register_magicdrop_impl \
                    "$CHAIN_ID" \
                    "$REGISTRY_PROXY_ADDRESS" \
                    "${IMPL_ADDRESSES[$STANDARD]}" \
                    "$CLEAN_STANDARD" \
                    "$IS_DEFAULT" \
                    "$MINT_FEE" \
                    "$DEPLOYMENT_FEE" \
                    "$RESUME" \
                    "$DRY_RUN" 2>&1); then
                    echo "success:${IMPL_ADDRESSES[$STANDARD]}" > "$temp_file"
                else
                    echo "error:$DEPLOY_OUTPUT" > "$temp_file"
                fi
            ) &  # End subshell and background it
            pids["${CHAIN_ID}_${STANDARD}"]=$!
        done
    done

    # Wait for all registrations to complete and collect results
    for CHAIN_ID in "${DEPLOYMENT_CHAINS[@]}"; do
        for STANDARD in "${IMPL_STANDARDS[@]}"; do
            wait ${pids["${CHAIN_ID}_${STANDARD}"]}
            
            if [ -f "$tmp_dir/result_${CHAIN_ID}_${STANDARD}" ]; then
                result=$(cat "$tmp_dir/result_${CHAIN_ID}_${STANDARD}")
                
                if [[ $result == success:* ]]; then
                    IMPL_ADDRESS=${result#success:}
                    results["${CHAIN_ID}_${STANDARD}"]=$IMPL_ADDRESS
                else
                    error_msg=${result#error:}
                    echo "Registration failed for $STANDARD on chain $CHAIN_ID: $error_msg"
                    all_succeeded=false
                fi
            else
                echo "Registration failed for $STANDARD on chain $CHAIN_ID: No result file found"
                all_succeeded=false
            fi
        done
    done

    # Cleanup
    rm -rf "$tmp_dir"

    # If any registration failed, exit with error
    if [ "$all_succeeded" = false ]; then
        echo "One or more registrations failed. Exiting."
        exit 1
    fi

    return 0
}

# Run deployments
deploy_registry
deploy_factory
deploy_impls
# register_impls

# At the end of the script, replace the "Done" message
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Done"
echo "Total execution time: $DURATION seconds"
