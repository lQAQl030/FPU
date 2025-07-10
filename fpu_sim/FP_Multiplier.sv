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

    // --- Local variables ---
    logic normal_path_enable;
    logic [52:0] norm_mant_a, norm_mant_b;
    logic signed [11:0] unb_exp_a, unb_exp_b, sum_unb_exp, final_unb_exp;
    logic [105:0] product_mant_raw;
    logic [105:0] product_mant_normalized;
    logic [53:0] result_mant_unrounded_ext;
    logic [53:0] result_mant_rounded_ext;
    logic lsb, g_bit, r_bit, s_bit, round_up;
    int bias, max_unb_exp, min_unb_exp, denorm_shift_amt, denorm_shift_limit;
    int shift_amt_a, shift_amt_b;
    logic [53:0] shifted_val; // For gradual underflow calculation

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

    function automatic integer count_leading_zeros(input [52:0] man);
        for (int i = 51; i >= 0; i--) if (man[i]) return 51 - i; return 52;
    endfunction

    always_comb begin
        // --- Default assignments ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        normal_path_enable=1;
        norm_mant_a=0; norm_mant_b=0; unb_exp_a=0; unb_exp_b=0; sum_unb_exp=0;
        product_mant_raw=0; product_mant_normalized=0; final_unb_exp=0; 
        lsb=0; g_bit=0; r_bit=0; s_bit=0; round_up=0;
        bias=0; max_unb_exp=0; min_unb_exp=0; denorm_shift_amt=0;
        result_mant_unrounded_ext=0; result_mant_rounded_ext=0;
        shift_amt_a=0; shift_amt_b=0; shifted_val=0;

        // --- 1. Special Value Handling ---
        final_sign = sign_a_dec ^ sign_b_dec;
        if (is_a_nan || is_b_nan) begin 
            normal_path_enable=0; final_exp_biased = '1; final_mant = {1'b1, 52'h80000_00000000};
            if ((is_a_nan && !operand_a[is_double_precision ? 51 : 22]) || (is_b_nan && !operand_b[is_double_precision ? 51 : 22])) flag_invalid=1;
        end else if ((is_a_zero && is_b_infinity)||(is_a_infinity && is_b_zero)) begin 
            normal_path_enable=0; flag_invalid=1; final_exp_biased = '1; final_mant = {1'b1, 52'h80000_00000000};
        end else if (is_a_zero || is_b_zero) begin 
            normal_path_enable=0;
        end else if (is_a_infinity || is_b_infinity) begin 
            normal_path_enable=0; final_exp_biased = '1; final_mant = 0;
        end
        
        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            bias = is_double_precision ? 1023 : 127;

            // --- 2a. Handle Denormals ---
            unb_exp_a = is_a_denormal ? (1-bias) : $signed(exp_a_dec) - bias;
            if (is_a_denormal) begin shift_amt_a = count_leading_zeros(mant_a_dec) + 1; norm_mant_a = mant_a_dec << shift_amt_a; unb_exp_a = unb_exp_a - shift_amt_a; end 
            else norm_mant_a = mant_a_dec;
            unb_exp_b = is_b_denormal ? (1-bias) : $signed(exp_b_dec) - bias;
            if (is_b_denormal) begin shift_amt_b = count_leading_zeros(mant_b_dec) + 1; norm_mant_b = mant_b_dec << shift_amt_b; unb_exp_b = unb_exp_b - shift_amt_b; end 
            else norm_mant_b = mant_b_dec;
            
            // --- 2b. Calculation & 2c. Normalization ---
            sum_unb_exp = unb_exp_a + unb_exp_b;
            product_mant_raw = norm_mant_a * norm_mant_b;
            if (product_mant_raw[105]) begin final_unb_exp = sum_unb_exp + 1; product_mant_normalized = product_mant_raw >> 1; end 
            else begin final_unb_exp = sum_unb_exp; product_mant_normalized = product_mant_raw; end
            
            // --- 2d. Rounding ---
            result_mant_unrounded_ext = product_mant_normalized[104:51];
            lsb = result_mant_unrounded_ext[1]; g_bit = result_mant_unrounded_ext[0];
            r_bit = product_mant_normalized[50]; s_bit = |product_mant_normalized[49:0];
            flag_inexact = g_bit | r_bit | s_bit;
            case (rounding_mode) 3'b000: round_up = g_bit & (r_bit | s_bit | lsb); default: round_up = 0; endcase
            result_mant_rounded_ext = result_mant_unrounded_ext[53:1] + round_up;

            // --- 2e. Post-Rounding Normalization ---
            if (result_mant_rounded_ext[53]) begin final_mant = result_mant_rounded_ext >> 1; final_unb_exp += 1; end 
            else begin final_mant = result_mant_rounded_ext; end
            
            // --- 2f. Final Pack & Overflow/Underflow check (REVISED) ---
            max_unb_exp = is_double_precision ? 1023 : 127;
            min_unb_exp = is_double_precision ? -1022 : -126;
            denorm_shift_limit = is_double_precision ? 54 : 24;

            if (final_unb_exp > max_unb_exp) begin 
                flag_overflow=1; flag_inexact=1; final_exp_biased = '1; final_mant = 0;
            end else if (final_unb_exp < min_unb_exp) begin
                flag_underflow = 1'b1;
                denorm_shift_amt = min_unb_exp - final_unb_exp;
                if (denorm_shift_amt < denorm_shift_limit) begin
                    // ** FIX: Use temp var for shift, then select bits **
                    shifted_val = final_mant >> (denorm_shift_amt - 1);
                    lsb = shifted_val[1];
                    g_bit = shifted_val[0];
                    if (denorm_shift_amt > 1) begin
                        shifted_val = final_mant >> (denorm_shift_amt - 2);
                        r_bit = shifted_val[0];
                    end else r_bit = 0;
                    if (denorm_shift_amt > 2) s_bit = |(final_mant & ((1 << (denorm_shift_amt-2))-1));
                    else s_bit = 0;
                    
                    flag_inexact = flag_inexact | g_bit | r_bit | s_bit;
                    case (rounding_mode) 3'b000: round_up = g_bit & (r_bit | s_bit | lsb); default: round_up = 0; endcase
                    final_mant = (final_mant >> denorm_shift_amt) + round_up;
                end else begin
                    final_mant = 0; flag_inexact = 1'b1;
                end
                final_exp_biased = 0;
            end else begin
                final_exp_biased = final_unb_exp + bias;
            end
        end
    end
endmodule
