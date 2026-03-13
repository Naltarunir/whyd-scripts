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
# -----------------------------------------------------------------------

set -u
export LANG=C.UTF-8

# =======================================================================
# ── COLOUR CONSTANTS ────────────────────────────────────────────────────
# =======================================================================
# Always-on ANSI — no terminal detection. The wrapper opens the log in a
# viewer that renders escape codes, so colour is always appropriate.

readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_RED=$'\033[31m'
readonly C_CYAN=$'\033[36m'
readonly C_BOLD_RED=$'\033[1;31m'
readonly C_BOLD_GREEN=$'\033[1;32m'
readonly C_BOLD_YELLOW=$'\033[1;33m'
readonly C_BOLD_CYAN=$'\033[1;36m'

# =======================================================================
# ── BOX LAYOUT HELPERS ──────────────────────────────────────────────────
# =======================================================================
# Section boxes are 67 display-characters wide:
#
#   ┌─ TITLE ── ... ──┐    open_section "TITLE"
#   │ content              row_* helpers (open right edge by design)
#   └── ... ──────────┘    close_section
#
# Width formula for open_section:
#   ┌(1) ─(1) (1) TITLE(n) (1) fill(f) ┐(1) = 67  →  f = 62 − n
# close border: └ + 65×─ + ┘ = 67

# _box_fill N
# Outputs N repetitions of ─ (pure bash, no external tools).
_box_fill() {
    local n="$1" fill='' i
    for (( i=0; i<n; i++ )); do fill+='─'; done
    printf '%s' "$fill"
}

