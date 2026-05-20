#!/usr/bin/env bash
# -----------------------------------------------------------------------
# Copyright (c) 2026 Naltarunir (https://github.com/Naltarunir)
# 
# This software is licensed under the European Union Public License 1.2 
# (EUPL-1.2) or later.
#
# The full text of the license can be found at:
# https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# -----------------------------------------------------------------------
# Please refer to the README.md before raising an issue on GitHub. 
#
# NOTE: 'set -e' and 'pipefail' are intentionally omitted. 
# Visit https://mywiki.wooledge.org/BashFAQ/105 for details.
#
# Each section handles its own errors verbosely rather than aborting silently.
# 
# bios-info — verify hardware/BIOS settings after a BIOS update
#
# One-time sudoers setup (replace 'youruser' with your actual username):
#   sudo visudo -f /etc/sudoers.d/system-status
#   youruser ALL=(ALL) NOPASSWD: /usr/bin/dmidecode -t memory   ← Arch/Mabox
#   youruser ALL=(ALL) NOPASSWD: /usr/sbin/dmidecode -t memory  ← Debian/Ubuntu
#   youruser ALL=(ALL) NOPASSWD: /usr/bin/lspci -s * -vv
#   sudo chmod 0440 /etc/sudoers.d/system-status

# Note: run directly (bash bios-info), do not source it.
# If sourced anyway, nounset state is saved and restored at the end.
[[ $- == *u* ]] && _SS_U_WAS_SET=1 || _SS_U_WAS_SET=0
set -u

# ────────────────────────────────────────────────────────────────
# COLOURS — disabled automatically when not a TTY, TERM=dumb,
#           or NO_COLOR is set (https://no-color.dev)
# Only used for signaling: GREEN=ok, YELLOW=warn, RED=fail
# ────────────────────────────────────────────────────────────────
if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' YELLOW='' RED='' BOLD='' RESET=''
fi

# ────────────────────────────────────────────────────────────────
# DISTRO DETECTION — for package install hints
# ────────────────────────────────────────────────────────────────
_PKG_INSTALL="your package manager"
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID_LIKE:-${ID:-}}" in
        *arch*)             _PKG_INSTALL="pacman -S" ;;
        *debian*|*ubuntu*)  _PKG_INSTALL="apt install" ;;
        *fedora*|*rhel*)    _PKG_INSTALL="dnf install" ;;
        *opensuse*)         _PKG_INSTALL="zypper install" ;;
    esac
fi

# ────────────────────────────────────────────────────────────────
# HELPERS
# ────────────────────────────────────────────────────────────────

ok()   { echo -e "${GREEN}│ ✓ ${*}${RESET}"; }
warn() { echo -e "${YELLOW}│ ⚠ ${*}${RESET}"; }
fail() { echo -e "${RED}│ ✗ ${*}${RESET}"; }
info() { echo    "│ ${*}"; }
sect() { echo -e "${BOLD}${*}${RESET}"; }

VERDICTS=()

verdict_ok()   { VERDICTS+=("ok:${*}"); }
verdict_warn() { VERDICTS+=("warn:${*}"); }
verdict_fail() { VERDICTS+=("fail:${*}"); }

flush_verdicts() {
    if [[ ${#VERDICTS[@]} -gt 0 ]]; then
        echo "│ ──────────────────────────────────────────────────────────────"
        for v in "${VERDICTS[@]}"; do
            local type="${v%%:*}"
            local msg="${v#*:}"
            case "$type" in
                ok)   echo -e "${GREEN}│ ✓ ${msg}${RESET}" ;;
                warn) echo -e "${YELLOW}│ ⚠ ${msg}${RESET}" ;;
                fail) echo -e "${RED}│ ✗ ${msg}${RESET}" ;;
            esac
        done
        VERDICTS=()
    fi
}

