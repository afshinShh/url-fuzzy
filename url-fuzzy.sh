#!/bin/bash

################################################################################
# URL Fuzzy - URL Payload Fuzzer
# Purpose: Generate permutations of character replacements and test URL payloads
# Usage: ./url-fuzzy.sh [options]
################################################################################

# Don't use -e here because we need to continue even on curl timeout/errors
set -uo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Global variables
declare -a URLS=()
declare -a FIND_CHARS=()
declare -a REPLACE_CHARS=()
declare -a GENERATED_PAYLOADS=()
declare -A RESPONSE_CACHE=()
VERBOSE=false
TIMEOUT=10
OUTPUT_FILE=""

################################################################################
# Helper Functions
################################################################################

print_banner() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   URL Fuzzy - URL Payload Fuzzer                       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_info() {
    echo -e "${CYAN}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_payload() {
    echo -e "${YELLOW}[PAYLOAD]${NC} $1"
}

show_help() {
    cat << 'EOF'
Usage: ./url-fuzzy.sh [OPTIONS]

OPTIONS:
    -u, --url URL               Single URL to test (can be used multiple times)
    -f, --file FILE             File containing URLs (one per line)
    -c, --find CHARS            Hex characters to find (space-separated, e.g., "%0D %0A")
    -r, --replace CHARS         Replacement characters (space-separated, e.g., "%20 %00")
    -t, --timeout SECONDS       Curl timeout in seconds (default: 10)
    -o, --output FILE           Save results to file
    -v, --verbose               Enable verbose output
    -h, --help                  Show this help message
    --interactive               Interactive mode (prompted for inputs)

EXAMPLES:
    # Single URL with predefined character replacements
    ./url-fuzzy.sh -u "https://example.com/api?q=%0D%0A" -c "%0D %0A" -r "%20 %00"

    # Multiple URLs with gopher payloads
    ./url-fuzzy.sh \
        -u "gopher://target1:6379/payload" \
        -u "gopher://target2:6379/payload" \
        -c "%0D %0A %09" \
        -r "%20 %00 %FF" \
        -o results.txt -v

    # Batch mode with file input
    ./url-fuzzy.sh -f urls.txt -c "%0D %0A" -r "%20 %00"

    # Interactive mode (prompted for URLs and character sets)
    ./url-fuzzy.sh --interactive

EOF
}

################################################################################
# Input Processing Functions
################################################################################

read_urls_interactive() {
    print_info "Enter URLs (one per line, empty line to finish):"
    while read -r url; do
        if [[ -z "$url" ]]; then
            break
        fi
        URLS+=("$url")
        print_success "Added URL: $url"
    done
}

read_urls_from_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        print_error "File not found: $file"
        return 1
    fi
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        URLS+=("$url")
    done < "$file"
    print_success "Loaded ${#URLS[@]} URLs from $file"
}

read_chars_interactive() {
    print_info "Enter characters to find (hex format, space-separated):"
    print_info "Example: %0D %0A %09"
    read -r -a FIND_CHARS

    print_info "Enter replacement characters (hex format, space-separated):"
    print_info "Example: %20 %00 %FF"
    read -r -a REPLACE_CHARS
}

