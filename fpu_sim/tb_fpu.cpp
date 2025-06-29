// tb_fpu.cpp
#include <iostream>
#include <vector>
#include <cstdint>
#include <cmath>
#include <iomanip>

// Verilator核心標頭檔
#include "verilated.h"
#include "verilated_vcd_c.h"

// FPU Top模組的Verilator生成標頭檔
#include "VFPU_Top.h"

// 輔助函數，用於在float/double和其整數表示之間轉換
// 這對於設定操作數和比較結果至關重要
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

// 測試案例結構
struct TestCase {
    std::string name;
    uint8_t  opcode;
    uint64_t operand_a;
    uint64_t operand_b;
    uint8_t  rounding_mode;

    // 預期輸出
    uint64_t expected_result;
    bool     expected_invalid;
    bool     expected_overflow;
    bool     expected_underflow;
    bool     expected_inexact;
    // 比較旗標
    bool     expected_lt;
    bool     expected_eq;
    bool     expected_gt;
    bool     expected_unordered;
};

// 模擬時鐘
vluint64_t main_time = 0;
double sc_time_stamp() {
    return main_time;
}

// 執行單個測試案例的函數
bool run_test(VFPU_Top* top, VerilatedVcdC* tfp, const TestCase& test) {
    // 設定輸入
    top->opcode = test.opcode;
    top->operand_a = test.operand_a;
    top->operand_b = test.operand_b;
    top->rounding_mode = test.rounding_mode;

    // 模擬一個時脈週期
    top->clk = 0;
    top->eval();
    main_time++;
    if (tfp) tfp->dump(main_time);
    
    top->clk = 1;
    top->eval();
    main_time++;
    if (tfp) tfp->dump(main_time);

    // 檢查輸出
    bool pass = true;
    // 根據操作碼檢查不同的輸出
    // ** FIX: Use C++ binary literal `0b` instead of Verilog's `5'b` **
    if (test.opcode >= 0b01010 && test.opcode <= 0b01011) { // Compare Ops
        if (top->flag_lt != test.expected_lt) {
            pass = false;
            std::cout << "    \033[31m[FAIL]\033[0m LT flag mismatch. Got: " << (int)top->flag_lt << ", Expected: " << (int)test.expected_lt << std::endl;
        }
        if (top->flag_eq != test.expected_eq) {
            pass = false;
            std::cout << "    \033[31m[FAIL]\033[0m EQ flag mismatch. Got: " << (int)top->flag_eq << ", Expected: " << (int)test.expected_eq << std::endl;
        }
        if (top->flag_gt != test.expected_gt) {
            pass = false;
            std::cout << "    \033[31m[FAIL]\033[0m GT flag mismatch. Got: " << (int)top->flag_gt << ", Expected: " << (int)test.expected_gt << std::endl;
        }
        if (top->flag_unordered != test.expected_unordered) {
            pass = false;
            std::cout << "    \033[31m[FAIL]\033[0m Unordered flag mismatch. Got: " << (int)top->flag_unordered << ", Expected: " << (int)test.expected_unordered << std::endl;
        }
    } else { // Arithmetic/Convert Ops
        // INT check
        if (test.opcode == 0b0010010 && top->result_out != test.expected_result) {
             pass = false;
             std::cout << "    \033[31m[FAIL]\033[0m Result mismatch (INT32). Got: " << std::dec << top->result_out << ", Expected: " << test.expected_result << std::endl;
        }
        // FP32 check (only lower 32 bits matter)
        else if (test.opcode % 2 == 0 && (top->result_out & 0xFFFFFFFF) != (test.expected_result & 0xFFFFFFFF)) {
             pass = false;
             std::cout << "    \033[31m[FAIL]\033[0m Result mismatch (FP32). Got: " << std::hex << u32_to_f32(top->result_out & 0xFFFFFFFF) << ", Expected: " << u32_to_f32(test.expected_result & 0xFFFFFFFF) << std::dec << std::endl;
        }
        // FP64 check (all 64 bits matter)
        else if (test.opcode % 2 != 0 && top->result_out != test.expected_result) {
             pass = false;
             std::cout << "    \033[31m[FAIL]\033[0m Result mismatch (FP64). Got: " << std::hex << u64_to_f64(top->result_out) << ", Expected: " << u64_to_f64(test.expected_result) << std::dec << std::endl;
        }
    }

    // 檢查狀態旗標
    if (top->flag_invalid != test.expected_invalid) {
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
    // 初始化Verilator
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    // 實例化FPU模組
    VFPU_Top* top = new VFPU_Top;

    // 實例化VCD波形追蹤器
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("waveform.vcd");

    // 定義Opcode (與 FPU_Top.v 中一致)
    const uint8_t OP_FADD_S = 0b0000000, OP_FADD_D = 0b0000001;
    const uint8_t OP_FSUB_S = 0b0000100, OP_FSUB_D = 0b0000101;
    const uint8_t OP_FMUL_S = 0b0001000, OP_FMUL_D = 0b0001001;
    const uint8_t OP_FDIV_S = 0b0001100, OP_FDIV_D = 0b0001101;
    const uint8_t OP_FSQRT_S = 0b0101100, OP_FSQRT_D = 0b0101101;
    const uint8_t OP_FCMP_S = 0b1010000, OP_FCMP_D = 0b1010001;
    const uint8_t OP_FCVT_S_W = 0b0010100;
    const uint8_t OP_FCVT_W_S = 0b0010010;

    // 定義測試案例
    std::vector<TestCase> test_suite = {
        {"FADD.S: 1.5 + 2.75", OP_FADD_S, f32_to_u32(1.5f), f32_to_u32(2.75f), 0, f32_to_u32(4.25f), 0,0,0,0, 0,0,0,0},
        {"FADD.D: 10.5 + 20.25", OP_FADD_D, f64_to_u64(10.5), f64_to_u64(20.25), 0, f64_to_u64(30.75), 0,0,0,0, 0,0,0,0},
        {"FSUB.S: 10.0 - 5.5", OP_FSUB_S, f32_to_u32(10.0f), f32_to_u32(5.5f), 0, f32_to_u32(4.5f), 0,0,0,0, 0,0,0,0},
        {"FMUL.D: 3.0 * 2.5", OP_FMUL_D, f64_to_u64(3.0), f64_to_u64(2.5), 0, f64_to_u64(7.5), 0,0,0,0, 0,0,0,0},
        {"FDIV.S: 100.0 / 4.0", OP_FDIV_S, f32_to_u32(100.0f), f32_to_u32(4.0f), 0, f32_to_u32(25.0f), 0,0,0,0, 0,0,0,0},
        {"FSQRT.D: sqrt(16.0)", OP_FSQRT_D, f64_to_u64(16.0), 0, 0, f64_to_u64(4.0), 0,0,0,0, 0,0,0,0},
        {"FSQRT.D: sqrt(-1.0) -> Invalid NaN", OP_FSQRT_D, f64_to_u64(-1.0), 0, 0, 0x7ff8000000000000, 1,0,0,0, 0,0,0,0},
        {"DIV.S by Zero -> Infinity", OP_FDIV_S, f32_to_u32(5.0f), f32_to_u32(0.0f), 0, 0x7f800000, 0,1,0,0, 0,0,0,0}, 
        {"Inf - Inf -> Invalid NaN", OP_FSUB_D, f64_to_u64(INFINITY), f64_to_u64(INFINITY), 0, 0x7ff8000000000000, 1,0,0,0, 0,0,0,0},
        {"FCMP.D: 5.0 > 3.0", OP_FCMP_D, f64_to_u64(5.0), f64_to_u64(3.0), 0, 0, 0,0,0,0, 0,0,1,0},
        {"FCMP.S: -2.0 < -1.0", OP_FCMP_S, f32_to_u32(-2.0f), f32_to_u32(-1.0f), 0, 0, 0,0,0,0, 1,0,0,0},
        {"FCMP.D: 7.0 == 7.0", OP_FCMP_D, f64_to_u64(7.0), f64_to_u64(7.0), 0, 0, 0,0,0,0, 0,1,0,0},
        {"FCMP.D: +0.0 == -0.0", OP_FCMP_D, f64_to_u64(0.0), f64_to_u64(-0.0), 0, 0, 0,0,0,0, 0,1,0,0},
        {"FCMP.D: 5.0 vs NaN -> Unordered", OP_FCMP_D, f64_to_u64(5.0), f64_to_u64(NAN), 0, 0, 1,0,0,0, 0,0,0,1}, // Invalid flag for SNaN
        {"FCVT.S.W: int(123) -> float", OP_FCVT_S_W, 123, 0, 0, f32_to_u32(123.0f), 0,0,0,0, 0,0,0,0},
        {"FCVT.W.S: float(3.75) -> int (RTZ)", OP_FCVT_W_S, f32_to_u32(3.75f), 0, 1, 3, 0,0,0,1, 0,0,0,0} // Inexact=1
    };

    // 重置FPU
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

    // 執行所有測試
    int passed_count = 0;
    for (const auto& test : test_suite) {
        std::cout << "Running test: " << test.name << "..." << std::endl;
        if (run_test(top, tfp, test)) {
            std::cout << "  \033[32m[PASS]\033[0m" << std::endl;
            passed_count++;
        }
    }
    
    // 輸出總結
    std::cout << "\n----------------------------------------" << std::endl;
    std::cout << "Test Summary: " << passed_count << " / " << test_suite.size() << " passed." << std::endl;
    std::cout << "----------------------------------------" << std::endl;

    // 清理
    tfp->close();
    delete top;
    
    return (passed_count == test_suite.size()) ? 0 : 1;
}