# ────────────────────────────────────────────────────────────────
# HELP
# ────────────────────────────────────────────────────────────────
show_help() {
    cat <<'EOF'
Usage: bios-info [--help|--check|--full]

Checks BIOS/hardware settings after a BIOS update.
No arguments needed for normal use — just run it.

Options:
  --help    Show this message
  --check   Verify setup requirements without running the full check
  --full    Extended check — adds C-states, power limits (PL1/PL2),
            Above 4G decoding, SATA mode, ECC, boot order, Thunderbolt

One-time setup (required for RAM speed, RAM type/slots, and PCIe/BAR info):

  1. Find your dmidecode path:
       which dmidecode
       → /usr/bin/dmidecode   (Arch/Mabox)
       → /usr/sbin/dmidecode  (Debian/Ubuntu)

  2. Create sudoers entry:
       sudo visudo -f /etc/sudoers.d/system-status

     Add these lines (replace 'youruser' with your actual username):
       youruser ALL=(ALL) NOPASSWD: /usr/bin/dmidecode -t memory
       youruser ALL=(ALL) NOPASSWD: /usr/bin/lspci -s * -vv

  3. Lock the file:
       sudo chmod 0440 /etc/sudoers.d/system-status

Without sudoers:
  - RAM speed, type, and slot info will show as unavailable
  - Resizable BAR and PCIe info will be skipped (discrete GPU only)
  - NVMe PCIe link speed will be skipped
  - Above 4G decoding check will be limited (--full)
EOF
}

# ────────────────────────────────────────────────────────────────
# CHECK
# ────────────────────────────────────────────────────────────────
show_check() {
    echo ""
    sect "┌─ SETUP CHECK ─────────────────────────────────────────────────┘"

    DMIDECODE=$(command -v dmidecode 2>/dev/null)
    if [[ -n "$DMIDECODE" ]]; then
        ok "dmidecode found: $DMIDECODE"
        if sudo -n "$DMIDECODE" -t memory >/dev/null 2>&1; then
            ok "sudoers: dmidecode entry OK"
        else
            fail "sudoers: dmidecode entry MISSING or WRONG PATH"
            info "  Add to /etc/sudoers.d/system-status (replace youruser with your username):"
            info "  youruser ALL=(ALL) NOPASSWD: $DMIDECODE -t memory"
        fi
    else
        fail "dmidecode: not installed ($_PKG_INSTALL dmidecode)"
    fi

    LSPCI=$(command -v lspci 2>/dev/null)
    if [[ -n "$LSPCI" ]]; then
        ok "lspci found: $LSPCI"
        FIRST_PCI=$(lspci | awk '{print $1; exit}')
        if sudo -n "$LSPCI" -s "$FIRST_PCI" -vv >/dev/null 2>&1; then
            ok "sudoers: lspci entry OK"
        else
            fail "sudoers: lspci entry MISSING or WRONG PATH"
            info "  Add to /etc/sudoers.d/system-status (replace youruser with your username):"
            info "  youruser ALL=(ALL) NOPASSWD: $LSPCI -s * -vv"
        fi
    else
        fail "lspci: not installed ($_PKG_INSTALL pciutils)"
    fi

    if command -v glxinfo >/dev/null 2>&1; then
        ok "glxinfo found (Mesa info available)"
    else
        warn "glxinfo: not installed — Mesa info unavailable"
        info "  Install: $_PKG_INSTALL mesa-utils"
    fi

    if command -v vulkaninfo >/dev/null 2>&1; then
        ok "vulkaninfo found (Vulkan info available)"
    else
        warn "vulkaninfo: not installed — Vulkan info unavailable"
        info "  Install: $_PKG_INSTALL vulkan-tools"
    fi

    if command -v efibootmgr >/dev/null 2>&1; then
        ok "efibootmgr found (boot order available in --full)"
    else
        warn "efibootmgr: not installed — boot order unavailable in --full"
        info "  Install: $_PKG_INSTALL efibootmgr"
    fi

    if ! sudo -n "${DMIDECODE:-dmidecode}" -t memory >/dev/null 2>&1 || \
       ! sudo -n "${LSPCI:-lspci}" -s "${FIRST_PCI:-00:00.0}" -vv >/dev/null 2>&1; then
        SUDOERS_FILE="/etc/sudoers.d/system-status"
        if [[ -f "$SUDOERS_FILE" ]]; then
            PERMS=$(stat -c "%a" "$SUDOERS_FILE")
            if [[ "$PERMS" == "440" ]]; then
                ok "$SUDOERS_FILE permissions: $PERMS (correct)"
            else
                warn "$SUDOERS_FILE permissions: $PERMS (should be 440)"
                info "  Fix: sudo chmod 0440 $SUDOERS_FILE"
            fi
        else
            warn "No sudoers entry found — see --help for setup instructions"
        fi
    fi

    sect "└───────────────────────────────────────────────────────────────┐" 
    echo ""
}