# open_section TITLE
# Prints a coloured titled top border. Title must be plain ASCII.
open_section() {
    local title="$1"
    local fill_count=$(( 62 - ${#title} ))
    (( fill_count < 1 )) && fill_count=1
    local fill; fill=$(_box_fill "$fill_count")
    printf "%b┌─ %b%s%b%b %s┐%b\n" \
    "$C_BOLD" "$C_BOLD_CYAN" "$title" "$C_RESET" "$C_BOLD" "$fill" "$C_RESET"
}

# close_section
# Prints the bottom border of a section box.
close_section() {
    printf '└%s┘\n' "$(_box_fill 65)"
}

# =======================================================================
# ── ROW PRINT HELPERS ───────────────────────────────────────────────────
# =======================================================================
# All row_* functions print exactly one │-prefixed line to stdout.
# Use these everywhere inside open_section / close_section pairs.

# row_ok MESSAGE
# Green ✓ — value is correct / feature is active.
row_ok() {
    printf "│ ${C_BOLD_GREEN}✓${C_RESET} %s\n" "$*"
}

# row_fail MESSAGE
# Red ✗ — value is wrong or a desired BIOS feature is disabled.
row_fail() {
    printf "│ ${C_RED}✗${C_RESET} %s\n" "$*"
}

# row_warn MESSAGE
# Yellow ⚠ — degraded: something couldn't be read or is suboptimal.
row_warn() {
    printf "│ ${C_BOLD_YELLOW}⚠${C_RESET} %s\n" "$*"
}

# row_error MESSAGE
# Bold red — unexpected script-level failure (not a BIOS setting issue).
row_error() {
    printf "│ ${C_BOLD_RED}✗ ERROR:${C_RESET} %s\n" "$*"
}

# row_info MESSAGE
# Plain indented text — supplementary detail, sub-items.
row_info()  { printf "│   %s\n" "$*"; }

# row_hint MESSAGE
# Cyan → — actionable next step the user should take.
row_hint() {
    printf "│   ${C_CYAN}→${C_RESET} %s\n" "$*"
}

# row_label LABEL VALUE
# Aligned "│   LABEL:          VALUE" line for key/value pairs.
row_label() { 
    printf "│   ${C_BOLD}%-16s${C_RESET} %s\n" "${1}:" "$2";
}

# row_blank
# Empty │ line — visual spacer inside a section.
row_blank() { printf "│\n"; }

# row_sub MESSAGE
# Indented sub-item (one level deeper than row_info), for codec lists etc.
row_sub()   { printf "│     %s\n" "$*"; }

# =======================================================================
# ── SYSFS / FILE HELPERS ────────────────────────────────────────────────
# =======================================================================

# read_sys PATH [FALLBACK]
# Reads a sysfs (or any) file; returns FALLBACK string if missing or
# unreadable. Never exits non-zero — safe inside $(…) and arithmetic.
read_sys() {
    local path="$1" fallback="${2:-}"
    if [[ -f "$path" ]]; then
        cat "$path" 2>/dev/null || printf '%s' "$fallback"
    else
        printf '%s' "$fallback"
    fi
}

# =======================================================================
# ── COMMAND / DEPENDENCY HELPERS ────────────────────────────────────────
# =======================================================================

# Returns 0 if CMD is on PATH, 1 otherwise. Silent.
have() { command -v "$1" >/dev/null 2>&1; }

# require_cmd CMD [PACMAN_PKG]
# Prints row_warn + pacman install hint if CMD is missing.
# Returns 0 if found, 1 if not — caller can short-circuit its section.
#
# Example:
#   require_cmd vainfo libva-utils || { close_section; echo; continue; }
require_cmd() {
    local cmd="$1"
    local pkg="${2:-$cmd}"
    if have "$cmd"; then
        return 0
    fi
    row_warn "${cmd} not installed — section skipped"
    row_hint "sudo pacman -S ${pkg}"
    return 1
}

# =======================================================================
# ── SUDO VALIDATION HELPERS ─────────────────────────────────────────────
# =======================================================================

# sudo_ok CMD [ARGS...]
# Silently tests whether passwordless sudo -n works for this exact command.
# Returns 0 on success, 1 on failure. Prints nothing.
#
# Use this when you want to branch without printing anything yourself:
#   if sudo_ok /usr/sbin/dmidecode -t memory; then ... fi
sudo_ok() {
    sudo -n "$@" >/dev/null 2>&1
}

# sudo_require LABEL CMD [ARGS...]
# Like sudo_ok, but on failure emits row_warn + row_hint explaining
# exactly which sudoers rule to add, using the full command path.
# Returns 0 on success, 1 on failure.
#
# Example:
#   sudo_require "RAM speed" /usr/sbin/dmidecode -t memory || return
sudo_require() {
    local label="$1"; shift
    if sudo -n "$@" >/dev/null 2>&1; then
        return 0
    fi
    local full_cmd; full_cmd=$(command -v "${1}") || full_cmd="${1}"
    row_warn "${label}: passwordless sudo not configured"
    row_hint "Add to /etc/sudoers.d/system-status:"
    row_info "  ${USER} ALL=(ALL) NOPASSWD: ${full_cmd} ${*:2}"
    row_hint "Then: sudo chmod 0440 /etc/sudoers.d/system-status"
    return 1
}

# =======================================================================
# ── SCRIPT START ────────────────────────────────────────────────────────
# =======================================================================

printf "\n"
echo   "╔═════════════════════════════════════════════════════════════════╗"
echo   "║                 'What have you done?' - Checker                 ║"
echo   "║         Verifying hardware settings after BIOS update           ║"
echo   "╚═════════════════════════════════════════════════════════════════╝"

# -----------------------------------------------------------------------
# CPU INFO
# -----------------------------------------------------------------------
open_section "CPU"

CPU_MODEL=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null \
    | xargs 2>/dev/null) || CPU_MODEL=""
if [[ -z "$CPU_MODEL" ]]; then
    row_warn "Could not read CPU model from /proc/cpuinfo"
else
    row_label "Model" "$CPU_MODEL"
fi

# Frequency — prefer cpufreq sysfs, fall back to /proc/cpuinfo MHz line
if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    CUR_FREQ=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    MAX_FREQ=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
    if [[ -n "$CUR_FREQ" && -n "$MAX_FREQ" ]]; then
        row_label "Speed" "$((CUR_FREQ/1000)) MHz  (max: $((MAX_FREQ/1000)) MHz)"
    else
        row_warn "cpufreq sysfs present but values are unreadable"
    fi
else
    CPU_MHZ=$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo 2>/dev/null \
        | xargs 2>/dev/null) || CPU_MHZ=""
    row_label "Speed" "${CPU_MHZ:-Unknown} MHz  (cpufreq sysfs unavailable)"
fi

# Hardware Virtualisation (AMD-V / Intel VT-x)
if grep -q svm /proc/cpuinfo 2>/dev/null; then
    row_ok  "AMD-V (SVM) virtualisation: ENABLED"
elif grep -q vmx /proc/cpuinfo 2>/dev/null; then
    row_ok  "Intel VT-x virtualisation: ENABLED"
else
    row_fail "Hardware virtualisation: NOT DETECTED"
    row_hint "BIOS › CPU Configuration › SVM Mode (AMD) or VT-x (Intel)"
fi

# SMT — Simultaneous Multi-Threading
LOGICAL_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null) || LOGICAL_CORES=0
if [[ "$LOGICAL_CORES" -eq 0 ]]; then
    row_warn "Could not count logical cores from /proc/cpuinfo"
