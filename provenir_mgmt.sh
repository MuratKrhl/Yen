#!/bin/sh
##############################################################################
# PROVENIR SERVICE MANAGEMENT CONSOLE
# Version : 2.0
# Platform : AIX / Linux (POSIX sh)
# Author   : Middleware Engineering
##############################################################################

##############################################################################
# ANSI COLORS
##############################################################################
RED=$(printf '\033[38;5;196m')
GREEN=$(printf '\033[38;5;82m')
YELLOW=$(printf '\033[38;5;220m')
BLUE=$(printf '\033[38;5;39m')
CYAN=$(printf '\033[38;5;51m')
MAGENTA=$(printf '\033[38;5;171m')
ORANGE=$(printf '\033[38;5;208m')
GRAY=$(printf '\033[38;5;240m')
WHITE=$(printf '\033[38;5;255m')
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
RESET=$(printf '\033[0m')

##############################################################################
# CONFIG
##############################################################################
PROV_SERVICE="prov7adm"
TOMCAT_SERVICE="tomcat"
HTTPD_BIN="/usr/IBMIHS/bin/apachectl"
FILEBEAT_SERVICE="filebeat"

PROV_USER="prov7adm"
TOMCAT_USER="was"
HTTPD_USER="www"

DUMP_DIR="/sw/WAS_IMAGES/MuratK/Provenir"
PROV_LOG="/vhosting/log/provenir/adminserverd.log"
TOMCAT_LOG="/var/log/tomcat/catalina.out"

AUDIT_LOG="/sw/WAS_IMAGES/MuratK/Provenir/audit.log"
HOSTNAME=$(hostname)
OPERATOR=$(id -un)

VERIFY_WAIT=5
VERIFY_RETRIES=3

##############################################################################
# AUDIT LOG
##############################################################################
audit_log() {
    ACTION="$1"
    TARGET="$2"
    RESULT="$3"
    DURATION="$4"
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$DUMP_DIR" 2>/dev/null
    printf "%s | operator=%-10s | action=%-20s | target=%-10s | result=%-8s | duration=%s\n" \
        "$TS" "$OPERATOR" "$ACTION" "$TARGET" "$RESULT" "$DURATION" >> "$AUDIT_LOG" 2>/dev/null
}

##############################################################################
# UI HELPERS
##############################################################################
clear_screen() { clear; }

color_bar() {
    PERCENT="$1"
    COLOR="$2"
    FILL=$(( PERCENT / 5 ))
    EMPTY=$(( 20 - FILL ))
    printf "%b" "$COLOR"
    i=0; while [ $i -lt $FILL ]; do printf "█"; i=$(( i + 1 )); done
    printf "%b" "$GRAY"
    i=0; while [ $i -lt $EMPTY ]; do printf "░"; i=$(( i + 1 )); done
    printf "%b" "$RESET"
}

progress_bar() {
    LABEL="$1"
    STEPS="${2:-20}"
    SLEEP="${3:-0.1}"
    printf "  %b%s%b %b[%b" "$CYAN" "$LABEL" "$RESET" "$BLUE" "$RESET"
    i=0
    while [ $i -lt $STEPS ]; do
        printf "%b█%b" "$GREEN" "$RESET"
        sleep "$SLEEP" 2>/dev/null || sleep 1
        i=$(( i + 1 ))
    done
    printf "%b]%b\n" "$BLUE" "$RESET"
}

