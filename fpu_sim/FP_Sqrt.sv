module FP_Sqrt (
    input logic clk,
    input logic rst_n,
    input logic [63:0] operand_a,
    input logic        is_double_precision,
    input logic [2:0]  rounding_mode,
    output logic [63:0] result,
    output logic       flag_invalid,
    output logic       flag_overflow,
    output logic       flag_underflow,
    output logic       flag_inexact
);
    // --- Sub-module Connections ---
    logic        sign_a_dec;
    logic [10:0] exp_a_dec;
    logic [52:0] mant_a_dec;
    logic is_a_zero, is_a_infinity, is_a_nan, is_a_denormal;
    logic        final_sign;
    logic [10:0] final_exp_biased;
    logic [52:0] final_mant;
    logic enc_is_result_zero, enc_is_result_infinity, enc_is_result_nan, enc_is_result_denormal;

    // --- Local Variables (Module Scope) ---
    logic normal_path_enable;
    logic [107:0] radicand;
    logic [53:0]  sqrt_int_res;
    logic signed [11:0] unb_exp_a, final_unb_exp;
    logic g_bit, r_bit, s_bit, round_up;
    int bias, max_exp, min_exp;
    
    // -- Behavioral Sqrt Algorithm Variables (Module Scope) --
    logic [107:0] rem;
    logic [107:0] root;
    logic [107:0] bit_shifter;
    logic [53+26:0] temp_mant_norm;
    
    // --- Instantiate Sub-modules ---
    FP_Decoder decoder_a (
        .fp_in(operand_a), .is_double_precision(is_double_precision),
        .sign_out(sign_a_dec), .exponent_out(exp_a_dec), .mantissa_out(mant_a_dec),
        .is_zero(is_a_zero), .is_infinity(is_a_infinity), .is_nan(is_a_nan), .is_denormal(is_a_denormal)
    );
    FP_Encoder encoder(
        .sign_in(final_sign), .exponent_in(final_exp_biased), .mantissa_in(final_mant),
        .is_double_precision(is_double_precision), .fp_out(result)
    );

    always_comb begin
        // --- Default assignments ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        enc_is_result_zero=0; enc_is_result_infinity=0; enc_is_result_nan=0; enc_is_result_denormal=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        normal_path_enable=1; radicand=0; sqrt_int_res=0; unb_exp_a=0; final_unb_exp=0;
        g_bit=0; r_bit=0; s_bit=0; round_up=0;
        bias=0; max_exp=0; min_exp=0;
        rem=0; root=0; bit_shifter=0; temp_mant_norm=0;

        // --- 1. Special Value Handling ---
        final_sign = 1'b0;
        if (is_a_nan) begin normal_path_enable=0; enc_is_result_nan=1; if(!mant_a_dec[51]) flag_invalid=1; end
        else if (sign_a_dec == 1'b1 && !is_a_zero) begin normal_path_enable=0; final_exp_biased=11'b11111111111; final_mant={2'b11, 51'b0}; flag_invalid=1; enc_is_result_nan=1; end
        else if (is_a_zero) begin normal_path_enable=0; enc_is_result_zero=1; end
        else if (is_a_infinity) begin normal_path_enable=0; enc_is_result_infinity=1; end

        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            bias = is_double_precision ? 1023 : 127;
            unb_exp_a = (exp_a_dec==0) ? (1-bias) : (exp_a_dec - bias);

            // --- 2a. Prepare Radicand and Exponent ---
            if (unb_exp_a[0]) begin // If exponent is odd
                radicand = {mant_a_dec, 1'b0} << 53; // Use 2*M, scaled up.
                final_unb_exp = (unb_exp_a - 1) / 2;
            end else begin // If exponent is even
                radicand = mant_a_dec << 54; // Use M, scaled up.
                final_unb_exp = unb_exp_a / 2;
            end

            // --- 2b. Behavioral Integer Square Root ---
            rem = radicand;
            bit_shifter = 1'b1 << 106;
            for (int i = 0; i < 54; i = i + 1) begin
                root = root >> 1;
                if (rem >= (root | bit_shifter)) begin
                    rem = rem - (root | bit_shifter);
                    root = root | bit_shifter;
                end
                bit_shifter = bit_shifter >> 2;
            end
            sqrt_int_res = root >> 1;

            // --- 2c. Normalize and Round ---
            temp_mant_norm = sqrt_int_res << 26;
            
            final_mant = temp_mant_norm[53+26 : 26];
            g_bit = temp_mant_norm[25];
            r_bit = temp_mant_norm[24];
            s_bit = |temp_mant_norm[23:0];

            flag_inexact = g_bit | r_bit | s_bit;
            round_up = (rounding_mode == 3'b000 && g_bit && (r_bit || s_bit || final_mant[0])) ||
                       (rounding_mode == 3'b011 && flag_inexact);

            final_mant = final_mant + round_up;
            if(final_mant[53]) begin final_mant >>= 1; final_unb_exp += 1; end

            // --- 2d. Final Pack & Overflow/Underflow Check ---
            max_exp = is_double_precision ? 1023 : 127;
            min_exp = is_double_precision ? -1022 : -126;

            if (final_unb_exp > max_exp) begin flag_overflow=1; flag_inexact=1; enc_is_result_infinity=1; end
            else if (final_unb_exp < min_exp) begin flag_underflow=1; flag_inexact=1; enc_is_result_zero=1; end
            else final_exp_biased = final_unb_exp + bias;
        end
    end
endmodule