# ────────────────────────────────────────────────────────────────
# ARGUMENT HANDLING
# ────────────────────────────────────────────────────────────────
FULL_MODE=false
case "${1:-}" in
    --help|-h)  show_help;  exit 0 ;;
    --check|-c) show_check; exit 0 ;;
    --full|-f)  FULL_MODE=true ;;
    "")         ;;
    *)          echo "Unknown option: $1  (use --help)"; exit 1 ;;
esac

echo ""
if [[ "$FULL_MODE" == true ]]; then
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║     SYSTEM STATUS CHECK - BIOS Settings ok? [FULL MODE]        ║${RESET}"
    echo -e "${BOLD}║     Verifying hardware settings after BIOS update              ║${RESET}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${RESET}"
else
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║        SYSTEM STATUS CHECK - BIOS Settings ok?                 ║${RESET}"
    echo -e "${BOLD}║        Verifying hardware settings after BIOS update           ║${RESET}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${RESET}"
fi
echo ""

# ────────────────────────────────────────────────────────────────
# CPU
# ────────────────────────────────────────────────────────────────
sect "┌─ CPU ─────────────────────────────────────────────────────────┘" 
VERDICTS=()

CPU_MODEL=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs)
info "Model: $CPU_MODEL"

if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    CUR_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    MAX_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)
    [[ -n "$CUR_FREQ" && -n "$MAX_FREQ" ]] && info "Speed: $((CUR_FREQ/1000)) MHz (max: $((MAX_FREQ/1000)) MHz)"
else
    CPU_MHZ=$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo | xargs)
    info "Speed: ${CPU_MHZ:-Unknown} MHz"
fi

MICROCODE=$(awk '/microcode/ {print $3; exit}' /proc/cpuinfo 2>/dev/null)
UCODE_PKG=$(pacman -Q intel-ucode 2>/dev/null || pacman -Q amd-ucode 2>/dev/null)
UCODE_DATE=$(echo "$UCODE_PKG" | grep -oE '[0-9]{8}')
UCODE_NAME=$(echo "$UCODE_PKG" | awk '{print $1}')
if [[ -n "$UCODE_DATE" ]]; then
    info "Microcode: ${MICROCODE:-Unknown} ($UCODE_NAME $UCODE_DATE)"
else
    info "Microcode: ${MICROCODE:-Unknown}"
fi

CPU_VENDOR=$(awk -F: '/vendor_id/ {print $2; exit}' /proc/cpuinfo | xargs)

IOMMU_GROUPS=$(ls /sys/class/iommu/ 2>/dev/null | wc -l)
if [[ "$IOMMU_GROUPS" -eq 0 ]] && ! grep -qiE "intel_iommu|amd_iommu|iommu" /proc/cmdline 2>/dev/null; then
    info "IOMMU: Not active (only needed for VM/GPU passthrough)"
fi

LOGICAL_CORES=$(grep -c "^processor" /proc/cpuinfo)
THREADS_PER_CORE=$(lscpu 2>/dev/null | awk '/Thread\(s\) per core/ {print $NF}')
THREADS_PER_CORE=${THREADS_PER_CORE:-1}
PHYSICAL_CORES=$((LOGICAL_CORES / THREADS_PER_CORE))

if [[ "$FULL_MODE" == true ]]; then
    RAPL_PATH="/sys/class/powercap/intel-rapl/intel-rapl:0"
    if [[ -d "$RAPL_PATH" ]]; then
        PL1_UW=$(cat "$RAPL_PATH/constraint_0_power_limit_uw" 2>/dev/null)
        PL2_UW=$(cat "$RAPL_PATH/constraint_1_power_limit_uw" 2>/dev/null)
        if [[ "$PL1_UW" =~ ^[0-9]+$ && "$PL2_UW" =~ ^[0-9]+$ ]]; then
            info "Power Limits: PL1 $((PL1_UW/1000000))W / PL2 $((PL2_UW/1000000))W"
        fi
    else
        info "Power Limits: Intel RAPL not available"
    fi
fi

if command -v checkupdates >/dev/null 2>&1; then
    if checkupdates 2>/dev/null | grep -qE "intel-ucode|amd-ucode"; then
        verdict_warn "Microcode package update available — update your system"
    else
        verdict_ok "Microcode package up to date"
    fi
fi

if grep -q vmx /proc/cpuinfo; then
    verdict_ok "Intel VT-x: ENABLED"
