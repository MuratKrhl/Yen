#!/bin/ksh
# =============================================================================
# PROVENIR & TOMCAT SERVIS YONETIM SCRIPTI
# =============================================================================
# JBoss bagimsiz, Provenir + Tomcat + HTTPD + Filebeat odakli
# TUI (Terminal UI) - ANSI Renkli Dashboard
# Log akisi entegreli
# =============================================================================

# -----------------------------------------------------------------------------
# KONFIGURASYON
# -----------------------------------------------------------------------------
PROV_SERVICE="prov7adm"
TOMCAT_SERVICE="tomcat"
HTTPD_BIN="/usr/IBMIHS/bin/apachectl"
FILEBEAT_SERVICE="filebeat"

DUMP_BASE="/sw/WAS_IMAGES/MuratK/Provenir"
LOG_DIR="/var/log/prov-admin"

HOSTNAME=$(hostname)
DATE_STR=$(date +%Y%m%d_%H%M%S)
TODAY=$(date +%Y%m%d)

# Provenir log path (varsayilan, ortama gore ayarlanmali)
PROV_LOG="/var/log/prov7adm"
TOMCAT_LOG="/var/log/tomcat"
HTTPD_LOG="/var/log/httpd"
FILEBEAT_LOG="/var/log/filebeat"

# -----------------------------------------------------------------------------
# ANSI RENKLER (Resimdeki gibi: siyah arka plan, parlak metinler)
# -----------------------------------------------------------------------------
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"

