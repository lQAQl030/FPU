# FPU module

## 1. Overview

This project is a comprehensive behavioral model of a Floating-Point Unit. It is designed with modular architecture that separates decoding, encoding, and execution of various floating-point operations. The primary goal of this FPU is to serve as a functionally correct reference model for educational purposes and as a foundation for further development, such as integration into a RISC-V processor core.

The entire FPU is verified using a C++ testbench powered by **Verilator**, ensuring its operational correctness against a suite of standard and edge-case tests.

## 2. Features

The FPU supports a significant subset of the IEEE 754 standard for floating-point arithmetic.

#### Supported Data Types
*   **Single Precision** (FP32)
*   **Double Precision** (FP64)
*   32-bit Signed and Unsigned Integers for conversion operations.

#### Supported Operations
The FPU uses a custom opcode to select operations, which can be easily mapped from a processor's instruction decoder.

*   **Arithmetic:**
    *   `FADD` (Addition)
    *   `FSUB` (Subtraction)
    *   `FMUL` (Multiplication)
    *   `FDIV` (Division)
    *   `FSQRT` (Square Root)
*   **Comparison:**
    *   `FCMP` (Compare less than, equal, greater than)
*   **Conversions:**
    *   FP64 <-> FP32
    *   FP32/FP64 -> Signed/Unsigned Integer
    *   Signed/Unsigned Integer -> FP32/FP64
*   **FMA(to be added):**
    *   `fmadd` (Addition after Multiplication)
    *   `fmsub` (Subtraction after Multiplication)

#### IEEE 754 Compliance
*   **Rounding Modes:**
    *   Round to Nearest, ties to Even (RNE) - _Default_
    *   Round Towards Zero (RTZ)
    *   Round Down (towards -∞) (RDN)
    *   Round Up (towards +∞) (RUP)
*   **Exception Flags:**
    *   `Invalid Operation` (NV)
    *   `Division by Zero` (DZ)
    *   `Overflow` (OF)
    *   `Underflow` (UF)
    *   `Inexact` (NX)
*   **Special Values:** Correctly handles `+Zero`, `-Zero`, `Infinities`, `NaNs` (QNaN and SNaN), and `Denormalized Numbers`.

## 3. Architecture

The FPU is designed with a top-down, modular approach. The `FPU_Top` module acts as the central hub that decodes incoming instructions and dispatches them to the appropriate functional unit.

#### Key Modules

*   **`FPU_Top.sv`**: The main entry point. It contains the opcode decoder, multiplexes the operands to the correct unit, and selects the final result and flags.
*   **`FP_Decoder.sv`**: A crucial utility module that takes a raw 64-bit floating-point number and decodes it into its constituent parts: sign, exponent, mantissa, and type (Zero, NaN, Inf, Denormal).
*   **`FP_Encoder.sv`**: The counterpart to the decoder. It takes a sign, exponent, and mantissa and encodes them into the final IEEE 754 bit-level representation.
*   **Functional Units**: Each major operation is encapsulated in its own module for clarity and separation of concerns.

## 4. Module Breakdown

The project is composed of the following SystemVerilog and C++ files:

#### RTL Modules
:::info
Replace FP to SP or DP
:::
*   `FPU_Top.sv`: Top-level FPU module.
*   `FP_Decoder.sv`: Decodes FP numbers.
*   `FP_Encoder.sv`: Encodes FP numbers.
*   `FP_Adder.sv`: Performs floating-point addition and subtraction.
*   `FP_Multiplier.sv`: Performs floating-point multiplication.
*   `FP_Divider.sv`: Performs floating-point division using a behavioral integer-based fixed-point algorithm.
*   `FP_Sqrt.sv`: Performs floating-point square root.
*   `FP_Compare.sv`: Compares two floating-point numbers.
*   `FP_Convert.sv`: Handles all conversions between FP, integer, and different precisions.

#### Verification Environment
*   `tb_fpu.cpp`: A comprehensive C++ testbench that instantiates the Verilated FPU model.
*   `Makefile`: A makefile to automate the compilation and simulation process with Verilator.

## 5. Verification Strategy

The FPU's correctness is established through a testbench environment powered by **Verilator**.

1.  **Verilation**: The SystemVerilog RTL is compiled into a cycle-accurate C++ model using Verilator.
2.  **C++ Testbench**: The `tb_fpu.cpp` testbench defines a large suite of testcases. Each testcase includes:
    *   Operands A and B
    *   Operation and rounding mode
    *   Expected result
    *   Expected status flags (`Invalid`, `Overflow`, etc.)
3.  **Execution & Comparison**: For each test, the testbench drives the FPU inputs, simulates the clock, and compares the FPU's output signals against the expected values.
4.  **Test Coverage**: The test suite includes:
    *   Basic arithmetic sanity checks.
    *   All rounding modes for inexact results.
    *   Edge cases involving special values (NaN, Infinity, Zero, Denormals).
    *   Tests designed to trigger overflow and underflow conditions.

## 6. How to Run the Simulation

To compile and run the FPU simulation, follow these steps.

#### Prerequisites
*   **Verilator**: An open-source SystemVerilog simulator and linter.
*   **A C++ Compiler**: `g++` or `clang++`.
*   **GNU Make**.

#### Steps
1.  **Compile the FPU with Verilator:**
    ```bash
    # This command verilates the RTL and compiles the C++ testbench
    make
    ```
2.  **Run the simulation:**
    ```bash
    # This executes the compiled testbench
    ./obj_dir/VFPU_Top
    ```
3.  **Review the Output:** The testbench will print `[PASS]` or `[FAIL]` for each test case, followed by a final summary. A `waveform.vcd` file is also generated for debugging with a waveform viewer like GTKWave.