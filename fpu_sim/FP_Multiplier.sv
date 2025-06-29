module FP_Multiplier (
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

    // --- Local variables declared at module scope ---
    logic normal_path_enable;
    logic [52:0] norm_mant_a, norm_mant_b;
    logic signed [11:0] unb_exp_a, unb_exp_b, sum_unb_exp, final_unb_exp;
    logic [105:0] product_mant;
    logic g_bit, r_bit, s_bit, round_up;
    int bias, max_exp, min_exp, lz;
    logic [52:0] result_mant_unrounded;

    // --- Instantiate Sub-modules (Explicit Connections) ---
    FP_Decoder decoder_a (
        .fp_in(operand_a),
        .is_double_precision(is_double_precision),
        .sign_out(sign_a_dec),
        .exponent_out(exp_a_dec),
        .mantissa_out(mant_a_dec),
        .is_zero(is_a_zero),
        .is_infinity(is_a_infinity),
        .is_nan(is_a_nan),
        .is_denormal(is_a_denormal)
    );
    FP_Decoder decoder_b (
        .fp_in(operand_b),
        .is_double_precision(is_double_precision),
        .sign_out(sign_b_dec),
        .exponent_out(exp_b_dec),
        .mantissa_out(mant_b_dec),
        .is_zero(is_b_zero),
        .is_infinity(is_b_infinity),
        .is_nan(is_b_nan),
        .is_denormal(is_b_denormal)
    );
    FP_Encoder encoder (
        .sign_in(final_sign),
        .exponent_in(final_exp_biased),
        .mantissa_in(final_mant),
        .is_double_precision(is_double_precision),
        .fp_out(result)
    );

    always_comb begin
        // --- Default assignments to prevent latches ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        enc_is_result_zero=0; enc_is_result_infinity=0; enc_is_result_nan=0; enc_is_result_denormal=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        normal_path_enable=1;
        norm_mant_a=0; norm_mant_b=0; unb_exp_a=0; unb_exp_b=0; sum_unb_exp=0;
        product_mant=0; final_unb_exp=0; g_bit=0; r_bit=0; s_bit=0; round_up=0;
        bias=0; max_exp=0; min_exp=0; lz=0; result_mant_unrounded=0;

        // --- 1. Special Value Handling ---
        final_sign = sign_a_dec ^ sign_b_dec;
        if (is_a_nan || is_b_nan) begin normal_path_enable=0; enc_is_result_nan=1; if((is_a_nan&&!mant_a_dec[51])||(is_b_nan&&!mant_b_dec[51])) flag_invalid=1; end
        else if ((is_a_zero&&is_b_infinity)||(is_a_infinity&&is_b_zero)) begin normal_path_enable=0; enc_is_result_nan=1; flag_invalid=1; end
        else if (is_a_zero || is_b_zero) begin normal_path_enable=0; enc_is_result_zero=1; end
        else if (is_a_infinity || is_b_infinity) begin normal_path_enable=0; enc_is_result_infinity=1; end
        
        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            bias = is_double_precision ? 1023 : 127;

            // --- 2a. Handle Denormals ---
            norm_mant_a = mant_a_dec;
            unb_exp_a = (exp_a_dec==0) ? 12'($signed(1-bias)) : 12'($signed(exp_a_dec) - bias);
            if (is_a_denormal) begin
                lz = $clog2(mant_a_dec);
                norm_mant_a = mant_a_dec << (53 - lz);
                unb_exp_a = unb_exp_a - 12'($signed(52 - (lz-1)));
            end
            
            norm_mant_b = mant_b_dec;
            unb_exp_b = (exp_b_dec==0) ? 12'($signed(1-bias)) : 12'($signed(exp_b_dec) - bias);
            if (is_b_denormal) begin
                lz = $clog2(mant_b_dec);
                norm_mant_b = mant_b_dec << (53 - lz);
                unb_exp_b = unb_exp_b - 12'($signed(52 - (lz-1)));
            end
            
            // --- 2b. Calculation ---
            sum_unb_exp = unb_exp_a + unb_exp_b;
            product_mant = norm_mant_a * norm_mant_b;

            // --- 2c. Normalization ---
            if (product_mant[105]) begin final_unb_exp = sum_unb_exp + 1; product_mant >>= 1; end
            else begin final_unb_exp = sum_unb_exp; end
            
            // --- 2d. Rounding ---
            if (is_double_precision) begin
                // FIX: Assign to the module-scope variable, don't re-declare it.
                result_mant_unrounded = product_mant[104:52];
                g_bit = product_mant[51];
                r_bit = product_mant[50];
                s_bit = |product_mant[49:0];
            end else begin
                result_mant_unrounded = {product_mant[104:82], 29'b0};
                g_bit = product_mant[81];
                r_bit = product_mant[80];
                s_bit = |product_mant[79:0];
            end
            
            flag_inexact = g_bit | r_bit | s_bit;
            round_up = (rounding_mode == 3'b000 && g_bit && (r_bit || s_bit || result_mant_unrounded[is_double_precision?0:29])) ||
                       (rounding_mode == 3'b011 && flag_inexact && !final_sign) ||
                       (rounding_mode == 3'b010 && flag_inexact && final_sign);

            final_mant = result_mant_unrounded + (round_up ? (is_double_precision ? 1 : (1<<29)) : 0);

            if (final_mant[53]) begin final_mant >>= 1; final_unb_exp += 1; end

            // --- 2e. Final Pack & Overflow/Underflow check ---
            max_exp = is_double_precision ? 1023 : 127;
            min_exp = is_double_precision ? -1022 : -126;
            if (final_unb_exp > max_exp) begin flag_overflow=1; flag_inexact=1; enc_is_result_infinity=1; end
            else if (final_unb_exp < min_exp) begin flag_underflow=1; flag_inexact=1; enc_is_result_zero=1; end
            else final_exp_biased = final_unb_exp + bias;
        end
    end
endmodule
