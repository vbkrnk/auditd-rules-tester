#!/bin/bash
# ==============================================================================
# auditd Rules Testing Script by vbkrnk
# Version: 2.0
# Description: Automatically reads all active auditd rules via auditctl -l,
#              generates corresponding OS events to trigger each rule, and
#              produces a structured TXT report with rule <-> log pairs.
# Supports: CentOS, Oracle Linux, Ubuntu
# Usage: sudo ./auditd_rules_tester_v2.sh
# ==============================================================================

REPORT_FILE="./audit_test_report_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
SLEEP_AFTER_ACTION=1
RULES_FILE="/tmp/auditd_active_rules_$$.txt"
ACTED_FILE="/tmp/auditd_acted_$$.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "$1"; }
info() { log "${GREEN}[INFO]${NC} $1"; }
warn() { log "${YELLOW}[WARN]${NC} $1"; }
err()  { log "${RED}[ERR]${NC} $1"; }
step() { log "${CYAN}[....] $1${NC}"; }

# ==============================================================================
# PREREQUISITES
# ==============================================================================
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root!"
        exit 1
    fi
    if ! command -v auditctl &>/dev/null; then
        err "auditctl not found. Please install the audit/auditd package."
        exit 1
    fi
    if ! auditctl -l &>/dev/null; then
        err "auditctl -l failed. Is auditd running?"
        exit 1
    fi
    if [[ ! -f /var/log/audit/audit.log ]]; then
        warn "/var/log/audit/audit.log not found. Log search will be limited."
    fi
    touch "$ACTED_FILE"
    info "Prerequisites check passed."
}

