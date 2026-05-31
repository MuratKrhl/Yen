#!/bin/bash
###############################################################################
# Nginx Reverse Proxy Inventory Script with CSV/Excel Export
# Description: Comprehensive Nginx reverse proxy reconnaissance using only
#              curl and openssl. No package installation required.
#              CSV export compatible with Excel, LibreOffice, Google Sheets
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
TIMEOUT=15
OUTPUT_DIR=""
CSV_FILE=""

###############################################################################
# CSV EXPORT FUNCTIONS
###############################################################################

init_csv() {
    local csv_path="$1"
    echo "Category,Check,Status,Detail,Severity,Timestamp" > "$csv_path"
    CSV_FILE="$csv_path"
}

csv_write() {
    local category="$1"
    local check="$2"
    local status="$3"
    local detail="${4:-}"
    local severity="${5:-Info}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    detail="${detail//\"/\"\"}"
    detail="${detail//,/ }"
    echo "\"$category\",\"$check\",\"$status\",\"$detail\",\"$severity\",\"$timestamp\"" >> "$CSV_FILE"
}

csv_info() { csv_write "$1" "$2" "Info" "$3" "Info"; }
csv_success() { csv_write "$1" "$2" "Pass" "$3" "Low"; }
csv_warn() { csv_write "$1" "$2" "Warning" "$3" "Medium"; }
csv_fail() { csv_write "$1" "$2" "Fail" "$3" "High"; }
csv_critical() { csv_write "$1" "$2" "Critical" "$3" "Critical"; }

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "==============================================================="
    echo "     NGINX REVERSE PROXY INVENTORY TOOL"
    echo "     curl + openssl only - no packages needed"
    echo "     CSV/Excel Export Enabled"
    echo "==============================================================="
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}${BOLD}===============================================================${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}===============================================================${NC}"
}

print_subsection() {
    echo ""
    echo -e "${MAGENTA}${BOLD}--> $1${NC}"
    echo -e "${MAGENTA}----------------------------------------------------------------${NC}"
}

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

check_dependencies() {
    local missing=()
    if ! command -v curl &>/dev/null; then missing+=("curl"); fi
    if ! command -v openssl &>/dev/null; then missing+=("openssl"); fi
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
    print_success "Dependencies check passed"
}

validate_target() {
    local target="$1"
    if [ -z "$target" ]; then
        print_error "Target cannot be empty"
        usage
        exit 1
    fi
    local clean_target="${target#http://}"
    clean_target="${clean_target#https://}"
    echo "$clean_target"
}

get_domain() { echo "$1" | cut -d':' -f1; }

get_port() {
    local target="$1"
    if [[ "$target" == *":"* ]]; then
        echo "$target" | cut -d':' -f2
    else
        echo "443"
    fi
}

###############################################################################
# INVENTORY MODULES
###############################################################################

