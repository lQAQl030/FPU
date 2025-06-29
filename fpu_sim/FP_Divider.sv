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
    // --- Sub-module Outputs ---
    logic        sign_a_dec, sign_b_dec;
    logic [10:0] exp_a_dec, exp_b_dec;
    logic [52:0] mant_a_dec, mant_b_dec;
    logic is_a_zero, is_a_infinity, is_a_nan, is_a_denormal;
    logic is_b_zero, is_b_infinity, is_b_nan, is_b_denormal;

    // --- Final Result Components ---
    logic        final_sign;
    logic [10:0] final_exp_biased;
    logic [52:0] final_mant;
    logic enc_is_result_zero, enc_is_result_infinity, enc_is_result_nan, enc_is_result_denormal;

    // --- Local Variables (Module Scope) ---
    logic normal_path_enable;
    logic [52:0] norm_mant_a, norm_mant_b;
    logic signed [11:0] unb_exp_a, unb_exp_b, diff_unb_exp, final_unb_exp;
    logic [107:0] dividend; // For division: mantissa << (53+2)
    logic [56:0] quotient, remainder;
    logic [53:0] norm_quotient;
    logic g_bit, r_bit, s_bit, round_up;
    int bias, max_exp, min_exp, lz;

    // --- Instantiate Sub-modules (Explicit Connections) ---
    FP_Decoder decoder_a(
        .fp_in(operand_a), .is_double_precision(is_double_precision),
        .sign_out(sign_a_dec), .exponent_out(exp_a_dec), .mantissa_out(mant_a_dec),
        .is_zero(is_a_zero), .is_infinity(is_a_infinity), .is_nan(is_a_nan), .is_denormal(is_a_denormal)
    );
    FP_Decoder decoder_b(
        .fp_in(operand_b), .is_double_precision(is_double_precision),
        .sign_out(sign_b_dec), .exponent_out(exp_b_dec), .mantissa_out(mant_b_dec),
        .is_zero(is_b_zero), .is_infinity(is_b_infinity), .is_nan(is_b_nan), .is_denormal(is_b_denormal)
    );
    FP_Encoder encoder(
        .sign_in(final_sign), .exponent_in(final_exp_biased), .mantissa_in(final_mant),
        .is_double_precision(is_double_precision), .fp_out(result)
    );

    always_comb begin
        // --- Default assignments to prevent latches ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        enc_is_result_zero=0; enc_is_result_infinity=0; enc_is_result_nan=0; enc_is_result_denormal=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        normal_path_enable=1;
        norm_mant_a=0; norm_mant_b=0; unb_exp_a=0; unb_exp_b=0; diff_unb_exp=0;
        dividend=0; quotient=0; remainder=0; norm_quotient=0;
        final_unb_exp=0; g_bit=0; r_bit=0; s_bit=0; round_up=0;
        bias=0; max_exp=0; min_exp=0; lz=0;

        // --- 1. Special Value Handling ---
        final_sign = sign_a_dec ^ sign_b_dec;
        if (is_a_nan || is_b_nan) begin normal_path_enable=0; enc_is_result_nan=1; if((is_a_nan&&!mant_a_dec[51])||(is_b_nan&&!mant_b_dec[51])) flag_invalid=1; end
        else if ((is_a_infinity && is_b_infinity) || (is_a_zero && is_b_zero)) begin normal_path_enable=0; flag_invalid=1; enc_is_result_nan=1; end
        else if (!is_a_zero && is_b_zero) begin normal_path_enable=0; final_sign=(sign_a_dec ^ sign_b_dec); final_exp_biased=11'b11111111111; flag_overflow=1; enc_is_result_infinity=1; end
        else if (is_a_infinity) begin normal_path_enable=0; enc_is_result_infinity=1; end
        else if (is_a_zero) begin normal_path_enable=0; enc_is_result_zero=1; end
        else if (is_b_infinity) begin normal_path_enable=0; enc_is_result_zero=1; end

        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            bias = is_double_precision ? 1023 : 127;

            // --- 2a. Denormalize Inputs ---
            norm_mant_a = mant_a_dec;
            unb_exp_a = (exp_a_dec==0) ? (1-bias) : (exp_a_dec - bias);
            if (is_a_denormal) begin
                lz = $clog2(mant_a_dec); norm_mant_a = mant_a_dec << (53 - lz); unb_exp_a = unb_exp_a - (52 - (lz-1));
            end
            norm_mant_b = mant_b_dec;
            unb_exp_b = (exp_b_dec==0) ? (1-bias) : (exp_b_dec - bias);
            if (is_b_denormal) begin
                lz = $clog2(mant_b_dec); norm_mant_b = mant_b_dec << (53 - lz); unb_exp_b = unb_exp_b - (52 - (lz-1));
            end

            // --- 2b. Prepare for Division ---
            diff_unb_exp = unb_exp_a - unb_exp_b;
            // Extend dividend for precision. If M_A < M_B, pre-shift left by 1 and adjust exponent
            if (norm_mant_a < norm_mant_b) begin
                dividend = {norm_mant_a, 55'b0} << 1;
                diff_unb_exp = diff_unb_exp - 1;
            end else begin
                dividend = {norm_mant_a, 55'b0};
            end

            // --- 2c. Behavioral Mantissa Division ---
            quotient = dividend / norm_mant_b;
            remainder = dividend % norm_mant_b;

            // --- 2d. Normalization & Rounding ---
            // The quotient will be 1.xxxx... because of the pre-shift.
            // We need 53 bits + G, R, S.
            // The quotient has 54 bits of precision (1. + 53 frac). GRS comes from remainder.
            final_unb_exp = diff_unb_exp;
            norm_quotient = quotient[56:3]; // 54 bits: 1. + 53 fractional
            
            g_bit = quotient[2];
            r_bit = quotient[1];
            s_bit = quotient[0] | (remainder != 0); // Sticky is any remaining bit or non-zero remainder

            flag_inexact = g_bit | r_bit | s_bit;
            round_up = (rounding_mode == 3'b000 && g_bit && (r_bit | s_bit | norm_quotient[0])) ||
                       (rounding_mode == 3'b011 && flag_inexact && !final_sign) ||
                       (rounding_mode == 3'b010 && flag_inexact && final_sign);

            final_mant = norm_quotient + round_up;
            if (final_mant[53]) begin // Mantissa overflowed to 10.0...
                final_mant >>= 1;
                final_unb_exp += 1;
            end

            // --- 2e. Final Pack & Overflow/Underflow check ---
            max_exp = is_double_precision ? 1023 : 127;
            min_exp = is_double_precision ? -1022 : -126;
            if (final_unb_exp > max_exp) begin flag_overflow=1; flag_inexact=1; enc_is_result_infinity=1; end
            else if (final_unb_exp < min_exp) begin flag_underflow=1; flag_inexact=1; enc_is_result_zero=1; end
            else final_exp_biased = final_unb_exp + bias;
        end
    end
endmodule
