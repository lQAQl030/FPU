#include <iostream>
#include <vector>
#include <cstdint>
#include <cmath>
#include <iomanip>

// Verilator header
#include "verilated.h"
#include "verilated_vcd_c.h"

// FPU Top module header
#include "VFPU_Top.h"

// helper function
uint32_t i32_to_u32(int32_t i) {
    union { int32_t i; uint32_t u; } converter = {i};
    return converter.u;
}

int32_t u32_to_i32(uint32_t u) {
    union { uint32_t u; int32_t i; } converter = {u};
    return converter.i;
}

uint32_t f32_to_u32(float f) {
    union { float f; uint32_t u; } converter = {f};
    return converter.u;
}
uint64_t f64_to_u64(double d) {
    union { double d; uint64_t u; } converter = {d};
    return converter.u;
}
float u32_to_f32(uint32_t u) {
    union { uint32_t u; float f; } converter = {u};
    return converter.f;
}
double u64_to_f64(uint64_t u) {
    union { uint64_t u; double d; } converter = {u};
    return converter.d;
}

// --- Opcode Definitions (Must match FPU_Top.v) ---
const uint8_t OP_FADD_S  = 0b0000000, OP_FADD_D  = 0b0000001;
const uint8_t OP_FSUB_S  = 0b0000100, OP_FSUB_D  = 0b0000101;
const uint8_t OP_FMUL_S  = 0b0001000, OP_FMUL_D  = 0b0001001;
const uint8_t OP_FDIV_S  = 0b0001100, OP_FDIV_D  = 0b0001101;
const uint8_t OP_FSQRT_S = 0b0101100, OP_FSQRT_D = 0b0101101;
const uint8_t OP_FCMP_S  = 0b1010000, OP_FCMP_D  = 0b1010001;

const uint8_t OP_FCVT_D_S  = 0b0100001;
const uint8_t OP_FCVT_W_S  = 0b1100000;
const uint8_t OP_FCVT_D_W  = 0b1101001;

const uint8_t OP_FCVT_S_D  = 0b0100000;
const uint8_t OP_FCVT_W_D  = 0b1100001;
const uint8_t OP_FCVT_S_W  = 0b0010100;

const uint8_t CMP_EQ = 0b010;
const uint8_t CMP_LT = 0b001;
const uint8_t CMP_LE = 0b000;
const uint8_t CMP_NN = 0b111;

// --- Test Case Result Type ---
enum ResultType {
    FP32, FP64, INT, CMP
};

// define testcase
struct TestCase {
    std::string name;
    uint8_t  func7;
    uint8_t  func3;
    ResultType result_type;

    uint64_t operand_a;
    uint64_t operand_b;
    uint64_t expected_result;
    
    uint8_t  rounding_mode;
    bool     cvt_wu;

    bool     expected_invalid;
    bool     expected_divbyzero;
    bool     expected_overflow;
    bool     expected_underflow;
    bool     expected_inexact;

    bool     expected_cmp;
};

// simulate clock
vluint64_t main_time = 0;
double sc_time_stamp() {
    return main_time;
}