elif ! have lscpu; then
    row_warn "lscpu not found — cannot verify SMT status"
    row_hint "sudo pacman -S util-linux"
else
    THREADS_PER_CORE=$(lscpu 2>/dev/null | awk '/Thread\(s\) per core/ {print $NF}') \
        || THREADS_PER_CORE=""
    if [[ -z "$THREADS_PER_CORE" || ! "$THREADS_PER_CORE" =~ ^[0-9]+$ ]]; then
        row_warn "Could not parse threads-per-core from lscpu output"
    else
        PHYSICAL_CORES=$(( LOGICAL_CORES / THREADS_PER_CORE ))
        if [[ "$THREADS_PER_CORE" -ge 2 ]]; then
            row_ok   "SMT: ENABLED  ($PHYSICAL_CORES cores → $LOGICAL_CORES threads)"
        elif [[ "$THREADS_PER_CORE" -eq 1 ]]; then
            row_fail "SMT: DISABLED  ($PHYSICAL_CORES physical cores, no hyperthreading)"
            row_hint "BIOS › AMD CBS › CPU Common Options › Thread Enablement"
        else
            row_warn "SMT: unexpected threads-per-core value: ${THREADS_PER_CORE}"
        fi
    fi
fi

close_section; echo

# -----------------------------------------------------------------------
# CPU ARCHITECTURE LEVEL & ZEN GENERATION
# -----------------------------------------------------------------------
open_section "CPU ARCHITECTURE"

FLAGS=$(grep -m1 "^flags" /proc/cpuinfo 2>/dev/null | cut -d: -f2) || FLAGS=""

if [[ -z "$FLAGS" ]]; then
    row_warn "Cannot read CPU flags from /proc/cpuinfo — architecture detection skipped"
else
    # has_flag: checks for a whole-word flag match in the flags string
    has_flag() { [[ " $FLAGS " == *" $1 "* ]]; }

    # ── x86-64 microarchitecture level detection ──────────────────────
    # Each level is a strict superset of the one below (per the ABI spec).
    ARCH_LEVEL=1

    # v2: SSE3, SSSE3, SSE4.1, SSE4.2, CX16 (CMPXCHG16B), LAHF, POPCNT
    if has_flag pni   && has_flag ssse3  && has_flag sse4_1 && has_flag sse4_2 \
    && has_flag cx16  && has_flag lahf_lm && has_flag popcnt; then
        ARCH_LEVEL=2
    fi

    # v3: v2 + AVX, AVX2, BMI1, BMI2, F16C, FMA, MOVBE, XSAVE
    if [[ $ARCH_LEVEL -ge 2 ]] \
    && has_flag avx   && has_flag avx2  && has_flag bmi1  && has_flag bmi2 \
    && has_flag f16c  && has_flag fma   && has_flag movbe && has_flag xsave; then
        ARCH_LEVEL=3
    fi

    # v4: v3 + AVX-512 F, BW, CD, DQ, VL
    if [[ $ARCH_LEVEL -ge 3 ]] \
    && has_flag avx512f  && has_flag avx512bw && has_flag avx512cd \
    && has_flag avx512dq && has_flag avx512vl; then
        ARCH_LEVEL=4
    fi

    case $ARCH_LEVEL in
        4) row_ok   "x86-64-v4  (AVX-512 — maximum ISA level)" ;;
        3) row_ok   "x86-64-v3  (AVX2 + FMA — modern baseline)" ;;
        2) row_warn "x86-64-v2  (SSE4.2 only — some modern software may not run)" ;;
        *) row_fail "x86-64-v1  (baseline only — very old CPU)" ;;
    esac

    # ── Key SIMD extensions ───────────────────────────────────────────
    row_blank
    row_info "SIMD / ISA extensions:"
 
    # AVX-512 subsets (only list what's actually present)
    AVX512_FOUND=false
    for f in avx512f avx512bw avx512cd avx512dq avx512vl \
              avx512vnni avx512bf16 avx512ifma avx512vbmi; do
        if has_flag "$f"; then
            row_sub "✓ ${f}"
            AVX512_FOUND=true
        fi
    done
    if $AVX512_FOUND; then
        row_ok  "AVX-512: supported"
    else
        row_info "AVX-512: not supported by this CPU"
    fi

    # Other notable extensions
    has_flag avx    && row_sub "✓ AVX"
    has_flag fma    && row_sub "✓ FMA3"
    has_flag bmi2   && row_sub "✓ BMI2"
    has_flag sha_ni && row_sub "✓ SHA-NI"
    if has_flag avx2; then
        row_sub "✓ AVX2"
    else
        row_sub "✗ AVX2"
    fi

    if has_flag aes; then
        row_sub "✓ AES-NI"
    else
        row_sub "✗ AES-NI  (hardware crypto unavailable)"
    fi