inventory_basic_headers() {
    local target="$1"
    local category="HTTP_Headers"
    print_section "1. BASIC CONNECTIVITY & HTTP HEADERS"
    csv_info "$category" "Section_Start" "Beginning HTTP header analysis"

    print_subsection "1.1 HTTP Response Headers Port 80"
    local http_headers
    http_headers=$(curl -s -I --max-time "$TIMEOUT" --connect-timeout 10 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" "http://$target/" 2>/dev/null || true)

    if [ -n "$http_headers" ]; then
        echo "$http_headers" | grep -E "^(HTTP|Server|Date|Content-Type|Content-Length|Connection|Via|X-[^ :]+|Cache-Control|Expires|ETag|Last-Modified|Location|Strict-Transport-Security|Content-Security-Policy|X-Frame-Options|X-Content-Type-Options|Referrer-Policy|Permissions-Policy):" || true

        if echo "$http_headers" | grep -qi "Server:.*nginx"; then
            print_success "Nginx signature detected"
            local nginx_version
            nginx_version=$(echo "$http_headers" | grep -i "^Server:" | grep -oE "nginx/[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
            csv_success "$category" "Nginx_Detection" "Nginx detected: $nginx_version"
        elif echo "$http_headers" | grep -qi "Server:"; then
            local server_header
            server_header=$(echo "$http_headers" | grep -i "^Server:" | head -1)
            print_warn "Non-Nginx server: $server_header"
            csv_warn "$category" "Server_Header" "Non-Nginx: $server_header"
        else
            print_warn "No Server header found"
            csv_warn "$category" "Server_Header" "Server header missing"
        fi

        if echo "$http_headers" | grep -qi "^Via:"; then
            local via_val
            via_val=$(echo "$http_headers" | grep -i "^Via:" | head -1)
            print_info "Via header: $via_val"
            csv_info "$category" "Via_Header" "$via_val"
        fi

        local http_status
        http_status=$(echo "$http_headers" | head -1 | grep -oE "[0-9]{3}" || echo "000")
        csv_info "$category" "HTTP_Status" "Port 80 returned HTTP $http_status"
    else
        print_fail "No HTTP response from port 80"
        csv_fail "$category" "HTTP_Connectivity" "No response from port 80"
    fi

    print_subsection "1.2 HTTPS Response Headers Port 443"
    local https_headers
    https_headers=$(curl -s -I --insecure --max-time "$TIMEOUT" --connect-timeout 10 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" "https://$target/" 2>/dev/null || true)

    if [ -n "$https_headers" ]; then
        echo "$https_headers" | grep -E "^(HTTP|Server|Date|Content-Type|Content-Length|Connection|Via|X-[^ :]+|Cache-Control|Expires|ETag|Last-Modified|Location|Strict-Transport-Security|Content-Security-Policy|X-Frame-Options|X-Content-Type-Options|Referrer-Policy|Permissions-Policy):" || true

        if echo "$https_headers" | grep -qi "Strict-Transport-Security"; then
            local hsts_val
            hsts_val=$(echo "$https_headers" | grep -i "Strict-Transport-Security" | head -1)
            print_success "HSTS enabled: $hsts_val"
            csv_success "$category" "HSTS" "$hsts_val"
        else
            print_warn "HSTS header not found"
            csv_warn "$category" "HSTS" "HSTS header missing"
        fi

        if echo "$https_headers" | grep -qi "Content-Security-Policy"; then
            local csp_val
            csp_val=$(echo "$https_headers" | grep -i "Content-Security-Policy" | head -1)
            print_success "CSP present: $csp_val"
            csv_success "$category" "CSP" "$csp_val"
        else
            csv_warn "$category" "CSP" "Content-Security-Policy missing"
        fi

        local https_status
        https_status=$(echo "$https_headers" | head -1 | grep -oE "[0-9]{3}" || echo "000")
        csv_info "$category" "HTTPS_Status" "Port 443 returned HTTP $https_status"
    else
        print_fail "No HTTPS response from port 443"
        csv_fail "$category" "HTTPS_Connectivity" "No response from port 443"
    fi
}

inventory_tls_certificate() {
    local target="$1"
    local domain
    domain=$(get_domain "$target")
    local port
    port=$(get_port "$target")
    [ "$port" = "443" ] && port="443"
    local category="TLS_Certificate"

    print_section "2. TLS/SSL CERTIFICATE ANALYSIS"
    csv_info "$category" "Section_Start" "Beginning TLS certificate analysis"

    print_subsection "2.1 Certificate Details"
    local cert_info
    cert_info=$(echo | openssl s_client -connect "$domain:$port" -servername "$domain" -showcerts 2>/dev/null | openssl x509 -noout -text 2>/dev/null || true)

    if [ -n "$cert_info" ]; then
        print_success "Certificate retrieved successfully"

        local subject issuer validity serial sig_algo pk_algo key_len san
        subject=$(echo "$cert_info" | grep "Subject:" | head -1 | sed 's/^[[:space:]]*/  /')
        issuer=$(echo "$cert_info" | grep "Issuer:" | head -1 | sed 's/^[[:space:]]*/  /')
        validity=$(echo "$cert_info" | grep -A2 "Validity" | grep -E "Not (Before|After)" | sed 's/^[[:space:]]*/  /')
        serial=$(echo "$cert_info" | grep "Serial Number" | head -1 | sed 's/^[[:space:]]*/  /')
        sig_algo=$(echo "$cert_info" | grep "Signature Algorithm" | head -1 | sed 's/^[[:space:]]*/  /')
        pk_algo=$(echo "$cert_info" | grep "Public Key Algorithm:" | head -1 | sed 's/^[[:space:]]*/  /')
        key_len=$(echo "$cert_info" | grep "RSA Public-Key:" | head -1 | sed 's/^[[:space:]]*/  /')
        san=$(echo "$cert_info" | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*/  /')

        echo -e "${CYAN}Subject:${NC} $subject"
        echo -e "${CYAN}Issuer:${NC} $issuer"
        echo -e "${CYAN}Validity:${NC} $validity"
        echo -e "${CYAN}Serial:${NC} $serial"
        echo -e "${CYAN}Signature:${NC} $sig_algo"
        echo -e "${CYAN}Public Key:${NC} $pk_algo"
        echo -e "${CYAN}Key Length:${NC} $key_len"
        echo -e "${CYAN}SAN:${NC} $san"

        csv_info "$category" "Subject" "$subject"
        csv_info "$category" "Issuer" "$issuer"
        csv_info "$category" "Validity" "$validity"
        csv_info "$category" "Serial" "$serial"
        csv_info "$category" "Signature_Algorithm" "$sig_algo"
        csv_info "$category" "Public_Key" "$pk_algo"
        csv_info "$category" "Key_Length" "$key_len"
        csv_info "$category" "SAN" "$san"

        if echo "$cert_info" | grep -q "Issuer:.*= $domain"; then
            print_warn "Certificate appears to be self-signed"
            csv_warn "$category" "Self_Signed" "Self-signed certificate detected"
        fi

        local not_after
        not_after=$(echo "$cert_info" | grep "Not After" | sed 's/.*Not After : //')
        if [ -n "$not_after" ]; then
            local expiry_epoch current_epoch days_until_expiry
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo "0")
            current_epoch=$(date +%s)
            days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

            if [ "$days_until_expiry" -lt 0 ]; then
                print_error "Certificate EXPIRED ${days_until_expiry#-} days ago!"
                csv_critical "$category" "Certificate_Expiry" "Expired ${days_until_expiry#-} days ago"
            elif [ "$days_until_expiry" -lt 30 ]; then
                print_warn "Certificate expires in $days_until_expiry days"
                csv_warn "$category" "Certificate_Expiry" "Expires in $days_until_expiry days"
            else
                print_success "Certificate valid for $days_until_expiry days"
                csv_success "$category" "Certificate_Expiry" "Valid for $days_until_expiry days"
            fi
        fi
    else
        print_fail "Could not retrieve certificate"
        csv_fail "$category" "Certificate_Retrieval" "TLS handshake failed"
    fi

    print_subsection "2.2 TLS Protocol and Cipher"
    local tls_info
    tls_info=$(echo | openssl s_client -connect "$domain:$port" -servername "$domain" 2>/dev/null || true)

    if [ -n "$tls_info" ]; then
        local protocol cipher verify_code
        protocol=$(echo "$tls_info" | grep "Protocol " | head -1 | sed 's/^[[:space:]]*/  /')
        cipher=$(echo "$tls_info" | grep "Cipher    :" | head -1 | sed 's/^[[:space:]]*/  /')

        echo -e "${CYAN}Protocol:${NC} $protocol"
        echo -e "${CYAN}Cipher:${NC} $cipher"

        csv_info "$category" "TLS_Protocol" "$protocol"
        csv_info "$category" "Cipher" "$cipher"

        if echo "$tls_info" | grep -q "TLS session ticket"; then
            print_success "Session tickets supported"
            csv_success "$category" "Session_Tickets" "Supported"
        fi

        verify_code=$(echo "$tls_info" | grep "Verify return code:" | sed 's/.*Verify return code: //')
        if [ -n "$verify_code" ]; then
            if echo "$verify_code" | grep -q "0 (ok)"; then
                print_success "Certificate verification: TRUSTED"
                csv_success "$category" "Verification" "Certificate trusted"
            else
                print_warn "Certificate verification: $verify_code"
                csv_warn "$category" "Verification" "$verify_code"
            fi
        fi
    else
        print_fail "TLS connection failed"
        csv_fail "$category" "TLS_Connection" "Connection failed"
    fi
}

inventory_tls_versions() {
    local target="$1"
    local domain
    domain=$(get_domain "$target")
    local port
    port=$(get_port "$target")
    [ "$port" = "443" ] && port="443"
    local category="TLS_Versions"

    print_section "3. TLS VERSION & CIPHER SUPPORT"
    csv_info "$category" "Section_Start" "Testing TLS version support"

    print_subsection "3.1 TLS Version Support"

    local versions=("tls1_3" "tls1_2" "tls1_1" "tls1")
    local version_names=("TLS 1.3" "TLS 1.2" "TLS 1.1" "TLS 1.0")

    for i in "${!versions[@]}"; do
        local version="${versions[$i]}"
        local name="${version_names[$i]}"

        local result
        result=$(echo | timeout 10 openssl s_client -connect "$domain:$port" -servername "$domain" "-$version" 2>/dev/null | grep "Protocol " || true)

        if [ -n "$result" ]; then
            if [ "$version" = "tls1_3" ] || [ "$version" = "tls1_2" ]; then
                print_success "$name: SUPPORTED"
                csv_success "$category" "$name" "Supported"
            else
                print_warn "$name: SUPPORTED (deprecated)"
                csv_warn "$category" "$name" "Supported but deprecated"
            fi
            echo "  $result" | sed 's/^[[:space:]]*/    /'
        else
            print_fail "$name: NOT SUPPORTED"
            csv_success "$category" "$name" "Not supported (good)"
        fi
    done

    print_subsection "3.2 Cipher Suite Analysis"

    local current_cipher
    current_cipher=$(echo | openssl s_client -connect "$domain:$port" -servername "$domain" 2>/dev/null | grep "Cipher    :" | head -1 | sed 's/.*Cipher    : //' || true)

    if [ -n "$current_cipher" ]; then
        echo -e "${CYAN}Negotiated Cipher:${NC} $current_cipher"

        if echo "$current_cipher" | grep -qiE "(NULL|EXPORT|DES|RC4|MD5|anon)"; then
            print_error "WEAK cipher detected: $current_cipher"
            csv_critical "$category" "Cipher_Strength" "Weak cipher: $current_cipher"
        elif echo "$current_cipher" | grep -qiE "(AES_256|AES_128|CHACHA20)"; then
            print_success "Strong cipher detected: $current_cipher"
            csv_success "$category" "Cipher_Strength" "Strong cipher: $current_cipher"
        else
            print_warn "Cipher strength unknown: $current_cipher"
            csv_warn "$category" "Cipher_Strength" "Unknown strength: $current_cipher"
        fi
    fi

    print_subsection "3.3 Forward Secrecy Check"
    local fs_cipher
    fs_cipher=$(echo | openssl s_client -connect "$domain:$port" -servername "$domain" -cipher 'ECDHE:DHE' 2>/dev/null | grep "Cipher    :" | head -1 || true)

    if [ -n "$fs_cipher" ]; then
        print_success "Forward Secrecy (ECDHE/DHE) supported"
        echo "  $fs_cipher"
        csv_success "$category" "Forward_Secrecy" "ECDHE/DHE supported"
    else
        print_warn "Forward Secrecy may not be available"
        csv_warn "$category" "Forward_Secrecy" "May not be available"
    fi
}

inventory_proxy_behavior() {
    local target="$1"
    local domain
    domain=$(get_domain "$target")
    local category="Proxy_Behavior"

    print_section "4. PROXY BEHAVIOR & HEADER ANALYSIS"
    csv_info "$category" "Section_Start" "Analyzing proxy behavior"

    print_subsection "4.1 Proxy Header Detection"

    local response
    response=$(curl -s -I --insecure --max-time "$TIMEOUT" -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" -H "X-Forwarded-For: 1.2.3.4" -H "X-Real-IP: 10.0.0.1" -H "X-Forwarded-Proto: https" "https://$target/" 2>/dev/null || true)

    if [ -n "$response" ]; then
        echo -e "${CYAN}Response headers when proxy headers injected:${NC}"
        echo "$response" | grep -E "^(HTTP|Server|Via|X-[^ :]+|Cache-Control|Age):" || true

        if echo "$response" | grep -qi "X-Forwarded"; then
            print_warn "Proxy may be reflecting X-Forwarded headers"
            csv_warn "$category" "Header_Reflection" "Proxy reflecting X-Forwarded headers"
        fi
    fi

    print_subsection "4.2 Via Header Analysis"
    local via_header
    via_header=$(curl -s -I --insecure --max-time "$TIMEOUT" "https://$target/" 2>/dev/null | grep -i "^Via:" || true)

    if [ -n "$via_header" ]; then
        print_info "Via header present: $via_header"
        if echo "$via_header" | grep -qi "nginx"; then
            print_success "Nginx identified in Via header"
            csv_success "$category" "Via_Header" "Nginx in Via: $via_header"
        else
            csv_info "$category" "Via_Header" "$via_header"
        fi
    else
        print_info "No Via header (headers may be stripped)"
        csv_info "$category" "Via_Header" "No Via header found"
    fi

    print_subsection "4.3 X-Cache / Cache Status"
    local cache_header
    cache_header=$(curl -s -I --insecure --max-time "$TIMEOUT" "https://$target/" 2>/dev/null | grep -iE "^(X-Cache|X-Cache-Status|CF-Cache-Status|X-Proxy-Cache):" || true)

    if [ -n "$cache_header" ]; then
        print_info "Cache status headers detected:"
        echo "$cache_header" | sed 's/^/  /'
        csv_info "$category" "Cache_Headers" "$cache_header"
    else
        print_info "No cache status headers found"
        csv_info "$category" "Cache_Headers" "No cache headers found"
    fi

    print_subsection "4.4 Backend IP Leakage Check"
    local body_content
    body_content=$(curl -s --insecure --max-time "$TIMEOUT" "https://$target/" 2>/dev/null | head -100 || true)

    local internal_ips
    internal_ips=$(echo "$body_content" | grep -oE '(192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)' | sort -u || true)

    if [ -n "$internal_ips" ]; then
        print_warn "Potential internal IP addresses leaked in response:"
        echo "$internal_ips" | sed 's/^/  /'
        csv_critical "$category" "IP_Leakage" "Internal IPs leaked: $internal_ips"
    else
        print_success "No obvious internal IP leakage detected"
        csv_success "$category" "IP_Leakage" "No internal IP leakage detected"
    fi
}

inventory_http_methods() {
    local target="$1"
    local category="HTTP_Methods"

    print_section "5. HTTP METHODS & OPTIONS"
    csv_info "$category" "Section_Start" "Testing HTTP methods"

    print_subsection "5.1 OPTIONS Method"
    local options_response
    options_response=$(curl -s -I -X OPTIONS --max-time "$TIMEOUT" "http://$target/" 2>/dev/null || true)

    if [ -n "$options_response" ]; then
        local allow_header
        allow_header=$(echo "$options_response" | grep -i "^Allow:" || true)
        if [ -n "$allow_header" ]; then
            print_success "OPTIONS method supported"
            echo "  $allow_header"
            csv_success "$category" "OPTIONS" "Supported: $allow_header"
        else
            print_info "OPTIONS responded but no Allow header"
            echo "$options_response" | head -3 | sed 's/^/  /'
            csv_info "$category" "OPTIONS" "No Allow header in response"
        fi
    else
        print_fail "OPTIONS method failed or blocked"
        csv_fail "$category" "OPTIONS" "Method failed or blocked"
    fi

    print_subsection "5.2 Common Methods Test"
    local methods=("GET" "HEAD" "POST" "PUT" "DELETE" "PATCH" "TRACE" "CONNECT")

    for method in "${methods[@]}"; do
        local method_response
        method_response=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" --max-time "$TIMEOUT" "http://$target/" 2>/dev/null || echo "000")

        printf "  %-10s HTTP %s
" "$method" "$method_response"

        if [ "$method_response" = "200" ] && [ "$method" = "TRACE" ]; then
            csv_critical "$category" "$method" "HTTP $method_response - XST Vulnerability"
        elif [ "$method_response" = "405" ]; then
            csv_success "$category" "$method" "HTTP $method_response - Blocked"
        elif [ "$method_response" = "000" ]; then
            csv_fail "$category" "$method" "Connection failed"
        else
            csv_info "$category" "$method" "HTTP $method_response"
        fi
    done

    print_subsection "5.3 TRACE Method (XST Check)"
    local trace_response
    trace_response=$(curl -s -I -X TRACE --max-time "$TIMEOUT" "http://$target/" 2>/dev/null || true)

    if [ -n "$trace_response" ]; then
        local trace_code
        trace_code=$(echo "$trace_response" | head -1 | grep -oE '[0-9]{3}' || echo "???")
        if [ "$trace_code" = "200" ]; then
            print_error "TRACE method returns 200 - Potential XST vulnerability!"
            csv_critical "$category" "TRACE" "HTTP 200 - XST vulnerability detected"
        else
            print_success "TRACE method blocked (HTTP $trace_code)"
            csv_success "$category" "TRACE" "Blocked with HTTP $trace_code"
        fi
    else
        print_success "TRACE method appears blocked"
        csv_success "$category" "TRACE" "Connection blocked"
    fi
}

inventory_virtual_hosts() {
    local target="$1"
    local domain
    domain=$(get_domain "$target")
    local port
    port=$(get_port "$target")
    [ "$port" = "443" ] && port="443"
    local category="Virtual_Host"

    print_section "6. VIRTUAL HOST & SNI ANALYSIS"
    csv_info "$category" "Section_Start" "Analyzing virtual host configuration"

    print_subsection "6.1 SNI Support Test"

    local with_sni
    with_sni=$(echo | openssl s_client -connect "$domain:$port" -servername "$domain" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null || true)

    local without_sni
    without_sni=$(echo | openssl s_client -connect "$domain:$port" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null || true)

    if [ -n "$with_sni" ] && [ -n "$without_sni" ]; then
        if [ "$with_sni" = "$without_sni" ]; then
            print_info "Same certificate with and without SNI"
            echo "  $with_sni"
            csv_info "$category" "SNI" "Same certificate with/without SNI"
        else
            print_success "Different certificates detected (SNI active)"
            echo -e "${CYAN}With SNI:${NC}"
            echo "  $with_sni"
            echo -e "${CYAN}Without SNI:${NC}"
            echo "  $without_sni"
            csv_success "$category" "SNI" "Multiple certificates - SNI active"
        fi
    elif [ -n "$with_sni" ]; then
        print_success "SNI supported, certificate found"
        echo "  $with_sni"
        csv_success "$category" "SNI" "SNI supported"
    else
        print_fail "Could not retrieve certificate for SNI analysis"
        csv_fail "$category" "SNI" "Certificate retrieval failed"
    fi

    print_subsection "6.2 Default Server Behavior"
    local ip_address
    ip_address=$(getent hosts "$domain" | awk '{print $1}' | head -1 || true)

    if [ -n "$ip_address" ]; then
        print_info "Resolved IP: $ip_address"
        csv_info "$category" "DNS_Resolution" "IP: $ip_address"

        local ip_response
        ip_response=$(curl -s -I --insecure --max-time "$TIMEOUT" -H "Host: $domain" "https://$ip_address/" 2>/dev/null || true)

        if [ -n "$ip_response" ]; then
            local ip_code
            ip_code=$(echo "$ip_response" | head -1 | grep -oE '[0-9]{3}' || echo "???")
            print_info "Direct IP access with Host header: HTTP $ip_code"
            csv_info "$category" "IP_Access" "Direct IP with Host header: HTTP $ip_code"
        fi

        local no_host_response
        no_host_response=$(curl -s -I --insecure --max-time "$TIMEOUT" "https://$ip_address/" 2>/dev/null || true)

        if [ -n "$no_host_response" ]; then
            local no_host_code
            no_host_code=$(echo "$no_host_response" | head -1 | grep -oE '[0-9]{3}' || echo "???")
            print_info "Direct IP access without Host header: HTTP $no_host_code"
            csv_info "$category" "IP_No_Host" "Direct IP without Host: HTTP $no_host_code"
        fi
    fi
}

inventory_error_pages() {
    local target="$1"
    local category="Error_Pages"

    print_section "7. ERROR PAGE FINGERPRINTING"
    csv_info "$category" "Section_Start" "Fingerprinting error pages"

    print_subsection "7.1 404 Not Found"
    local notfound_response
    notfound_response=$(curl -s --max-time "$TIMEOUT" "http://$target/thispagedoesnotexist$(date +%s)" 2>/dev/null || true)

    if [ -n "$notfound_response" ]; then
        local notfound_code
        notfound_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "http://$target/thispagedoesnotexist$(date +%s)" 2>/dev/null || echo "000")

        echo -e "${CYAN}HTTP Status:${NC} $notfound_code"
        echo -e "${CYAN}Response Length:${NC} ${#notfound_response} bytes"
        echo -e "${CYAN}First 5 lines:${NC}"
        echo "$notfound_response" | head -5 | sed 's/^/  /'

        csv_info "$category" "404_Status" "HTTP $notfound_code"
        csv_info "$category" "404_Size" "${#notfound_response} bytes"

        if echo "$notfound_response" | grep -qiE "(nginx|nginx/|Welcome to nginx)"; then
            print_warn "Nginx default/error page content detected"
            csv_warn "$category" "Nginx_Default_Page" "Default Nginx error page detected"
        fi

        local version_in_error
        version_in_error=$(echo "$notfound_response" | grep -oiE "nginx/[0-9]+\.[0-9]+\.[0-9]+" | head -1 || true)
        if [ -n "$version_in_error" ]; then
            print_warn "Nginx version exposed in error page: $version_in_error"
            csv_warn "$category" "Version_Exposure" "Version in error page: $version_in_error"
        fi
    else
        print_fail "No response for 404 test"
        csv_fail "$category" "404_Test" "No response"
    fi

    print_subsection "7.2 403 Forbidden Test"
    local forbidden_response
    forbidden_response=$(curl -s --max-time "$TIMEOUT" "http://$target/..%2f..%2fetc%2fpasswd" 2>/dev/null || true)

    if [ -n "$forbidden_response" ]; then
        local forbidden_code
        forbidden_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "http://$target/..%2f..%2fetc%2fpasswd" 2>/dev/null || echo "000")
        echo -e "${CYAN}HTTP Status for path traversal attempt:${NC} $forbidden_code"
        csv_info "$category" "403_Test" "Path traversal attempt: HTTP $forbidden_code"
    fi

    print_subsection "7.3 Directory Listing Test"
    local dirlist_response
    dirlist_response=$(curl -s --max-time "$TIMEOUT" "http://$target/images/" 2>/dev/null || true)

    if [ -n "$dirlist_response" ]; then
        if echo "$dirlist_response" | grep -qiE "(Index of|Directory listing|\[DIR\]|Parent Directory)"; then
            print_warn "Directory listing may be enabled"
            csv_warn "$category" "Directory_Listing" "Autoindex may be enabled on /images/"
        else
            print_success "Directory listing appears disabled"
            csv_success "$category" "Directory_Listing" "Autoindex appears disabled"
        fi
    fi
}

inventory_security_headers() {
    local target="$1"
    local category="Security_Headers"

    print_section "8. SECURITY HEADERS AUDIT"
    csv_info "$category" "Section_Start" "Auditing security headers"

    local headers
    headers=$(curl -s -I --insecure --max-time "$TIMEOUT" "https://$target/" 2>/dev/null || true)

    if [ -z "$headers" ]; then
        headers=$(curl -s -I --max-time "$TIMEOUT" "http://$target/" 2>/dev/null || true)
    fi

    if [ -n "$headers" ]; then
        local security_headers=(
            "Strict-Transport-Security:HSTS"
            "Content-Security-Policy:CSP"
            "X-Frame-Options:Clickjacking_Protection"
            "X-Content-Type-Options:MIME_Sniffing_Protection"
            "Referrer-Policy:Referrer_Policy"
            "Permissions-Policy:Permissions_Policy"
            "X-XSS-Protection:XSS_Filter"
            "Expect-CT:Certificate_Transparency"
        )

        for header_info in "${security_headers[@]}"; do
            local header_name="${header_info%%:*}"
            local header_desc="${header_info##*:}"

            local header_value
            header_value=$(echo "$headers" | grep -i "^$header_name:" || true)

            if [ -n "$header_value" ]; then
                print_success "$header_desc present"
                echo "  $header_value"
                csv_success "$category" "$header_desc" "$header_value"
            else
                print_warn "$header_desc missing"
                csv_warn "$category" "$header_desc" "Header missing"
            fi
        done

        local server_header
        server_header=$(echo "$headers" | grep -i "^Server:" || true)
        if [ -n "$server_header" ]; then
            echo ""
            echo -e "${CYAN}Server Header:${NC}"
            echo "  $server_header"

            if echo "$server_header" | grep -qiE "nginx/[0-9]+\.[0-9]+\.[0-9]+"; then
                print_warn "Nginx version exposed: $(echo "$server_header" | grep -oE "nginx/[0-9]+\.[0-9]+\.[0-9]+")"
                csv_warn "$category" "Server_Version" "Version exposed: $server_header"
            elif echo "$server_header" | grep -qi "nginx" && ! echo "$server_header" | grep -qiE "[0-9]+\.[0-9]+"; then
                print_success "Nginx version hidden"
                csv_success "$category" "Server_Version" "Version hidden"
            fi
        fi

        local powered_by
        powered_by=$(echo "$headers" | grep -i "^X-Powered-By:" || true)
        if [ -n "$powered_by" ]; then
            print_warn "X-Powered-By header exposes technology: $powered_by"
            csv_warn "$category" "X-Powered-By" "Technology exposed: $powered_by"
        fi
    else
        print_fail "Could not retrieve headers for security audit"
        csv_fail "$category" "Header_Retrieval" "Could not retrieve headers"
    fi
}

inventory_rate_limit_waf() {
    local target="$1"
    local category="Rate_Limit_WAF"

    print_section "9. RATE LIMITING & WAF DETECTION"
    csv_info "$category" "Section_Start" "Testing rate limiting and WAF"

    print_subsection "9.1 Rapid Request Test (10 requests)"
    local codes=()

    for i in {1..10}; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://$target/" 2>/dev/null || echo "000")
        codes+=("$code")
        sleep 0.1
    done

    echo -e "${CYAN}Response codes:${NC} ${codes[*]}"
    csv_info "$category" "Rapid_Requests" "Codes: ${codes[*]}"

    if echo "${codes[*]}" | grep -q "429"; then
        print_success "Rate limiting detected (HTTP 429)"
        csv_success "$category" "Rate_Limit" "HTTP 429 detected"
    elif echo "${codes[*]}" | grep -q "403"; then
        print_warn "Some requests blocked (HTTP 403) - possible WAF"
        csv_warn "$category" "WAF_Detection" "HTTP 403 responses detected"
    else
        print_info "No rate limiting detected in 10 rapid requests"
        csv_info "$category" "Rate_Limit" "No rate limiting in 10 requests"
    fi

    print_subsection "9.2 WAF/Security Filter Test"

    local suspicious_ua_response
    suspicious_ua_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" -A "sqlmap/1.0" "http://$target/" 2>/dev/null || echo "000")

    echo -e "${CYAN}Normal UA response:${NC} ${codes[0]}"
    echo -e "${CYAN}SQLMap UA response:${NC} $suspicious_ua_response"
    csv_info "$category" "SQLMap_UA" "Normal: ${codes[0]} SQLMap: $suspicious_ua_response"

    if [ "$suspicious_ua_response" != "${codes[0]}" ] && [ "$suspicious_ua_response" != "000" ]; then
        print_warn "Different response for suspicious User-Agent (WAF possible)"
        csv_warn "$category" "WAF_UA_Filter" "Different response for SQLMap UA"
    fi

    local sqli_response
    sqli_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "http://$target/?id=1' OR '1'='1" 2>/dev/null || echo "000")

    echo -e "${CYAN}SQLi pattern response:${NC} $sqli_response"
    csv_info "$category" "SQLi_Pattern" "Response: HTTP $sqli_response"

    if [ "$sqli_response" = "403" ] || [ "$sqli_response" = "406" ]; then
        print_warn "Request with SQLi pattern blocked - WAF likely active"
        csv_success "$category" "WAF_SQLi" "SQLi pattern blocked - WAF active"
    fi

    print_subsection "9.3 Request Size Limit Test"
    local large_data
    large_data=$(python3 -c 'print("A"*5000)' 2>/dev/null || printf '%*s' 5000 | tr ' ' 'A')

    local large_response
    large_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" -X POST -d "$large_data" "http://$target/" 2>/dev/null || echo "000")

    echo -e "${CYAN}Large POST (5KB) response:${NC} $large_response"
    csv_info "$category" "Size_Limit" "5KB POST response: HTTP $large_response"

    if [ "$large_response" = "413" ]; then
        print_info "Request size limit enforced (HTTP 413)"
        csv_success "$category" "Size_Limit" "HTTP 413 - Size limit enforced"
    fi
}

inventory_redirects() {
    local target="$1"
    local category="Redirects"

    print_section "10. REDIRECT & URL ANALYSIS"
    csv_info "$category" "Section_Start" "Analyzing redirects"

    print_subsection "10.1 HTTP to HTTPS Redirect"
    local redirect_chain
    redirect_chain=$(curl -s -L -I --max-time "$TIMEOUT" -w "
FINAL_URL:%{url_effective}
" "http://$target/" 2>/dev/null | grep -E "^(HTTP|Location:|FINAL_URL)" || true)

    if [ -n "$redirect_chain" ]; then
        echo -e "${CYAN}Redirect chain:${NC}"
        echo "$redirect_chain" | sed 's/^/  /'

        if echo "$redirect_chain" | grep -q "FINAL_URL:https://"; then
            print_success "HTTP redirects to HTTPS"
            csv_success "$category" "HTTP_to_HTTPS" "Redirect to HTTPS active"
        else
            csv_warn "$category" "HTTP_to_HTTPS" "No HTTPS redirect detected"
        fi
    else
        print_info "No redirect chain detected"
        csv_info "$category" "Redirects" "No redirect chain"
    fi

    print_subsection "10.2 WWW vs Non-WWW"
    local www_domain="www.$target"
    local www_response
    www_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "http://$www_domain/" 2>/dev/null || echo "000")

    echo -e "${CYAN}www.$target response:${NC} HTTP $www_response"
    csv_info "$category" "WWW_Test" "www.$target: HTTP $www_response"

    if [ "$www_response" = "200" ] || [ "$www_response" = "301" ] || [ "$www_response" = "302" ]; then
        print_info "www subdomain responds"
        csv_info "$category" "WWW_Available" "www subdomain responds"
    fi
}

inventory_robots_sitemap() {
    local target="$1"
    local category="Discovery"

    print_section "11. ROBOTS.TXT & SITEMAP"
    csv_info "$category" "Section_Start" "Checking robots.txt and sitemap"

    print_subsection "11.1 robots.txt"
    local robots
    robots=$(curl -s --max-time "$TIMEOUT" "http://$target/robots.txt" 2>/dev/null || true)

    if [ -n "$robots" ] && [ "${#robots}" -lt 5000 ]; then
        local robots_code
        robots_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "http://$target/robots.txt" 2>/dev/null || echo "000")

        if [ "$robots_code" = "200" ]; then
            print_success "robots.txt found"
            echo "$robots" | head -20 | sed 's/^/  /'
            csv_success "$category" "robots.txt" "Found and accessible"

            local sitemap_count
            sitemap_count=$(echo "$robots" | grep -ci "Sitemap:" || echo "0")
            if [ "$sitemap_count" -gt 0 ]; then
                print_info "Sitemap references found: $sitemap_count"
                csv_info "$category" "Sitemap_References" "$sitemap_count sitemap(s) referenced"
            fi

            local disallows
            disallows=$(echo "$robots" | grep -i "Disallow:" | head -10 | tr '
' '; ')
            if [ -n "$disallows" ]; then
                csv_info "$category" "Disallow_Entries" "$disallows"
            fi
        else
            print_info "robots.txt returned HTTP $robots_code"
            csv_info "$category" "robots.txt" "HTTP $robots_code"
        fi
    else
        print_info "robots.txt not found or too large"
        csv_info "$category" "robots.txt" "Not found"
    fi

    print_subsection "11.2 sitemap.xml"
    local sitemap
    sitemap=$(curl -s --max-time "$TIMEOUT" "http://$target/sitemap.xml" 2>/dev/null | head -20 || true)

    if [ -n "$sitemap" ]; then
        local sitemap_code
        sitemap_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "http://$target/sitemap.xml" 2>/dev/null || echo "000")

        if [ "$sitemap_code" = "200" ]; then
            print_success "sitemap.xml found"
            echo "$sitemap" | head -10 | sed 's/^/  /'
            csv_success "$category" "sitemap.xml" "Found and accessible"
        fi
    fi
}

