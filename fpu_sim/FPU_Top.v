module FPU_Top (
    input clk,
    input rst_n,

    // --- Control Signals ---
    input [6:0]  func7,         // Operation code to select the function
    input [2:0]  func3,
    input [2:0]  rounding_mode,  // Rounding mode for arithmetic operations
    input        cvt_wu,

    // --- Data Inputs ---
    input [63:0] operand_a,      // Operand A (can be FP64, FP32, INT32, UINT32)
    input [63:0] operand_b,      // Operand B (can be FP64, FP32)

    // --- Data Outputs ---
    output reg [63:0] result_out,     // Result of the operation

    // --- Status Flags ---
    output       flag_invalid,
    output       flag_divbyzero,
    output       flag_overflow,
    output       flag_underflow,
    output       flag_inexact,

    // --- Comparison Flags (only valid for compare opcodes) ---
    output       flag_cmp
);

    // --- Opcode Definitions ---
    localparam OP_FADD_S  = 7'b0000000; // FP32 Add
    localparam OP_FSUB_S  = 7'b0000100; // FP32 Subtract
    localparam OP_FADD_D  = 7'b0000001; // FP64 Add
    localparam OP_FSUB_D  = 7'b0000101; // FP64 Subtract
    // localparam OP_FMUL_S  = 7'b0001000; // FP32 Multiply
    // localparam OP_FMUL_D  = 7'b0001001; // FP64 Multiply
    // localparam OP_FDIV_S  = 7'b0001100; // FP32 Divide
    // localparam OP_FDIV_D  = 7'b0001101; // FP64 Divide
    // localparam OP_FSQRT_S = 7'b0101100; // FP32 Square Root
    // localparam OP_FSQRT_D = 7'b0101101; // FP64 Square Root
    localparam OP_FCMP_S  = 7'b1010000; // FP32 Compare
    localparam OP_FCMP_D  = 7'b1010001; // FP64 Compare

    localparam OP_FCVT_D_S  = 7'b0100001; // FP32 -> FP64
    localparam OP_FCVT_W_S  = 7'b1100000; // FP32 -> INT32 // UINT32 same
    localparam OP_FCVT_D_W  = 7'b1101001; // INT32 -> FP64 // UINT32 same
    
    // localparam OP_FCVT_S_D  = 7'b0100000; // FP64 -> FP32
    // localparam OP_FCVT_W_D  = 7'b1100001; // FP64 -> INT32 // UINT32 same
    // localparam OP_FCVT_S_W  = 7'b1101000; // INT32 -> FP32 // UINT32 same


    // --- Internal Wires for connecting to sub-modules ---
    reg [31:0] sp_adder_result;
    reg sp_adder_invalid, sp_adder_overflow, sp_adder_underflow, sp_adder_inexact;

    reg [63:0] dp_adder_result;
    reg dp_adder_invalid, dp_adder_overflow, dp_adder_underflow, dp_adder_inexact;

    reg sp_cmp, sp_cmp_invalid;
    reg dp_cmp, dp_cmp_invalid;

    reg [63:0] sp_convert_result;
    reg sp_convert_invalid, sp_convert_overflow, sp_convert_underflow, sp_convert_inexact;

    // --- Sub-module control signals ---
    reg [1:0]  convert_input_type;
    reg [1:0]  convert_output_type;

    // --- Conversion Type Constants ---
    localparam FP32 = 2'b00, FP64 = 2'b01, INT32 = 2'b10, UINT32 = 2'b11;

    // --- Instantiate all functional units ---
    SP_Adder sp_adder_inst (
        .operand_a(operand_a[31:0]),
        .operand_b(operand_b[31:0]),
        .is_subtraction(func7[2]),
        .rounding_mode(rounding_mode),
        .result(sp_adder_result),
        .flag_invalid(sp_adder_invalid), .flag_overflow(sp_adder_overflow),
        .flag_underflow(sp_adder_underflow), .flag_inexact(sp_adder_inexact)
    );
    DP_Adder dp_adder_inst (
        .operand_a(operand_a),
        .operand_b(operand_b),
        .is_subtraction(func7[2]),
        .rounding_mode(rounding_mode),
        .result(dp_adder_result),
        .flag_invalid(dp_adder_invalid), .flag_overflow(dp_adder_overflow),
        .flag_underflow(dp_adder_underflow), .flag_inexact(dp_adder_inexact)
    );

    SP_Compare sp_compare_inst (
        .operand_a(operand_a[31:0]), .operand_b(operand_b[31:0]),
        .func3(func3),
        .flag_cmp(sp_cmp), .flag_invalid(sp_cmp_invalid)
    );

    DP_Compare dp_compare_inst (
        .operand_a(operand_a), .operand_b(operand_b),
        .func3(func3),
        .flag_cmp(dp_cmp), .flag_invalid(dp_cmp_invalid)
    );

    SP_Convert sp_convert_inst (
        .operand_in(operand_a[31:0]), 
        .input_type(convert_input_type),
        .output_type(convert_output_type),
        .rounding_mode(rounding_mode),
        .result(sp_convert_result),
        .flag_invalid(sp_convert_invalid), .flag_overflow(sp_convert_overflow),
        .flag_underflow(sp_convert_underflow), .flag_inexact(sp_convert_inexact)
    );

    // FP_Multiplier multiplier_inst (
    //     .clk(clk), .rst_n(rst_n),
    //     .operand_a(operand_a), .operand_b(operand_b),
    //     .is_double_precision(is_double),
    //     .rounding_mode(rounding_mode),
    //     .result(multiplier_result),
    //     .flag_invalid(multiplier_invalid), .flag_overflow(multiplier_overflow),
    //     .flag_underflow(multiplier_underflow), .flag_inexact(multiplier_inexact)
    // );

    // FP_Divider divider_inst (
    //     .clk(clk), .rst_n(rst_n),
    //     .operand_a(operand_a), .operand_b(operand_b),
    //     .is_double_precision(is_double),
    //     .rounding_mode(rounding_mode),
    //     .result(divider_result),
    //     .flag_invalid(divider_invalid), .flag_overflow(divider_overflow),
    //     .flag_underflow(divider_underflow), .flag_inexact(divider_inexact)
    // );

    // FP_Sqrt sqrt_inst (
    //     .clk(clk), .rst_n(rst_n),
    //     .operand_a(operand_a),
    //     .is_double_precision(is_double),
    //     .rounding_mode(rounding_mode),
    //     .result(sqrt_result),
    //     .flag_invalid(sqrt_invalid), .flag_overflow(sqrt_overflow),
    //     .flag_underflow(sqrt_underflow), .flag_inexact(sqrt_inexact)
    // );


    // --- Main Combinational Logic: Opcode Decoding and Output Muxing ---
    always @(*) begin
        // Default assignments to avoid latches
        result_out     = '0;
        flag_invalid   = 1'b0;
        flag_divbyzero = 1'b0;
        flag_overflow  = 1'b0;
        flag_underflow = 1'b0;
        flag_inexact   = 1'b0;
        flag_cmp = 0;

        convert_input_type = '0;
        convert_output_type = '0;

        // Decode opcode to select operation and drive outputs
        case (func7)
            OP_FADD_S, OP_FSUB_S: begin
                result_out = {32'b0, sp_adder_result};
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {sp_adder_invalid, sp_adder_overflow, sp_adder_underflow, sp_adder_inexact};
            end
            OP_FADD_D, OP_FSUB_D: begin
                result_out = dp_adder_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {dp_adder_invalid, dp_adder_overflow, dp_adder_underflow, dp_adder_inexact};
            end
            OP_FCMP_S: begin
                flag_cmp = sp_cmp;
                flag_invalid = sp_cmp_invalid;
            end
            OP_FCMP_D: begin
                flag_cmp = dp_cmp;
                flag_invalid = dp_cmp_invalid;
            end
            OP_FCVT_D_S, OP_FCVT_W_S, OP_FCVT_D_W: begin
                result_out = sp_convert_result;
                {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {sp_convert_invalid, sp_convert_overflow, sp_convert_underflow, sp_convert_inexact};
                case (func7)
                    OP_FCVT_D_S: begin convert_input_type = FP32; convert_output_type = FP64; end
                    OP_FCVT_W_S: begin convert_input_type = FP32; convert_output_type = (cvt_wu) ? UINT32 : INT32; end
                    OP_FCVT_D_W: begin convert_input_type = (cvt_wu) ? UINT32 : INT32; convert_output_type = FP64; end
                    default: begin convert_input_type = FP32; convert_output_type = FP64; end
                endcase
            end

            // OP_FMUL_S, OP_FMUL_D: begin
            //     is_double = opcode[0];
            //     result_out = multiplier_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {multiplier_invalid, multiplier_overflow, multiplier_underflow, multiplier_inexact};
            // end
            // OP_FDIV_S, OP_FDIV_D: begin
            //     is_double = opcode[0];
            //     result_out = divider_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {divider_invalid, divider_overflow, divider_underflow, divider_inexact};
            // end
            // OP_FSQRT_S, OP_FSQRT_D: begin
            //     is_double = opcode[0];
            //     result_out = sqrt_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {sqrt_invalid, sqrt_overflow, sqrt_underflow, sqrt_inexact};
            // end
            
            // // --- Conversion Opcodes ---
            // OP_FCVT_S_D: begin
            //     convert_input_type = FP64;
            //     convert_output_type = FP32;
            //     result_out = convert_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            // end
            // OP_FCVT_D_S: begin
            //     convert_input_type = FP32;
            //     convert_output_type = FP64;
            //     result_out = convert_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            // end
            // OP_FCVT_W_S: begin
            //     is_double = 1'b0; // Op is on FP32
            //     convert_input_type = FP32;
            //     convert_output_type = INT32;
            //     result_out = convert_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            // end
            // OP_FCVT_WU_S: begin
            //     is_double = 1'b0; // Op is on FP32
            //     convert_input_type = FP32;
            //     convert_output_type = UINT32;
            //     result_out = convert_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            // end
            // OP_FCVT_S_W: begin
            //     is_double = 1'b0; // Result is FP32
            //     convert_input_type = INT32;
            //     convert_output_type = FP32;
            //     result_out = convert_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            // end
            // OP_FCVT_S_WU: begin
            //     is_double = 1'b0; // Result is FP32
            //     convert_input_type = UINT32;
            //     convert_output_type = FP32;
            //     result_out = convert_result;
            //     {flag_invalid, flag_overflow, flag_underflow, flag_inexact} = {convert_invalid, convert_overflow, convert_underflow, convert_inexact};
            // end

            default: begin
                // Default to an invalid operation, return QNaN
                result_out     = 64'h7FF8_0000_0000_0000; // Default QNaN
                flag_invalid   = 1'b1;
            end
        endcase
    end

endmodule