fi

# ── AMD Zen generation via CPUID family/model (using lscpu) ────────────
FAMILY=$(lscpu 2>/dev/null | awk -F: '/^CPU family:/ {print $2; exit}' | xargs) || FAMILY=""
MODEL_NUM=$(lscpu 2>/dev/null | awk -F: '/^Model:/ {print $2; exit}' | xargs) || MODEL_NUM=""

if [[ -n "$FAMILY" ]]; then
    row_blank
    case "$FAMILY" in
        26)  row_ok "AMD microarchitecture: Zen 5  (Family 1Ah)" ;;
        25)
            case "${MODEL_NUM:-0}" in
                16|17|24|25|32|96|97|116|117)
                    row_ok "AMD microarchitecture: Zen 4  (Family 19h)" ;;
                1|8|33|80|81)
                    row_ok "AMD microarchitecture: Zen 3  (Family 19h)" ;;
                *)
                    row_info "AMD Family 19h, Model ${MODEL_NUM:-unknown}  (Zen 3 or Zen 4 — verify)" ;;
            esac ;;
        23)  row_info "AMD Family 17h  (Zen / Zen+ / Zen 2 — see lscpu for exact model)" ;;
        22)  row_info "AMD Family 16h  (Jaguar/Puma — pre-Zen)" ;;
        *)   row_info "CPU Family: ${FAMILY}  (non-AMD or unrecognised)" ;;
    esac
fi

close_section; echo

# -----------------------------------------------------------------------
# RAM INFO
# -----------------------------------------------------------------------
open_section "RAM"

TOTAL_RAM=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' \
    /proc/meminfo 2>/dev/null) || TOTAL_RAM=""
if [[ -z "$TOTAL_RAM" ]]; then
    row_warn "Could not read MemTotal from /proc/meminfo"
else
    row_label "Total" "$TOTAL_RAM"
fi

if ! require_cmd dmidecode; then
    : # require_cmd already printed the warning + hints
elif sudo_require "RAM speed (dmidecode)" /usr/sbin/dmidecode -t memory; then
    RAM_SPEED=$(sudo -n /usr/sbin/dmidecode -t memory 2>/dev/null \
        | awk -F: '/Speed:/ && !/Unknown/ && !/Configured/ {print $2}' \
        | grep -v "^[[:space:]]*$" | sort -u | head -1 | xargs 2>/dev/null) \
        || RAM_SPEED=""
    if [[ -n "$RAM_SPEED" ]]; then
        row_ok  "Speed: ${RAM_SPEED}"
    else
        row_warn "Speed: dmidecode returned no speed data"
        row_hint "Verify XMP/DOCP is enabled in BIOS"
        row_hint "BIOS › Overclocking › DOCP/XMP Profile"
    fi
fi

close_section; echo

# -----------------------------------------------------------------------
# GPU & GRAPHICS
# -----------------------------------------------------------------------
open_section "GPU & GRAPHICS"

GPU_NAME=$(lspci 2>/dev/null | grep -E "VGA|3D" | grep -i AMD \
    | cut -d: -f3- | xargs 2>/dev/null) || GPU_NAME=""
if [[ -z "$GPU_NAME" ]]; then
    row_warn "No AMD GPU detected via lspci"
else
    row_label "GPU" "$GPU_NAME"
fi