title_bar() {
    TITLE="$1"
    WIDTH=82
    clear_screen
    printf "%b" "$CYAN$BOLD"
    printf "╔"
    i=0; while [ $i -lt $WIDTH ]; do printf "═"; i=$(( i + 1 )); done
    printf "╗\n"
    PADDING=$(( ( WIDTH - ${#TITLE} ) / 2 ))
    printf "║"
    i=0; while [ $i -lt $PADDING ]; do printf " "; i=$(( i + 1 )); done
    printf "%b%s%b%b" "$WHITE$BOLD" "$TITLE" "$RESET" "$CYAN$BOLD"
    RPAD=$(( WIDTH - PADDING - ${#TITLE} ))
    i=0; while [ $i -lt $RPAD ]; do printf " "; i=$(( i + 1 )); done
    printf "║\n"
    printf "╚"
    i=0; while [ $i -lt $WIDTH ]; do printf "═"; i=$(( i + 1 )); done
    printf "╝\n"
    printf "%b" "$RESET"
    printf "\n"
}

section_line() {
    printf "%b" "$GRAY"
    printf "  ──────────────────────────────────────────────────────────────────────────\n"
    printf "%b" "$RESET"
}

pause_screen() {
    printf "\n"
    printf "  %b Press ENTER to return to menu...%b" "$DIM" "$RESET"
    read dummy
}

##############################################################################
# JAVA_HOME AUTO-DISCOVERY
##############################################################################
# Tries multiple strategies to find JAVA_HOME for a given process user.
# Strategy 1: Read from /proc/<pid>/environ
# Strategy 2: Read from user's profile via su -c
# Strategy 3: which java fallback
##############################################################################
discover_java_home() {
    SERVICE_USER="$1"
    PID="$2"

    FOUND_JAVA=""

    # Strategy 1: /proc environ (Linux)
    if [ -n "$PID" ] && [ -f "/proc/$PID/environ" ]; then
        FOUND_JAVA=$(tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep "^JAVA_HOME=" | cut -d'=' -f2-)
    fi

    # Strategy 2: AIX /proc
    if [ -z "$FOUND_JAVA" ] && [ -n "$PID" ]; then
        FOUND_JAVA=$(dzdo su - "$SERVICE_USER" -c "cat /proc/$PID/environ 2>/dev/null | tr '\0' '\n' | grep JAVA_HOME | cut -d= -f2-" 2>/dev/null)
    fi

    # Strategy 3: User environment profile
    if [ -z "$FOUND_JAVA" ] && [ -n "$SERVICE_USER" ]; then
        FOUND_JAVA=$(dzdo su - "$SERVICE_USER" -c 'echo $JAVA_HOME' 2>/dev/null)
    fi

    # Strategy 4: which java
    if [ -z "$FOUND_JAVA" ]; then
        JAVA_BIN=$(dzdo su - "$SERVICE_USER" -c 'which java 2>/dev/null' 2>/dev/null)
        if [ -n "$JAVA_BIN" ]; then
            FOUND_JAVA=$(dirname "$(dirname "$JAVA_BIN")")
        fi
    fi

    printf "%s" "$FOUND_JAVA"
}

##############################################################################
# PID HELPERS
##############################################################################
get_pid() {
    SERVICE="$1"
    case "$SERVICE" in
        provenir)
            ps -ef | grep -v grep | grep "$PROV_SERVICE" | awk 'NR==1{print $2}' ;;
        tomcat)
            ps -ef | grep -v grep | grep "[Cc]atalina" | awk 'NR==1{print $2}' ;;
        httpd)
            ps -ef | grep -v grep | grep "httpd" | grep -v apachectl | awk 'NR==1{print $2}' ;;
        filebeat)
            ps -ef | grep -v grep | grep "filebeat" | awk 'NR==1{print $2}' ;;
    esac
}

get_all_pids() {
    SERVICE="$1"
    case "$SERVICE" in
        provenir)
            ps -ef | grep -v grep | grep "$PROV_SERVICE" | awk '{print $2}' ;;
        tomcat)
            ps -ef | grep -v grep | grep "[Cc]atalina" | awk '{print $2}' ;;
    esac
}

##############################################################################
# METRICS
##############################################################################
get_metric() {
    PID="$1"
    FIELD="$2"
    if [ -z "$PID" ] || [ "$PID" = "-" ]; then
        printf -- "-"
        return
    fi
    ps -p "$PID" -o "$FIELD=" 2>/dev/null | tr -d ' '
}

get_thread_count() {
    PID="$1"
    if [ -z "$PID" ]; then printf "0"; return; fi
    # Linux
    COUNT=$(ls /proc/"$PID"/task 2>/dev/null | wc -l | tr -d ' ')
    if [ -z "$COUNT" ] || [ "$COUNT" = "0" ]; then
        COUNT=$(ps -p "$PID" -o nlwp= 2>/dev/null | tr -d ' ')
    fi
    printf "%s" "${COUNT:--}"
}

get_uptime_str() {
    PID="$1"
    if [ -z "$PID" ]; then printf "-"; return; fi
    ETIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ')
    printf "%s" "${ETIME:--}"
}

##############################################################################
# SERVICE ROW (for dashboard)
##############################################################################
service_row() {
    NAME="$1"
    LABEL="$2"
    PID=$(get_pid "$NAME")

    if [ -n "$PID" ]; then
        STATUS="RUNNING"
        CPU=$(get_metric "$PID" "pcpu")
        MEM=$(get_metric "$PID" "pmem")
        THREADS=$(get_thread_count "$PID")
        UPTIME=$(get_uptime_str "$PID")
        OWNER=$(get_metric "$PID" "user")
        STATUS_COLOR="$GREEN"
        DOT="●"
    else
        STATUS="STOPPED"
        PID="-"; CPU="-"; MEM="-"; THREADS="-"; UPTIME="-"; OWNER="-"
        STATUS_COLOR="$RED"
        DOT="○"
    fi

    printf "  %b%s%b %-12s" "$STATUS_COLOR$BOLD" "$DOT" "$RESET" "$LABEL"
    printf " %b%-10s%b" "$STATUS_COLOR$BOLD" "$STATUS" "$RESET"
    printf " PID=%b%-8s%b" "$CYAN" "$PID" "$RESET"
    printf " CPU=%b%-6s%b" "$YELLOW" "$CPU%" "$RESET"
    printf " MEM=%b%-6s%b" "$BLUE" "$MEM%" "$RESET"
    printf " THR=%b%-5s%b" "$MAGENTA" "$THREADS" "$RESET"
    printf " UP=%b%s%b\n" "$GRAY" "$UPTIME" "$RESET"
}

##############################################################################
# DASHBOARD
##############################################################################
dashboard() {
    title_bar "PROVENIR SERVICE DASHBOARD"

    HOST=$(hostname)
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    LOAD=$(uptime 2>/dev/null | sed 's/.*load average:/load:/')

    printf "  %bHOST%b  : %b%s%b\n" "$CYAN$BOLD" "$RESET" "$WHITE" "$HOST" "$RESET"
    printf "  %bDATE%b  : %b%s%b\n" "$CYAN$BOLD" "$RESET" "$WHITE" "$NOW" "$RESET"
    printf "  %bOPER%b  : %b%s%b\n" "$CYAN$BOLD" "$RESET" "$YELLOW" "$OPERATOR" "$RESET"
    printf "  %bSYS%b   : %b%s%b\n" "$CYAN$BOLD" "$RESET" "$GRAY" "$LOAD" "$RESET"
    printf "\n"
    section_line

    printf "  %b%-12s %-10s %-10s %-8s %-8s %-5s %-12s%b\n" \
        "$BOLD$WHITE" "SERVICE" "STATUS" "PID" "CPU%" "MEM%" "THR" "UPTIME" "$RESET"
    section_line

    service_row "provenir" "prov7adm"
    service_row "tomcat"   "tomcat"
    service_row "httpd"    "httpd(IHS)"
    service_row "filebeat" "filebeat"

    section_line
    printf "\n"
}

##############################################################################
# PROCESS VERIFY LOOP
# Checks after stop/start and retries up to VERIFY_RETRIES times
##############################################################################
verify_stopped() {
    SERVICE="$1"
    LABEL="$2"
    printf "\n  %bWaiting %ss for process to terminate...%b\n" "$YELLOW" "$VERIFY_WAIT" "$RESET"
    sleep "$VERIFY_WAIT"

    i=1
    while [ $i -le $VERIFY_RETRIES ]; do
        printf "  %b[Verify %d/%d]%b " "$CYAN" "$i" "$VERIFY_RETRIES" "$RESET"
        progress_bar "Checking process..." 10 0.1
        PID=$(get_pid "$SERVICE")
        if [ -z "$PID" ]; then
            printf "\n  %b✔ %s STOPPED.%b Process not found. Tüm process'ler temizlendi.\n" \
                "$GREEN$BOLD" "$LABEL" "$RESET"
            return 0
        else
            printf "  %b⚠ Process still alive: PID=%s. Bekleniyor...%b\n" "$YELLOW" "$PID" "$RESET"
            sleep 3
        fi
        i=$(( i + 1 ))
    done

    printf "\n  %b✘ %s STOP FAILED.%b PID=%s hala aktif. Manuel müdahale gerekebilir.\n" \
        "$RED$BOLD" "$LABEL" "$RESET" "$PID"
    return 1
}

verify_started() {
    SERVICE="$1"
    LABEL="$2"
    printf "\n  %bWaiting %ss for process to initialize...%b\n" "$YELLOW" "$VERIFY_WAIT" "$RESET"
    sleep "$VERIFY_WAIT"

    i=1
    while [ $i -le $VERIFY_RETRIES ]; do
        printf "  %b[Verify %d/%d]%b " "$CYAN" "$i" "$VERIFY_RETRIES" "$RESET"
        progress_bar "Checking process..." 10 0.1
        PID=$(get_pid "$SERVICE")
        if [ -n "$PID" ]; then
            CPU=$(get_metric "$PID" "pcpu")
            MEM=$(get_metric "$PID" "pmem")
            THR=$(get_thread_count "$PID")
            printf "\n  %b✔ %s RUNNING!%b\n" "$GREEN$BOLD" "$LABEL" "$RESET"
            printf "  %b  PID=%-8s CPU=%-6s MEM=%-6s THREADS=%s%b\n" \
                "$CYAN" "$PID" "${CPU}%" "${MEM}%" "$THR" "$RESET"
            return 0
        else
            printf "  %b⚠ Process henüz başlamadı. Bekleniyor...%b\n" "$YELLOW" "$RESET"
            sleep 3
        fi
        i=$(( i + 1 ))
    done

    printf "\n  %b✘ %s START FAILED.%b Process bulunamadı. Log dosyasını kontrol edin.\n" \
        "$RED$BOLD" "$LABEL" "$RESET"
    return 1
}

##############################################################################
# RUN COMMAND WITH USER SWITCH
##############################################################################
run_command() {
    TITLE="$1"
    CMD="$2"
    RUN_USER="$3"
    START_TIME=$(date '+%s' 2>/dev/null || echo 0)

    title_bar "$TITLE"
    section_line
    printf "  %bCommand  :%b %b%s%b\n" "$CYAN$BOLD" "$RESET" "$WHITE" "$CMD" "$RESET"
    printf "  %bRun As   :%b %b%s%b\n" "$CYAN$BOLD" "$RESET" "$YELLOW" "${RUN_USER:-$(id -un)}" "$RESET"
    printf "  %bOperator :%b %b%s%b\n" "$CYAN$BOLD" "$RESET" "$GRAY" "$OPERATOR" "$RESET"
    section_line
    printf "\n"

    if [ -n "$RUN_USER" ]; then
        dzdo su - "$RUN_USER" -c "$CMD"
    else
        dzdo sh -c "$CMD"
    fi

    RET=$?
    END_TIME=$(date '+%s' 2>/dev/null || echo 0)
    DURATION=$(( END_TIME - START_TIME ))

    printf "\n"
    section_line
    if [ "$RET" -eq 0 ]; then
        printf "  %b✔ Command completed successfully (exit=%d, %ds)%b\n" \
            "$GREEN$BOLD" "$RET" "$DURATION" "$RESET"
    else
        printf "  %b✘ Command returned non-zero exit code: %d%b\n" \
            "$RED$BOLD" "$RET" "$RESET"
    fi
    section_line

    return $RET
}

##############################################################################
# STOP / START OPERATIONS
##############################################################################
op_stop_provenir() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    run_command "STOP PROVENIR" "service $PROV_SERVICE stop" "$PROV_USER"
    verify_stopped "provenir" "prov7adm"
    RES=$?
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "STOP_PROVENIR" "prov7adm" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

op_start_provenir() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    title_bar "START PROVENIR"
    section_line
    printf "  %bJAVA_HOME Discovery...%b\n" "$CYAN$BOLD" "$RESET"
    progress_bar "Scanning process environment" 15 0.08

    JAVA_HOME_FOUND=$(discover_java_home "$PROV_USER" "$(get_pid provenir)")
    if [ -n "$JAVA_HOME_FOUND" ]; then
        printf "  %b✔ JAVA_HOME : %s%b\n" "$GREEN" "$JAVA_HOME_FOUND" "$RESET"
        printf "  %b  jstack    : %s/bin/jstack%b\n" "$GRAY" "$JAVA_HOME_FOUND" "$RESET"
        printf "  %b  jmap      : %s/bin/jmap%b\n" "$GRAY" "$JAVA_HOME_FOUND" "$RESET"
    else
        printf "  %b⚠ JAVA_HOME tespit edilemedi. User env fallback kullanılacak.%b\n" "$YELLOW" "$RESET"
    fi
    section_line
    printf "\n"

    run_command "START PROVENIR" "service $PROV_SERVICE start" "$PROV_USER"
    verify_started "provenir" "prov7adm"
    RES=$?

    if [ $RES -eq 0 ]; then
        printf "\n  %b  Uygulama açıldı. Decision Engine'ler kontrol edilebilir.%b\n" \
            "$GREEN$BOLD" "$RESET"
        printf "  %b  Port 8080 üzerinden erişim sağlanabilir.%b\n" "$CYAN" "$RESET"
    fi
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "START_PROVENIR" "prov7adm" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

op_stop_tomcat() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    run_command "STOP TOMCAT" "systemctl stop $TOMCAT_SERVICE" "$TOMCAT_USER"
    verify_stopped "tomcat" "tomcat"
    RES=$?
    [ $RES -eq 0 ] && printf "\n  %b  Tomcat kapatıldı.%b\n" "$GREEN$BOLD" "$RESET"
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "STOP_TOMCAT" "tomcat" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

op_start_tomcat() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    title_bar "START TOMCAT"
    section_line
    printf "  %bJAVA_HOME Discovery for Tomcat (user: %s)...%b\n" "$CYAN$BOLD" "$TOMCAT_USER" "$RESET"
    progress_bar "Scanning user environment" 15 0.08
    JAVA_HOME_FOUND=$(discover_java_home "$TOMCAT_USER" "$(get_pid tomcat)")
    if [ -n "$JAVA_HOME_FOUND" ]; then
        printf "  %b✔ JAVA_HOME : %s%b\n" "$GREEN" "$JAVA_HOME_FOUND" "$RESET"
    else
        printf "  %b⚠ JAVA_HOME tespit edilemedi.%b\n" "$YELLOW" "$RESET"
    fi
    section_line
    printf "\n"
    run_command "START TOMCAT" "systemctl start $TOMCAT_SERVICE" "$TOMCAT_USER"
    verify_started "tomcat" "tomcat"
    RES=$?
    [ $RES -eq 0 ] && printf "\n  %b  Tomcat açıldı.%b\n" "$GREEN$BOLD" "$RESET"
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "START_TOMCAT" "tomcat" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

op_stop_httpd() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    run_command "STOP HTTPD (IHS)" "$HTTPD_BIN -k stop" "$HTTPD_USER"
    verify_stopped "httpd" "httpd"
    RES=$?
    [ $RES -eq 0 ] && printf "\n  %b  HTTPD kapatıldı.%b\n" "$GREEN$BOLD" "$RESET"
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "STOP_HTTPD" "httpd" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

op_start_httpd() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    run_command "START HTTPD (IHS)" "$HTTPD_BIN -k start" "$HTTPD_USER"
    verify_started "httpd" "httpd"
    RES=$?
    [ $RES -eq 0 ] && printf "\n  %b  HTTPD açıldı.%b\n" "$GREEN$BOLD" "$RESET"
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "START_HTTPD" "httpd" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

op_stop_filebeat() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    run_command "STOP FILEBEAT" "systemctl stop $FILEBEAT_SERVICE" ""
    verify_stopped "filebeat" "filebeat"
    RES=$?
    [ $RES -eq 0 ] && printf "\n  %b  Filebeat kapatıldı.%b\n" "$GREEN$BOLD" "$RESET"
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "STOP_FILEBEAT" "filebeat" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

op_start_filebeat() {
    T=$(date '+%s' 2>/dev/null || echo 0)
    run_command "START FILEBEAT" "systemctl start $FILEBEAT_SERVICE" ""
    verify_started "filebeat" "filebeat"
    RES=$?
    [ $RES -eq 0 ] && printf "\n  %b  Filebeat açıldı.%b\n" "$GREEN$BOLD" "$RESET"
    DUR=$(( $(date '+%s' 2>/dev/null || echo 0) - T ))
    audit_log "START_FILEBEAT" "filebeat" "$([ $RES -eq 0 ] && echo SUCCESS || echo FAILED)" "${DUR}s"
    pause_screen
}

##############################################################################
# THREAD DUMP
##############################################################################
op_thread_dump() {
    title_bar "GET THREAD DUMP"

    # List active prov7adm processes
    printf "  %bActive prov7adm processes:%b\n\n" "$CYAN$BOLD" "$RESET"
    section_line
    printf "  %b%-8s %-30s %-8s %-8s %-8s%b\n" \
        "$BOLD$WHITE" "PID" "COMMAND" "CPU%" "MEM%" "THREADS" "$RESET"
    section_line

    PIDS=$(get_all_pids "provenir")
    if [ -z "$PIDS" ]; then
        printf "  %b✘ No prov7adm process found. Servis çalışmıyor olabilir.%b\n" "$RED$BOLD" "$RESET"
        pause_screen
        return
    fi

    for P in $PIDS; do
        CMD=$(ps -p "$P" -o comm= 2>/dev/null | tr -d ' ')
        CPU=$(get_metric "$P" "pcpu")
        MEM=$(get_metric "$P" "pmem")
        THR=$(get_thread_count "$P")
        printf "  %b%-8s%b %-30s %b%-8s%b %b%-8s%b %b%-8s%b\n" \
            "$GREEN" "$P" "$RESET" \
            "${CMD:--}" \
            "$YELLOW" "${CPU}%" "$RESET" \
            "$BLUE" "${MEM}%" "$RESET" \
            "$MAGENTA" "$THR" "$RESET"
    done
    section_line
    printf "\n"

    # Discover JAVA_HOME
    printf "  %bJAVA_HOME Discovery...%b\n" "$CYAN$BOLD" "$RESET"
    progress_bar "Scanning prov7adm environ" 15 0.08
    FIRST_PID=$(echo "$PIDS" | awk 'NR==1')
    JAVA_HOME_FOUND=$(discover_java_home "$PROV_USER" "$FIRST_PID")

    if [ -n "$JAVA_HOME_FOUND" ]; then
        JSTACK_BIN="$JAVA_HOME_FOUND/bin/jstack"
        printf "  %b✔ JAVA_HOME : %s%b\n" "$GREEN" "$JAVA_HOME_FOUND" "$RESET"
        printf "  %b  jstack    : %s%b\n" "$GRAY" "$JSTACK_BIN" "$RESET"
    else
        JSTACK_BIN=$(dzdo su - "$PROV_USER" -c 'which jstack 2>/dev/null' 2>/dev/null)
        if [ -z "$JSTACK_BIN" ]; then
            printf "  %b✘ jstack bulunamadı. JAVA_HOME set edilmemiş olabilir.%b\n" "$RED$BOLD" "$RESET"
            pause_screen
            return
        fi
        printf "  %b⚠ Fallback jstack: %s%b\n" "$YELLOW" "$JSTACK_BIN" "$RESET"
    fi

    printf "\n  %bThread dump alınacak PID'i girin:%b " "$YELLOW$BOLD" "$RESET"
    read TARGET_PID

    # Validate PID
    VALID=0
    for P in $PIDS; do
        if [ "$P" = "$TARGET_PID" ]; then VALID=1; fi
    done
    if [ "$VALID" -eq 0 ]; then
        printf "  %b✘ Geçersiz PID: %s%b\n" "$RED$BOLD" "$TARGET_PID" "$RESET"
        pause_screen
        return
    fi

    mkdir -p "$DUMP_DIR"
    TS=$(date '+%Y%m%d_%H%M%S')
    DUMP_FILE="${DUMP_DIR}/${HOSTNAME}_${TARGET_PID}_${TS}.tdump"

    printf "\n"
    progress_bar "Running jstack -l $TARGET_PID ..." 20 0.12

    dzdo su - "$PROV_USER" -c "$JSTACK_BIN -l $TARGET_PID" > "$DUMP_FILE" 2>&1
    RET=$?

    printf "\n"
    if [ $RET -eq 0 ]; then
        SIZE=$(wc -c < "$DUMP_FILE" 2>/dev/null | tr -d ' ')
        printf "  %b✔ Thread dump başarıyla alındı!%b\n" "$GREEN$BOLD" "$RESET"
        printf "  %b  File    : %s%b\n" "$CYAN" "$DUMP_FILE" "$RESET"
        printf "  %b  Size    : %s bytes%b\n" "$GRAY" "$SIZE" "$RESET"
        printf "  %b  PID     : %s%b\n" "$GRAY" "$TARGET_PID" "$RESET"
        audit_log "THREAD_DUMP" "prov7adm:$TARGET_PID" "SUCCESS" "-"
    else
        printf "  %b✘ Thread dump alınamadı. Exit=%d%b\n" "$RED$BOLD" "$RET" "$RESET"
        audit_log "THREAD_DUMP" "prov7adm:$TARGET_PID" "FAILED" "-"
    fi
    pause_screen
}

##############################################################################
# HEAP DUMP
##############################################################################
op_heap_dump() {
    title_bar "GET HEAP DUMP"

    printf "  %bActive prov7adm processes:%b\n\n" "$CYAN$BOLD" "$RESET"
    section_line
    printf "  %b%-8s %-30s %-8s %-8s%b\n" \
        "$BOLD$WHITE" "PID" "COMMAND" "CPU%" "MEM%" "$RESET"
    section_line

    PIDS=$(get_all_pids "provenir")
    if [ -z "$PIDS" ]; then
        printf "  %b✘ No prov7adm process found.%b\n" "$RED$BOLD" "$RESET"
        pause_screen
        return
    fi

    for P in $PIDS; do
        CMD=$(ps -p "$P" -o comm= 2>/dev/null | tr -d ' ')
        CPU=$(get_metric "$P" "pcpu")
        MEM=$(get_metric "$P" "pmem")
        printf "  %b%-8s%b %-30s %b%-8s%b %b%-8s%b\n" \
            "$GREEN" "$P" "$RESET" \
            "${CMD:--}" \
            "$YELLOW" "${CPU}%" "$RESET" \
            "$BLUE" "${MEM}%" "$RESET"
    done
    section_line
    printf "\n"

    printf "  %b⚠  UYARI: Heap dump sırasında JVM kısa süre duraklar (GC pause)!%b\n" \
        "$ORANGE$BOLD" "$RESET"
    printf "  %b   Production ortamında dikkatli kullanın.%b\n\n" "$YELLOW" "$RESET"

    printf "  %bJAVA_HOME Discovery...%b\n" "$CYAN$BOLD" "$RESET"
    progress_bar "Scanning prov7adm environ" 15 0.08
    FIRST_PID=$(echo "$PIDS" | awk 'NR==1')
    JAVA_HOME_FOUND=$(discover_java_home "$PROV_USER" "$FIRST_PID")

    if [ -n "$JAVA_HOME_FOUND" ]; then
        JMAP_BIN="$JAVA_HOME_FOUND/bin/jmap"
        printf "  %b✔ JAVA_HOME : %s%b\n" "$GREEN" "$JAVA_HOME_FOUND" "$RESET"
        printf "  %b  jmap      : %s%b\n" "$GRAY" "$JMAP_BIN" "$RESET"
    else
        JMAP_BIN=$(dzdo su - "$PROV_USER" -c 'which jmap 2>/dev/null' 2>/dev/null)
        if [ -z "$JMAP_BIN" ]; then
            printf "  %b✘ jmap bulunamadı.%b\n" "$RED$BOLD" "$RESET"
            pause_screen
            return
        fi
        printf "  %b⚠ Fallback jmap: %s%b\n" "$YELLOW" "$JMAP_BIN" "$RESET"
    fi

    printf "\n  %bHeap dump alınacak PID'i girin:%b " "$YELLOW$BOLD" "$RESET"
    read TARGET_PID

    VALID=0
    for P in $PIDS; do
        if [ "$P" = "$TARGET_PID" ]; then VALID=1; fi
    done
    if [ "$VALID" -eq 0 ]; then
        printf "  %b✘ Geçersiz PID: %s%b\n" "$RED$BOLD" "$TARGET_PID" "$RESET"
        pause_screen
        return
    fi

    mkdir -p "$DUMP_DIR"
    TS=$(date '+%Y%m%d_%H%M%S')
    DUMP_FILE="${DUMP_DIR}/${HOSTNAME}_heap_${TARGET_PID}_${TS}.hprof"

    printf "\n"
    progress_bar "Running jmap -dump:format=b ..." 25 0.15

    dzdo su - "$PROV_USER" -c "$JMAP_BIN -dump:format=b,file=$DUMP_FILE $TARGET_PID" 2>&1
    RET=$?

    printf "\n"
    if [ $RET -eq 0 ]; then
        SIZE=$(wc -c < "$DUMP_FILE" 2>/dev/null | tr -d ' ')
        printf "  %b✔ Heap dump başarıyla alındı!%b\n" "$GREEN$BOLD" "$RESET"
        printf "  %b  File : %s%b\n" "$CYAN" "$DUMP_FILE" "$RESET"
        printf "  %b  Size : %s bytes%b\n" "$GRAY" "$SIZE" "$RESET"
        audit_log "HEAP_DUMP" "prov7adm:$TARGET_PID" "SUCCESS" "-"
    else
        printf "  %b✘ Heap dump alınamadı. Exit=%d%b\n" "$RED$BOLD" "$RET" "$RESET"
        audit_log "HEAP_DUMP" "prov7adm:$TARGET_PID" "FAILED" "-"
    fi
    pause_screen
}

##############################################################################
# LIVE LOG VIEWER
##############################################################################
live_logs() {
    LOGFILE="$1"
    LABEL="$2"
    title_bar "LIVE LOG — $LABEL"
    printf "  %b%s%b\n\n" "$GRAY" "$LOGFILE" "$RESET"
    printf "  %bCTRL+C ile çıkabilirsiniz.%b\n\n" "$YELLOW" "$RESET"
    section_line
    if [ ! -f "$LOGFILE" ]; then
        printf "  %b✘ Log dosyası bulunamadı: %s%b\n" "$RED$BOLD" "$LOGFILE" "$RESET"
        pause_screen
        return
    fi
    tail -f "$LOGFILE"
}

##############################################################################
# MENU
##############################################################################
show_menu() {
    title_bar "PROVENIR SERVICE MANAGEMENT CONSOLE"

    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    printf "  %b%s%b  %bHost:%b %s  %bUser:%b %s\n\n" \
        "$GRAY" "$NOW" "$RESET" \
        "$CYAN$BOLD" "$RESET" "$HOSTNAME" \
        "$YELLOW$BOLD" "$RESET" "$OPERATOR"

    printf "  %b ┌─ MONITORING ──────────────────────────────────────────┐%b\n" "$BLUE" "$RESET"
    printf "  %b │%b %b[1]%b  %-50s%b │%b\n" "$BLUE" "$RESET" "$CYAN$BOLD" "$RESET" "Dashboard — All Services Status" "$BLUE" "$RESET"
    printf "  %b └───────────────────────────────────────────────────────┘%b\n\n" "$BLUE" "$RESET"

    printf "  %b ┌─ PROVENIR ─────────────────────────────────────────────┐%b\n" "$GREEN" "$RESET"
    printf "  %b │%b %b[2]%b  %-50s%b │%b\n" "$GREEN" "$RESET" "$RED$BOLD"   "$RESET" "Stop  Provenir" "$GREEN" "$RESET"
    printf "  %b │%b %b[3]%b  %-50s%b │%b\n" "$GREEN" "$RESET" "$GREEN$BOLD" "$RESET" "Start Provenir" "$GREEN" "$RESET"
    printf "  %b └───────────────────────────────────────────────────────┘%b\n\n" "$GREEN" "$RESET"

    printf "  %b ┌─ TOMCAT ───────────────────────────────────────────────┐%b\n" "$ORANGE" "$RESET"
    printf "  %b │%b %b[4]%b  %-50s%b │%b\n" "$ORANGE" "$RESET" "$RED$BOLD"   "$RESET" "Stop  Tomcat" "$ORANGE" "$RESET"
    printf "  %b │%b %b[5]%b  %-50s%b │%b\n" "$ORANGE" "$RESET" "$GREEN$BOLD" "$RESET" "Start Tomcat" "$ORANGE" "$RESET"
    printf "  %b └───────────────────────────────────────────────────────┘%b\n\n" "$ORANGE" "$RESET"

    printf "  %b ┌─ HTTPD / FILEBEAT ─────────────────────────────────────┐%b\n" "$MAGENTA" "$RESET"
    printf "  %b │%b %b[6]%b  %-50s%b │%b\n" "$MAGENTA" "$RESET" "$RED$BOLD"   "$RESET" "Stop  HTTPD (IHS)" "$MAGENTA" "$RESET"
    printf "  %b │%b %b[7]%b  %-50s%b │%b\n" "$MAGENTA" "$RESET" "$GREEN$BOLD" "$RESET" "Start HTTPD (IHS)" "$MAGENTA" "$RESET"
    printf "  %b │%b %b[8]%b  %-50s%b │%b\n" "$MAGENTA" "$RESET" "$RED$BOLD"   "$RESET" "Stop  Filebeat" "$MAGENTA" "$RESET"
    printf "  %b │%b %b[9]%b  %-50s%b │%b\n" "$MAGENTA" "$RESET" "$GREEN$BOLD" "$RESET" "Start Filebeat" "$MAGENTA" "$RESET"
    printf "  %b └───────────────────────────────────────────────────────┘%b\n\n" "$MAGENTA" "$RESET"

    printf "  %b ┌─ DIAGNOSTICS ──────────────────────────────────────────┐%b\n" "$YELLOW" "$RESET"
    printf "  %b │%b %b[10]%b %-50s%b │%b\n" "$YELLOW" "$RESET" "$YELLOW$BOLD" "$RESET" "Get Thread Dump (Provenir)" "$YELLOW" "$RESET"
    printf "  %b │%b %b[11]%b %-50s%b │%b\n" "$YELLOW" "$RESET" "$YELLOW$BOLD" "$RESET" "Get Heap Dump   (Provenir)" "$YELLOW" "$RESET"
    printf "  %b │%b %b[12]%b %-50s%b │%b\n" "$YELLOW" "$RESET" "$CYAN$BOLD"   "$RESET" "Live Log — Provenir" "$YELLOW" "$RESET"
    printf "  %b │%b %b[13]%b %-50s%b │%b\n" "$YELLOW" "$RESET" "$CYAN$BOLD"   "$RESET" "Live Log — Tomcat" "$YELLOW" "$RESET"
    printf "  %b └───────────────────────────────────────────────────────┘%b\n\n" "$YELLOW" "$RESET"

    printf "  %b[0]%b  Exit\n\n" "$GRAY$BOLD" "$RESET"
    printf "  %bSelection%b : " "$CYAN$BOLD" "$RESET"
}

##############################################################################
# MAIN LOOP
##############################################################################
while true; do
    show_menu
    read CHOICE
    case "$CHOICE" in
        1)  dashboard; pause_screen ;;
        2)  op_stop_provenir ;;
        3)  op_start_provenir ;;
        4)  op_stop_tomcat ;;
        5)  op_start_tomcat ;;
        6)  op_stop_httpd ;;
        7)  op_start_httpd ;;
        8)  op_stop_filebeat ;;
        9)  op_start_filebeat ;;
        10) op_thread_dump ;;
        11) op_heap_dump ;;
        12) live_logs "$PROV_LOG" "Provenir" ;;
        13) live_logs "$TOMCAT_LOG" "Tomcat" ;;
        0)
            clear_screen
            printf "\n  %b✔ Console closed. Görüşmek üzere.%b\n\n" "$GREEN$BOLD" "$RESET"
            exit 0
            ;;
        *)
            printf "\n  %b✘ Geçersiz seçim: %s%b\n" "$RED$BOLD" "$CHOICE" "$RESET"
            sleep 1
            ;;
    esac
done