elif grep -q svm /proc/cpuinfo; then
    verdict_ok "AMD-V (SVM): ENABLED"
else
    [[ "$CPU_VENDOR" == *"Intel"* ]] \
        && verdict_fail "Intel VT-x: NOT DETECTED (check BIOS settings)" \
        || verdict_fail "AMD-V (SVM): NOT DETECTED (check BIOS settings)"
fi

if [[ "$IOMMU_GROUPS" -gt 0 ]]; then
    verdict_ok "IOMMU: ACTIVE ($IOMMU_GROUPS groups)"
elif grep -qiE "intel_iommu|amd_iommu|iommu" /proc/cmdline 2>/dev/null; then
    verdict_warn "IOMMU: in kernel cmdline but no groups found (check BIOS VT-d/AMD-Vi)"
fi

if [[ "$THREADS_PER_CORE" -eq 2 ]]; then
    verdict_ok "SMT: ENABLED ($PHYSICAL_CORES cores → $LOGICAL_CORES threads)"
elif [[ "$THREADS_PER_CORE" -eq 1 ]]; then
    verdict_fail "SMT: DISABLED ($PHYSICAL_CORES cores, enable in BIOS)"
fi

if [[ "$FULL_MODE" == true ]]; then
    if [[ -f /sys/module/intel_idle/parameters/max_cstate ]]; then
        MAX_CSTATE=$(cat /sys/module/intel_idle/parameters/max_cstate 2>/dev/null)
        if [[ "$MAX_CSTATE" -ge 6 ]]; then
            verdict_ok "C-States: All enabled (max C${MAX_CSTATE})"
        else
            verdict_warn "C-States: Limited to C${MAX_CSTATE} (BIOS may be restricting)"
        fi
    elif [[ -f /sys/module/acpi_idle/parameters/max_cstate ]]; then
        MAX_CSTATE=$(cat /sys/module/acpi_idle/parameters/max_cstate 2>/dev/null)
        verdict_ok "C-States: max C${MAX_CSTATE} (via acpi_idle)"
    fi
fi

flush_verdicts
sect "└───────────────────────────────────────────────────────────────┐"
echo

# ────────────────────────────────────────────────────────────────
# RAM
# ────────────────────────────────────────────────────────────────
sect "┌─ RAM ─────────────────────────────────────────────────────────┘"
VERDICTS=()

TOTAL_RAM=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)
info "Total: $TOTAL_RAM"

DMIDECODE=$(command -v dmidecode 2>/dev/null)
DMIDECODE_MEM=""
if [[ -n "$DMIDECODE" ]] && sudo -n "$DMIDECODE" -t memory >/dev/null 2>&1; then
    DMIDECODE_MEM=$(sudo -n "$DMIDECODE" -t memory 2>/dev/null)

    RAM_TYPE=$(awk '/^\s*Type:/ && !/Unknown/ && !/Other/ && !/Error/ {
        gsub(/^\s+|\s+$/, "", $2); print $2; exit}' <<< "$DMIDECODE_MEM")
    info "Type: ${RAM_TYPE:-Unknown}"

    SLOTS_TOTAL=$(grep -c "Memory Device" <<< "$DMIDECODE_MEM" || true)
    SLOTS_USED=$(awk '/^\s*Size:/ && /GB|MB/ {count++} END {print count+0}' <<< "$DMIDECODE_MEM")
    info "Slots: $SLOTS_USED of $SLOTS_TOTAL populated"

    if [[ "$FULL_MODE" == true ]]; then
        ECC=$(awk '/Error Correction Type:/ {
            sub(/.*: /, ""); gsub(/^\s+|\s+$/, ""); print; exit}' <<< "$DMIDECODE_MEM")
        [[ -n "$ECC" ]] && info "ECC: $ECC"
    fi

    RAM_SPEED=$(awk -F: '/^\s*Speed:/ && /[0-9]/ && !/Unknown/ {
        gsub(/^\s+|\s+$/, "", $2); print $2; exit}' <<< "$DMIDECODE_MEM")
    if [[ -n "$RAM_SPEED" ]]; then
        verdict_ok "Speed: $RAM_SPEED"
    else
        verdict_warn "Speed: Unable to detect (check XMP/DOCP/EXPO in BIOS)"
    fi
else
    verdict_warn "dmidecode not available (or missing sudoers entry)"
fi

flush_verdicts
sect "└───────────────────────────────────────────────────────────────┐"
echo