inventory_ocsp_ct() {
    local target="$1"
    local domain
    domain=$(get_domain "$target")
    local port
    port=$(get_port "$target")
    [ "$port" = "443" ] && port="443"
    local category="Certificate_Features"

    print_section "12. OCSP & CERTIFICATE TRANSPARENCY"
    csv_info "$category" "Section_Start" "Checking OCSP and CT"

    print_subsection "12.1 OCSP Stapling"
    local ocsp_response
    ocsp_response=$(echo | openssl s_client -connect "$domain:$port" -servername "$domain" -status 2>/dev/null | grep -A5 "OCSP response" || true)

    if [ -n "$ocsp_response" ]; then
        print_success "OCSP Stapling supported"
        echo "$ocsp_response" | sed 's/^/  /'
        csv_success "$category" "OCSP_Stapling" "Supported"
    else
        print_info "OCSP Stapling not detected or not supported"
        csv_info "$category" "OCSP_Stapling" "Not detected"
    fi

    print_subsection "12.2 Certificate Transparency"
    local ct_info
    ct_info=$(echo | openssl s_client -connect "$domain:$port" -servername "$domain" 2>/dev/null | openssl x509 -noout -text 2>/dev/null | grep -A2 "CT Precertificate SCTs" || true)

    if [ -n "$ct_info" ]; then
        print_success "Certificate Transparency SCTs found"
        echo "$ct_info" | sed 's/^/  /'
        csv_success "$category" "Certificate_Transparency" "SCTs found"
    else
        print_info "No CT Precertificate SCTs found in certificate"
        csv_info "$category" "Certificate_Transparency" "No SCTs found"
    fi
}