# Mesa / OpenGL
if require_cmd glxinfo mesa-utils; then
    MESA_VER=$(glxinfo -B 2>/dev/null \
        | awk -F: '/OpenGL version string/ {print $2}' | xargs 2>/dev/null) \
        || MESA_VER=""
    RENDERER=$(glxinfo -B 2>/dev/null \
        | awk -F: '/OpenGL renderer string/ {print $2}' | xargs 2>/dev/null) \
        || RENDERER=""
    if [[ -z "$MESA_VER" ]]; then
        row_warn "glxinfo found but returned no output — is DISPLAY/WAYLAND_DISPLAY set?"
    else
        row_label "Mesa" "$MESA_VER"
        row_label "Renderer" "$RENDERER"
    fi
fi

# GPU Clock Speeds via DRM power state sysfs
row_blank
GPU_SCLK="" GPU_MCLK="" CLOCKS_FOUND=false
for card in /sys/class/drm/card*/device; do
    [[ -f "$card/pp_dpm_sclk" ]] \
        && GPU_SCLK=$(grep "\*" "$card/pp_dpm_sclk" 2>/dev/null | awk '{print $2}') || true
    [[ -f "$card/pp_dpm_mclk" ]] \
        && GPU_MCLK=$(grep "\*" "$card/pp_dpm_mclk" 2>/dev/null | awk '{print $2}') || true
    if [[ -n "$GPU_SCLK" && -n "$GPU_MCLK" ]]; then
        row_ok   "GPU clocks active"
        row_label "Core" "$GPU_SCLK"
        row_label "Memory" "$GPU_MCLK"
        CLOCKS_FOUND=true
        break
    fi
done
$CLOCKS_FOUND || row_warn "GPU clock sysfs not found  (amdgpu driver loaded?)"

# Vulkan
if require_cmd vulkaninfo vulkan-tools; then
    VULKAN_VER=$(vulkaninfo --summary 2>/dev/null \
        | awk -F: '/Vulkan Instance Version/ {print $2}' | xargs 2>/dev/null) \
        || VULKAN_VER=""
    row_label "Vulkan" "${VULKAN_VER:-Available (version parse failed)}"
fi

# VRAM via DRM sysfs
row_blank
VRAM_FOUND=false
for CARD in /sys/class/drm/card*/device/mem_info_vram_total; do
    [[ -f "$CARD" ]] || continue
    CARD_DIR=$(dirname "$CARD")
    VRAM_TOTAL=$(cat "$CARD" 2>/dev/null)           || VRAM_TOTAL=""
    VRAM_USED=$(cat "${CARD_DIR}/mem_info_vram_used" 2>/dev/null) || VRAM_USED=""
    if [[ -n "$VRAM_TOTAL" && "$VRAM_TOTAL" -gt 0 ]]; then
        row_label "VRAM" \
            "$((VRAM_USED / 1024 / 1024)) MiB used / $((VRAM_TOTAL / 1024 / 1024)) MiB total"
        VRAM_FOUND=true
        break
    fi
done
$VRAM_FOUND || row_warn "VRAM sysfs not found  (amdgpu driver may not be loaded)"

close_section; echo

# -----------------------------------------------------------------------
# VA-API — Hardware Video Decode / Encode
# -----------------------------------------------------------------------
open_section "VA-API  (HARDWARE VIDEO ACCELERATION)"

