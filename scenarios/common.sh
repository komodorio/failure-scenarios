#!/bin/bash

# Common functions and variables for failure injection scenarios

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the script directory (scenarios/)
SCENARIOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get the project root directory (parent of scenarios/)
PROJECT_ROOT="$(dirname "${SCENARIOS_DIR}")"

# Source common helper functions for state management
# shellcheck source=../lib/common-helpers.sh
source "${PROJECT_ROOT}/lib/common-helpers.sh"

# Directories
MANIFESTS_DIR="${PROJECT_ROOT}/bank-of-anthos/kubernetes-manifests"
BACKUP_DIR="${PROJECT_ROOT}/bank-of-anthos/kubernetes-manifests-backup"

# Namespace - determine based on priority:
# 1. Explicitly set NAMESPACE environment variable (allows manual override)
# 2. State namespace (requires state to exist and scenario name can be determined)
# Usage: NAMESPACE="my-namespace" ./scenarios/some-scenario.sh
if [ -z "${NAMESPACE:-}" ]; then
    # Try to determine scenario name from script path
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        script_name=$(basename "${BASH_SOURCE[0]}")
        if [[ "$script_name" =~ ^(.+)-scenario\.sh$ ]]; then
            scenario_name="${BASH_REMATCH[1]}"
            if state_exists; then
                NAMESPACE=$(get_namespace_with_timestamp "$scenario_name")
            else
                print_error "No state found. Please run ./batch/setup-all-scenarios.sh first."
                print_info "Alternatively, set NAMESPACE environment variable: NAMESPACE=<namespace> $0"
                exit 1
            fi
        else
            print_error "Cannot determine scenario name from script path: ${BASH_SOURCE[0]}"
            print_info "Please set NAMESPACE environment variable: NAMESPACE=<namespace> $0"
            exit 1
        fi
    else
        print_error "Cannot determine script path. Please set NAMESPACE environment variable: NAMESPACE=<namespace> $0"
        exit 1
    fi
fi

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

# Function to check if Bank of Anthos is deployed
check_deployment() {
    print_info "Checking if Bank of Anthos is deployed..."

    if ! kubectl get deployment frontend -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_error "Bank of Anthos is not deployed. Please run setup-bank-of-anthos.sh first."
        exit 1
    fi

    print_success "Bank of Anthos deployment found"
}

# Function to check if manifests directory exists
check_manifests() {
    if [ ! -d "${MANIFESTS_DIR}" ]; then
        print_error "Manifests directory not found: ${MANIFESTS_DIR}"
        print_info "Please ensure you are in the correct directory"
        exit 1
    fi
}

# Function to create backup of original manifests
create_backup() {
    if [ ! -d "${BACKUP_DIR}" ]; then
        print_info "Creating backup of original manifests..."
        mkdir -p "${BACKUP_DIR}"
        cp -r "${MANIFESTS_DIR}"/*.yaml "${BACKUP_DIR}/"
        print_success "Backup created at: ${BACKUP_DIR}"
    else
        print_info "Backup already exists at: ${BACKUP_DIR}"
    fi
}

# Default auto-apply action - does nothing by default
# Scenarios can override this function to call action_inject() if they want auto-apply
action_auto_apply() {
    # Default: do nothing
    :
}

# Function to handle common scenario entry point logic
# This function should be called at the end of each scenario script
# Usage: handle_scenario_command "$@"
#
# Prerequisites: The scenario script must define:
#   - action_inject() function
#   - action_revert() function
# Optional: Override action_auto_apply() for custom auto-apply logic
handle_scenario_command() {
    local ACTION="${1:-inject}"  # Default to inject if no argument provided

    case "$ACTION" in
        inject)
            action_inject
            ;;
        revert)
            action_revert
            ;;
        auto-apply)
            action_auto_apply
            ;;
        *)
            print_error "Invalid action: $ACTION"
            echo ""
            echo "Usage: $0 [inject|revert|auto-apply]"
            echo ""
            echo "Actions:"
            echo "  inject      - Apply the failure scenario (default)"
            echo "  revert      - Revert the failure scenario"
            echo "  auto-apply  - Auto-apply if AUTO_DEPLOY is enabled"
            echo ""
            exit 1
            ;;
    esac
}
