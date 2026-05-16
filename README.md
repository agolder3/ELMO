# ELMO

ELMO is a statistical power leakage simulator for the ARM Cortex-M0 family. It takes a compiled Thumb binary and produces noise-free, cycle-accurate (or instruction-accurate) power consumption traces without requiring physical hardware.

**Paper:** [Towards Practical Tools for Side Channel Aware Software Engineering](https://www.usenix.org/conference/usenixsecurity17/technical-sessions/presentation/mccann) (USENIX Security 2017)

## Quick Start

Run everything automatically (downloads the ARM toolchain, builds ELMO, compiles examples, runs experiments):

```bash
bash tools/setup_and_run_example.sh
```

No sudo required — the toolchain is installed locally into `.local_toolchains/`.

## Manual Setup

### Prerequisites

- GCC (any recent version) and `make`
- GNU ARM Embedded Toolchain (tested: v10.3-2021.10) — download from https://developer.arm.com/open-source/gnu-toolchain/gnu-rm

### Build ELMO

```bash
make
```

### Install ARM Toolchain

```bash
# Download and extract (example for Linux x86_64)
cd /tmp
wget https://developer.arm.com/-/media/Files/downloads/gnu-rm/10.3-2021.10/gcc-arm-none-eabi-10.3-2021.10-x86_64-linux.tar.bz2
tar xjf gcc-arm-none-eabi-10.3-2021.10-x86_64-linux.tar.bz2 -C ~/.local/

# Add to PATH
export PATH=~/.local/gcc-arm-none-eabi-10.3-2021.10/bin:$PATH
```

### Build Example Binaries

```bash
# Assemble the shared ELMO API helper functions
arm-none-eabi-as -mthumb -mcpu=cortex-m0 -o Examples/elmoasmfunctions.o Examples/elmoasmfunctions.s

# Build any example
cd Examples/DPATraces/MBedAES && make && cd -
cd Examples/FixedvsRandom/MBedAES && make && cd -
cd Examples/FixedvsRandom/MaskedAES_R1 && make && cd -
```

### Run ELMO

```bash
./elmo path/to/binary.bin
```

## Examples

ELMO ships with three examples. Each requires specific `#define` settings in `elmodefines.h` — rebuild ELMO (`make clean && make`) after changing defines.

| # | Example | Defines Needed | Command |
|---|---------|---------------|---------|
| 1 | DPA Trace Generation | Comment out `FIXEDVSRANDOM` and `MASKFLOW` | `./elmo Examples/DPATraces/MBedAES/MBedAES.bin` |
| 2 | Fixed vs Random (AES) | `FIXEDVSRANDOM` | `./elmo Examples/FixedvsRandom/MBedAES/MBedAES.bin -Ntrace 200` |
| 3 | Masked AES + MaskFlow | `FIXEDVSRANDOM` and `MASKFLOW` | `./elmo Examples/FixedvsRandom/MaskedAES_R1/MaskedAES_R1.bin` |

**Example 1** generates 200 power traces for AES with random plaintexts and a fixed key. Useful for DPA attacks.

**Example 2** performs a first-order fixed-vs-random t-test (TVLA) on AES. The `-Ntrace N` flag sets the number of traces at runtime.

**Example 3** performs first-order and second-order leakage detection on a masked AES implementation, using the MaskFlow analysis to efficiently identify which instructions share masks.

## Configuration (`elmodefines.h`)

Key defines:

| Define | Effect |
|--------|--------|
| `FIXEDVSRANDOM` | Enable automated fixed-vs-random t-test |
| `MASKFLOW` | Enable mask flow analysis for higher-order leakage detection |
| `ENERGYMODEL` | Enable energy consumption estimation |
| `MEMORY_EXTENSION` | Model read/write bus leakage (enabled by default) |
| `CYCLEACCURATE 1` | Cycle-accurate traces (default); set to `0` for instruction-accurate |
| `BINARYTRACES` | Output traces in binary format (faster, smaller) |
| `COEFFSFILE` | Path to model coefficient file (default: `coeffs_M3.txt`) |

## Command-Line Flags

| Flag | Description |
|------|-------------|
| `-Ntrace N` | Set number of traces (overrides binary's hardcoded value via `LoadN()`) |
| `-fvr N` | Run fixed-vs-random on N pre-generated traces (skip trace generation) |
| `-starttrace N` | Start trace numbering at N |
| `-startghosttrace N` | Run program but only store traces from number N onward |
| `--vcd` | Output VCD waveform file (`output.vcd`) |

## Output

All output goes to the `output/` directory:

- `output/traces/` — Simulated power traces (one file per trace)
- `output/asmoutput/` — Disassembly of executed instructions
- `output/nonprofiledindexes/` — Indexes of non-profiled instructions
- `output/randdata.txt` — Random data generated via `randbyte()`
- `output/printdata.txt` — Data printed via `printbyte()`
- `output/fixedvsrandomtstatistics.txt` — T-test results (when FIXEDVSRANDOM enabled)
- `output/masks.txt` — Mask flow information (when MASKFLOW enabled)

## ELMO API Functions

Use these in your C code (include `elmoasmfunctionsdef.h` and link `elmoasmfunctions.o`):

| Function | Purpose |
|----------|---------|
| `starttrigger()` | Begin recording a trace |
| `endtrigger()` | End recording a trace |
| `endprogram()` | Terminate ELMO |
| `randbyte(&var)` | Generate a random byte |
| `readbyte(&var)` | Read a byte from the data file |
| `printbyte(&var)` | Print a byte to output file |
| `LoadN(&N)` | Load trace count from `-Ntrace` command-line argument |
| `resetdatafile()` | Reset data file pointer to beginning |
| `setmaskflowstart(n)` | Set mask flow start bit (for MaskFlow) |
| `initialisemaskflow(&var)` | Initialize mask at memory address (for MaskFlow) |

## Power Models

Three coefficient files are provided:

- `coeffs.txt` — Original ST M0 core model
- `coeffs_M3.txt` — M3 core model (default)
- `coeffs_LPC.txt` — NXP LPC1114 M0 core model

Switch models by changing `COEFFSFILE` in `elmodefines.h` or renaming the desired file to `coeffs.txt`.

The models capture:
- Weighted Hamming weight/distance on ALU operand buses (3-instruction context window)
- Second-order bit interactions for shift and multiply instructions
- Memory bus Hamming distance (when `MEMORY_EXTENSION` is defined)

## Running Tests

```bash
# Tests require ELMO built with test/elmodefinestest.h instead of elmodefines.h
# Pre-compiled test binaries are in test/elmotestbinaries/
cd test && python elmotest.py
```

## Writing Your Own Code

1. Write a C program using the ELMO API functions (see `Examples/ProjectTemplate/` for a template)
2. Include `elmoasmfunctionsdef.h` and link `elmoasmfunctions.o`
3. Use the provided linker script (`.ld` file) targeting Cortex-M0
4. Compile with: `arm-none-eabi-gcc -mthumb -mcpu=cortex-m0 -Os ...`
5. Produce a `.bin` file: `arm-none-eabi-objcopy -Obinary main.elf main.bin`
6. Run: `./elmo main.bin`

Only include security-critical code within the trigger region — non-critical code adds overhead and may encounter unsupported instructions.

## Documentation

Full documentation is in [ELMODocumentation.pdf](ELMODocumentation.pdf).

## License

University of Bristol Open Access Software Licence. See [LICENSE.txt](LICENSE.txt).

## References

- D. McCann, C. Whitnall, and E. Oswald. "Towards practical tools for side channel aware software engineering: 'grey box' modelling for instruction leakages." USENIX Security, 2017.
- D. McCann and E. Oswald. "Practical evaluation of masking software countermeasures on an IoT processor." IVSC, 2017.