# ────────────────────────────────────────────────────────────────
# GPU & GRAPHICS
# ────────────────────────────────────────────────────────────────
sect "┌─ GPU & GRAPHICS ──────────────────────────────────────────────┘"
VERDICTS=()

GPU_LINE=$(lspci | grep -E "VGA|3D|Display" | head -1)
GPU_NAME=$(echo "$GPU_LINE" | cut -d: -f3- | xargs)
GPU_PCI=$(echo "$GPU_LINE" | awk '{print $1}')

if echo "$GPU_NAME" | grep -qi "intel"; then       GPU_VENDOR="intel"
elif echo "$GPU_NAME" | grep -qi "amd\|radeon"; then GPU_VENDOR="amd"
elif echo "$GPU_NAME" | grep -qi "nvidia"; then     GPU_VENDOR="nvidia"
else                                                 GPU_VENDOR="unknown"
fi

info "GPU: ${GPU_NAME:-None detected}"

if command -v glxinfo >/dev/null 2>&1; then
    GLXINFO=$(glxinfo -B 2>/dev/null)
    info "Mesa: $(awk -F: '/OpenGL version string/ {print $2}' <<< "$GLXINFO" | xargs)"
    info "Renderer: $(awk -F: '/OpenGL renderer string/ {print $2}' <<< "$GLXINFO" | xargs)"
else
    info "Mesa info: glxinfo not available"
fi

if command -v vulkaninfo >/dev/null 2>&1; then
    VULKAN_API=$(vulkaninfo --summary 2>/dev/null | awk -F: '/Vulkan Instance Version/ {print $2}' | xargs)
    info "Vulkan: ${VULKAN_API:-Available}"
fi

if [[ "$GPU_VENDOR" == "amd" ]]; then
    GPU_SCLK="" GPU_MCLK=""
    for card in /sys/class/drm/card*/device; do
        [[ -f "$card/pp_dpm_sclk" ]] && GPU_SCLK=$(grep "\*" "$card/pp_dpm_sclk" | awk '{print $2}')
        [[ -f "$card/pp_dpm_mclk" ]] && GPU_MCLK=$(grep "\*" "$card/pp_dpm_mclk" | awk '{print $2}')
        if [[ -n "$GPU_SCLK" && -n "$GPU_MCLK" ]]; then
            info "Clocks: Core $GPU_SCLK | Memory $GPU_MCLK"; break
        fi
    done
    VRAM_FOUND=false
    for CARD in /sys/class/drm/card*/device/mem_info_vram_total; do
        [[ -f "$CARD" ]] || continue
        CARD_DIR=$(dirname "$CARD")
        VRAM_TOTAL=$(cat "$CARD" 2>/dev/null)
        VRAM_USED=$(cat "${CARD_DIR}/mem_info_vram_used" 2>/dev/null)
        if [[ "$VRAM_TOTAL" =~ ^[0-9]+$ && "$VRAM_TOTAL" -gt 0 ]]; then
            VRAM_FOUND=true
            info "VRAM: $((VRAM_USED/1024/1024)) MiB used / $((VRAM_TOTAL/1024/1024)) MiB total"
            break
        fi
    done
    [[ "$VRAM_FOUND" == false ]] && info "VRAM: Unable to detect"
elif [[ "$GPU_VENDOR" == "intel" ]]; then
    info "VRAM: Shared system RAM (integrated GPU)"
fi

flush_verdicts
sect "└───────────────────────────────────────────────────────────────┐"
echo

# ────────────────────────────────────────────────────────────────
# STORAGE
# ────────────────────────────────────────────────────────────────
sect "┌─ STORAGE ─────────────────────────────────────────────────────┘"
VERDICTS=()

NVME_COUNT=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    NVME_PCI=$(echo "$line" | awk '{print $1}')
    NVME_NAME=$(echo "$line" | cut -d: -f3- | xargs)
    NVME_COUNT=$((NVME_COUNT + 1))
    NVME_LNKSTA=$(sudo -n lspci -s "$NVME_PCI" -vv 2>/dev/null | grep "LnkSta:")
    info "NVMe $NVME_COUNT: $NVME_NAME"
    if [[ -n "$NVME_LNKSTA" ]]; then
        NVME_SPEED=$(echo "$NVME_LNKSTA" | sed -E 's/.*Speed ([^,]+),.*/\1/')
        NVME_WIDTH=$(echo "$NVME_LNKSTA" | sed -E 's/.*Width x([0-9]+).*/\1/')
        [[ "$NVME_SPEED" != "$NVME_LNKSTA" ]] && info "        PCIe $NVME_SPEED x$NVME_WIDTH"
    fi
