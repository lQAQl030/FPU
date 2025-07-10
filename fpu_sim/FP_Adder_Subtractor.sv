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
    logic [10:0] exp_a_dec, exp_b_dec;
    logic [52:0] mant_a_dec, mant_b_dec;
    logic is_a_zero, is_a_infinity, is_a_nan, is_a_denormal;
    logic is_b_zero, is_b_infinity, is_b_nan, is_b_denormal;
    
    // --- Final Result Components ---
    logic        final_sign;
    logic [10:0] final_exp_biased;
    logic [52:0] final_mant;

    // --- Local variables (All declared at module scope) ---
    logic normal_path_enable;
    logic eff_sign_b, eff_sub;
    logic signed [11:0] exp_unbiased_a, exp_unbiased_b, final_unb_exp;
    logic [52:0] mant_a_norm, mant_b_norm;
    int exp_diff;
    logic [55:0] mant_larger, mant_smaller, temp_smaller;
    logic [56:0] mant_sum;
    int norm_shift_amt;
    logic [53:0] mant_rounded;
    logic [23:0] sp_mant_rounded;
    logic lsb, g_bit, r_bit, s_bit, round_up;
    int bias, max_unb_exp, min_unb_exp;
    logic [53:0] denorm_temp, shifted_denorm_g;

    // --- Instantiate Sub-modules ---
    FP_Decoder decoder_a ( .fp_in(operand_a), .is_double_precision(is_double_precision), .sign_out(sign_a_dec), .exponent_out(exp_a_dec), .mantissa_out(mant_a_dec), .is_zero(is_a_zero), .is_infinity(is_a_infinity), .is_nan(is_a_nan), .is_denormal(is_a_denormal) );
    FP_Decoder decoder_b ( .fp_in(operand_b), .is_double_precision(is_double_precision), .sign_out(sign_b_dec), .exponent_out(exp_b_dec), .mantissa_out(mant_b_dec), .is_zero(is_b_zero), .is_infinity(is_b_infinity), .is_nan(is_b_nan), .is_denormal(is_b_denormal) );
    FP_Encoder encoder ( .sign_in(final_sign), .exponent_in(final_exp_biased), .mantissa_in(final_mant), .is_double_precision(is_double_precision), .fp_out(result) );
    
    function automatic integer count_leading_zeros_52(input [52:0] val);
        for (int i = 52; i >= 0; i--) if (val[i]) return 52 - i; return 53;
    endfunction
    function automatic integer count_leading_zeros_56(input [56:0] val);
        for (int i = 56; i >= 0; i--) if (val[i]) return 56 - i; return 57;
    endfunction

    always_comb begin
        // --- Defaults ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        normal_path_enable = 1'b1;
        temp_smaller=0; denorm_temp=0; shifted_denorm_g=0;

        // --- 1. Special Value Handling ---
        eff_sign_b = sign_b_dec ^ is_subtraction;
        if (is_a_nan || is_b_nan) begin
            normal_path_enable=0; flag_invalid=1; final_exp_biased='1; final_mant={1'b1, 52'h80000_00000000};
        end else if (is_a_infinity) begin
            normal_path_enable=0; if (is_b_infinity && sign_a_dec != eff_sign_b) begin flag_invalid=1; final_exp_biased='1; final_mant={1'b1, 52'h80000_00000000}; end else begin final_sign=sign_a_dec; final_exp_biased='1; final_mant=0; end
        end else if (is_b_infinity) begin
            normal_path_enable=0; final_sign=eff_sign_b; final_exp_biased='1; final_mant=0;
        end else if (is_a_zero) begin
            normal_path_enable=0; result = is_subtraction ? {~operand_b[63], operand_b[62:0]} : operand_b;
        end else if (is_b_zero) begin
            normal_path_enable=0; result = operand_a;
        end

        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            bias = is_double_precision ? 1023 : 127;
            
            norm_shift_amt = is_a_denormal ? count_leading_zeros_52(mant_a_dec) : 0;
            mant_a_norm = mant_a_dec << norm_shift_amt;
            exp_unbiased_a = is_a_denormal ? (1 - bias - norm_shift_amt) : ($signed(exp_a_dec) - bias);

            norm_shift_amt = is_b_denormal ? count_leading_zeros_52(mant_b_dec) : 0;
            mant_b_norm = mant_b_dec << norm_shift_amt;
            exp_unbiased_b = is_b_denormal ? (1 - bias - norm_shift_amt) : ($signed(exp_b_dec) - bias);

            if ((exp_unbiased_a > exp_unbiased_b) || ((exp_unbiased_a == exp_unbiased_b) && (mant_a_norm >= mant_b_norm))) begin
                final_unb_exp = exp_unbiased_a; final_sign = sign_a_dec;
                mant_larger = {mant_a_norm, 3'b0}; exp_diff = exp_unbiased_a - exp_unbiased_b;
                temp_smaller = {mant_b_norm, 3'b0};
                s_bit = (exp_diff > 56) ? |temp_smaller : |(temp_smaller & ((64'd1 << exp_diff) - 1));
                mant_smaller = (temp_smaller >> exp_diff) | s_bit;
            end else begin
                final_unb_exp = exp_unbiased_b; final_sign = eff_sign_b;
                mant_larger = {mant_b_norm, 3'b0}; exp_diff = exp_unbiased_b - exp_unbiased_a;
                temp_smaller = {mant_a_norm, 3'b0};
                s_bit = (exp_diff > 56) ? |temp_smaller : |(temp_smaller & ((64'd1 << exp_diff) - 1));
                mant_smaller = (temp_smaller >> exp_diff) | s_bit;
            end

            eff_sub = (sign_a_dec != eff_sign_b);
            if (eff_sub) mant_sum = mant_larger - mant_smaller; else mant_sum = mant_larger + mant_smaller;

            if (mant_sum == 0) begin final_sign = (rounding_mode==3'b010) & sign_a_dec & eff_sign_b; final_exp_biased='0; final_mant='0; normal_path_enable=0; end
            
            if (normal_path_enable) begin
                if (mant_sum[56]) begin // Addition overflow
                    mant_sum >>= 1; final_unb_exp += 1;
                end else if (!mant_sum[55]) begin // Subtraction cancellation or normal add
                    norm_shift_amt = count_leading_zeros_56(mant_sum) - 1;
                    mant_sum <<= norm_shift_amt; final_unb_exp -= norm_shift_amt;
                end
                
                if (is_double_precision) begin
                    lsb = mant_sum[3]; g_bit = mant_sum[2]; r_bit = mant_sum[1]; s_bit = mant_sum[0];
                    flag_inexact = g_bit | r_bit | s_bit;
                    case (rounding_mode)
                        3'b000: round_up = g_bit & (lsb | r_bit | s_bit); 3'b001: round_up = 1'b0;
                        3'b010: round_up = flag_inexact & final_sign; 3'b011: round_up = flag_inexact & ~final_sign;
                        default: round_up = 1'b0;
                    endcase
                    mant_rounded = mant_sum[55:3] + round_up;
                    if (mant_rounded[53]) begin mant_rounded >>= 1; final_unb_exp += 1; end
                    final_mant = mant_rounded;
                end else begin
                    lsb = mant_sum[32]; g_bit = mant_sum[31]; r_bit = mant_sum[30]; s_bit = |mant_sum[29:0];
                    flag_inexact = g_bit | r_bit | s_bit;
                    case (rounding_mode)
                        3'b000: round_up = g_bit & (lsb | r_bit | s_bit); 3'b001: round_up = 1'b0;
                        3'b010: round_up = flag_inexact & final_sign; 3'b011: round_up = flag_inexact & ~final_sign;
                        default: round_up = 1'b0;
                    endcase
                    sp_mant_rounded = mant_sum[55:32] + round_up;
                    if (sp_mant_rounded[24]) begin sp_mant_rounded >>= 1; final_unb_exp += 1; end
                    final_mant = {sp_mant_rounded, 29'b0};
                end

                max_unb_exp = is_double_precision ? 1023 : 127; min_unb_exp = is_double_precision ? -1022 : -126;
                if (final_unb_exp > max_unb_exp) begin
                    flag_overflow=1; flag_inexact=1; final_exp_biased='1; final_mant=0;
                end else if (final_unb_exp+bias < min_unb_exp) begin
                    norm_shift_amt = min_unb_exp - final_unb_exp;
                    denorm_temp = {1'b1, final_mant[52:1]};
                    if (norm_shift_amt < 54) begin
                        s_bit = |(denorm_temp & ((64'd1 << (norm_shift_amt - 1)) - 1));
                        shifted_denorm_g = denorm_temp >> (norm_shift_amt - 1);
                        g_bit = shifted_denorm_g[0]; lsb = shifted_denorm_g[1];
                        flag_inexact = g_bit | s_bit;
                        if (flag_inexact) flag_underflow=1;
                        case(rounding_mode) 3'b000: round_up = g_bit & (lsb | s_bit); default: round_up=0; endcase
                        final_mant = (denorm_temp >> norm_shift_amt) + round_up;
                    end else begin final_mant = 0; flag_inexact=1; flag_underflow=1; end
                    final_exp_biased = 0;
                end else final_exp_biased = final_unb_exp + bias;
            end
        end
    end
endmodule