// run one testcase
bool run_test(VFPU_Top* top, VerilatedVcdC* tfp, const TestCase& test) {
    // setting inputs
    top->func7 = test.func7;
    top->func3 = test.func3;
    top->operand_a = test.operand_a;
    top->operand_b = test.operand_b;
    top->rounding_mode = test.rounding_mode;
    top->cvt_wu = test.cvt_wu;

    // simulate one clock
    top->clk = 0;
    top->eval();
    main_time++;
    if (tfp) tfp->dump(main_time);
    
    top->clk = 1;
    top->eval();
    main_time++;
    if (tfp) tfp->dump(main_time);

    // output check
    bool pass = true;
    switch (test.result_type) {
        case CMP:
            if (top->flag_cmp != test.expected_cmp) {
                pass = false;
                std::cout << "    \033[31m[FAIL]\033[0m Compare mismatch. Got: " << (int)top->flag_cmp << ", Expected: " << (int)test.expected_cmp << std::endl;
            }
            break;
        
        case INT:
            if (top->result_out != test.expected_result) {
                 pass = false;
                 std::cout << "    \033[31m[FAIL]\033[0m Result mismatch (INT). Got: " << std::dec << (int32_t)top->result_out << ", Expected: " << (int32_t)test.expected_result << std::endl;
            }
            break;

        case FP32:
            if ((top->result_out & 0xFFFFFFFF) != (test.expected_result & 0xFFFFFFFF)) {
                 pass = false;
                 std::cout << "    \033[31m[FAIL]\033[0m Result mismatch (FP32). Got: 0x" << std::hex << (top->result_out & 0xFFFFFFFF) << " (" << u32_to_f32(top->result_out & 0xFFFFFFFF) 
                           << "), Expected: 0x" << (test.expected_result & 0xFFFFFFFF) << " (" << u32_to_f32(test.expected_result & 0xFFFFFFFF) << ")" << std::dec << std::endl;
            }
            break;

        case FP64:
             if (top->result_out != test.expected_result) {
                 pass = false;
                 std::cout << "    \033[31m[FAIL]\033[0m Result mismatch (FP64). Got: 0x" << std::hex << top->result_out << " (" << u64_to_f64(top->result_out)
                           << "), Expected: 0x" << test.expected_result << " (" << u64_to_f64(test.expected_result) << ")" << std::dec << std::endl;
            }
            break;
    }

    // flag check
    if (top->flag_invalid != test.expected_invalid) {
        pass = false;
        std::cout << "    \033[31m[FAIL]\033[0m Invalid flag mismatch. Got: " << (int)top->flag_invalid << ", Expected: " << (int)test.expected_invalid << std::endl;
    }
    if (top->flag_divbyzero != test.expected_divbyzero) {
        pass = false;
        std::cout << "    \033[31m[FAIL]\033[0m Invalid flag mismatch. Got: " << (int)top->flag_invalid << ", Expected: " << (int)test.expected_invalid << std::endl;
    }
    if (top->flag_overflow != test.expected_overflow) {
        pass = false;
        std::cout << "    \033[31m[FAIL]\033[0m Overflow flag mismatch. Got: " << (int)top->flag_overflow << ", Expected: " << (int)test.expected_overflow << std::endl;
    }
    if (top->flag_underflow != test.expected_underflow) {
        pass = false;
        std::cout << "    \033[31m[FAIL]\033[0m Underflow flag mismatch. Got: " << (int)top->flag_underflow << ", Expected: " << (int)test.expected_underflow << std::endl;
    }
    if (top->flag_inexact != test.expected_inexact) {
        pass = false;
        std::cout << "    \033[31m[FAIL]\033[0m Inexact flag mismatch. Got: " << (int)top->flag_inexact << ", Expected: " << (int)test.expected_inexact << std::endl;
    }
    
    return pass;
}

