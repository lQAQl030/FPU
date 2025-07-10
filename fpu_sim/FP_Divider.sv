module FP_Divider (
    input logic clk,
    input logic rst_n,
    input logic [63:0] operand_a,
    input logic [63:0] operand_b,
    input logic        is_double_precision,
    input logic [2:0]  rounding_mode,
    output logic [63:0] result,
    output logic       flag_invalid,
    output logic       flag_overflow,
    output logic       flag_underflow,
    output logic       flag_inexact
);
    // --- Sub-module Connections ---
    logic        sign_a_dec, sign_b_dec;
    logic [10:0] exp_a_dec, exp_b_dec;
    logic [52:0] mant_a_dec, mant_b_dec;
    logic is_a_zero, is_a_infinity, is_a_nan, is_a_denormal;
    logic is_b_zero, is_b_infinity, is_b_nan, is_b_denormal;

    // --- Final Result Components ---
    logic        final_sign;
    logic [10:0] final_exp_biased;
    logic [52:0] final_mant;

    // --- Local Variables ---
    logic normal_path_enable;
    logic [52:0] norm_mant_a, norm_mant_b;
    logic signed [11:0] unb_exp_a, unb_exp_b, diff_unb_exp, final_unb_exp;

    localparam int precision_shift = 60; 
    logic [52+precision_shift:0] dividend;
    logic [52:0]                divisor;
    logic [52+precision_shift:0] quotient;
    logic [52+precision_shift:0] norm_quotient;
    
    logic [23:0] sp_mant_unrounded;
    logic [52:0] result_mant_unrounded;
    logic [52:0] result_mant_rounded;
    logic lsb, g_bit, r_bit, s_bit, round_up;
    int bias, max_unb_exp, min_unb_exp;
    int denorm_shift_a, denorm_shift_b;

    // --- Instantiate Sub-modules ---
    FP_Decoder decoder_a( .fp_in(operand_a), .is_double_precision(is_double_precision), .sign_out(sign_a_dec), .exponent_out(exp_a_dec), .mantissa_out(mant_a_dec), .is_zero(is_a_zero), .is_infinity(is_a_infinity), .is_nan(is_a_nan), .is_denormal(is_a_denormal) );
    FP_Decoder decoder_b( .fp_in(operand_b), .is_double_precision(is_double_precision), .sign_out(sign_b_dec), .exponent_out(exp_b_dec), .mantissa_out(mant_b_dec), .is_zero(is_b_zero), .is_infinity(is_b_infinity), .is_nan(is_b_nan), .is_denormal(is_b_denormal) );
    FP_Encoder encoder( .sign_in(final_sign), .exponent_in(final_exp_biased), .mantissa_in(final_mant), .is_double_precision(is_double_precision), .fp_out(result) );

    function automatic integer count_leading_zeros_53(input [52:0] val);
        for (int i = 51; i >= 0; i--) if (val[i]) return 51 - i;
        return 52;
    endfunction

    always_comb begin
        // --- Default assignments ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        normal_path_enable=1;
        norm_mant_a=0; norm_mant_b=0; unb_exp_a=0; unb_exp_b=0; diff_unb_exp=0;
        dividend=0; divisor=0; quotient=0; norm_quotient=0;
        sp_mant_unrounded=0; result_mant_unrounded=0; result_mant_rounded=0;
        final_unb_exp=0; lsb=0; g_bit=0; r_bit=0; s_bit=0; round_up=0;
        bias=0; max_unb_exp=0; min_unb_exp=0; 
        denorm_shift_a=0; denorm_shift_b=0;

        // --- 1. Special Value Handling ---
        final_sign = sign_a_dec ^ sign_b_dec;
        if ((is_a_nan || is_b_nan) || (is_a_infinity && is_b_infinity) || (is_a_zero && is_b_zero)) begin
            normal_path_enable = 0; flag_invalid = 1'b1; final_exp_biased = '1;
            final_mant = {1'b1, 52'h80000_00000000};
        end else if (is_b_zero) begin
            normal_path_enable = 0; flag_overflow = 1'b1; final_exp_biased = '1; final_mant = '0;
        end else if (is_a_infinity) begin
            normal_path_enable = 0; final_exp_biased = '1; final_mant = '0;
        end else if (is_a_zero) begin
            normal_path_enable = 0;
        end else if (is_b_infinity) begin
            normal_path_enable = 0;
        end

        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            bias = is_double_precision ? 1023 : 127;

            unb_exp_a = is_a_denormal ? (1-bias) : $signed(exp_a_dec) - bias;
            if (is_a_denormal) begin denorm_shift_a = count_leading_zeros_53(mant_a_dec)+1; norm_mant_a = mant_a_dec << denorm_shift_a; unb_exp_a -= denorm_shift_a;
            end else norm_mant_a = mant_a_dec;
            
            unb_exp_b = is_b_denormal ? (1-bias) : $signed(exp_b_dec) - bias;
            if (is_b_denormal) begin denorm_shift_b = count_leading_zeros_53(mant_b_dec)+1; norm_mant_b = mant_b_dec << denorm_shift_b; unb_exp_b -= denorm_shift_b;
            end else norm_mant_b = mant_b_dec;

            // --- 2b. Unconditional High-Precision Division ---
            dividend = {norm_mant_a, {precision_shift{1'b0}}};
            divisor = norm_mant_b;
            quotient = dividend / divisor;

            // --- 2c. Post-Division Normalization ---
            final_unb_exp = unb_exp_a - unb_exp_b;
            // Check if result is < 1.0 (i.e. if norm_mant_a < norm_mant_b)
            if (!quotient[precision_shift]) begin
                // Result is 0.xxxxx, so shift left by 1 and decrement exponent
                norm_quotient = quotient << 1;
                final_unb_exp = final_unb_exp - 1;
            end else begin
                // Result is 1.xxxxx, no shift needed
                norm_quotient = quotient;
            end
            
            // --- 2d. Rounding Logic ---
            if (is_double_precision) begin
                result_mant_unrounded = {norm_quotient[precision_shift], norm_quotient[precision_shift-1:precision_shift-52]};
                lsb   = result_mant_unrounded[0];
                g_bit = norm_quotient[precision_shift-53];
                r_bit = norm_quotient[precision_shift-54];
                s_bit = |norm_quotient[precision_shift-55:0];
            end else begin // Single Precision
                sp_mant_unrounded = {norm_quotient[precision_shift], norm_quotient[precision_shift-1:precision_shift-23]};
                lsb = sp_mant_unrounded[0];
                g_bit = norm_quotient[precision_shift-24];
                r_bit = norm_quotient[precision_shift-25];
                s_bit = |norm_quotient[precision_shift-26:0];
            end

            flag_inexact = g_bit | r_bit | s_bit;
            
            case(rounding_mode)
                3'b000: round_up = g_bit & (lsb | r_bit | s_bit); // RNE
                3'b001: round_up = 1'b0;                          // RTZ
                3'b010: round_up = flag_inexact & final_sign;     // RDN
                3'b011: round_up = flag_inexact & ~final_sign;    // RUP
                default: round_up = 1'b0;
            endcase
            
            if (is_double_precision) begin
                result_mant_rounded = result_mant_unrounded + round_up;
            end else begin
                result_mant_rounded = {sp_mant_unrounded + round_up, 29'b0};
            end
            

            if (result_mant_rounded[53]) begin
                final_mant = result_mant_rounded >> 1;
                final_unb_exp += 1;
            end else begin
                final_mant = result_mant_rounded;
            end
            
            // --- 2e. Final Pack & Overflow/Underflow check ---
            max_unb_exp = is_double_precision ? 1023 : 127;
            min_unb_exp = is_double_precision ? -1022 : -126;
            // if (final_unb_exp > max_unb_exp) begin flag_overflow=1; flag_inexact=1; end
            // else if (final_unb_exp < min_unb_exp) begin flag_underflow=1; flag_inexact=1; end
            begin final_exp_biased = final_unb_exp + bias; end
        end
    end
endmodule
