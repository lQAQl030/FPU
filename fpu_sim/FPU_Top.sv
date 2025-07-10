module FPU_Top (
    input logic clk,
    input logic rst_n,

    // --- Control Signals ---
    input logic [6:0]  opcode,         // Operation code to select the function
    input logic [2:0]  rounding_mode,  // Rounding mode for arithmetic operations

    // --- Data Inputs ---
    input logic [63:0] operand_a,      // Operand A (can be FP64, FP32, INT32, UINT32)
    input logic [63:0] operand_b,      // Operand B (can be FP64, FP32)

    // --- Data Outputs ---
    output logic [63:0] result_out,     // Result of the operation

    // --- Status Flags ---
    output logic       flag_invalid,
    output logic       flag_overflow,
    output logic       flag_underflow,
    output logic       flag_inexact,

    // --- Comparison Flags (only valid for compare opcodes) ---
    output logic       flag_lt,
    output logic       flag_eq,
    output logic       flag_gt,
    output logic       flag_unordered
);

    // --- Opcode Definitions ---
    localparam OP_FADD_S  = 7'b0000000; // FP32 Add
    localparam OP_FADD_D  = 7'b0000001; // FP64 Add
    localparam OP_FSUB_S  = 7'b0000100; // FP32 Subtract
    localparam OP_FSUB_D  = 7'b0000101; // FP64 Subtract
    localparam OP_FMUL_S  = 7'b0001000; // FP32 Multiply
    localparam OP_FMUL_D  = 7'b0001001; // FP64 Multiply
    localparam OP_FDIV_S  = 7'b0001100; // FP32 Divide
    localparam OP_FDIV_D  = 7'b0001101; // FP64 Divide
    localparam OP_FSQRT_S = 7'b0101100; // FP32 Square Root
    localparam OP_FSQRT_D = 7'b0101101; // FP64 Square Root
    localparam OP_FCMP_S  = 7'b1010000; // FP32 Compare
    localparam OP_FCMP_D  = 7'b1010001; // FP64 Compare
    
    localparam OP_FCVT_S_D  = 7'b0010000; // FP64 -> FP32
    localparam OP_FCVT_D_S  = 7'b0010001; // FP32 -> FP64
    localparam OP_FCVT_W_S  = 7'b0010010; // FP32 -> INT32
    localparam OP_FCVT_WU_S = 7'b0010011; // FP32 -> UINT32
    localparam OP_FCVT_S_W  = 7'b0010100; // INT32 -> FP32
    localparam OP_FCVT_S_WU = 7'b0010101; // UINT32 -> FP32

    // --- Internal Wires for connecting to sub-modules ---
    logic [63:0] adder_result, multiplier_result, divider_result, sqrt_result, convert_result;
    logic        adder_invalid, multiplier_invalid, divider_invalid, sqrt_invalid, convert_invalid;
    logic        adder_overflow, multiplier_overflow, divider_overflow, sqrt_overflow, convert_overflow;
    logic        adder_underflow, multiplier_underflow, divider_underflow, sqrt_underflow, convert_underflow;
    logic        adder_inexact, multiplier_inexact, divider_inexact, sqrt_inexact, convert_inexact;

    logic        cmp_lt, cmp_eq, cmp_gt, cmp_unordered, cmp_invalid;

    // --- Sub-module control signals ---
    logic        adder_sub_op;
    logic        is_double;
    logic [1:0]  convert_input_type;
    logic [1:0]  convert_output_type;

    // --- Conversion Type Constants ---
    localparam FP32 = 2'b00, FP64 = 2'b01, INT32 = 2'b10, UINT32 = 2'b11;
    
    // --- Intermediate Flags ---
    logic        sel_adder_flags, sel_mult_flags, sel_div_flags, sel_sqrt_flags, sel_conv_flags, sel_cmp_flags;
    logic [3:0]  arith_flags;
    logic [3:0]  adder_flags, mult_flags, div_flags, sqrt_flags, conv_flags;

    // --- Instantiate all functional units ---
    FP_Adder_Subtractor adder_inst (
        .clk(clk), .rst_n(rst_n),
        .operand_a(operand_a), .operand_b(operand_b),
        .is_subtraction(adder_sub_op),
        .is_double_precision(is_double),
        .rounding_mode(rounding_mode),
        .result(adder_result),
        .flag_invalid(adder_invalid), .flag_overflow(adder_overflow),
        .flag_underflow(adder_underflow), .flag_inexact(adder_inexact)
    );

    FP_Multiplier multiplier_inst (
        .clk(clk), .rst_n(rst_n),
        .operand_a(operand_a), .operand_b(operand_b),
        .is_double_precision(is_double),
        .rounding_mode(rounding_mode),
        .result(multiplier_result),
        .flag_invalid(multiplier_invalid), .flag_overflow(multiplier_overflow),
        .flag_underflow(multiplier_underflow), .flag_inexact(multiplier_inexact)
    );

    FP_Divider divider_inst (
        .clk(clk), .rst_n(rst_n),
        .operand_a(operand_a), .operand_b(operand_b),
        .is_double_precision(is_double),
        .rounding_mode(rounding_mode),
        .result(divider_result),
        .flag_invalid(divider_invalid), .flag_overflow(divider_overflow),
        .flag_underflow(divider_underflow), .flag_inexact(divider_inexact)
    );

    FP_Sqrt sqrt_inst (
        .clk(clk), .rst_n(rst_n),
        .operand_a(operand_a),
        .is_double_precision(is_double),
        .rounding_mode(rounding_mode),
        .result(sqrt_result),
        .flag_invalid(sqrt_invalid), .flag_overflow(sqrt_overflow),
        .flag_underflow(sqrt_underflow), .flag_inexact(sqrt_inexact)
    );

    FP_Compare compare_inst (
        .operand_a(operand_a), .operand_b(operand_b),
        .is_double_precision(is_double),
        .flag_lt(cmp_lt), .flag_eq(cmp_eq), .flag_gt(cmp_gt),
        .flag_unordered(cmp_unordered), .flag_invalid(cmp_invalid)
    );

    FP_Convert convert_inst (
        .clk(clk), .rst_n(rst_n),
        .operand_in(operand_a), // Convert uses only one operand
        .input_type(convert_input_type),
        .output_type(convert_output_type),
        .rounding_mode(rounding_mode),
        .result(convert_result),
        .flag_invalid(convert_invalid), .flag_overflow(convert_overflow),
        .flag_underflow(convert_underflow), .flag_inexact(convert_inexact)
    );


    // --- Main Combinational Logic: Opcode Decoding and Output Muxing ---
    always_comb begin
        // Default assignments to avoid latches
        result_out     = '0;
        flag_invalid   = 1'b0;
        flag_overflow  = 1'b0;
        flag_underflow = 1'b0;
        flag_inexact   = 1'b0;
        flag_lt        = 1'b0;
        flag_eq        = 1'b0;
        flag_gt        = 1'b0;
        flag_unordered = 1'b0;

        adder_sub_op = 1'b0;
        is_double    = 1'b0;

        convert_input_type = '0;
        convert_output_type = '0;

        // Decode opcode to select operation and drive outputs
        case (opcode)
            OP_FADD_S, OP_FADD_D, OP_FSUB_S, OP_FSUB_D: begin
                is_double = opcode[0];
                adder_sub_op = opcode[2];
                result_out = adder_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {adder_invalid, adder_overflow, adder_underflow, adder_inexact};
            end
            OP_FMUL_S, OP_FMUL_D: begin
                is_double = opcode[0];
                result_out = multiplier_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {multiplier_invalid, multiplier_overflow, multiplier_underflow, multiplier_inexact};
            end
            OP_FDIV_S, OP_FDIV_D: begin
                is_double = opcode[0];
                result_out = divider_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {divider_invalid, divider_overflow, divider_underflow, divider_inexact};
            end
            OP_FSQRT_S, OP_FSQRT_D: begin
                is_double = opcode[0];
                result_out = sqrt_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {sqrt_invalid, sqrt_overflow, sqrt_underflow, sqrt_inexact};
            end
            OP_FCMP_S, OP_FCMP_D: begin
                is_double = opcode[0];
                // Compare result is not a FP number but flags.
                flag_invalid = cmp_invalid;
                flag_lt = cmp_lt;
                flag_eq = cmp_eq;
                flag_gt = cmp_gt;
                flag_unordered = cmp_unordered;
            end
            
            // --- Conversion Opcodes ---
            OP_FCVT_S_D: begin
                convert_input_type = FP64;
                convert_output_type = FP32;
                result_out = convert_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            end
            OP_FCVT_D_S: begin
                convert_input_type = FP32;
                convert_output_type = FP64;
                result_out = convert_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            end
            OP_FCVT_W_S: begin
                is_double = 1'b0; // Op is on FP32
                convert_input_type = FP32;
                convert_output_type = INT32;
                result_out = convert_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            end
            OP_FCVT_WU_S: begin
                is_double = 1'b0; // Op is on FP32
                convert_input_type = FP32;
                convert_output_type = UINT32;
                result_out = convert_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            end
            OP_FCVT_S_W: begin
                is_double = 1'b0; // Result is FP32
                convert_input_type = INT32;
                convert_output_type = FP32;
                result_out = convert_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            end
            OP_FCVT_S_WU: begin
                is_double = 1'b0; // Result is FP32
                convert_input_type = UINT32;
                convert_output_type = FP32;
                result_out = convert_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            end

            default: begin
                // Default to an invalid operation, return QNaN
                result_out     = 64'h7FF8_0000_0000_0000; // Default QNaN
                flag_invalid   = 1'b1;
            end
        endcase
    end

endmodule
