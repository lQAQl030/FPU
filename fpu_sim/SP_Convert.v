module SP_Convert (
    input [31:0]    operand_in,
    input [1:0]     input_type,
    input [1:0]     output_type,
    input [2:0]     rounding_mode,
    output reg [63:0]   result,
    output reg      flag_invalid,
    output reg      flag_overflow,
    output reg      flag_underflow,
    output reg      flag_inexact
);
    // --- Type & Constant Definitions ---
    localparam FP_TYPE_FP32 = 2'b00, FP_TYPE_FP64 = 2'b01;
    localparam FP_TYPE_INT32 = 2'b10, FP_TYPE_UINT32 = 2'b11;
    localparam FP64_QNAN_MANT = {1'b1, 52'h80000_00000000};
    localparam INT32_MAX_VAL = 64'h000000007FFFFFFF;
    localparam INT32_MIN_VAL = 64'h0000000080000000;
    localparam UINT32_MAX_VAL = 64'h00000000FFFFFFFF;
    localparam UINT32_MIN_VAL = 64'h0000000000000000;

    // operand a
    reg sign_a_dec;
    reg [7:0] exp_a_dec;
    reg [23:0] mant_a_dec;
    reg is_a_zero, is_a_infinity, is_a_nan, is_a_denormal;

    // result
    reg final_sign;
    reg [10:0] final_exp;
    reg [52:0] final_mant;

    reg [63:0] result_dp;
    reg [63:0] result_int;
    
    // Decode / Encode
    SP_Decoder decoder_a ( .fp_in(operand_in), .sign_out(sign_a_dec), .exponent_out(exp_a_dec), .mantissa_out(mant_a_dec), .is_zero(is_a_zero), .is_infinity(is_a_infinity), .is_nan(is_a_nan), .is_denormal(is_a_denormal) );
    DP_Encoder encoder ( .sign_in(final_sign), .exponent_in(final_exp), .mantissa_in(final_mant), .fp_out(result_dp) );

    reg normal_path_enable;

    always @(*) begin

        // init
        flag_invalid = 0; flag_overflow = 0; flag_underflow = 0; flag_inexact = 0;
        normal_path_enable = 1;

        final_sign=0; final_exp='0; final_mant='0;
        result_int = '0;

        // --- 1. Special Value Handling ---
        if (input_type == FP_TYPE_FP32) begin
            if (is_a_nan) begin

                normal_path_enable = 0;
                flag_invalid = 1; // NV
                if (output_type == FP_TYPE_INT32) begin result_int = INT32_MIN_VAL; end // int32
                else if (output_type == FP_TYPE_UINT32) begin result_int = UINT32_MAX_VAL; end // uint32
                else begin final_sign = 0; final_exp = '1; final_mant = FP64_QNAN_MANT; end // double (NaN)

            end else if (is_a_infinity) begin

                normal_path_enable = 0;
                if (output_type == FP_TYPE_INT32) begin flag_invalid = 1; flag_overflow = 1; result_int = (sign_a_dec) ? INT32_MIN_VAL : INT32_MAX_VAL; end // int32 (NV, OF)
                else if (output_type == FP_TYPE_UINT32) begin flag_invalid = 1; flag_overflow = !sign_a_dec; result_int = (sign_a_dec) ? UINT32_MIN_VAL : UINT32_MAX_VAL; end // uint32 (NV, OF(+))
                else begin final_sign = sign_a_dec; final_exp = '1; final_mant = '0; end // double (inf)

            end else if (is_a_zero) begin

                normal_path_enable = 0;
                if (output_type == FP_TYPE_INT32 || output_type == FP_TYPE_UINT32) begin result_int = '0; end // 0
                else begin final_sign = sign_a_dec; final_exp = '0; final_mant = '0; end // 0

            end

        end else if (operand_in[31:0] == 0) begin

            normal_path_enable = 0;
            final_sign = 0; final_exp = '0; final_mant = '0; // 0

        end

        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            // --- FP -> FP Conversion ---
            if ((input_type == FP_TYPE_FP32) && (output_type == FP_TYPE_FP64)) begin
                final_sign = sign_a_dec; final_exp = {3'b0, exp_a_dec} + 11'd896; final_mant = {mant_a_dec, 29'b0};
                if (exp_a_dec == 11'b0) begin
                    final_exp += 11'd1;
                    for (int i = 52; i >= 29; i--) begin
                        if (!final_mant[52]) begin
                            final_mant <<= 1; final_exp -= 1;
                        end else begin
                            i = 0;
                        end
                    end
                end
                
            end
            // // --- FP -> INT Conversion (Logic is sound, no change needed) ---
            // else if (input_type == FP_TYPE_FP32 || input_type == FP_TYPE_FP64) begin
            //     unb_exp_in = $signed(dec_exp_biased) - (input_type == FP_TYPE_FP64 ? FP64_BIAS : FP32_BIAS);
            //     if (unb_exp_in < 0) begin
            //         int_result = 0; 
            //         g_bit = dec_mant[52];
            //         s_bit = |dec_mant[51:0];
            //         flag_inexact = g_bit | s_bit;
            //         if (flag_inexact && ((rounding_mode==3'b011 && !dec_sign) || (rounding_mode==3'b010 && dec_sign))) int_result=1;
            //     end else if (unb_exp_in > 31) begin
            //         flag_invalid=1;
            //         flag_inexact=1;
            //         if (output_type == FP_TYPE_UINT32) begin
            //             int_result = dec_sign ? 0 : UINT32_MAX_VAL;
            //         end else begin
            //             int_result = dec_sign ? INT32_MIN_VAL : INT32_MAX_VAL;
            //         end
            //     end else begin
            //         shift_amt = 52 - {21'b0, unb_exp_in};
            //         int_result = {11'b0, dec_mant} >> shift_amt;
            //         lsb = int_result[0];
            //         if (shift_amt > 0) begin
            //             shifted_val = {11'b0, dec_mant} << (64 - shift_amt);
            //             g_bit = shifted_val[63];
            //             r_bit = shifted_val[62];
            //             s_bit = |shifted_val[61:0];
            //         end
            //         flag_inexact = g_bit | r_bit | s_bit;
            //         case(rounding_mode)
            //             3'b000: round_up = g_bit & (lsb | r_bit | s_bit);
            //             default: round_up=0;
            //         endcase;
            //         int_result += {63'b0, round_up};
            //         if (dec_sign) begin
            //             if (output_type == FP_TYPE_UINT32) begin
            //                 flag_invalid=1; int_result=0;
            //             end else if (int_result[63:32] != 0 || int_result > 64'h0000000080000000) begin
            //                 flag_invalid=1; flag_inexact=1; int_result=INT32_MIN_VAL;
            //             end else int_result = -int_result;
            //         end else begin
            //             if (output_type == FP_TYPE_UINT32) begin
            //                 if (int_result[63:32] != 0) begin
            //                     flag_invalid=1; flag_inexact=1; int_result=UINT32_MAX_VAL;
            //                 end
            //             end else if (int_result > INT32_MAX_VAL) begin
            //                 flag_invalid=1; flag_inexact=1; int_result=INT32_MAX_VAL;
            //             end
            //         end
            //     end
            // end
            // // --- INT -> FP Conversion (REWRITTEN) ---
            // else begin
            //     precision = (output_type == FP_TYPE_FP64) ? 53 : 24;
            //     final_sign = (input_type == FP_TYPE_INT32) && operand_in[31];
            //     abs_int_in = final_sign ? -operand_in[31:0] : operand_in[31:0];
            //     msb_pos = $clog2(abs_int_in);
            //     msb_index = msb_pos - 1;
            //     unb_exp_out = msb_index[10:0];
            //     abs_int_extended = {32'b0, abs_int_in};
            //     if (msb_pos > precision) begin // Inexact conversion, needs rounding
            //         shift_amt = msb_pos - precision;
            //         shifted_val = abs_int_extended << (64 - shift_amt);
            //         g_bit = shifted_val[63]; r_bit = shifted_val[62]; s_bit = |shifted_val[61:0];

            //         abs_int_extended >>= shift_amt;
            //         temp_mant = abs_int_extended[53:0];
            //         lsb = temp_mant[0];
            //         flag_inexact = g_bit | r_bit | s_bit;
            //         case(rounding_mode)
            //             3'b000: round_up = g_bit & (lsb | r_bit | s_bit);
            //             default: round_up = 0;
            //         endcase
            //         temp_mant += {53'b0, round_up};
            //         if(temp_mant[precision]) begin
            //             unb_exp_out+=1; temp_mant>>=1;
            //         end
            //         frac_mask = (1 << (precision - 1)) - 1;
            //         frac_part = {10'b0, temp_mant} & frac_mask;
            //         frac_part <<= (52 - (precision - 1));
            //         final_mant = frac_part[52:0];
            //     end else begin // Exact conversion
            //         frac_mask = (1 << (msb_pos - 1)) - 1;
            //         frac_part = {32'b0, abs_int_in} & frac_mask;
            //         shift_amt = 52 - (msb_pos - 1);
            //         frac_part <<= shift_amt;
            //         final_mant = frac_part[52:0];
            //     end
            //     final_exp_biased = unb_exp_out + ((output_type == FP_TYPE_FP64) ? FP64_BIAS : FP32_BIAS);
            // end
        end
    end

    always @(*) begin
        // --- 3. Final Result Muxing ---
        result = (output_type == FP_TYPE_FP64) ? result_dp : result_int;
    end
endmodule