done < <(lspci | grep -i "Non-Volatile\|NVMe")
[[ "$NVME_COUNT" -eq 0 ]] && info "NVMe: None detected"

if [[ "$FULL_MODE" == true ]]; then
    SATA_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        SATA_COUNT=$((SATA_COUNT + 1))
        SATA_NAME=$(echo "$line" | cut -d: -f3- | xargs)
        if echo "$SATA_NAME" | grep -qi "ahci"; then
            verdict_ok "SATA $SATA_COUNT: AHCI mode — $SATA_NAME"
        elif echo "$SATA_NAME" | grep -qi "raid"; then
            verdict_warn "SATA $SATA_COUNT: RAID mode — use AHCI for Linux unless intentional"
        else
            info "SATA $SATA_COUNT: $SATA_NAME"
        fi
    done < <(lspci | grep -iE "SATA|AHCI" | grep -iv "NVMe\|Non-Volatile")
    [[ "$SATA_COUNT" -eq 0 ]] && info "SATA: No SATA controller detected"
fi

flush_verdicts
sect "└───────────────────────────────────────────────────────────────┐"
echo

# ────────────────────────────────────────────────────────────────
# PERFORMANCE FEATURES
# ────────────────────────────────────────────────────────────────
sect "┌─ PERFORMANCE FEATURES ────────────────────────────────────────┘"
VERDICTS=()

if [[ "$GPU_VENDOR" == "intel" ]]; then
    info "BAR/PCIe: Integrated GPU — no discrete PCIe slot"
elif [[ -n "${GPU_PCI:-}" ]]; then
    BAR_INFO=$(sudo -n lspci -s "$GPU_PCI" -vv 2>/dev/null | grep -i "Region 0")
    if [[ -n "$BAR_INFO" ]]; then
        BAR_SIZE=$(echo "$BAR_INFO" | sed -E 's/.*\[size=([^]]+)\].*/\1/')
        if [[ -n "$BAR_SIZE" && "$BAR_SIZE" != "$BAR_INFO" ]]; then
            if [[ "$BAR_SIZE" == *"G"* ]]; then
                verdict_ok "Resizable BAR: ENABLED ($BAR_SIZE)"
            else
                verdict_fail "Resizable BAR: DISABLED ($BAR_SIZE) — enable in BIOS"
            fi
        fi
    fi
    PCIE_INFO=$(sudo -n lspci -s "$GPU_PCI" -vv 2>/dev/null | grep -i "LnkSta:")
    if [[ -n "$PCIE_INFO" ]]; then
        PCIE_SPEED=$(echo "$PCIE_INFO" | sed -E 's/.*Speed ([^,]+),.*/\1/')
        PCIE_WIDTH=$(echo "$PCIE_INFO" | sed -E 's/.*Width x([0-9]+).*/\1/')
        if [[ "$PCIE_SPEED" == *"32GT/s"* && "$PCIE_WIDTH" == "16" ]]; then
            verdict_ok "PCIe: Gen5 x16 @ 32GT/s (maximum performance)"
        elif [[ "$PCIE_SPEED" == *"16GT/s"* && "$PCIE_WIDTH" == "16" ]]; then
            verdict_ok "PCIe: Gen4 x16 @ 16GT/s (good)"
        elif [[ "$PCIE_WIDTH" != "16" ]]; then
            verdict_warn "PCIe: $PCIE_SPEED x$PCIE_WIDTH (expected x16)"
        elif [[ "$PCIE_SPEED" == *"8GT/s"* ]]; then
            verdict_warn "PCIe: Gen3 @ 8GT/s (slower than expected)"
        else
            info "PCIe: $PCIE_SPEED x$PCIE_WIDTH"
        fi
    fi
fi

if [[ "$FULL_MODE" == true ]]; then
    AB4G=$(sudo -n lspci -vv 2>/dev/null | grep -c "Memory at.*64-bit, prefetchable" || true)
    if [[ "$AB4G" -gt 0 ]]; then
        verdict_ok "Above 4G Decoding: Active ($AB4G 64-bit prefetchable regions)"
    else
        info "Above 4G Decoding: No 64-bit prefetchable BARs detected"
    fi