if require_cmd vainfo libva-utils; then

    # Auto-detect DRI render node; honour $VAAPI_DEVICE env override
    VAAPI_DEV="${VAAPI_DEVICE:-}"
    if [[ -z "$VAAPI_DEV" ]]; then
        for dev in /dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/card0; do
            [[ -e "$dev" ]] && { VAAPI_DEV="$dev"; break; }
        done
    fi

    if [[ -z "$VAAPI_DEV" ]]; then
        row_error "No DRI device found under /dev/dri/"
        row_hint  "Check amdgpu is loaded:  lsmod | grep amdgpu"
        row_hint  "Check udev rules:        ls -la /dev/dri/"
    else
        row_label "Device" "$VAAPI_DEV"

        VAINFO_OUT=$(vainfo --display drm --device "$VAAPI_DEV" 2>&1) \
            && VAINFO_RC=0 || VAINFO_RC=$?

        if [[ $VAINFO_RC -ne 0 ]]; then
            row_error "vainfo exited with code ${VAINFO_RC}"
            # Surface the actual error lines so the user isn't left guessing
            while IFS= read -r errline; do
                row_info "  ${errline}"
            done < <(echo "$VAINFO_OUT" | grep -iE "error|failed|cannot|libva" | head -5)
            row_blank
            row_hint "Common causes:"
            row_sub  "libva-mesa-driver not installed  (sudo pacman -S libva-mesa-driver)"
            row_sub  "User not in 'render' group       (sudo usermod -aG render \$USER)"
            row_sub  "amdgpu driver not loaded         (lsmod | grep amdgpu)"
            row_sub  "LIBVA_DRIVER_NAME not set        (export LIBVA_DRIVER_NAME=radeonsi)"
        else
            # VA-API version
            VA_VER=$(echo "$VAINFO_OUT" \
                | awk '/VA-API version/ {match($0,/[0-9]+\.[0-9]+\.[0-9]+/,a); print a[0]; exit}') \
                || VA_VER=""
            [[ -n "$VA_VER" ]] && row_ok "VA-API version: ${VA_VER}"

            # Driver string
            VA_DRV=$(echo "$VAINFO_OUT" \
                | awk -F: '/Driver version/ {print $2; exit}' | xargs 2>/dev/null) \
                || VA_DRV=""
            [[ -n "$VA_DRV" ]] && row_label "Driver" "$VA_DRV"

            # Total profile count
            PROFILE_COUNT=$(echo "$VAINFO_OUT" | grep -c "VAProfile") || PROFILE_COUNT=0
            row_label "Profiles" "${PROFILE_COUNT} reported"
            row_blank

            # ── Per-codec decode / encode breakdown ───────────────────
            # check_vaapi_codec LABEL VAPROFILE_PATTERN
            check_vaapi_codec() {
                local label="$1" pattern="$2"
                local lines; lines=$(echo "$VAINFO_OUT" | grep "$pattern")
                if [[ -z "$lines" ]]; then
                    row_sub "✗ ${label}  (not advertised)"
                    return
                fi
                local dec=0 enc=0
                echo "$lines" | grep -q "Decode"    && dec=1
                echo "$lines" | grep -q "EncSlice"  && enc=1
                local caps=""
                [[ $dec -eq 1 ]] && caps+="Decode "
                [[ $enc -eq 1 ]] && caps+="Encode"
                if [[ $dec -eq 1 || $enc -eq 1 ]]; then
                    row_sub "✓ ${label}  (${caps})"
                else
                    row_sub "~ ${label}  (profile present but no Decode/Encode entrypoint)"
                fi
            }

            row_info "Codec support:"
            check_vaapi_codec "H.264  / AVC  " "VAProfileH264"
            check_vaapi_codec "H.265  / HEVC " "VAProfileHEVC"
            check_vaapi_codec "AV1           " "VAProfileAV1"
            check_vaapi_codec "VP9           " "VAProfileVP9"
            check_vaapi_codec "VP8           " "VAProfileVP8"
            check_vaapi_codec "MPEG-2        " "VAProfileMPEG2"
        fi
    fi
fi

close_section; echo

# -----------------------------------------------------------------------
# PERFORMANCE FEATURES — Resizable BAR, PCIe, Power Profile
# -----------------------------------------------------------------------
open_section "PERFORMANCE FEATURES"

AMD_GPU_PCI=$(lspci 2>/dev/null \
    | grep -iE "VGA.*AMD|AMD.*VGA" | awk '{print $1}' | head -1) \
    || AMD_GPU_PCI=""

if [[ -z "$AMD_GPU_PCI" ]]; then
    row_warn "No AMD VGA device found via lspci — BAR and PCIe checks skipped"
