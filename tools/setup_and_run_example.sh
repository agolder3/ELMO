#!/usr/bin/env bash
# setup_and_run_example.sh - Build ELMO and run all three documented experiments
# Usage: bash tools/setup_and_run_example.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

###############################################################################
# 1. Install ARM Embedded Toolchain (locally, no sudo)
###############################################################################
TOOLCHAIN_NAME="gcc-arm-none-eabi-10.3-2021.10"
TOOLCHAIN_TARBALL="${TOOLCHAIN_NAME}-x86_64-linux.tar.bz2"
TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu-rm/10.3-2021.10/${TOOLCHAIN_TARBALL}"
LOCAL_PREFIX="$REPO_ROOT/.local_toolchains"
INSTALL_DIR="$LOCAL_PREFIX/${TOOLCHAIN_NAME}"

mkdir -p "$LOCAL_PREFIX"

if [ -x "$INSTALL_DIR/bin/arm-none-eabi-gcc" ]; then
    echo "==> Toolchain already installed at $INSTALL_DIR"
else
    echo "==> Downloading ${TOOLCHAIN_TARBALL}..."
    cd /tmp
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$TOOLCHAIN_TARBALL" "$TOOLCHAIN_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -sL -o "$TOOLCHAIN_TARBALL" "$TOOLCHAIN_URL"
    else
        echo "Error: neither wget nor curl available." >&2
        exit 1
    fi
    echo "==> Extracting to $LOCAL_PREFIX..."
    tar -xjf "$TOOLCHAIN_TARBALL" -C "$LOCAL_PREFIX"
    rm -f "$TOOLCHAIN_TARBALL"
    cd "$REPO_ROOT"
fi

export PATH="$INSTALL_DIR/bin:$PATH"
echo "==> Using toolchain: $(arm-none-eabi-gcc --version | head -1)"

###############################################################################
# 2. Build ELMO host binary
###############################################################################
echo ""
echo "==> Building ELMO host binary..."
make clean
make

###############################################################################
# 3. Assemble elmoasmfunctions.o (shared by all examples)
###############################################################################
echo ""
echo "==> Assembling elmoasmfunctions.o..."
arm-none-eabi-as -mthumb -mcpu=cortex-m0 \
    -o Examples/elmoasmfunctions.o Examples/elmoasmfunctions.s

###############################################################################
# 4. Build example ARM binaries
###############################################################################
echo ""
echo "==> Building Example 1 (DPA Traces / MBedAES)..."
cd Examples/DPATraces/MBedAES
make clean 2>/dev/null || true
make
cd "$REPO_ROOT"

echo "==> Building Example 2 (FixedvsRandom / MBedAES)..."
cd Examples/FixedvsRandom/MBedAES
make clean 2>/dev/null || true
make
cd "$REPO_ROOT"

echo "==> Building Example 3 (FixedvsRandom / MaskedAES_R1)..."
cd Examples/FixedvsRandom/MaskedAES_R1
make clean 2>/dev/null || true
make
cd "$REPO_ROOT"

###############################################################################
# 5. Run experiments
#    NOTE: elmodefines.h must be configured for each experiment and ELMO rebuilt.
#    We run each experiment in turn, modifying the config as needed.
###############################################################################
mkdir -p output/traces output/nonprofiledindexes output/asmoutput

# --- EXPERIMENT 1: DPA Trace Generation ---
echo ""
echo "================================================================"
echo "==> EXPERIMENT 1: AES DPA Trace Generation (200 traces)"
echo "    Config: FIXEDVSRANDOM=off, MASKFLOW=off"
echo "================================================================"
# Disable FIXEDVSRANDOM for basic trace generation
# Use $ anchor to match only the bare defines, not FIXEDVSRANDOMFAIL/FIXEDVSRANDOMFILE/MASKFLOWOUTPUTFILE
sed -i 's/^#define FIXEDVSRANDOM$/\/\/#define FIXEDVSRANDOM/' elmodefines.h
sed -i 's/^#define MASKFLOW$/\/\/#define MASKFLOW/' elmodefines.h
make clean && make

rm -f output/traces/* output/nonprofiledindexes/* output/asmoutput/*
rm -f output/randdata.txt output/printdata.txt output/fixedvsrandomtstatistics.txt

./elmo Examples/DPATraces/MBedAES/MBedAES.bin

echo ""
echo "==> Example 1 complete. Traces: $(ls output/traces/ | wc -l)"
echo "    Random data: output/randdata.txt"
echo "    Ciphertexts: output/printdata.txt"
echo ""

# --- EXPERIMENT 2: Fixed vs Random (non-masked AES) ---
echo "================================================================"
echo "==> EXPERIMENT 2: AES Fixed vs Random (200 traces, quick test)"
echo "    Config: FIXEDVSRANDOM=on, MASKFLOW=off"
echo "================================================================"
# Enable FIXEDVSRANDOM
sed -i 's/^\/\/#define FIXEDVSRANDOM$/#define FIXEDVSRANDOM/' elmodefines.h
make clean && make

rm -f output/traces/* output/nonprofiledindexes/* output/asmoutput/*
rm -f output/randdata.txt output/printdata.txt output/fixedvsrandomtstatistics.txt

./elmo Examples/FixedvsRandom/MBedAES/MBedAES.bin -Ntrace 200

echo ""
echo "==> Example 2 complete."
echo "    T-statistics: output/fixedvsrandomtstatistics.txt"
echo ""

# --- EXPERIMENT 3: Masked AES with MaskFlow ---
echo "================================================================"
echo "==> EXPERIMENT 3: Masked AES Fixed vs Random + MaskFlow (200 traces, quick test)"
echo "    Config: FIXEDVSRANDOM=on, MASKFLOW=on"
echo "    NOTE: Full run uses 40000 traces. Using 200 for validation."
echo "================================================================"
# Enable MASKFLOW
sed -i 's/^\/\/#define MASKFLOW$/#define MASKFLOW/' elmodefines.h
make clean && make

rm -f output/traces/* output/nonprofiledindexes/* output/asmoutput/*
rm -f output/randdata.txt output/printdata.txt output/fixedvsrandomtstatistics.txt output/masks.txt

./elmo Examples/FixedvsRandom/MaskedAES_R1/MaskedAES_R1.bin

echo ""
echo "==> Example 3 complete."
echo "    T-statistics: output/fixedvsrandomtstatistics.txt"
echo "    Mask info: output/masks.txt"
echo ""

###############################################################################
# 6. Restore default elmodefines.h config and rebuild
###############################################################################
echo "==> Restoring default elmodefines.h (FIXEDVSRANDOM=on, MASKFLOW=off)..."
sed -i 's/^#define MASKFLOW$/\/\/#define MASKFLOW/' elmodefines.h
make clean && make

echo ""
echo "================================================================"
echo "ALL EXPERIMENTS COMPLETED SUCCESSFULLY"
echo "================================================================"
echo ""
echo "Output files are in the 'output/' directory."
echo "See ELMODocumentation.md for full documentation."
