#!/bin/bash

# Common Helper Functions
# This file contains shared utility functions used across multiple scripts

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Dynamically discover scenario files
# Find all *-scenario.sh files in scenarios directory and extract scenario names
# Usage: SCENARIOS=($(discover_scenarios "/path/to/project"))
discover_scenarios() {
    local project_root="${1:-.}"
    local scenarios=()

    # Find all scenario files and extract scenario names
    for scenario_file in "${project_root}/scenarios"/*-scenario.sh; do
        if [ -f "$scenario_file" ]; then
            # Extract filename without path and extension
            local filename=$(basename "$scenario_file")
            # Remove -scenario.sh suffix to get scenario name
            local scenario_name="${filename%-scenario.sh}"
            scenarios+=("$scenario_name")
        fi
    done

    # Sort scenarios alphabetically
    if [ ${#scenarios[@]} -gt 0 ]; then
        IFS=$'\n' scenarios=($(sort <<<"${scenarios[*]}"))
        unset IFS
    fi

    echo "${scenarios[@]}"
}

# Convert scenario name to title case for display
# Usage: display_name=$(scenario_to_title_case "bad-deployment")
# Output: "Bad Deployment"
scenario_to_title_case() {
    local scenario_name="$1"
    echo "$scenario_name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1'
}

# Get the base namespace for a scenario (mapped or default)
# This function looks up the scenario in the mapping config file
# Usage: namespace_base=$(get_namespace_base "bad-deployment")
# Returns: "bank-of-springfield" (if mapped) or "bad-deployment-scenario" (if not)
get_namespace_base() {
    local scenario="$1"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/../config/namespace-mapping.conf"

    # If config file doesn't exist, use default
    if [ ! -f "$config_file" ]; then
        echo "${scenario}-scenario"
        return
    fi

    # Look up the scenario in the config file
    # Format: scenario-name=namespace-base
    local mapped_namespace
    mapped_namespace=$(grep "^${scenario}=" "$config_file" 2>/dev/null | cut -d'=' -f2 | xargs)

    # Return mapped namespace or default
    if [ -n "$mapped_namespace" ]; then
        echo "$mapped_namespace"
    else
        echo "${scenario}-scenario"
    fi
}

# State management functions
# State is stored in a ConfigMap in the default namespace
STATE_CONFIGMAP_NAME="failure-scenarios-state"
STATE_NAMESPACE="default"

# Check if state exists
# Returns 0 if state exists, 1 otherwise
state_exists() {
    kubectl get configmap "$STATE_CONFIGMAP_NAME" -n "$STATE_NAMESPACE" >/dev/null 2>&1
}

# Get the current state timestamp
# Returns the timestamp string if state exists, empty string otherwise
get_state_timestamp() {
    if state_exists; then
        kubectl get configmap "$STATE_CONFIGMAP_NAME" -n "$STATE_NAMESPACE" -o jsonpath='{.data.timestamp}' 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Create new state with timestamp
# Generates a new timestamp and stores it in a ConfigMap
create_state() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    
    # Create or update the ConfigMap
    kubectl create configmap "$STATE_CONFIGMAP_NAME" \
        --from-literal=timestamp="$timestamp" \
        --from-literal=created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        -n "$STATE_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    
    echo "$timestamp"
}

# Remove state
# Deletes the state ConfigMap
remove_state() {
    kubectl delete configmap "$STATE_CONFIGMAP_NAME" -n "$STATE_NAMESPACE" >/dev/null 2>&1 || true
}

# Get namespace name with timestamp for a scenario
# Requires state to exist (state must be created via setup-all-scenarios.sh)
# Usage: namespace=$(get_namespace_with_timestamp "bad-deployment")
# Returns: "bank-of-springfield-20240101-120000" (if mapped) or "bad-deployment-scenario-20240101-120000" (if not)
get_namespace_with_timestamp() {
    local scenario="$1"
    local timestamp
    local namespace_base

    # Get base namespace (uses mapping if available)
    namespace_base=$(get_namespace_base "$scenario")

    timestamp=$(get_state_timestamp)
    if [ -z "$timestamp" ]; then
        echo "ERROR: No state timestamp found" >&2
        return 1
    fi

    echo "${namespace_base}-${timestamp}"
}

# Get all namespaces for current state
# Returns array of namespace names with current timestamp
get_all_state_namespaces() {
    local project_root="${1:-.}"
    local scenarios=()
    local timestamp
    local namespaces=()
    local namespace_base

    timestamp=$(get_state_timestamp)
    if [ -z "$timestamp" ]; then
        echo ""
        return
    fi

    scenarios=($(discover_scenarios "$project_root"))

    for scenario in "${scenarios[@]}"; do
        namespace_base=$(get_namespace_base "$scenario")
        namespaces+=("${namespace_base}-${timestamp}")
    done

    echo "${namespaces[@]}"
}

# Delete namespaces in parallel
# Takes an array of namespace names and deletes them concurrently
# Usage: delete_namespaces_parallel "namespace1" "namespace2" "namespace3"
# Returns: 0 if all deletions succeeded, 1 if any failed
delete_namespaces_parallel() {
    local namespaces_to_delete=("$@")

    if [ ${#namespaces_to_delete[@]} -eq 0 ]; then
        print_info "No namespaces to delete"
        return 0
    fi

    print_info "Deleting ${#namespaces_to_delete[@]} namespace(s) in parallel..."
    echo ""

    local pids=()
    local namespace_names=()

    # Launch all deletions in background
    for namespace in "${namespaces_to_delete[@]}"; do
        print_info "Starting deletion: ${namespace}"

        (
            # Delete Helm releases first
            if command -v helm >/dev/null 2>&1; then
                helm list -n "$namespace" --short 2>/dev/null | xargs -r -I {} helm uninstall {} -n "$namespace" 2>/dev/null || true
            fi

            # Force delete namespace without waiting
            kubectl delete namespace "$namespace" --force --grace-period=0 2>/dev/null
            echo $? > "/tmp/${namespace}-deletion.status"
        ) &

        pids+=($!)
        namespace_names+=("$namespace")
    done

    # Wait for all deletions to complete
    echo ""
    print_info "Waiting for all deletions to complete..."
    echo ""

    local success_count=0
    local fail_count=0

    for i in "${!pids[@]}"; do
        pid="${pids[$i]}"
        namespace="${namespace_names[$i]}"

        # Wait for this specific process
        wait "$pid" 2>/dev/null || true

        # Check exit status
        if [ -f "/tmp/${namespace}-deletion.status" ]; then
            status=$(cat "/tmp/${namespace}-deletion.status")
            if [ "$status" -eq 0 ]; then
                print_success "${namespace} - deletion initiated"
                ((success_count++))
            else
                print_error "${namespace} - deletion failed (exit code: ${status})"
                ((fail_count++))
            fi
            rm -f "/tmp/${namespace}-deletion.status"
        else
            print_warning "${namespace} - status unknown"
            ((fail_count++))
        fi
    done

    echo ""
    print_success "Successfully deleted ${success_count} namespace(s)"
    if [ $fail_count -gt 0 ]; then
        print_warning "Failed to delete ${fail_count} namespace(s)"
    fi
    echo ""

    # Return non-zero if any deletions failed
    [ $fail_count -eq 0 ]
}