# Arka plan siyah (40), metin parlak
C_WHITE="\033[1;37m"
C_GREEN="\033[1;32m"
C_CYAN="\033[1;36m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_MAGENTA="\033[1;35m"
C_BLUE="\033[1;34m"

# Arka plan renkleri
BG_BLACK="\033[40m"
BG_GREEN="\033[42m"
BG_RED="\033[41m"
BG_BLUE="\033[44m"

# -----------------------------------------------------------------------------
# EKRAN YARDIMCILARI
# -----------------------------------------------------------------------------
clear_screen() {
    clear
    # Alternatif: printf "\033[2J\033[H"
}

cursor_hide() {
    printf "\033[?25l"
}

cursor_show() {
    printf "\033[?25h"
}

# -----------------------------------------------------------------------------
# BOX DRAWING KARAKTERLERI (Unicode)
# -----------------------------------------------------------------------------
BOX_TL="╔"; BOX_TR="╗"; BOX_BL="╚"; BOX_BR="╝"
BOX_H="═"; BOX_V="║"; BOX_ML="╠"; BOX_MR="╣"
BOX_TM="╦"; BOX_BM="╩"; BOX_CR="╬"

# -----------------------------------------------------------------------------
# TUI BILESENLERI
# -----------------------------------------------------------------------------
draw_header() {
    local title="$1"
    local width=78
    local padding=$(( (width - ${#title}) / 2 ))

    printf "${C_CYAN}${BOX_TL}"
    for i in $(seq 1 $((width-2))); do printf "${BOX_H}"; done
    printf "${BOX_TR}\n"

    printf "${BOX_V}${C_WHITE}"
    for i in $(seq 1 $padding); do printf " "; done
    printf "%s" "$title"
    for i in $(seq 1 $((width - 2 - padding - ${#title}))); do printf " "; done
    printf "${C_CYAN}${BOX_V}\n"

    printf "${BOX_ML}"
    for i in $(seq 1 $((width-2))); do printf "${BOX_H}"; done
    printf "${BOX_MR}${C_RESET}\n"
}

draw_footer() {
    local width=78
    printf "${C_CYAN}${BOX_BL}"
    for i in $(seq 1 $((width-2))); do printf "${BOX_H}"; done
    printf "${BOX_BR}${C_RESET}\n"
}

draw_line() {
    local width=78
    printf "${C_CYAN}${BOX_ML}"
    for i in $(seq 1 $((width-2))); do printf "${BOX_H}"; done
    printf "${BOX_MR}${C_RESET}\n"
}

draw_empty_line() {
    local width=78
    printf "${C_CYAN}${BOX_V}"
    for i in $(seq 1 $((width-2))); do printf " "; done
    printf "${BOX_V}${C_RESET}\n"
}

draw_text_line() {
    local text="$1"
    local color="${2:-$C_WHITE}"
    local width=78
    local text_len=${#text}
    local pad=$((width - 2 - text_len))

    printf "${C_CYAN}${BOX_V}${color} %s%*s ${C_CYAN}${BOX_V}${C_RESET}\n" "$text" "$pad" ""
}

draw_status_box() {
    local label="$1"
    local status="$2"
    local color="$3"
    local width=36

    if [[ "$status" == "RUNNING" ]]; then
        local status_color="${C_GREEN}"
        local bg="${BG_GREEN}"
    elif [[ "$status" == "STOPPED" ]]; then
        local status_color="${C_RED}"
        local bg="${BG_RED}"
    else
        local status_color="${C_YELLOW}"
        local bg="${BG_BLACK}"
    fi

    printf "${C_CYAN}${BOX_V}${C_WHITE} %-15s${C_CYAN}${BOX_V}" "$label"
    printf "${bg}${status_color} %s ${C_RESET}${C_CYAN}" "$status"
    # Padding
    local pad=$((width - 17 - ${#status}))
    for i in $(seq 1 $pad); do printf " "; done
    printf "${BOX_V}${C_RESET}"
}

# -----------------------------------------------------------------------------
# SERVIS DURUM KONTROLU
# -----------------------------------------------------------------------------
get_service_status() {
    local service="$1"
    local pid=""
    local status="STOPPED"
    local cpu="-"
    local mem="-"
    local threads="-"
    local uptime="-"
    local owner="-"

    case "$service" in
        "provenir")
            pid=$(pgrep -u prov7adm -f "prov7adm" 2>/dev/null | head -1)
            if [[ -z "$pid" ]]; then
                pid=$(ps -ef | grep -v grep | grep "prov7adm" | awk '{print $2}' | head -1)
            fi
            ;;
        "tomcat")
            pid=$(pgrep -u was -f "tomcat" 2>/dev/null | head -1)
            if [[ -z "$pid" ]]; then
                pid=$(ps -ef | grep -v grep | grep "tomcat" | awk '{print $2}' | head -1)
            fi
            ;;
        "httpd")
            pid=$(pgrep -f "httpd" 2>/dev/null | head -1)
            if [[ -z "$pid" ]]; then
                pid=$(ps -ef | grep -v grep | grep "httpd" | grep -v "apachectl" | awk '{print $2}' | head -1)
            fi
            ;;
        "filebeat")
            pid=$(pgrep -f "filebeat" 2>/dev/null | head -1)
            if [[ -z "$pid" ]]; then
                pid=$(ps -ef | grep -v grep | grep "filebeat" | awk '{print $2}' | head -1)
            fi
            ;;
    esac

    if [[ -n "$pid" && "$pid" != "" ]]; then
        status="RUNNING"
        # CPU ve MEM bilgisi
        local ps_info=$(ps -p "$pid" -o pid,pcpu,pmem,nlwp,etimes,user 2>/dev/null | tail -1)
        if [[ -n "$ps_info" ]]; then
            cpu=$(echo "$ps_info" | awk '{print $2}')
            mem=$(echo "$ps_info" | awk '{print $3}')
            threads=$(echo "$ps_info" | awk '{print $4}')
            local etimes=$(echo "$ps_info" | awk '{print $5}')
            owner=$(echo "$ps_info" | awk '{print $6}')

            # Uptime hesaplama (saniye -> gun/saat/dakika)
            local days=$((etimes / 86400))
            local hours=$(((etimes % 86400) / 3600))
            local mins=$(((etimes % 3600) / 60))
            if [[ $days -gt 0 ]]; then
                uptime="${days}d ${hours}h ${mins}m"
            else
                uptime="${hours}h ${mins}m"
            fi
        fi
    fi

    echo "${status}|${pid}|${cpu}|${mem}|${threads}|${uptime}|${owner}"
}

# -----------------------------------------------------------------------------
# ANLIK STATUS DASHBOARD (Resimdeki gibi hiyerarsik)
# -----------------------------------------------------------------------------
show_dashboard() {
    clear_screen

    # === HEADER ===
    draw_header "  PROVENIR SERVIS YONETIM KONSOLU  "

    # Host ve tarih bilgisi
    local dt=$(date "+%Y-%m-%d %H:%M:%S")
    draw_text_line "  HOST: ${HOSTNAME}    TARIH: ${dt}    KULLANICI: $(whoami)" "$C_DIM"
    draw_line

    # === SERVIS DURUMLARI (2x2 Grid) ===
    local prov=$(get_service_status "provenir")
    local tom=$(get_service_status "tomcat")
    local http=$(get_service_status "httpd")
    local fb=$(get_service_status "filebeat")

    local prov_status=$(echo "$prov" | cut -d'|' -f1)
    local prov_pid=$(echo "$prov" | cut -d'|' -f2)
    local prov_cpu=$(echo "$prov" | cut -d'|' -f3)
    local prov_mem=$(echo "$prov" | cut -d'|' -f4)
    local prov_thr=$(echo "$prov" | cut -d'|' -f5)
    local prov_up=$(echo "$prov" | cut -d'|' -f6)
    local prov_own=$(echo "$prov" | cut -d'|' -f7)

    local tom_status=$(echo "$tom" | cut -d'|' -f1)
    local tom_pid=$(echo "$tom" | cut -d'|' -f2)
    local tom_cpu=$(echo "$tom" | cut -d'|' -f3)
    local tom_mem=$(echo "$tom" | cut -d'|' -f4)
    local tom_thr=$(echo "$tom" | cut -d'|' -f5)
    local tom_up=$(echo "$tom" | cut -d'|' -f6)
    local tom_own=$(echo "$tom" | cut -d'|' -f7)

    local http_status=$(echo "$http" | cut -d'|' -f1)
    local http_pid=$(echo "$http" | cut -d'|' -f2)
    local http_cpu=$(echo "$http" | cut -d'|' -f3)
    local http_mem=$(echo "$http" | cut -d'|' -f4)
    local http_thr=$(echo "$http" | cut -d'|' -f5)
    local http_up=$(echo "$http" | cut -d'|' -f6)
    local http_own=$(echo "$http" | cut -d'|' -f7)

    local fb_status=$(echo "$fb" | cut -d'|' -f1)
    local fb_pid=$(echo "$fb" | cut -d'|' -f2)
    local fb_cpu=$(echo "$fb" | cut -d'|' -f3)
    local fb_mem=$(echo "$fb" | cut -d'|' -f4)
    local fb_thr=$(echo "$fb" | cut -d'|' -f5)
    local fb_up=$(echo "$fb" | cut -d'|' -f6)
    local fb_own=$(echo "$fb" | cut -d'|' -f7)

    # Provenir Box
    draw_empty_line
    draw_text_line "  ◆ PROVENIR (prov7adm)" "$C_CYAN"
    draw_text_line "     PID: ${prov_pid} | OWNER: ${prov_own}" "$C_WHITE"
    draw_text_line "     CPU: ${prov_cpu}% | MEM: ${prov_mem}% | THREADS: ${prov_thr}" "$C_WHITE"
    draw_text_line "     UPTIME: ${prov_up} | STATUS: ${prov_status}" "$C_GREEN"

    draw_empty_line
    draw_text_line "  ◆ TOMCAT (was)" "$C_CYAN"
    draw_text_line "     PID: ${tom_pid} | OWNER: ${tom_own}" "$C_WHITE"
    draw_text_line "     CPU: ${tom_cpu}% | MEM: ${tom_mem}% | THREADS: ${tom_thr}" "$C_WHITE"
    draw_text_line "     UPTIME: ${tom_up} | STATUS: ${tom_status}" "$C_GREEN"

    draw_empty_line
    draw_text_line "  ◆ HTTPD (www)" "$C_CYAN"
    draw_text_line "     PID: ${http_pid} | OWNER: ${http_own}" "$C_WHITE"
    draw_text_line "     CPU: ${http_cpu}% | MEM: ${http_mem}% | THREADS: ${http_thr}" "$C_WHITE"
    draw_text_line "     UPTIME: ${http_up} | STATUS: ${http_status}" "$C_GREEN"

    draw_empty_line
    draw_text_line "  ◆ FILEBEAT" "$C_CYAN"
    draw_text_line "     PID: ${fb_pid} | OWNER: ${fb_own}" "$C_WHITE"
    draw_text_line "     CPU: ${fb_cpu}% | MEM: ${fb_mem}% | THREADS: ${fb_thr}" "$C_WHITE"
    draw_text_line "     UPTIME: ${fb_up} | STATUS: ${fb_status}" "$C_GREEN"

    draw_line

    # === METRIKLER ===
    draw_text_line "  ◆ SISTEM METRIKLERI" "$C_MAGENTA"
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local mem_info=$(free -m 2>/dev/null | awk 'NR==2{printf "%.1f/%.1f GB (%%%s)", $3/1024, $2/1024, $3*100/$2}')
    local disk_info=$(df -h / 2>/dev/null | awk 'NR==2{print $5 " kullanim"}')

    draw_text_line "     Load Avg: ${load} | Memory: ${mem_info}" "$C_WHITE"
    draw_text_line "     Disk (/): ${disk_info}" "$C_WHITE"

    draw_line
    draw_footer

    printf "\n"
}

# -----------------------------------------------------------------------------
# LOG AKISI (Stop/Start islemlerinde anlik log takibi)
# -----------------------------------------------------------------------------
# Log dosyasini bulma fonksiyonu
find_log_file() {
    local service="$1"
    local logfile=""

    case "$service" in
        "provenir")
            # Provenir log path'leri - ortama gore ayarlanmali
            if [[ -f "/var/log/prov7adm/prov7adm.log" ]]; then
                logfile="/var/log/prov7adm/prov7adm.log"
            elif [[ -f "/var/log/prov7adm/catalina.out" ]]; then
                logfile="/var/log/prov7adm/catalina.out"
            elif [[ -f "/opt/prov7adm/logs/prov7adm.log" ]]; then
                logfile="/opt/prov7adm/logs/prov7adm.log"
            fi
            ;;
        "tomcat")
            if [[ -f "/var/log/tomcat/catalina.out" ]]; then
                logfile="/var/log/tomcat/catalina.out"
            elif [[ -f "/opt/tomcat/logs/catalina.out" ]]; then
                logfile="/opt/tomcat/logs/catalina.out"
            elif [[ -f "/usr/share/tomcat/logs/catalina.out" ]]; then
                logfile="/usr/share/tomcat/logs/catalina.out"
            fi
            ;;
        "httpd")
            if [[ -f "/var/log/httpd/error_log" ]]; then
                logfile="/var/log/httpd/error_log"
            elif [[ -f "/var/log/httpd/ssl_error_log" ]]; then
                logfile="/var/log/httpd/ssl_error_log"
            fi
            ;;
        "filebeat")
            if [[ -f "/var/log/filebeat/filebeat" ]]; then
                logfile="/var/log/filebeat/filebeat"
            elif [[ -f "/var/log/filebeat/filebeat.log" ]]; then
                logfile="/var/log/filebeat/filebeat.log"
            fi
            ;;
    esac

    echo "$logfile"
}

# Anlik log akisi - Stop/Start islemlerinde
tail_log_live() {
    local service="$1"
    local operation="$2"  # STOP veya START
    local logfile=$(find_log_file "$service")
    local timeout=30        # Maksimum 30 saniye log takibi
    local start_time=$(date +%s)

    clear_screen
    draw_header "  LOG AKISI: ${service} - ${operation}  "

    if [[ -z "$logfile" || ! -f "$logfile" ]]; then
        draw_text_line "  Log dosyasi bulunamadi: ${service}" "$C_RED"
        draw_text_line "  Varsayilan path'ler kontrol edildi." "$C_YELLOW"
        draw_footer
        printf "\n"
        print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
        read bos
        return
    fi

    # Log dosyasinin son satir numarasini al
    local last_line=$(wc -l < "$logfile" 2>/dev/null)
    [[ -z "$last_line" ]] && last_line=0

    draw_text_line "  Log: ${logfile}" "$C_DIM"
    draw_text_line "  Takip basliyor... (CTRL+C ile cikabilirsiniz)" "$C_DIM"
    draw_line

    local line_count=0
    local max_display=20  # Ekranda gosterilecek max satir

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Timeout kontrolu
        if [[ $elapsed -ge $timeout ]]; then
            printf "\n${C_YELLOW}\t[TIMEOUT: ${timeout}s log takibi sona erdi]${C_RESET}\n"
            break
        fi

        # Yeni satirlari kontrol et
        local current_lines=$(wc -l < "$logfile" 2>/dev/null)
        [[ -z "$current_lines" ]] && current_lines=0

        if [[ $current_lines -gt $last_line ]]; then
            local new_lines=$((current_lines - last_line))

            # Yeni satirlari goster (son max_display kadar)
            tail -n "$new_lines" "$logfile" 2>/dev/null | while IFS= read -r line; do
                # Satir uzunlugunu limitle (78 karakter)
                if [[ ${#line} -gt 75 ]]; then
                    line="${line:0:72}..."
                fi

                # Renklendirme - log seviyelerine gore
                if [[ "$line" == *"ERROR"* || "$line" == *"FATAL"* ]]; then
                    printf "${C_RED}  %s${C_RESET}\n" "$line"
                elif [[ "$line" == *"WARN"* || "$line" == *"WARNING"* ]]; then
                    printf "${C_YELLOW}  %s${C_RESET}\n" "$line"
                elif [[ "$line" == *"INFO"* && "$line" == *"started"* || "$line" == *"Started"* ]]; then
                    printf "${C_GREEN}  %s${C_RESET}\n" "$line"
                else
                    printf "${C_WHITE}  %s${C_RESET}\n" "$line"
                fi

                ((line_count++))
            done

            last_line=$current_lines
        fi

        # Servis durumunu kontrol et (START icin RUNNING, STOP icin STOPPED)
        local current_status=$(get_service_status "$service" | cut -d'|' -f1)

        if [[ "$operation" == "START" && "$current_status" == "RUNNING" ]]; then
            printf "\n${C_GREEN}\t[SERVIS BASARIYLA BASLATILDI - PID: $(get_service_status "$service" | cut -d'|' -f2)]${C_RESET}\n"
            break
        elif [[ "$operation" == "STOP" && "$current_status" == "STOPPED" ]]; then
            printf "\n${C_GREEN}\t[SERVIS BASARIYLA DURDURULDU]${C_RESET}\n"
            break
        fi

        sleep 1
    done

    draw_footer
    printf "\n"
    print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
    read bos
}

# -----------------------------------------------------------------------------
# SERVIS OPERASYONLARI
# -----------------------------------------------------------------------------
stop_service() {
    local service="$1"
    local command="$2"
    local user="$3"

    clear_screen
    draw_header "  STOP: ${service}  "

    # Mevcut durum kontrolu
    local status_info=$(get_service_status "$service")
    local status=$(echo "$status_info" | cut -d'|' -f1)

    if [[ "$status" == "STOPPED" ]]; then
        draw_text_line "  ${service} zaten DURDURULMUS durumda." "$C_YELLOW"
        draw_footer
        printf "\n"
        print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
        read bos
        return
    fi

    # Onay
    draw_text_line "  ${service} durdurulacak. Onayliyor musunuz? (e/h)" "$C_WHITE"
    draw_footer
    printf "\n"
    print -n "\tSecim: "
    read cevap

    if [[ "$cevap" != "e" && "$cevap" != "E" ]]; then
        return
    fi

    # Komut calistir
    draw_text_line "  ${service} durduruluyor..." "$C_YELLOW"

    if [[ -n "$user" ]]; then
        dzdo su - "$user" -c "$command" 2>&1 | while read line; do
            printf "${C_DIM}  > %s${C_RESET}\n" "$line"
        done
    else
        eval "$command" 2>&1 | while read line; do
            printf "${C_DIM}  > %s${C_RESET}\n" "$line"
        done
    fi

    # Log akisini baslat
    tail_log_live "$service" "STOP"

    # 5 saniye bekle ve tekrar kontrol et
    sleep 5
    local final_status=$(get_service_status "$service" | cut -d'|' -f1)

    clear_screen
    draw_header "  STOP SONUCU: ${service}  "

    if [[ "$final_status" == "STOPPED" ]]; then
        draw_text_line "  ✓ ${service} basariyla durduruldu." "$C_GREEN"
    else
        draw_text_line "  ✗ ${service} durdurulamadi! Manuel kontrol gerekiyor." "$C_RED"
        draw_text_line "  PID: $(get_service_status "$service" | cut -d'|' -f2)" "$C_YELLOW"
    fi

    draw_footer
    printf "\n"
    print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
    read bos
}

start_service() {
    local service="$1"
    local command="$2"
    local user="$3"

    clear_screen
    draw_header "  START: ${service}  "

    # Mevcut durum kontrolu
    local status_info=$(get_service_status "$service")
    local status=$(echo "$status_info" | cut -d'|' -f1)

    if [[ "$status" == "RUNNING" ]]; then
        draw_text_line "  ${service} zaten CALISIYOR durumda." "$C_YELLOW"
        draw_text_line "  PID: $(echo "$status_info" | cut -d'|' -f2)" "$C_WHITE"
        draw_footer
        printf "\n"
        print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
        read bos
        return
    fi

    # Onay
    draw_text_line "  ${service} baslatilacak. Onayliyor musunuz? (e/h)" "$C_WHITE"
    draw_footer
    printf "\n"
    print -n "\tSecim: "
    read cevap

    if [[ "$cevap" != "e" && "$cevap" != "E" ]]; then
        return
    fi

    # Komut calistir
    draw_text_line "  ${service} baslatiliyor..." "$C_YELLOW"

    if [[ -n "$user" ]]; then
        dzdo su - "$user" -c "$command" 2>&1 | while read line; do
            printf "${C_DIM}  > %s${C_RESET}\n" "$line"
        done
    else
        eval "$command" 2>&1 | while read line; do
            printf "${C_DIM}  > %s${C_RESET}\n" "$line"
        done
    fi

    # Log akisini baslat
    tail_log_live "$service" "START"

    # 5 saniye bekle ve tekrar kontrol et
    sleep 5
    local final_status=$(get_service_status "$service" | cut -d'|' -f1)
    local final_pid=$(get_service_status "$service" | cut -d'|' -f2)

    clear_screen
    draw_header "  START SONUCU: ${service}  "

    if [[ "$final_status" == "RUNNING" ]]; then
        draw_text_line "  ✓ ${service} basariyla baslatildi." "$C_GREEN"
        draw_text_line "  PID: ${final_pid}" "$C_WHITE"

        if [[ "$service" == "provenir" ]]; then
            draw_text_line "  Decision Engine'ler kontrol edilebilir." "$C_CYAN"
        fi
    else
        draw_text_line "  ✗ ${service} baslatilamadi! Loglari kontrol edin." "$C_RED"
    fi

    draw_footer
    printf "\n"
    print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
    read bos
}

restart_tomcat() {
    clear_screen
    draw_header "  RESTART: TOMCAT  "

    local status_info=$(get_service_status "tomcat")
    local status=$(echo "$status_info" | cut -d'|' -f1)

    if [[ "$status" == "STOPPED" ]]; then
        draw_text_line "  Tomcat zaten durdurulmus. Once baslatmaniz gerekiyor." "$C_YELLOW"
        draw_footer
        printf "\n"
        print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
        read bos
        return
    fi

    draw_text_line "  Tomcat yeniden baslatilacak. Onayliyor musunuz? (e/h)" "$C_WHITE"
    draw_footer
    printf "\n"
    print -n "\tSecim: "
    read cevap

    if [[ "$cevap" != "e" && "$cevap" != "E" ]]; then
        return
    fi

    # Stop
    draw_text_line "  1/2: Tomcat durduruluyor..." "$C_YELLOW"
    dzdo systemctl stop tomcat 2>&1 | while read line; do
        printf "${C_DIM}  > %s${C_RESET}\n" "$line"
    done

    sleep 5

    # Start
    draw_text_line "  2/2: Tomcat baslatiliyor..." "$C_YELLOW"
    dzdo systemctl start tomcat 2>&1 | while read line; do
        printf "${C_DIM}  > %s${C_RESET}\n" "$line"
    done

    # Log akisi
    tail_log_live "tomcat" "START"

    sleep 5
    local final_status=$(get_service_status "tomcat" | cut -d'|' -f1)
    local final_pid=$(get_service_status "tomcat" | cut -d'|' -f2)

    clear_screen
    draw_header "  RESTART SONUCU: TOMCAT  "

    if [[ "$final_status" == "RUNNING" ]]; then
        draw_text_line "  ✓ Tomcat basariyla yeniden baslatildi." "$C_GREEN"
        draw_text_line "  Yeni PID: ${final_pid}" "$C_WHITE"
    else
        draw_text_line "  ✗ Tomcat yeniden baslatilamadi!" "$C_RED"
    fi

    draw_footer
    printf "\n"
    print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
    read bos
}

# -----------------------------------------------------------------------------
# THREAD DUMP & HEAP DUMP
# -----------------------------------------------------------------------------
get_thread_dump() {
    clear_screen
    draw_header "  THREAD DUMP  "

    # Provenir PID listele
    local pids=$(pgrep -u prov7adm -f "prov7adm" 2>/dev/null)
    if [[ -z "$pids" ]]; then
        pids=$(ps -ef | grep -v grep | grep "prov7adm" | awk '{print $2}')
    fi

    if [[ -z "$pids" ]]; then
        draw_text_line "  Provenir calismiyor. Thread dump alinamaz." "$C_RED"
        draw_footer
        printf "\n"
        print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
        read bos
        return
    fi

    draw_text_line "  Calisan Provenir Process'leri:" "$C_CYAN"

    local i=1
    local pid_array=""
    echo "$pids" | while read pid; do
        if [[ -n "$pid" ]]; then
            local cmd=$(ps -p "$pid" -o comm= 2>/dev/null)
            local cpu=$(ps -p "$pid" -o pcpu= 2>/dev/null | tr -d ' ')
            draw_text_line "    ${i}. PID: ${pid} | CMD: ${cmd} | CPU: ${cpu}%" "$C_WHITE"
            pid_array="${pid_array}${pid} "
            ((i++))
        fi
    done

    draw_text_line "  " "$C_WHITE"
    draw_text_line "  Thread dump alinacak PID'i girin (1-$((i-1))):" "$C_WHITE"
    draw_footer
    printf "\n"
    print -n "\tPID: "
    read selected_pid

    if [[ -z "$selected_pid" ]]; then
        return
    fi

    # Dump dizinini olustur
    mkdir -p "${DUMP_BASE}/${TODAY}"
    local dump_file="${DUMP_BASE}/${TODAY}/${HOSTNAME}_provenir_${selected_pid}_thread_${DATE_STR}.tdump"

    draw_text_line "  Thread dump aliniyor..." "$C_YELLOW"
    draw_text_line "  Hedef: ${dump_file}" "$C_DIM"

    dzdo su - prov7adm -c "jstack ${selected_pid} > ${dump_file} 2>&1" 2>/dev/null

    if [[ -f "$dump_file" && -s "$dump_file" ]]; then
        local size=$(ls -lh "$dump_file" | awk '{print $5}')
        draw_text_line "  ✓ Thread dump basariyla alindi." "$C_GREEN"
        draw_text_line "  Boyut: ${size}" "$C_WHITE"
    else
        draw_text_line "  ✗ Thread dump alinamadi!" "$C_RED"
    fi

    draw_footer
    printf "\n"
    print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
    read bos
}

get_heap_dump() {
    clear_screen
    draw_header "  HEAP DUMP  "

    # Provenir PID listele
    local pids=$(pgrep -u prov7adm -f "prov7adm" 2>/dev/null)
    if [[ -z "$pids" ]]; then
        pids=$(ps -ef | grep -v grep | grep "prov7adm" | awk '{print $2}')
    fi

    if [[ -z "$pids" ]]; then
        draw_text_line "  Provenir calismiyor. Heap dump alinamaz." "$C_RED"
        draw_footer
        printf "\n"
        print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
        read bos
        return
    fi

    draw_text_line "  Calisan Provenir Process'leri:" "$C_CYAN"

    local i=1
    echo "$pids" | while read pid; do
        if [[ -n "$pid" ]]; then
            local cmd=$(ps -p "$pid" -o comm= 2>/dev/null)
            local mem=$(ps -p "$pid" -o pmem= 2>/dev/null | tr -d ' ')
            draw_text_line "    ${i}. PID: ${pid} | CMD: ${cmd} | MEM: ${mem}%" "$C_WHITE"
            ((i++))
        fi
    done

    draw_text_line "  " "$C_WHITE"
    draw_text_line "  Heap dump alinacak PID'i girin:" "$C_WHITE"
    draw_footer
    printf "\n"
    print -n "\tPID: "
    read selected_pid

    if [[ -z "$selected_pid" ]]; then
        return
    fi

    # Dump dizinini olustur
    mkdir -p "${DUMP_BASE}/${TODAY}"
    local dump_file="${DUMP_BASE}/${TODAY}/${HOSTNAME}_provenir_${selected_pid}_heap_${DATE_STR}.hprof"

    draw_text_line "  Heap dump aliniyor... (Bu islem biraz zaman alabilir)" "$C_YELLOW"
    draw_text_line "  Hedef: ${dump_file}" "$C_DIM"

    dzdo su - prov7adm -c "jmap -dump:format=b,file=${dump_file} ${selected_pid} 2>&1" 2>/dev/null | while read line; do
        printf "${C_DIM}  > %s${C_RESET}\n" "$line"
    done

    if [[ -f "$dump_file" && -s "$dump_file" ]]; then
        local size=$(ls -lh "$dump_file" | awk '{print $5}')
        draw_text_line "  ✓ Heap dump basariyla alindi." "$C_GREEN"
        draw_text_line "  Boyut: ${size}" "$C_WHITE"
    else
        draw_text_line "  ✗ Heap dump alinamadi!" "$C_RED"
    fi

    draw_footer
    printf "\n"
    print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
    read bos
}

# -----------------------------------------------------------------------------
# ANA MENU
# -----------------------------------------------------------------------------
show_menu() {
    clear_screen

    # === HEADER ===
    draw_header "  PROVENIR SERVIS YONETIM KONSOLU  "

    local dt=$(date "+%Y-%m-%d %H:%M:%S")
    draw_text_line "  HOST: ${HOSTNAME}    TARIH: ${dt}" "$C_DIM"
    draw_line

    # === MENU (Resimdeki gibi hiyerarşik) ===
    draw_empty_line
    draw_text_line "  ◆ SERVIS DURUMLARI" "$C_MAGENTA"
    draw_text_line "    1. TUM SERVISLERI GOSTER (Dashboard)" "$C_WHITE"

    draw_empty_line
    draw_text_line "  ◆ PROVENIR ISLEMLERI" "$C_CYAN"
    draw_text_line "    2. STOP PROVENIR SERVER" "$C_WHITE"
    draw_text_line "    3. START PROVENIR SERVER" "$C_WHITE"

    draw_empty_line
    draw_text_line "  ◆ TOMCAT ISLEMLERI" "$C_CYAN"
    draw_text_line "    4. STOP TOMCAT SERVER" "$C_WHITE"
    draw_text_line "    5. START TOMCAT SERVER" "$C_WHITE"
    draw_text_line "    6. RESTART TOMCAT SERVER" "$C_WHITE"

    draw_empty_line
    draw_text_line "  ◆ HTTPD ISLEMLERI" "$C_CYAN"
    draw_text_line "    7. STOP HTTPD SERVER" "$C_WHITE"
    draw_text_line "    8. START HTTPD SERVER" "$C_WHITE"

    draw_empty_line
    draw_text_line "  ◆ FILEBEAT ISLEMLERI" "$C_CYAN"
    draw_text_line "    9. STOP FILEBEAT SERVER" "$C_WHITE"
    draw_text_line "   10. START FILEBEAT SERVER" "$C_WHITE"

    draw_empty_line
    draw_text_line "  ◆ DIAGNOSTIC" "$C_YELLOW"
    draw_text_line "   11. GET THREAD DUMP" "$C_WHITE"
    draw_text_line "   12. GET HEAP DUMP" "$C_WHITE"

    draw_empty_line
    draw_text_line "  ◆ SISTEM" "$C_RED"
    draw_text_line "    0. CIKIS" "$C_WHITE"

    draw_empty_line
    draw_footer

    printf "\n"
    print -n "\t${C_CYAN}Secim: ${C_RESET}"
}

# -----------------------------------------------------------------------------
# ANA FONKSIYON
# -----------------------------------------------------------------------------
main() {
    # Trap CTRL+C -> Menuye don
    trap 'menu_loop' 2

    # Log dizini olustur
    mkdir -p "$LOG_DIR" 2>/dev/null

    menu_loop
}

menu_loop() {
    while true; do
        show_menu
        read secim

        case "$secim" in
            1|01)
                show_dashboard
                print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
                read bos
                ;;
            2|02)
                stop_service "provenir" "service ${PROV_SERVICE} stop" "prov7adm"
                ;;
            3|03)
                start_service "provenir" "service ${PROV_SERVICE} start" "prov7adm"
                ;;
            4|04)
                stop_service "tomcat" "systemctl stop ${TOMCAT_SERVICE}" "was"
                ;;
            5|05)
                start_service "tomcat" "systemctl start ${TOMCAT_SERVICE}" "was"
                ;;
            6|06)
                restart_tomcat
                ;;
            7|07)
                stop_service "httpd" "${HTTPD_BIN} -k stop" "www"
                ;;
            8|08)
                start_service "httpd" "${HTTPD_BIN} -k start" "www"
                ;;
            9|09)
                stop_service "filebeat" "systemctl stop ${FILEBEAT_SERVICE}" ""
                ;;
            10)
                start_service "filebeat" "systemctl start ${FILEBEAT_SERVICE}" ""
                ;;
            11)
                get_thread_dump
                ;;
            12)
                get_heap_dump
                ;;
            0|00)
                clear_screen
                draw_header "  CIKIS  "
                draw_text_line "  Provenir Servis Yonetim Konsolu kapatiliyor..." "$C_GREEN"
                draw_footer
                printf "\n"
                cursor_show
                exit 0
                ;;
            *)
                clear_screen
                draw_header "  HATA  "
                draw_text_line "  Gecersiz secim! Lutfen 0-12 arasinda bir deger girin." "$C_RED"
                draw_footer
                printf "\n"
                print "\n\t${C_YELLOW}Devam etmek icin ENTER'a basin...${C_RESET}"
                read bos
                ;;
        esac
    done
}

# Baslat
cursor_hide
main
cursor_show