inventory_performance() {
    local target="$1"
    local category="Performance"

    print_section "13. PERFORMANCE METRICS"
    csv_info "$category" "Section_Start" "Measuring performance"

    print_subsection "13.1 Response Timing"
    local timing_info
    timing_info=$(curl -s -o /dev/null -w "
DNS_Lookup: %{time_namelookup}s
TCP_Connect: %{time_connect}s
SSL_Handshake: %{time_appconnect}s
TTFB: %{time_starttransfer}s
Total_Time: %{time_total}s
HTTP_Code: %{http_code}
Size: %{size_download} bytes
" --insecure --max-time 30 "https://$target/" 2>/dev/null || true)

    if [ -n "$timing_info" ]; then
        echo "$timing_info" | sed 's/^/  /'

        local dns_time tcp_time ssl_time ttfb total_time http_code size
        dns_time=$(echo "$timing_info" | grep "DNS_Lookup:" | sed 's/.*: //')
        tcp_time=$(echo "$timing_info" | grep "TCP_Connect:" | sed 's/.*: //')
        ssl_time=$(echo "$timing_info" | grep "SSL_Handshake:" | sed 's/.*: //')
        ttfb=$(echo "$timing_info" | grep "TTFB:" | sed 's/.*: //')
        total_time=$(echo "$timing_info" | grep "Total_Time:" | sed 's/.*: //')
        http_code=$(echo "$timing_info" | grep "HTTP_Code:" | sed 's/.*: //')
        size=$(echo "$timing_info" | grep "Size:" | sed 's/.*: //')

        csv_info "$category" "DNS_Lookup" "$dns_time"
        csv_info "$category" "TCP_Connect" "$tcp_time"
        csv_info "$category" "SSL_Handshake" "$ssl_time"
        csv_info "$category" "TTFB" "$ttfb"
        csv_info "$category" "Total_Time" "$total_time"
        csv_info "$category" "Response_Size" "$size"
        csv_info "$category" "HTTP_Code" "$http_code"
    else
        print_fail "Could not measure timing"
        csv_fail "$category" "Timing" "Measurement failed"
    fi

    print_subsection "13.2 Compression Support"
    local gzip_response
    gzip_response=$(curl -s -I --compressed --max-time "$TIMEOUT" "http://$target/" 2>/dev/null | grep -i "content-encoding" || true)

    if [ -n "$gzip_response" ]; then
        print_success "Compression supported: $gzip_response"
        csv_success "$category" "Compression" "$gzip_response"
    else
        print_info "Compression not detected or not advertised"
        csv_info "$category" "Compression" "Not detected"
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

usage() {
    echo "Usage: $0 [OPTIONS] <target>"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -o, --output DIR    Save results to directory"
    echo "  -c, --csv FILE      Export results to CSV file (Excel compatible)"
    echo "  -t, --timeout SEC   Set timeout in seconds (default: 15)"
    echo "  -v, --verbose       Enable verbose output"
    echo ""
    echo "Examples:"
    echo "  $0 example.com"
    echo "  $0 -o ./results -c report.csv example.com"
    echo "  $0 -t 20 -c inventory.csv nginx-proxy.internal:8443"
    echo ""
    echo "Target format:"
    echo "  domain.com"
    echo "  domain.com:8080"
    echo "  192.168.1.100"
    echo "  192.168.1.100:8443"
    echo ""
    echo "CSV Export:"
    echo "  The CSV file can be opened directly in Excel, LibreOffice Calc, or Google Sheets."
    echo "  Columns: Category, Check, Status, Detail, Severity, Timestamp"
}

main() {
    local target=""
    local csv_path=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--csv)
                csv_path="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    if [ -z "$target" ]; then
        print_error "No target specified"
        usage
        exit 1
    fi

    print_banner
    check_dependencies
    target=$(validate_target "$target")

    print_info "Starting inventory for: $target"
    print_info "Timeout: ${TIMEOUT}s"

    if [ -n "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
        print_info "Results will be saved to: $OUTPUT_DIR"
    fi

    if [ -n "$csv_path" ]; then
        if [ -n "$OUTPUT_DIR" ] && [[ ! "$csv_path" =~ ^/ ]]; then
            csv_path="$OUTPUT_DIR/$csv_path"
        fi
        init_csv "$csv_path"
        print_info "CSV export enabled: $csv_path"
        print_info "Open in Excel: File -> Open -> Select CSV -> Delimited -> Comma"
    fi

    # Run all inventory modules
    inventory_basic_headers "$target"
    inventory_tls_certificate "$target"
    inventory_tls_versions "$target"
    inventory_proxy_behavior "$target"
    inventory_http_methods "$target"
    inventory_virtual_hosts "$target"
    inventory_error_pages "$target"
    inventory_security_headers "$target"
    inventory_rate_limit_waf "$target"
    inventory_redirects "$target"
    inventory_robots_sitemap "$target"
    inventory_ocsp_ct "$target"
    inventory_performance "$target"

    # Summary
    echo ""
    echo -e "${GREEN}${BOLD}===============================================================${NC}"
    echo -e "${GREEN}${BOLD}  INVENTORY COMPLETE${NC}"
    echo -e "${GREEN}${BOLD}===============================================================${NC}"
    echo -e "${GREEN}Target:${NC} $target"
    echo -e "${GREEN}Completed:${NC} $(date '+%Y-%m-%d %H:%M:%S')"

    if [ -n "$OUTPUT_DIR" ]; then
        echo -e "${GREEN}Output:${NC} $OUTPUT_DIR/"
    fi

    if [ -n "$CSV_FILE" ]; then
        echo -e "${GREEN}CSV Export:${NC} $CSV_FILE"
        echo ""
        echo -e "${CYAN}Excel Import Instructions:${NC}"
        echo "  1. Open Excel / LibreOffice Calc / Google Sheets"
        echo "  2. File -> Open -> Browse to $CSV_FILE"
        echo "  3. Select 'Delimited' -> Next"
        echo "  4. Check 'Comma' -> Next -> Finish"
        echo ""
        echo -e "${CYAN}CSV Columns:${NC}"
        echo "  Category | Check | Status | Detail | Severity | Timestamp"
        echo ""
        echo -e "${CYAN}Pivot Table Suggestion:${NC}"
        echo "  Create pivot table with:"
        echo "    Rows: Category"
        echo "    Columns: Status"
        echo "    Values: Count of Check"
    fi

    echo ""
    echo -e "${YELLOW}Note: This tool uses only curl and openssl - no additional packages required.${NC}"
}

# Run main function
main "$@"