int main(int argc, char** argv, char** env) {
    // initialize Verilator
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    // initialize FPU
    VFPU_Top* top = new VFPU_Top;

    // initialize vcd
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("waveform.vcd");

    // Testcases
    std::vector<TestCase> test_suite = {
        // Name, func7, func3, ResultType, OpA, OpB, RoundMode, ConvertUnsigned, ExpectedResult, Inv, Dbz, Ovf, Unf, Inex,  cmp_result

        // --- Basic Sanity Checks ---
        // SP_Adder
            {"FADD.S: 1.5 + 2.75",        OP_FADD_S,    CMP_NN,    FP32,   f32_to_u32(1.5f),       f32_to_u32(2.75f),      f32_to_u32(4.25f),       0,    0,    0,0,0,0,0, 0},
            {"FADD.S: 123.55 + 0.375",    OP_FADD_S,    CMP_NN,    FP32,   f32_to_u32(123.55f),    f32_to_u32(0.375f),     f32_to_u32(123.925f),    0,    0,    0,0,0,0,0, 0},
            {"FSUB.S: 10.0 - 5.5",        OP_FSUB_S,    CMP_NN,    FP32,   f32_to_u32(10.0f),      f32_to_u32(5.5f),       f32_to_u32(4.5f),        0,    0,    0,0,0,0,0, 0},
            {"FSUB.S: 1.0 - 0.5625",      OP_FSUB_S,    CMP_NN,    FP32,   f32_to_u32(1.0f),       f32_to_u32(0.5625f),    f32_to_u32(0.4375f),     0,    0,    0,0,0,0,0, 0},
        // DP_Adder
            {"FADD.D: 1.5 + 2.75",        OP_FADD_D,    CMP_NN,    FP64,   f64_to_u64(1.5),        f64_to_u64(2.75),       f64_to_u64(4.25),       0,    0,    0,0,0,0,0, 0},
            {"FADD.D: 123.55 + 0.375",    OP_FADD_D,    CMP_NN,    FP64,   f64_to_u64(123.55),     f64_to_u64(0.375),      f64_to_u64(123.925),    0,    0,    0,0,0,0,0, 0},
            {"FSUB.D: 10.0 - 5.5",        OP_FSUB_D,    CMP_NN,    FP64,   f64_to_u64(10.0),       f64_to_u64(5.5),        f64_to_u64(4.5),        0,    0,    0,0,0,0,0, 0},
            {"FSUB.D: 1.0 - 0.5625",      OP_FSUB_D,    CMP_NN,    FP64,   f64_to_u64(1.0),        f64_to_u64(0.5625),     f64_to_u64(0.4375),     0,    0,    0,0,0,0,0, 0},
        // {"FMUL.D: 3.0 * 2.5",            OP_FMUL_D,  FP64, f64_to_u64(3.0),     f64_to_u64(2.5),     0, f64_to_u64(7.5),      0,0,0,0,0, 0,0,0,0},
        // {"FDIV.S: 100.0 / 4.0",          OP_FDIV_S,  FP32, f32_to_u32(100.0f),  f32_to_u32(4.0f),    0, f32_to_u32(25.0f),    0,0,0,0,0, 0,0,0,0},
        // {"FDIV.S: 4.0 / 10.0",           OP_FDIV_S,  FP32, f32_to_u32(4.0f),    f32_to_u32(10.0f),   0, f32_to_u32(0.4f),     0,0,0,0,1, 0,0,0,0},
        // {"FDIV.D: 90.0 / 4.0",           OP_FDIV_D,  FP32, f64_to_u64(90.0),    f64_to_u64(4.0),     0, f64_to_u64(22.5),     0,0,0,0,0, 0,0,0,0},
        // {"FDIV.D: 4.0 / 10.0",           OP_FDIV_D,  FP64, f64_to_u64(4.0),     f64_to_u64(10.0),    0, f64_to_u64(0.4),      0,0,0,0,1, 0,0,0,0},
        // {"FSQRT.D: sqrt(16.0)",          OP_FSQRT_D, FP64, f64_to_u64(16.0),    0,                   0, f64_to_u64(4.0),      0,0,0,0,0, 0,0,0,0},

        // --- Rounding Mode Tests (using 1/3 which is inexact) ---
        // {"FDIV.D: 1.0/3.0 (RNE)",        OP_FDIV_D,  FP64, f64_to_u64(1.0),     f64_to_u64(3.0),     0, 0x3FD5555555555555,   0,0,0,0,1, 0,0,0,0}, // RNE
        // {"FDIV.D: 1.0/3.0 (RTZ)",        OP_FDIV_D,  FP64, f64_to_u64(1.0),     f64_to_u64(3.0),     1, 0x3FD5555555555555,   0,0,0,0,1, 0,0,0,0}, // RTZ
        // {"FDIV.D: 1.0/3.0 (RDN)",        OP_FDIV_D,  FP64, f64_to_u64(1.0),     f64_to_u64(3.0),     2, 0x3FD5555555555555,   0,0,0,0,1, 0,0,0,0}, // RDN
        // {"FDIV.D: 1.0/3.0 (RUP)",        OP_FDIV_D,  FP64, f64_to_u64(1.0),     f64_to_u64(3.0),     3, 0x3FD5555555555556,   0,0,0,0,1, 0,0,0,0}, // RUP
        // {"FDIV.D: -1.0/3.0 (RDN)",       OP_FDIV_D,  FP64, f64_to_u64(-1.0),    f64_to_u64(3.0),     2, 0xBFD5555555555556,   0,0,0,0,1, 0,0,0,0}, // RDN (towards -inf)
        // {"FDIV.D: -1.0/3.0 (RUP)",       OP_FDIV_D,  FP64, f64_to_u64(-1.0),    f64_to_u64(3.0),     3, 0xBFD5555555555555,   0,0,0,0,1, 0,0,0,0}, // RUP (towards +inf)

        // --- Special Value Tests (Zero, Inf, NaN) ---
        // SP_Adder
            {"FADD.S: 1.0 + NAN -> Invalid NaN",    OP_FADD_S,    CMP_NN,    FP32,    f32_to_u32(1.0f),        f32_to_u32(NAN),         f32_to_u32(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FSUB.S: 1.0 - NAN -> Invalid NaN",    OP_FSUB_S,    CMP_NN,    FP32,    f32_to_u32(1.0f),        f32_to_u32(NAN),         f32_to_u32(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.S: NAN + 1.0 -> Invalid NaN",    OP_FADD_S,    CMP_NN,    FP32,    f32_to_u32(NAN),         f32_to_u32(1.0f),        f32_to_u32(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FSUB.S: NAN - 1.0 -> Invalid NaN",    OP_FSUB_S,    CMP_NN,    FP32,    f32_to_u32(NAN),         f32_to_u32(1.0f),        f32_to_u32(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.S: NAN + NAN -> Invalid NaN",    OP_FADD_S,    CMP_NN,    FP32,    f32_to_u32(NAN),         f32_to_u32(NAN),         f32_to_u32(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FSUB.S: NAN - NAN -> Invalid NaN",    OP_FSUB_S,    CMP_NN,    FP32,    f32_to_u32(NAN),         f32_to_u32(NAN),         f32_to_u32(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.S: Inf + 3.0 -> Inf",            OP_FADD_S,    CMP_NN,    FP32,    f32_to_u32(INFINITY),    f32_to_u32(3.0f),        f32_to_u32(INFINITY),     0,    0,    0,0,0,0,0, 0},
            {"FADD.S: 3.0 + Inf -> Inf",            OP_FADD_S,    CMP_NN,    FP32,    f32_to_u32(3.0f),        f32_to_u32(INFINITY),    f32_to_u32(INFINITY),     0,    0,    0,0,0,0,0, 0},
            {"FSUB.S: Inf - 3.0 -> Inf",            OP_FSUB_S,    CMP_NN,    FP32,    f32_to_u32(INFINITY),    f32_to_u32(3.0f),        f32_to_u32(INFINITY),     0,    0,    0,0,0,0,0, 0},
            {"FSUB.S: 3.0 - Inf -> Inf",            OP_FSUB_S,    CMP_NN,    FP32,    f32_to_u32(3.0f),        f32_to_u32(INFINITY),    f32_to_u32(-INFINITY),    0,    0,    0,0,0,0,0, 0},
            {"FSUB.S: Inf - Inf -> Invalid NaN",    OP_FSUB_S,    CMP_NN,    FP32,    f32_to_u32(INFINITY),    f32_to_u32(INFINITY),    f32_to_u32(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.S: 2.75 + 0.0",                  OP_FADD_S,    CMP_NN,    FP32,    f32_to_u32(2.75f),       f32_to_u32(0.0f),        f32_to_u32(2.75f),        0,    0,    0,0,0,0,0, 0},
            {"FSUB.S: 0.0 - 5.5",                   OP_FSUB_S,    CMP_NN,    FP32,    f32_to_u32(0.0f),        f32_to_u32(5.5f),        f32_to_u32(-5.5f),        0,    0,    0,0,0,0,0, 0},
        // DP_Adder
            {"FADD.D: 1.0 + NAN -> Invalid NaN",    OP_FADD_D,    CMP_NN,    FP64,    f64_to_u64(1.0),         f64_to_u64(NAN),         f64_to_u64(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FSUB.D: 1.0 - NAN -> Invalid NaN",    OP_FSUB_D,    CMP_NN,    FP64,    f64_to_u64(1.0),         f64_to_u64(NAN),         f64_to_u64(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.D: NAN + 1.0 -> Invalid NaN",    OP_FADD_D,    CMP_NN,    FP64,    f64_to_u64(NAN),         f64_to_u64(1.0),         f64_to_u64(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FSUB.D: NAN - 1.0 -> Invalid NaN",    OP_FSUB_D,    CMP_NN,    FP64,    f64_to_u64(NAN),         f64_to_u64(1.0),         f64_to_u64(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.D: NAN + NAN -> Invalid NaN",    OP_FADD_D,    CMP_NN,    FP64,    f64_to_u64(NAN),         f64_to_u64(NAN),         f64_to_u64(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FSUB.D: NAN - NAN -> Invalid NaN",    OP_FSUB_D,    CMP_NN,    FP64,    f64_to_u64(NAN),         f64_to_u64(NAN),         f64_to_u64(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.D: Inf + 3.0 -> Inf",            OP_FADD_D,    CMP_NN,    FP64,    f64_to_u64(INFINITY),    f64_to_u64(3.0),         f64_to_u64(INFINITY),     0,    0,    0,0,0,0,0, 0},
            {"FADD.D: 3.0 + Inf -> Inf",            OP_FADD_D,    CMP_NN,    FP64,    f64_to_u64(3.0),         f64_to_u64(INFINITY),    f64_to_u64(INFINITY),     0,    0,    0,0,0,0,0, 0},
            {"FSUB.D: Inf - 3.0 -> Inf",            OP_FSUB_D,    CMP_NN,    FP64,    f64_to_u64(INFINITY),    f64_to_u64(3.0),         f64_to_u64(INFINITY),     0,    0,    0,0,0,0,0, 0},
            {"FSUB.D: 3.0 - Inf -> Inf",            OP_FSUB_D,    CMP_NN,    FP64,    f64_to_u64(3.0),         f64_to_u64(INFINITY),    f64_to_u64(-INFINITY),    0,    0,    0,0,0,0,0, 0},
            {"FSUB.D: Inf - Inf -> Invalid NaN",    OP_FSUB_D,    CMP_NN,    FP64,    f64_to_u64(INFINITY),    f64_to_u64(INFINITY),    f64_to_u64(NAN),          0,    0,    1,0,0,0,0, 0},
            {"FADD.D: 2.75 + 0.0",                  OP_FADD_D,    CMP_NN,    FP64,    f64_to_u64(2.75),        f64_to_u64(0.0),         f64_to_u64(2.75),         0,    0,    0,0,0,0,0, 0},
            {"FSUB.D: 0.0 - 5.5",                   OP_FSUB_D,    CMP_NN,    FP64,    f64_to_u64(0.0),         f64_to_u64(5.5),         f64_to_u64(-5.5),         0,    0,    0,0,0,0,0, 0},
        // {"FSQRT.D: sqrt(-1.0) -> Invalid QNaN", OP_FSQRT_D, FP64, f64_to_u64(-1.0), 0,               0, f64_to_u64(NAN),   1,0,0,0,0, 0,0,0,0},
        // {"FDIV.S by Zero -> Infinity",   OP_FDIV_S,  FP32, f32_to_u32(5.0f),    f32_to_u32(0.0f),    0, f32_to_u32(INFINITY),   0,1,1,0,0, 0,0,0,0},
        // {"0 / 0 -> Invalid NaN  (32)",   OP_FDIV_S,  FP32, f32_to_u32(0.0f),    f32_to_u32(0.0f),    0, f32_to_u32(NAN),   1,0,0,0,0, 0,0,0,0},
        // {"0 / 0 -> Invalid QNaN (64)",   OP_FDIV_D,  FP64, f64_to_u64(0.0),     f64_to_u64(0.0),     0, f64_to_u64(NAN),   1,0,0,0,0, 0,0,0,0},
        // {"Inf / Inf -> Invalid QNaN",    OP_FDIV_D,  FP64, f64_to_u64(INFINITY),f64_to_u64(INFINITY),0, f64_to_u64(NAN),   1,0,0,0,0, 0,0,0,0},
        // {"0 * Inf -> Invalid QNaN",      OP_FMUL_D,  FP64, f64_to_u64(0.0),     f64_to_u64(INFINITY),0, f64_to_u64(NAN),   1,0,0,0,0, 0,0,0,0},

        // --- Compare Tests ---
        // SP_Compare
            {"FCMP.S: -2.0 < -1.0",           OP_FCMP_S,    CMP_LT,    CMP,    f32_to_u32(-2.0f),    f32_to_u32(-1.0f),    0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.S: 2.0 = 2.0",             OP_FCMP_S,    CMP_EQ,    CMP,    f32_to_u32(2.0f),     f32_to_u32(2.0f),     0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.S: 1.0 <= 2.0",            OP_FCMP_S,    CMP_LE,    CMP,    f32_to_u32(1.0f),     f32_to_u32(2.0f),     0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.S: 0.0 < -1.0",            OP_FCMP_S,    CMP_LT,    CMP,    f32_to_u32(0.0f),     f32_to_u32(-1.0f),    0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.S: 3.0 = 2.0",             OP_FCMP_S,    CMP_EQ,    CMP,    f32_to_u32(3.0f),     f32_to_u32(2.0f),     0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.S: 2.0 <= 1.0",            OP_FCMP_S,    CMP_LE,    CMP,    f32_to_u32(2.0f),     f32_to_u32(1.0f),     0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.S: +0 = -0",               OP_FCMP_S,    CMP_EQ,    CMP,    f32_to_u32(0.0f),     f32_to_u32(-0.0f),    0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.S: NaN = 2.0",             OP_FCMP_S,    CMP_EQ,    CMP,    f32_to_u32(NAN),      f32_to_u32(2.0f),     0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.S: SNaN = 2.0",            OP_FCMP_S,    CMP_EQ,    CMP,    0x7f800001,           f32_to_u32(2.0f),     0,    0,    0,    1,0,0,0,0, 0},
            {"FCMP.S: Normal <= Denormal",    OP_FCMP_S,    CMP_LE,    CMP,    0x00800000,           0x00000001,           0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.S: Denormal <= Normal",    OP_FCMP_S,    CMP_LE,    CMP,    0x00000001,           0x00800000,           0,    0,    0,    0,0,0,0,0, 1},
        // DP_Compare
            {"FCMP.D: -2.0 < -1.0",           OP_FCMP_D,    CMP_LT,    CMP,    f64_to_u64(-2.0),      f64_to_u64(-1.0),      0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.D: 2.0 = 2.0",             OP_FCMP_D,    CMP_EQ,    CMP,    f64_to_u64(2.0),       f64_to_u64(2.0),       0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.D: 1.0 <= 2.0",            OP_FCMP_D,    CMP_LE,    CMP,    f64_to_u64(1.0),       f64_to_u64(2.0),       0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.D: 0.0 < -1.0",            OP_FCMP_D,    CMP_LT,    CMP,    f64_to_u64(0.0),       f64_to_u64(-1.0),      0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.D: 3.0 = 2.0",             OP_FCMP_D,    CMP_EQ,    CMP,    f64_to_u64(3.0),       f64_to_u64(2.0),       0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.D: 2.0 <= 1.0",            OP_FCMP_D,    CMP_LE,    CMP,    f64_to_u64(2.0),       f64_to_u64(1.0),       0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.D: +0 = -0",               OP_FCMP_D,    CMP_EQ,    CMP,    f64_to_u64(0.0),       f64_to_u64(-0.0),      0,    0,    0,    0,0,0,0,0, 1},
            {"FCMP.D: NaN = 2.0",             OP_FCMP_D,    CMP_EQ,    CMP,    f64_to_u64(NAN),       f64_to_u64(2.0),       0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.D: SNaN = 2.0",            OP_FCMP_D,    CMP_EQ,    CMP,    0xfff0000000000001,    f64_to_u64(2.0),       0,    0,    0,    1,0,0,0,0, 0},
            {"FCMP.D: Normal <= Denormal",    OP_FCMP_D,    CMP_LE,    CMP,    0x0010000000000000,    0x0000000000000001,    0,    0,    0,    0,0,0,0,0, 0},
            {"FCMP.D: Denormal <= Normal",    OP_FCMP_D,    CMP_LE,    CMP,    0x0000000000000001,    0x0010000000000000,    0,    0,    0,    0,0,0,0,0, 1},

        // --- Conversion Tests ---
        // SP_Convert
            {"FCVT.D.S: float(3.75) -> double",     OP_FCVT_D_S,    CMP_NN,    FP64,    f32_to_u32(3.75f),    0,    f64_to_u64(3.75),      0,    0,    0,0,0,0,0, 0},
            {"FCVT.D.S: Min Denormal -> double",    OP_FCVT_D_S,    CMP_NN,    FP64,    0x00000001,           0,    0x36A0000000000000,    0,    0,    0,0,0,0,0, 0},
            // {"FCVT.S.W: int(123) -> float",        OP_FCVT_S_W,    CMP_NN,    FP32,    123,    0,    f32_to_u32(123.0f),    0,    0,    0,0,0,0,0, 0},
        // {"FCVT.W.S: float(3.75) -> int (RTZ)",  OP_FCVT_W_S, INT, f32_to_u32(3.75f),    0,                   1, 3,                    0,0,0,0,1, 0,0,0,0},
        // {"FCVT.W.S: float(3.5) -> int (RNE)",   OP_FCVT_W_S, INT, f32_to_u32(3.5f),     0,                   0, 4,                    0,0,0,0,1, 0,0,0,0},
        // {"FCVT.W.S: float(2.5) -> int (RNE)",   OP_FCVT_W_S, INT, f32_to_u32(2.5f),     0,                   0, 2,                    0,0,0,0,1, 0,0,0,0},
        // {"FCVT.W.S: Large float -> INT_MAX",    OP_FCVT_W_S, INT, f32_to_u32(3e9f),     0,                   0, 0x7FFFFFFF,           1,0,0,0,1, 0,0,0,0}, // Invalid=1
        // {"FCVT.W.S: Neg float -> INT_MIN",      OP_FCVT_W_S, INT, f32_to_u32(-3e9f),    0,                   0, 0x80000000,           1,0,0,0,1, 0,0,0,0}, // Invalid=1
        // {"FCVT.S.D: FP64 to FP32",              OP_FCVT_S_D, FP32, f64_to_u64(123.456), 0,                   0, f32_to_u32(123.456f), 0,0,0,0,1, 0,0,0,0}, // Inexact
        // {"FCVT.D.S: FP32 to FP64",              OP_FCVT_D_S, FP64, f32_to_u32(123.456f),0,                   0, f64_to_u64(123.456f), 0,0,0,0,0, 0,0,0,0}, // Exact

        // --- Denormal and Underflow Tests ---
        // SP_Adder
            {"FADD.S: Min_Normal + Min_Denormal",    OP_FADD_S,    CMP_NN,    FP32,    0x00800000,    0x00000001,    0x00800001,    0,    0,    0,0,0,0,0, 0}, // Result is min normal + 1
            {"FSUB.S: Min_Normal - Min_Denormal",    OP_FSUB_S,    CMP_NN,    FP32,    0x00800000,    0x00000001,    0x007FFFFF,    0,    0,    0,0,0,1,0, 0}, // Result is max denormal
        // DP_Adder
            {"FADD.D: Min_Normal + Min_Denormal",    OP_FADD_D,    CMP_NN,    FP64,    0x0010000000000000,    0x0000000000000001,    0x0010000000000001,    0,    0,    0,0,0,0,0, 0}, // Result is min normal + 1
            {"FSUB.D: Min_Normal - Min_Denormal",    OP_FSUB_D,    CMP_NN,    FP64,    0x0010000000000000,    0x0000000000000001,    0x000FFFFFFFFFFFFF,    0,    0,    0,0,0,1,0, 0}, // Result is max denormal
        // {"FMUL.S: Min_Normal * 0.5 -> Underflow", OP_FMUL_S, FP32, 0x00800000, f32_to_u32(0.5f), 0, 0x00400000, 0,0,0,1,0, 0,0,0,0}, // Underflow flag set, result is denormal
        // {"FMUL.S: Min_Denormal * 0.5 -> Flush to Zero", OP_FMUL_S, FP32, 0x00000001, f32_to_u32(0.5f), 0, 0x0, 0,0,0,1,1, 0,0,0,0}, // Underflow and Inexact

        // --- Overflow Tests ---
        // SP_Adder
            {"FADD.S: MAX_FLOAT + MAX_FLOAT -> Overflow",    OP_FADD_S,    CMP_NN,    FP32,    0x7F7FFFFF,    0x7F7FFFFF,    f32_to_u32(INFINITY),    0,    0,    0,0,1,0,1, 0},
        // DP_Adder
            {"FADD.D: MAX_FLOAT + MAX_FLOAT -> Overflow",    OP_FADD_D,    CMP_NN,    FP64,    0x7FEFFFFFFFFFFFFF,    0x7FEFFFFFFFFFFFFF,    f64_to_u64(INFINITY),    0,    0,    0,0,1,0,1, 0},
        // {"FMUL.D: MAX_FLOAT * 2.0 -> Overflow", OP_FMUL_D, FP64, 0x7FEFFFFFFFFFFFFF, f64_to_u64(2.0), 0, 0x7FF0000000000000, 0,0,1,0,1, 0,0,0,0},
        // {"FCVT.S.W: INT_MAX to FP32", OP_FCVT_S_W, FP32, 0x7FFFFFFF, 0, 0, 0x4f000000, 0,0,0,0,1, 0,0,0,0}, // 2147483647 -> 2.14748365E9 (inexact)
    };

    // reset
    top->rst_n = 0;
    top->clk = 0;
    top->eval();
    main_time++;
    if (tfp) tfp->dump(main_time);
    top->clk = 1;
    top->eval();
    main_time++;
    if (tfp) tfp->dump(main_time);
    top->rst_n = 1;

    // run tests
    int passed_count = 0;
    for (const auto& test : test_suite) {
        std::cout << "Running test: " << test.name << "..." << std::endl;
        if (run_test(top, tfp, test)) {
            std::cout << "  \033[32m[PASS]\033[0m" << std::endl;
            passed_count++;
        }
    }
    
    // Summary
    std::cout << "\n----------------------------------------" << std::endl;
    std::cout << "Test Summary: " << passed_count << " / " << test_suite.size() << " passed." << std::endl;
    std::cout << "----------------------------------------" << std::endl;

    // clean up
    tfp->close();
    delete top;
    
    return (passed_count == test_suite.size()) ? 0 : 1;
}