fi

if command -v powerprofilesctl >/dev/null 2>&1; then
    CURRENT_PROFILE=$(powerprofilesctl get 2>/dev/null)
    if [[ -n "$CURRENT_PROFILE" ]]; then
        if [[ "$CURRENT_PROFILE" == "performance" ]]; then
            verdict_ok "Power Profile: Performance mode"
        elif [[ "$CURRENT_PROFILE" == "balanced" ]]; then
            verdict_warn "Power Profile: Balanced (consider performance for gaming)"
        else
            info "Power Profile: $CURRENT_PROFILE"
        fi
    fi
else
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
        if [[ "$GOV" == "performance" ]]; then
            verdict_ok "CPU Governor: Performance"
        else
            info "CPU Governor: $GOV"
        fi
    fi
fi

flush_verdicts
sect "└───────────────────────────────────────────────────────────────┐"
echo

# ────────────────────────────────────────────────────────────────
# SYSTEM INFO
# ────────────────────────────────────────────────────────────────
sect "┌─ SYSTEM INFO ─────────────────────────────────────────────────┘"
VERDICTS=()

info "Kernel: $(uname -r)"

BIOS_VENDOR=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null)
BIOS_VERSION=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
BIOS_DATE=$(cat /sys/class/dmi/id/bios_date 2>/dev/null)
info "BIOS: ${BIOS_VENDOR:-Unknown} ${BIOS_VERSION:-Unknown}"
info "Date: ${BIOS_DATE:-Unknown}"

if [[ "$FULL_MODE" == true ]]; then
    if command -v efibootmgr >/dev/null 2>&1; then
        BOOT_CURRENT=$(efibootmgr 2>/dev/null | awk '/BootCurrent:/ {print $2}')
        info "Boot Current: ${BOOT_CURRENT:-Unknown}"
        info "Boot Order:"
        efibootmgr 2>/dev/null | awk \
            -v g="${GREEN}" -v r="${RED}" -v rs="${RESET}" \
            '/Boot[0-9A-F]{4}/ && !/BootCurrent|BootOrder|BootNext/ {
                active = /\*/ ? g "✓" rs : r "✗" rs
                sub(/Boot[0-9A-F]{4}[* ]+/, "")
                printf "│   %s %s\n", active, $0
            }' | head -6
    else
        info "Boot Order: efibootmgr not installed ($_PKG_INSTALL efibootmgr)"
    fi

    TB_DEVICES=$(ls /sys/bus/thunderbolt/devices/ 2>/dev/null | wc -l)
    if [[ "$TB_DEVICES" -gt 0 ]]; then
        TB_SECURITY=$(cat /sys/bus/thunderbolt/devices/domain0/security 2>/dev/null | xargs)
        info "Thunderbolt: Present (security: ${TB_SECURITY:-unknown}, devices: $TB_DEVICES)"
    else
        info "Thunderbolt: Not detected or disabled in BIOS"
    fi
fi

if [[ -d /sys/firmware/efi ]]; then
    verdict_ok "Boot Mode: UEFI"
    SB_VAR=$(find /sys/firmware/efi/efivars -name "SecureBoot-*" 2>/dev/null | head -1)
    if [[ -n "$SB_VAR" ]]; then
        SB_VAL=$(od -An -t u1 "$SB_VAR" 2>/dev/null | awk '{print $NF}')
        if [[ "$SB_VAL" == "1" ]]; then
            verdict_ok "Secure Boot: ENABLED"
        else
            verdict_warn "Secure Boot: DISABLED"
        fi
    elif command -v mokutil >/dev/null 2>&1; then
        SB_STATUS=$(mokutil --sb-state 2>/dev/null | xargs)
        verdict_warn "Secure Boot: ${SB_STATUS:-Unknown}"
    fi
else
    verdict_fail "Boot Mode: Legacy BIOS (not UEFI)"
fi

if [[ -d /sys/class/tpm/tpm0 ]]; then
    TPM_VER=$(cat /sys/class/tpm/tpm0/tpm_version_major 2>/dev/null)
    verdict_ok "TPM: Present (version ${TPM_VER:-?})"
else
    verdict_warn "TPM: Not detected (check BIOS fTPM/TPM setting)"
fi

flush_verdicts
sect "└───────────────────────────────────────────────────────────────┐"
echo