elif sudo_require "PCIe detail (lspci -vv)" /usr/bin/lspci -s "$AMD_GPU_PCI" -vv; then

    # ── Resizable BAR ─────────────────────────────────────────────────
    BAR_INFO=$(sudo -n lspci -s "$AMD_GPU_PCI" -vv 2>/dev/null \
        | grep -i "Region 0") || BAR_INFO=""

    if [[ -z "$BAR_INFO" ]]; then
        row_warn "Region 0 not found in lspci -vv output"
    else
        BAR_SIZE=$(echo "$BAR_INFO" | grep -oP '\[size=\K[^]]+') || BAR_SIZE=""
        if [[ -z "$BAR_SIZE" ]]; then
            row_warn "BAR size not parseable"
            row_info "Raw lspci output: ${BAR_INFO}"
        elif [[ "$BAR_SIZE" == *"G"* ]]; then
            row_ok   "Resizable BAR: ENABLED  (${BAR_SIZE})"
        else
            row_fail "Resizable BAR: DISABLED  (${BAR_SIZE} — expected 16G+)"
            row_hint "BIOS: Above 4G Decoding ON  +  Resizable BAR ON"
            row_hint "Gains: +10–15% rasterisation performance"
        fi
    fi

    # ── PCIe Link Speed & Width ───────────────────────────────────────
    PCIE_INFO=$(sudo -n lspci -s "$AMD_GPU_PCI" -vv 2>/dev/null \
        | grep -i "LnkSta:") || PCIE_INFO=""

    if [[ -z "$PCIE_INFO" ]]; then
        row_warn "LnkSta not found — driver may not have negotiated the link yet"
    else
        PCIE_SPEED=$(echo "$PCIE_INFO" | grep -oP 'Speed \K[^,]+') || PCIE_SPEED="Unknown"
        PCIE_WIDTH=$(echo "$PCIE_INFO" | grep -oP 'Width x\K[0-9]+')  || PCIE_WIDTH="?"

        if [[ -z "$PCIE_SPEED" || -z "$PCIE_WIDTH" ]]; then
            row_warn "Could not parse PCIe speed/width from lspci output"
            row_info "Raw: ${PCIE_INFO}"
        elif [[ "$PCIE_SPEED" == *"32GT/s"* && "$PCIE_WIDTH" == "16" ]]; then
            row_ok  "PCIe: Gen5 x16 @ 32GT/s  (maximum)"
        elif [[ "$PCIE_SPEED" == *"16GT/s"* && "$PCIE_WIDTH" == "16" ]]; then
            row_ok  "PCIe: Gen4 x16 @ 16GT/s  (good)"
        elif [[ "$PCIE_WIDTH" != "16" ]]; then
            row_warn "PCIe: ${PCIE_SPEED} x${PCIE_WIDTH}  (expected x16 — wrong slot?)"
        elif [[ "$PCIE_SPEED" == *"8GT/s"* ]]; then
            row_warn "PCIe: Gen3 @ 8GT/s  (slower than expected for this GPU)"
            row_hint "Check BIOS › PCIe link speed is not forced to Gen3"
        else
            row_info "PCIe: ${PCIE_SPEED} x${PCIE_WIDTH}"
        fi
    fi
fi

# ── Power Profile / CPU Governor ──────────────────────────────────────
row_blank
if have powerprofilesctl; then
    PROFILE=$(powerprofilesctl get 2>/dev/null) || PROFILE=""
    if [[ -z "$PROFILE" ]]; then
        row_warn "powerprofilesctl returned no active profile"
    elif [[ "$PROFILE" == "performance" ]]; then
        row_ok   "Power profile: performance"
    elif [[ "$PROFILE" == "balanced" ]]; then
        row_warn "Power profile: balanced"
        row_hint "Switch for gaming:  powerprofilesctl set performance"
    else
        row_info "Power profile: ${PROFILE}"
    fi
else
    GOV=$(read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    if [[ -z "$GOV" ]]; then
        row_warn "Power profile unknown  (no powerprofilesctl and cpufreq unavailable)"
    elif [[ "$GOV" == "performance" ]]; then
        row_ok   "CPU governor: performance"
    else
        row_warn "CPU governor: ${GOV}  (consider 'performance' during gaming)"
    fi
fi

close_section; echo

# -----------------------------------------------------------------------
# SYSTEM / BIOS INFO
# -----------------------------------------------------------------------
open_section "SYSTEM INFO"

row_label "Board"  "$(read_sys /sys/class/dmi/id/board_vendor) $(read_sys /sys/class/dmi/id/board_name)"
row_label "BIOS"   "$(read_sys /sys/class/dmi/id/bios_vendor)  $(read_sys /sys/class/dmi/id/bios_version)"
row_label "Date"   "$(read_sys /sys/class/dmi/id/bios_date)"
row_label "Kernel" "$(uname -r 2>/dev/null || echo 'Unknown')"

close_section; echo