validate_inputs() {
    if [[ ${#URLS[@]} -eq 0 ]]; then
        print_error "No URLs provided"
        return 1
    fi
    if [[ ${#FIND_CHARS[@]} -eq 0 ]]; then
        print_error "No find characters provided"
        return 1
    fi
    if [[ ${#REPLACE_CHARS[@]} -eq 0 ]]; then
        print_error "No replacement characters provided"
        return 1
    fi
    return 0
}

################################################################################
# Permutation and Payload Generation
################################################################################

generate_permutations() {
    local -n find_ref=$1
    local -n replace_ref=$2
    local -n output_ref=$3

    print_info "Generating payload permutations..."
    print_info "Find chars: ${find_ref[*]}"
    print_info "Replace chars: ${replace_ref[*]}"

    # Generate all possible combinations
    local combinations=()

    # For each find character, pair it with each replace character
    for find_char in "${find_ref[@]}"; do
        for replace_char in "${replace_ref[@]}"; do
            combinations+=("${find_char}:${replace_char}")
        done
    done

    print_success "Generated ${#combinations[@]} character replacement pairs"

    # For each URL, apply each combination
    for url in "${URLS[@]}"; do
        for combo in "${combinations[@]}"; do
            IFS=':' read -r find_char replace_char <<< "$combo"
            local payload="${url//${find_char}/${replace_char}}"
            output_ref+=("$payload")
        done
    done

    print_success "Total payloads generated: ${#output_ref[@]}"
}

################################################################################
# Payload Display and Confirmation
################################################################################

display_payloads() {
    local -n payloads=$1

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Generated Payloads (${#payloads[@]} total)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    local count=1
    for payload in "${payloads[@]}"; do
        # Truncate long payloads for display
        if [[ ${#payload} -gt 100 ]]; then
            print_payload "[$count] ${payload:0:97}..."
        else
            print_payload "[$count] $payload"
        fi
        ((count++))
    done

    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

confirm_execution() {
    echo -e "${YELLOW}Total payloads to test: ${#GENERATED_PAYLOADS[@]}${NC}"
    read -p "Do you want to proceed with testing? (yes/no): " -r response

    if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        return 0
    else
        print_warning "Testing cancelled by user"
        return 1
    fi
}

################################################################################
# HTTP Request and Response Analysis
################################################################################

# Hash function for response comparison (md5sum on Linux, md5 on macOS)
hash_response() {
    if command -v md5sum &>/dev/null; then
        echo "$1" | md5sum | awk '{print $1}'
    else
        echo -n "$1" | md5
    fi
}

test_payload() {
    local payload="$1"
    local index="$2"

    print_info "[$index/${#GENERATED_PAYLOADS[@]}] Testing: $payload"

    # Make the request with timeout
    local body
    local status

    # Run curl; capture exit code but don't fail on it
    body=$(curl -s --max-time "$TIMEOUT" "$payload" 2>/dev/null) || true
    local curl_exit=$?

    # Map curl exit code to a friendly status
    if [[ $curl_exit -eq 0 ]]; then
        status="OK"
        print_success "Curl exit: 0 (OK)"
    else
        case $curl_exit in
            28)
                status="TIMEOUT"
                print_warning "Timeout after $TIMEOUT seconds (curl exit 28)"
                ;;
            7)
                status="CONN_FAILED"
                print_error "Connection failed (curl exit 7)"
                ;;
            52)
                status="EMPTY_REPLY"
                print_warning "Empty reply from server (curl exit 52)"
                ;;
            *)
                status="CURL_ERROR_$curl_exit"
                print_error "Curl error code: $curl_exit"
                ;;
        esac
    fi

    # Show response body
    if [[ -n "$body" ]]; then
        echo -e "${CYAN}─── Response Body (${#body} bytes) ───${NC}"
        # Show full response or limit to 1500 chars for readability
        if [[ ${#body} -gt 1500 ]]; then
            echo "$body" | head -c 1500
            echo ""
            echo -e "${YELLOW}... (${#body} total bytes, truncated) ...${NC}"
        else
            echo "$body"
        fi
        echo -e "${CYAN}─── End Response ───${NC}"
    else
        echo -e "${YELLOW}[!] Empty response body${NC}"
    fi
    echo ""

    # Store response for comparison (ALWAYS succeeds)
    local response_hash
    response_hash=$(hash_response "$body")
    RESPONSE_CACHE["$index"]="$status|$response_hash|${#body}|$body"

    # ALWAYS return 0, never exit
    return 0
}

analyze_responses() {
    print_info "Analyzing responses for differences..."
    echo ""

    declare -A http_codes
    declare -A unique_hashes

    # Collect statistics
    for idx in "${!RESPONSE_CACHE[@]}"; do
        IFS='|' read -r status response_hash response_size _ <<< "${RESPONSE_CACHE[$idx]}" || true

        # Count statuses - use safe indexing even with set -u
        if [[ -z "${http_codes[$status]:-}" ]]; then
            http_codes[$status]=0
        fi
        ((http_codes[$status]++))

        # Track unique responses
        if [[ -z "${unique_hashes[$response_hash]:-}" ]]; then
            unique_hashes[$response_hash]="$idx"
        fi
    done

    # Report findings
    echo -e "${BLUE}Response Analysis Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    print_success "Response Statuses:"
    for code in $(printf '%s\n' "${!http_codes[@]}" | sort); do
        local count=${http_codes[$code]}
        if [[ "$code" == "OK" ]]; then
            echo -e "  ${GREEN}$code: $count responses${NC}"
        elif [[ "$code" =~ ^(TIMEOUT|CONN_FAILED|EMPTY_REPLY|CURL_ERROR).*$ ]]; then
            echo -e "  ${RED}$code: $count responses${NC}"
        else
            echo -e "  ${YELLOW}$code: $count responses${NC}"
        fi
    done

    echo ""
    print_success "Unique Response Hashes: ${#unique_hashes[@]}"

    local hash_count=1
    for hash in "${!unique_hashes[@]}"; do
        local payload_idx=${unique_hashes[$hash]}
        local cache_entry="${RESPONSE_CACHE[$payload_idx]:-}"
        if [[ -n "$cache_entry" ]]; then
            local response_size
            response_size=$(echo "$cache_entry" | cut -d'|' -f3)
            echo -e "  ${CYAN}Hash #$hash_count${NC}: $hash (${response_size} bytes)"
            echo -e "    ${MAGENTA}Example Payload Index:${NC} $payload_idx"
        fi
        ((hash_count++))
    done

    echo ""

    # Detect anomalies
    if [[ ${#unique_hashes[@]} -gt 1 ]]; then
        print_warning "Multiple different responses detected!"
        echo -e "  ${MAGENTA}This may indicate different payload handling or successful exploitation${NC}"
        echo ""

        # Show detailed differences
        echo -e "${BLUE}Response Differences:${NC}"
        local diff_count=1
        for hash in "${!unique_hashes[@]}"; do
            local payload_idx=${unique_hashes[$hash]}
            local response_data="${RESPONSE_CACHE[$payload_idx]:-}"

            if [[ -n "$response_data" ]]; then
                IFS='|' read -r status response_hash response_size body <<< "$response_data" || true

                echo -e "${MAGENTA}[Response Group $diff_count]${NC} - Hash: $hash"
                echo -e "  ${CYAN}Payload Index:${NC} $payload_idx"
                echo -e "  ${CYAN}Status:${NC} $status"
                echo -e "  ${CYAN}Size:${NC} $response_size bytes"
                if [[ -n "$body" ]]; then
                    echo -e "  ${CYAN}Preview:${NC}"
                    if [[ ${#body} -gt 300 ]]; then
                        echo "$body" | head -c 300 | sed 's/^/    /'
                        echo "    ... (truncated)"
                    else
                        echo "$body" | sed 's/^/    /'
                    fi
                fi
                echo ""
            fi
            ((diff_count++))
        done
    else
        print_success "All responses are identical (single hash)"
    fi
}

################################################################################
# Output Logging
################################################################################

save_results() {
    if [[ -z "$OUTPUT_FILE" ]]; then
        return
    fi

    {
        echo "URL Fuzzy - Test Results"
        echo "Generated: $(date)"
        echo "=================================="
        echo ""

        echo "Test Configuration:"
        echo "  URLs tested: ${#URLS[@]}"
        echo "  Find chars: ${FIND_CHARS[*]}"
        echo "  Replace chars: ${REPLACE_CHARS[*]}"
        echo "  Total payloads: ${#GENERATED_PAYLOADS[@]}"
        echo ""

        echo "Detailed Results:"
        echo ""

        for idx in "${!GENERATED_PAYLOADS[@]}"; do
            payload_num=$((idx + 1))
            echo "[$payload_num] Payload: ${GENERATED_PAYLOADS[$idx]}"

            if [[ -v RESPONSE_CACHE[$idx] ]]; then
                IFS='|' read -r status response_hash response_size body <<< "${RESPONSE_CACHE[$idx]}" || true
                echo "    Status: $status"
                echo "    Response Size: $response_size bytes"
                echo "    Response Hash: $response_hash"
                echo "    Response Body:"
                if [[ -n "$body" ]]; then
                    echo "$body" | sed 's/^/      /'
                else
                    echo "      (empty)"
                fi
            fi
            echo ""
        done

    } > "$OUTPUT_FILE"

    print_success "Results saved to: $OUTPUT_FILE"
}

################################################################################
# Main Execution
################################################################################

main() {
    print_banner

    local interactive_mode=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--url)
                URLS+=("$2")
                shift 2
                ;;
            -f|--file)
                read_urls_from_file "$2" || return 1
                shift 2
                ;;
            -c|--find)
                read -ra FIND_CHARS <<< "$2"
                shift 2
                ;;
            -r|--replace)
                read -ra REPLACE_CHARS <<< "$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --interactive)
                interactive_mode=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Interactive mode
    if [[ "$interactive_mode" == true ]] || [[ ${#URLS[@]} -eq 0 ]]; then
        read_urls_interactive
    fi

    if [[ ${#FIND_CHARS[@]} -eq 0 ]]; then
        read_chars_interactive
    fi

    # Validate inputs
    if ! validate_inputs; then
        print_error "Input validation failed"
        exit 1
    fi

    # Generate payloads
    generate_permutations FIND_CHARS REPLACE_CHARS GENERATED_PAYLOADS

    # Display and confirm
    display_payloads GENERATED_PAYLOADS

    if ! confirm_execution; then
        exit 0
    fi

    # Execute tests
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Testing Payloads${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    local index=0
    for payload in "${GENERATED_PAYLOADS[@]}"; do
        test_payload "$payload" "$((index + 1))" || true
        ((index++))
    done

    # Analyze results
    echo ""
    analyze_responses

    # Save results if output file specified
    save_results

    print_success "Testing completed!"
}

# Execute main function with all arguments
main "$@"
