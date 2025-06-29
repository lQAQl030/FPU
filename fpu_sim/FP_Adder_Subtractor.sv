module FP_Adder_Subtractor (
    input logic clk,
    input logic rst_n,
    input logic [63:0] operand_a,
    input logic [63:0] operand_b,
    input logic        is_subtraction,
    input logic        is_double_precision,
    input logic [2:0]  rounding_mode,
    output logic [63:0] result,
    output logic       flag_invalid,
    output logic       flag_overflow,
    output logic       flag_underflow,
    output logic       flag_inexact
);

    // --- Sub-module Outputs ---
    logic        sign_a_dec, sign_b_dec;
    logic [10:0] exp_a_dec, exp_b_dec; // Receives BIASED exponents
    logic [52:0] mant_a_dec, mant_b_dec;
    logic is_a_zero, is_a_infinity, is_a_nan, is_a_denormal;
    logic is_b_zero, is_b_infinity, is_b_nan, is_b_denormal;
    
    // --- Final Result Components to drive Encoder ---
    logic        final_sign;
    logic [10:0] final_exp_biased; // BIASED exponent for encoder
    logic [52:0] final_mant;
    logic enc_is_result_zero, enc_is_result_infinity, enc_is_result_nan, enc_is_result_denormal;

    // --- Local variables for combinational logic ---
    logic normal_path_enable;
    logic [56:0] mant_a_shifted, mant_b_shifted, mant_sum;
    logic eff_sign_b;
    logic signed [11:0] exp_unbiased_a, exp_unbiased_b, larger_exp_unbiased;
    logic [56:0] norm_mant;
    logic signed [11:0] final_unb_exp;
    logic g_bit, r_bit, s_bit, round_up;
    int bias, max_exp, min_exp, lead_one_pos, shift_amt;

    // --- Instantiate Sub-modules ---
    FP_Decoder decoder_a (
        .fp_in(operand_a), .is_double_precision(is_double_precision),
        .sign_out(sign_a_dec), .exponent_out(exp_a_dec), .mantissa_out(mant_a_dec),
        .is_zero(is_a_zero), .is_infinity(is_a_infinity), .is_nan(is_a_nan), .is_denormal(is_a_denormal)
    );
    FP_Decoder decoder_b (
        .fp_in(operand_b), .is_double_precision(is_double_precision),
        .sign_out(sign_b_dec), .exponent_out(exp_b_dec), .mantissa_out(mant_b_dec),
        .is_zero(is_b_zero), .is_infinity(is_b_infinity), .is_nan(is_b_nan), .is_denormal(is_b_denormal)
    );
    FP_Encoder encoder (
        .sign_in(final_sign), .exponent_in(final_exp_biased), .mantissa_in(final_mant),
        .is_double_precision(is_double_precision), .fp_out(result)
    );
    
    // Helper function for right shifting with G, R, S bit generation
    function automatic logic [56:0] shift_right_mantissa_with_grs(input logic [52:0] mant_in, input int shift);
        logic [105:0] extended_mant;
        logic g, r, s;
        if (shift <= 0) return {mant_in, 4'b0};
        if (shift >= 106) return '0;
        extended_mant = {mant_in, 53'b0};
        extended_mant = extended_mant >> (shift - 1);
        g = extended_mant[52]; r = extended_mant[51]; s = |extended_mant[50:0];
        return {mant_in >> shift, g, r, s};
    endfunction

    always_comb begin
        // --- Default assignments to prevent latches ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        enc_is_result_zero=0; enc_is_result_infinity=0; enc_is_result_nan=0; enc_is_result_denormal=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        normal_path_enable = 1'b1;
        mant_a_shifted=0; mant_b_shifted=0; mant_sum=0; eff_sign_b=0;
        exp_unbiased_a=0; exp_unbiased_b=0; larger_exp_unbiased=0;
        norm_mant=0; final_unb_exp=0; g_bit=0; r_bit=0; s_bit=0; round_up=0;
        bias=0; max_exp=0; min_exp=0; lead_one_pos=0; shift_amt=0;

        // --- Special Value Handling ---
        if (is_a_nan || is_b_nan) begin
            normal_path_enable = 0;
            enc_is_result_nan = 1'b1;
            if ((is_a_nan && !mant_a_dec[51]) || (is_b_nan && !mant_b_dec[51])) flag_invalid = 1'b1;
        end else if (is_a_infinity || is_b_infinity) begin
            normal_path_enable = 0;
            if (is_a_infinity && is_b_infinity && (sign_a_dec != (sign_b_dec ^ is_subtraction))) begin
                final_exp_biased=11'b11111111111;
                final_mant={2'b11, 51'b0};
                flag_invalid = 1'b1; enc_is_result_nan = 1'b1;
            end else begin
                enc_is_result_infinity = 1'b1;
                final_sign = is_a_infinity ? sign_a_dec : (sign_b_dec ^ is_subtraction);
            end
        end else if (is_a_zero && is_b_zero) begin
            normal_path_enable = 0; enc_is_result_zero = 1'b1;
            final_sign = (is_subtraction && rounding_mode == 3'b010) ? 1'b1 : (sign_a_dec & (sign_b_dec ^ is_subtraction));
        end else if (is_a_zero) begin
            normal_path_enable = 0; final_sign = sign_b_dec ^ is_subtraction;
            final_exp_biased = exp_b_dec; final_mant = mant_b_dec;
            enc_is_result_denormal = is_b_denormal;
        end else if (is_b_zero) begin
            normal_path_enable = 0; final_sign = sign_a_dec;
            final_exp_biased = exp_a_dec; final_mant = mant_a_dec;
            enc_is_result_denormal = is_a_denormal;
        end
        
        // --- Normal Path ---
        if (normal_path_enable) begin
            bias = is_double_precision ? 1023 : 127;
            exp_unbiased_a = (exp_a_dec == 0) ? (1-bias) : (exp_a_dec - bias);
            exp_unbiased_b = (exp_b_dec == 0) ? (1-bias) : (exp_b_dec - bias);

            if (exp_unbiased_a >= exp_unbiased_b) begin
                larger_exp_unbiased = exp_unbiased_a;
                mant_a_shifted = {mant_a_dec, 3'b0};
                mant_b_shifted = shift_right_mantissa_with_grs(mant_b_dec, exp_unbiased_a - exp_unbiased_b);
                final_sign = sign_a_dec;
            end else begin
                larger_exp_unbiased = exp_unbiased_b;
                mant_b_shifted = {mant_b_dec, 3'b0};
                mant_a_shifted = shift_right_mantissa_with_grs(mant_a_dec, exp_unbiased_b - exp_unbiased_a);
                final_sign = sign_b_dec ^ is_subtraction;
            end

            eff_sign_b = sign_b_dec ^ is_subtraction;
            if (sign_a_dec == eff_sign_b) begin
                mant_sum = mant_a_shifted + mant_b_shifted;
            end else begin
                if (mant_a_shifted >= mant_b_shifted) mant_sum = mant_a_shifted - mant_b_shifted;
                else begin mant_sum = mant_b_shifted - mant_a_shifted; final_sign = ~final_sign; end
            end
            
            if (mant_sum == 0) begin enc_is_result_zero = 1'b1; end else begin
                lead_one_pos = $clog2(mant_sum);
                shift_amt = 56 - lead_one_pos;
                final_unb_exp = larger_exp_unbiased - shift_amt;
                norm_mant = mant_sum << shift_amt + 1;

                g_bit = norm_mant[3]; r_bit = norm_mant[2]; s_bit = norm_mant[1];
                flag_inexact = g_bit | r_bit | s_bit;
                round_up = (rounding_mode == 3'b000 && g_bit && (r_bit | s_bit | norm_mant[4])) ||
                           (rounding_mode == 3'b011 && flag_inexact && !final_sign) ||
                           (rounding_mode == 3'b010 && flag_inexact && final_sign);

                final_mant = norm_mant[56:4] + round_up;
                if (final_mant[53]) begin final_mant >>= 1; final_unb_exp += 1; end
                
                max_exp = is_double_precision ? 1023 : 127;
                min_exp = is_double_precision ? -1022 : -126;

                if (final_unb_exp > max_exp) begin flag_overflow = 1; flag_inexact = 1; enc_is_result_infinity = 1; end
                else if (final_unb_exp < min_exp) begin flag_underflow = 1; flag_inexact = 1; enc_is_result_zero = 1; end
                else final_exp_biased = final_unb_exp + bias;
            end
        end
    end
endmodule