# ==============================================================================
# LOAD ACTIVE RULES FROM AUDITCTL
# ==============================================================================
load_active_rules() {
    info "Loading active rules via auditctl -l ..."
    auditctl -l 2>/dev/null | grep -v '^No rules' | grep -v '^List of rules' > "$RULES_FILE" || true
    local count
    count=$(wc -l < "$RULES_FILE")
    if [[ "$count" -eq 0 ]]; then
        warn "No active auditd rules found via auditctl -l. Trying rules files..."
        for rdir in /etc/audit/rules.d /etc/audit/audit.rules; do
            if [[ -d "$rdir" ]]; then
                grep -h '^-' "$rdir"/*.rules 2>/dev/null >> "$RULES_FILE" || true
            elif [[ -f "$rdir" ]]; then
                grep '^-' "$rdir" 2>/dev/null >> "$RULES_FILE" || true
            fi
        done
        count=$(wc -l < "$RULES_FILE")
    fi
    info "Rules loaded: $count"
}

# ==============================================================================
# REPORT HELPERS
# ==============================================================================
write_report_header() {
    cat >> "$REPORT_FILE" << EOF
================================================================================
  auditd Rules Testing Script by vbkrnk
  Host:    $(hostname)
  Date:    $(date '+%Y-%m-%d %H:%M:%S')
  OS:      $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -a)
  Rules:   $(wc -l < "$RULES_FILE") (loaded from this host via auditctl -l)
================================================================================

EOF
}

write_rule_result() {
    local rule="$1"
    local log_line="$2"
    printf -- "--------------------------------------------------------------------------------\n" >> "$REPORT_FILE"
    printf "RULE:\n  %s\n\nLOG (confirmation that the rule triggered):\n%s\n\n" \
        "$rule" "$log_line" >> "$REPORT_FILE"
}

# ==============================================================================
# AUDIT LOG SEARCH
# ==============================================================================
get_audit_log_by_key() {
    local key="$1"
    local result=""
    if command -v ausearch &>/dev/null; then
        result=$(ausearch -k "$key" --start recent 2>/dev/null | grep -v '^----' | tail -6 || true)
    fi
    if [[ -z "$result" ]] && [[ -f /var/log/audit/audit.log ]]; then
        result=$(grep "key=\"$key\"\|key=$key" /var/log/audit/audit.log 2>/dev/null | tail -3 || true)
    fi
    if [[ -z "$result" ]]; then
        result="  [NO ENTRY IN AUDIT LOG — rule did not trigger or event was not generated]"
    else
        result=$(echo "$result" | sed 's/^/  /')
    fi
    echo "$result"
}

get_audit_log_by_path() {
    local path="$1"
    local result=""
    if [[ -f /var/log/audit/audit.log ]]; then
        result=$(grep "name=\"$path\"\|exe=\"$path\"" /var/log/audit/audit.log 2>/dev/null | tail -3 || true)
    fi
    if [[ -z "$result" ]]; then
        result="  [NO ENTRY IN AUDIT LOG]"
    else
        result=$(echo "$result" | sed 's/^/  /')
    fi
    echo "$result"
}

flush_audit() {
    sleep "$SLEEP_AFTER_ACTION"
    auditctl -f 1 &>/dev/null || true
}

already_acted() {
    grep -qF "$1" "$ACTED_FILE" 2>/dev/null
}
mark_acted() {
    echo "$1" >> "$ACTED_FILE"
}

# ==============================================================================
# TRIGGER EVENT FOR A FILE PATH
# ==============================================================================
trigger_file_path() {
    local path="$1"
    local perm="$2"

    if already_acted "${path}:${perm}"; then
        return
    fi
    mark_acted "${path}:${perm}"

    if [[ -f "$path" ]]; then
        if [[ "$perm" == *"x"* ]]; then
            stat "$path" &>/dev/null || true
            head -c 4 "$path" &>/dev/null || true
        fi
        if [[ "$perm" == *"r"* ]]; then
            cat "$path" &>/dev/null || true
        fi
        if [[ "$perm" == *"w"* ]] || [[ "$perm" == *"a"* ]]; then
            touch -a "$path" &>/dev/null || true
        fi
    elif [[ -d "$path" ]]; then
        if [[ "$perm" == *"w"* ]] || [[ "$perm" == *"a"* ]]; then
            local tmpf="$path/.auditd_probe_$$"
            touch "$tmpf" 2>/dev/null && rm -f "$tmpf" 2>/dev/null || true
        fi
        if [[ "$perm" == *"r"* ]] || [[ "$perm" == *"x"* ]]; then
            ls "$path" &>/dev/null || true
        fi
    fi
}

# ==============================================================================
# TRIGGER EVENT FOR SYSCALL RULES
# ==============================================================================
trigger_syscall() {
    local syscall="$1"
    local key="$2"
    local extra_filters="$3"

    if already_acted "syscall:${syscall}:${key}"; then
        return
    fi
    mark_acted "syscall:${syscall}:${key}"

    case "$syscall" in
        execve|execveat)
            /bin/ls /tmp &>/dev/null || true
            ;;
        kill|"kill,exit_group"|"exit_group,kill"|exit_group)
            /bin/kill -0 $$ &>/dev/null || true
            ;;
        mount)
            : # unsafe to trigger — checking existing log entries only
            ;;
        rename|unlink|unlinkat|renameat|"rename,unlink,unlinkat,renameat")
            local td
            td=$(mktemp -d /tmp/auditd_probe_XXXXX)
            touch "$td/f_$$"
            rm -f "$td/f_$$"
            rmdir "$td"
            ;;
        connect)
            if echo "$extra_filters" | grep -q 'a2=0x1C'; then
                python3 -c "
import socket
try:
    s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    s.settimeout(0.1); s.connect(('::1', 19753, 0, 0))
except: pass
finally:
    try: s.close()
    except: pass
" &>/dev/null 2>&1 || true
            else
                python3 -c "
import socket
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.1); s.connect(('127.0.0.1', 19753))
except: pass
finally:
    try: s.close()
    except: pass
" &>/dev/null 2>&1 || true
            fi
            ;;
        sethostname|setdomainname|"sethostname,setdomainname")
            python3 -c "
import socket, ctypes
libc = ctypes.CDLL(None, use_errno=True)
name = socket.gethostname().encode()
libc.sethostname(name, len(name))
" &>/dev/null 2>&1 || true
            ;;
        setuid)
            python3 -c "
import ctypes
try:
    ctypes.CDLL(None).setuid(0)
except: pass
" &>/dev/null 2>&1 || true
            ;;
        reboot)
            : # unsafe to trigger — checking existing log entries only
            ;;
        *)
            /bin/ls /tmp &>/dev/null || true
            ;;
    esac
}

# ==============================================================================
# PARSE KEY FROM RULE (supports both -k <key> and -F key=<key>)
# ==============================================================================
parse_key() {
    local rule="$1"
    local key
    key=$(echo "$rule" | grep -oP '(?<=-k )\S+' | head -1)
    [[ -z "$key" ]] && key=$(echo "$rule" | grep -oP '(?<=-F key=)\S+' | head -1)
    echo "$key"
}

# ==============================================================================
# PROCESS A SINGLE RULE LINE
# ==============================================================================
process_rule() {
    local rule="$1"
    local log_entry=""

    [[ -z "$rule" ]] && return
    [[ "$rule" =~ ^[[:space:]]*# ]] && return
    [[ "$rule" =~ ^-[Dbe][[:space:]] ]] && return
    [[ "$rule" =~ ^-[Dbe]$ ]] && return

    # ---------------------------------------------------------------
    # WATCH RULE: -w <path> -p <perms> [-k <key>]
    # ---------------------------------------------------------------
    if [[ "$rule" =~ ^-w[[:space:]] ]]; then
        local watch_path perm key

        watch_path=$(echo "$rule" | grep -oP '(?<=-w )\S+')
        perm=$(echo "$rule" | grep -oP '(?<=-p )\S+')
        [[ -z "$perm" ]] && perm="wa"
        key=$(parse_key "$rule")

        if [[ -z "$watch_path" ]]; then
            write_rule_result "$rule" "  [PARSE ERROR: could not extract path]"
            return
        fi

        if [[ ! -e "$watch_path" ]]; then
            write_rule_result "$rule" "  [PATH $watch_path DOES NOT EXIST ON THIS OS — rule not applicable]"
            return
        fi

        trigger_file_path "$watch_path" "$perm"
        flush_audit

        if [[ -n "$key" ]]; then
            log_entry=$(get_audit_log_by_key "$key")
        else
            log_entry=$(get_audit_log_by_path "$watch_path")
        fi
        write_rule_result "$rule" "$log_entry"
        return
    fi

    # ---------------------------------------------------------------
    # SYSCALL RULE: -a <action>,<list> -S <syscalls> [-F ...] [-k <key>]
    # ---------------------------------------------------------------
    if [[ "$rule" =~ ^-a[[:space:]] ]]; then
        local action syscalls key path_filter perm_filter extra_filters

        action=$(echo "$rule" | grep -oP '(?<=-a )\S+')

        if [[ "$action" =~ ^never ]]; then
            write_rule_result "$rule" "  [NEVER rule — events are intentionally suppressed, no log entries expected]"
            return
        fi

        syscalls=$(echo "$rule" | grep -oP '(?<=-S )\S+')
        [[ -z "$syscalls" ]] && syscalls="all"

        key=$(parse_key "$rule")
        path_filter=$(echo "$rule" | grep -oP '(?<=-F path=)\S+' | head -1)
        perm_filter=$(echo "$rule" | grep -oP '(?<=-F perm=)\S+' | head -1)
        extra_filters=$(echo "$rule" | grep -oP '(-F \S+\s*)+' || true)

        if [[ -n "$path_filter" ]]; then
            if [[ ! -e "$path_filter" ]]; then
                write_rule_result "$rule" "  [PATH $path_filter DOES NOT EXIST ON THIS OS — rule not applicable]"
                return
            fi
            trigger_file_path "$path_filter" "${perm_filter:-x}"
            flush_audit
            if [[ -n "$key" ]]; then
                log_entry=$(get_audit_log_by_key "$key")
            else
                log_entry=$(get_audit_log_by_path "$path_filter")
            fi
            write_rule_result "$rule" "$log_entry"
            return
        fi

        trigger_syscall "$syscalls" "$key" "$extra_filters"
        flush_audit

        if [[ -n "$key" ]]; then
            log_entry=$(get_audit_log_by_key "$key")
        else
            log_entry="  [NO KEY (-k or -F key=) FOUND — cannot search audit log]"
        fi
        write_rule_result "$rule" "$log_entry"
        return
    fi

    write_rule_result "$rule" "  [RULE TYPE NOT RECOGNIZED — skipped]"
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     auditd Rules Testing Script by vbkrnk  v2.0         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    load_active_rules

    local total_rules
    total_rules=$(wc -l < "$RULES_FILE")

    if [[ "$total_rules" -eq 0 ]]; then
        err "No rules found. Exiting."
        exit 1
    fi

    > "$REPORT_FILE"
    write_report_header

    info "Starting test of $total_rules rules..."
    echo ""

    local idx=0
    while IFS= read -r rule; do
        [[ -z "${rule// }" ]] && continue
        [[ "$rule" =~ ^[[:space:]]*# ]] && continue
        [[ "$rule" =~ ^-[Dbe][[:space:]] ]] && continue
        [[ "$rule" =~ ^-[Dbe]$ ]] && continue

        idx=$((idx + 1))
        step "[$idx/$total_rules] $rule"
        process_rule "$rule"
    done < "$RULES_FILE"

    local confirmed not_exist never_rules no_log
    confirmed=$(grep -c 'type=SYSCALL\|type=PATH\|type=EXECVE\|type=CWD\|msg=audit' "$REPORT_FILE" 2>/dev/null || echo 0)
    not_exist=$(grep -c 'DOES NOT EXIST' "$REPORT_FILE" 2>/dev/null || echo 0)
    never_rules=$(grep -c 'NEVER rule' "$REPORT_FILE" 2>/dev/null || echo 0)
    no_log=$(grep -c 'NO ENTRY IN AUDIT LOG\|NO KEY' "$REPORT_FILE" 2>/dev/null || echo 0)

    cat >> "$REPORT_FILE" << EOF

================================================================================
  SUMMARY
  Total rules tested:             $idx
  Confirmed (log entries found):  $confirmed
  Not applicable (no path/dir):   $not_exist
  NEVER rules (suppressed):       $never_rules
  No log entry (did not trigger): $no_log
  Completed:                      $(date '+%Y-%m-%d %H:%M:%S')
================================================================================
EOF

    echo ""
    echo "════════════════════════════════════════════════════"
    info "Testing complete!"
    info "Report saved: $REPORT_FILE"
    echo "  Rules tested:            $idx"
    echo "  Not applicable (no path): $not_exist"
    echo "  NEVER rules:             $never_rules"
    echo "  No log entry:            $no_log"
    echo "════════════════════════════════════════════════════"

    rm -f "$RULES_FILE" "$ACTED_FILE"
}

main "$@"
