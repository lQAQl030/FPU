module FP_Convert (
    input logic clk,
    input logic rst_n,
    input logic [63:0] operand_in,
    input logic [1:0]  input_type,
    input logic [1:0]  output_type,
    input logic [2:0]  rounding_mode,
    output logic [63:0] result,
    output logic       flag_invalid,
    output logic       flag_overflow,
    output logic       flag_underflow,
    output logic       flag_inexact
);
    // --- Type Parameters ---
    localparam FP_TYPE_FP32 = 2'b00, FP_TYPE_FP64 = 2'b01;
    localparam FP_TYPE_INT32 = 2'b10, FP_TYPE_UINT32 = 2'b11;
    
    // --- FP Constants ---
    localparam FP32_BIAS = 127, FP64_BIAS = 1023;
    localparam INT32_MAX = 32'h7FFFFFFF;
    localparam INT32_MIN = 32'h80000000;
    localparam UINT32_MAX = 32'hFFFFFFFF;

    // --- Decoded Input Signals ---
    logic dec_sign;
    logic [10:0] dec_exp_biased;
    logic [52:0] dec_mant;
    logic dec_is_zero, dec_is_infinity, dec_is_nan, dec_is_denormal;

    // --- Final FP Result Components (before encoding) ---
    logic final_sign;
    logic [10:0] final_exp_biased;
    logic [52:0] final_mant;
    logic final_is_result_zero, final_is_result_infinity, final_is_result_nan, final_is_result_denormal;

    // --- Local Variables (Module Scope) ---
    logic [127:0] val_extended, shifted_val;
    logic lost_bits;
    logic [63:0] int_val;
    logic signed [11:0] unb_exp;
    logic [31:0] abs_val;
    int msb_pos;
    
    // --- Instantiate Decoder and Encoder (Explicit Connections) ---
    FP_Decoder decoder(
        .fp_in(operand_in),
        .is_double_precision(input_type == FP_TYPE_FP64),
        .sign_out(dec_sign),
        .exponent_out(dec_exp_biased),
        .mantissa_out(dec_mant),
        .is_zero(dec_is_zero),
        .is_infinity(dec_is_infinity),
        .is_nan(dec_is_nan),
        .is_denormal(dec_is_denormal)
    );
    logic [63:0] encoder_out;
    FP_Encoder encoder(
        .sign_in(final_sign),
        .exponent_in(final_exp_biased),
        .mantissa_in(final_mant),
        .is_double_precision(output_type == FP_TYPE_FP64),
        .fp_out(encoder_out)
    );

    always_comb begin
        // --- Default Assignments ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        final_is_result_zero=0; final_is_result_infinity=0; final_is_result_nan=0; final_is_result_denormal=0;
        result = '0;
        val_extended=0; shifted_val=0; lost_bits=0; int_val=0; unb_exp=0; abs_val=0; msb_pos = 0;

        // --- Main Conversion Logic ---
        if (input_type == FP_TYPE_FP32 || input_type == FP_TYPE_FP64) begin
            // --- FP -> (FP or INT) Conversion ---
            if (dec_is_nan) begin
                flag_invalid = 1'b1;
                if (output_type == FP_TYPE_INT32) result = INT32_MAX;
                else if (output_type == FP_TYPE_UINT32) result = UINT32_MAX;
                else final_is_result_nan = 1'b1;
            end else if (dec_is_infinity) begin
                flag_invalid = 1'b1;
                if (output_type == FP_TYPE_INT32) result = dec_sign ? INT32_MIN : INT32_MAX;
                else if (output_type == FP_TYPE_UINT32) result = dec_sign ? 0 : UINT32_MAX;
                else begin final_is_result_infinity = 1'b1; final_sign = dec_sign; end
            end else if (dec_is_zero) begin
                if (output_type == FP_TYPE_INT32 || output_type == FP_TYPE_UINT32) result = 0;
                else begin final_is_result_zero = 1'b1; final_sign = dec_sign; end
            end else begin
                unb_exp = dec_exp_biased - ((input_type == FP_TYPE_FP64) ? FP64_BIAS : FP32_BIAS);
                if (output_type == FP_TYPE_FP32 || output_type == FP_TYPE_FP64) begin
                    // --- FP -> FP ---
                    final_exp_biased = unb_exp + ((output_type == FP_TYPE_FP64) ? FP64_BIAS : FP32_BIAS);
                    final_mant = dec_mant; final_sign = dec_sign;
                end else begin
                    // --- FP -> INT ---
                    if (unb_exp < 0) begin int_val = 0; lost_bits = |dec_mant; end
                    else begin
                        val_extended = {dec_mant, 75'b0};
                        shifted_val = val_extended >> (52 - unb_exp);
                        int_val = shifted_val[127:75];
                        lost_bits = |(shifted_val[74:0]);
                    end
                    if(rounding_mode != 3'b001 && lost_bits) int_val += 1; // Simplified rounding
                    flag_inexact = lost_bits;
                    
                    if (dec_sign) begin
                        if (output_type == FP_TYPE_UINT32) begin flag_invalid=1; result=0; end
                        else begin
                            if (unb_exp > 31 || (unb_exp==31 && int_val > INT32_MIN)) begin flag_invalid=1; result=INT32_MIN; end
                            else result = -int_val;
                        end
                    end else begin
                        if (output_type == FP_TYPE_UINT32) begin
                           if (unb_exp > 31) begin flag_invalid=1; result=UINT32_MAX; end
                           else result = int_val;
                        end else begin // INT32
                           if (unb_exp > 30 || (unb_exp==30 && int_val > INT32_MAX)) begin flag_invalid=1; result=INT32_MAX; end
                           else result = int_val;
                        end
                    end
                end
            end
        end else begin
            // --- INT -> FP Conversion ---
            final_sign = (input_type == FP_TYPE_INT32) ? operand_in[31] : 1'b0;
            if (final_sign) abs_val = -operand_in[31:0]; else abs_val = operand_in[31:0];

            if (abs_val == 0) begin
                final_is_result_zero = 1;
            end else begin
                msb_pos = $clog2(abs_val) - 1;
                unb_exp = msb_pos;
                final_exp_biased = unb_exp + ((output_type == FP_TYPE_FP64) ? FP64_BIAS : FP32_BIAS);
                final_mant = abs_val << (52 - msb_pos);
            end
        end

        // Mux the final result
        if (output_type == FP_TYPE_FP32 || output_type == FP_TYPE_FP64) begin
            result = encoder_out;
        end
    end
endmodule
