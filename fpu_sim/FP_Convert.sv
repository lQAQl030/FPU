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
    // --- Type & Constant Definitions ---
    localparam FP_TYPE_FP32 = 2'b00, FP_TYPE_FP64 = 2'b01;
    localparam FP_TYPE_INT32 = 2'b10, FP_TYPE_UINT32 = 2'b11;
    localparam FP32_BIAS = 127, FP64_BIAS = 1023;
    localparam QNAN_MANT = {1'b1, 52'h80000_00000000};
    localparam INT32_MAX_VAL = 64'h000000007FFFFFFF;
    localparam INT32_MIN_VAL = 64'h0000000080000000;
    localparam UINT32_MAX_VAL = 64'h00000000FFFFFFFF;

    // --- Sub-module Connections (Decoded Input) ---
    logic dec_sign;
    logic [10:0] dec_exp_biased;
    logic [52:0] dec_mant;
    logic dec_is_zero, dec_is_infinity, dec_is_nan, dec_is_denormal;

    // --- Final Result Components ---
    logic        final_sign;
    logic [10:0] final_exp_biased;
    logic [52:0] final_mant;
    logic [63:0] int_result;

    // --- Local Variables ---
    logic normal_path_enable;
    logic signed [10:0] unb_exp_in, unb_exp_out;
    logic [31:0] abs_int_in;
    int shift_amt, msb_pos, msb_index, precision;
    logic g_bit, r_bit, s_bit, lsb, round_up;
    logic [53:0] temp_mant;
    logic [63:0] abs_int_extended;
    logic [63:0] shifted_val;
    logic [63:0] frac_mask;
    logic [63:0] frac_part;
    
    // --- Instantiate Decoder and Encoder ---
    FP_Decoder decoder(
        .fp_in(operand_in), .is_double_precision(input_type == FP_TYPE_FP64),
        .sign_out(dec_sign), .exponent_out(dec_exp_biased), .mantissa_out(dec_mant),
        .is_zero(dec_is_zero), .is_infinity(dec_is_infinity), .is_nan(dec_is_nan), .is_denormal(dec_is_denormal)
    );
    logic [63:0] encoder_out;
    FP_Encoder encoder(
        .sign_in(final_sign), .exponent_in(final_exp_biased), .mantissa_in(final_mant),
        .is_double_precision(output_type == FP_TYPE_FP64), .fp_out(encoder_out)
    );

    always_comb begin
        // --- Default assignments ---
        flag_invalid=0; flag_overflow=0; flag_underflow=0; flag_inexact=0;
        final_sign=0; final_exp_biased=0; final_mant=0;
        int_result=0; normal_path_enable=1'b1;
        unb_exp_in=0; unb_exp_out=0; abs_int_in=0;
        shift_amt=0; msb_pos=0; msb_index=0; precision=0; g_bit=0; r_bit=0; s_bit=0; lsb=0; round_up=0;
        temp_mant=0; abs_int_extended=0; shifted_val=0; frac_mask=0; frac_part=0;

        // --- 1. Special Value Handling ---
        if (input_type == FP_TYPE_FP32 || input_type == FP_TYPE_FP64) begin
            if (dec_is_nan || dec_is_infinity) begin
                normal_path_enable = 0; flag_invalid = dec_is_infinity || !(input_type == FP_TYPE_FP64 ? operand_in[51] : operand_in[22]);
                if (output_type == FP_TYPE_INT32) int_result = (dec_is_infinity && dec_sign) ? INT32_MIN_VAL : INT32_MAX_VAL;
                else if (output_type == FP_TYPE_UINT32) int_result = (dec_is_infinity && dec_sign) ? 0 : UINT32_MAX_VAL;
                else if (dec_is_infinity) begin final_sign=dec_sign; final_exp_biased='1; final_mant=0; end
                else begin final_exp_biased='1; final_mant = QNAN_MANT; end
            end else if (dec_is_zero) begin
                normal_path_enable = 0;
                if (output_type == FP_TYPE_INT32 || output_type == FP_TYPE_UINT32) int_result = 0;
                else begin final_sign=dec_sign; final_exp_biased=0; final_mant=0; end
            end
        end else if (operand_in[31:0] == 0) begin
            normal_path_enable = 0; final_sign = (input_type == FP_TYPE_INT32) ? operand_in[31] : 1'b0;
            final_exp_biased=0; final_mant=0;
        end

        // --- 2. Normal Path ---
        if (normal_path_enable) begin
            // --- FP -> FP Conversion (Logic is sound, no change needed) ---
            if ((input_type == FP_TYPE_FP32 || input_type == FP_TYPE_FP64) && (output_type == FP_TYPE_FP32 || output_type == FP_TYPE_FP64)) begin
                final_sign = dec_sign;
                unb_exp_in = (dec_exp_biased == 0) ? (1 - (input_type == FP_TYPE_FP64 ? FP64_BIAS : FP32_BIAS)) : ($signed(dec_exp_biased) - (input_type == FP_TYPE_FP64 ? FP64_BIAS : FP32_BIAS));
                if (input_type == FP_TYPE_FP32 && output_type == FP_TYPE_FP64) begin
                    final_exp_biased = unb_exp_in + FP64_BIAS; final_mant = dec_mant;
                end else begin
                    lsb = dec_mant[29]; g_bit = dec_mant[28];
                    r_bit = dec_mant[27];
                    s_bit = |dec_mant[26:0];
                    flag_inexact = g_bit | r_bit | s_bit;
                    case(rounding_mode)
                        3'b000: round_up = g_bit & (lsb | r_bit | s_bit);
                        default: round_up=0;
                    endcase;
                    temp_mant = {29'b0, {1'b0, dec_mant[52:29]} + {24'b0, round_up}};
                    if (temp_mant[24]) begin
                        unb_exp_in += 1;
                        temp_mant >>= 1;
                    end

                    final_mant = {temp_mant[23:0], 29'b0};
                    final_exp_biased = unb_exp_in + FP32_BIAS;
                end
            end
            // --- FP -> INT Conversion (Logic is sound, no change needed) ---
            else if (input_type == FP_TYPE_FP32 || input_type == FP_TYPE_FP64) begin
                unb_exp_in = $signed(dec_exp_biased) - (input_type == FP_TYPE_FP64 ? FP64_BIAS : FP32_BIAS);
                if (unb_exp_in < 0) begin
                    int_result = 0; 
                    g_bit = dec_mant[52];
                    s_bit = |dec_mant[51:0];
                    flag_inexact = g_bit | s_bit;
                    if (flag_inexact && ((rounding_mode==3'b011 && !dec_sign) || (rounding_mode==3'b010 && dec_sign))) int_result=1;
                end else if (unb_exp_in > 31) begin
                    flag_invalid=1;
                    flag_inexact=1;
                    if (output_type == FP_TYPE_UINT32) begin
                        int_result = dec_sign ? 0 : UINT32_MAX_VAL;
                    end else begin
                        int_result = dec_sign ? INT32_MIN_VAL : INT32_MAX_VAL;
                    end
                end else begin
                    shift_amt = 52 - {21'b0, unb_exp_in};
                    int_result = {11'b0, dec_mant} >> shift_amt;
                    lsb = int_result[0];
                    if (shift_amt > 0) begin
                        shifted_val = {11'b0, dec_mant} << (64 - shift_amt);
                        g_bit = shifted_val[63];
                        r_bit = shifted_val[62];
                        s_bit = |shifted_val[61:0];
                    end
                    flag_inexact = g_bit | r_bit | s_bit;
                    case(rounding_mode)
                        3'b000: round_up = g_bit & (lsb | r_bit | s_bit);
                        default: round_up=0;
                    endcase;
                    int_result += {63'b0, round_up};
                    if (dec_sign) begin
                        if (output_type == FP_TYPE_UINT32) begin
                            flag_invalid=1; int_result=0;
                        end else if (int_result[63:32] != 0 || int_result > 64'h0000000080000000) begin
                            flag_invalid=1; flag_inexact=1; int_result=INT32_MIN_VAL;
                        end else int_result = -int_result;
                    end else begin
                        if (output_type == FP_TYPE_UINT32) begin
                            if (int_result[63:32] != 0) begin
                                flag_invalid=1; flag_inexact=1; int_result=UINT32_MAX_VAL;
                            end
                        end else if (int_result > INT32_MAX_VAL) begin
                            flag_invalid=1; flag_inexact=1; int_result=INT32_MAX_VAL;
                        end
                    end
                end
            end
            // --- INT -> FP Conversion (REWRITTEN) ---
            else begin
                precision = (output_type == FP_TYPE_FP64) ? 53 : 24;
                final_sign = (input_type == FP_TYPE_INT32) && operand_in[31];
                abs_int_in = final_sign ? -operand_in[31:0] : operand_in[31:0];
                msb_pos = $clog2(abs_int_in);
                msb_index = msb_pos - 1;
                unb_exp_out = msb_index[10:0];
                abs_int_extended = {32'b0, abs_int_in};
                if (msb_pos > precision) begin // Inexact conversion, needs rounding
                    shift_amt = msb_pos - precision;
                    shifted_val = abs_int_extended << (64 - shift_amt);
                    g_bit = shifted_val[63]; r_bit = shifted_val[62]; s_bit = |shifted_val[61:0];

                    abs_int_extended >>= shift_amt;
                    temp_mant = abs_int_extended[53:0];
                    lsb = temp_mant[0];
                    flag_inexact = g_bit | r_bit | s_bit;
                    case(rounding_mode)
                        3'b000: round_up = g_bit & (lsb | r_bit | s_bit);
                        default: round_up = 0;
                    endcase
                    temp_mant += {53'b0, round_up};
                    if(temp_mant[precision]) begin
                        unb_exp_out+=1; temp_mant>>=1;
                    end
                    frac_mask = (1 << (precision - 1)) - 1;
                    frac_part = {10'b0, temp_mant} & frac_mask;
                    frac_part <<= (52 - (precision - 1));
                    final_mant = frac_part[52:0];
                end else begin // Exact conversion
                    frac_mask = (1 << (msb_pos - 1)) - 1;
                    frac_part = {32'b0, abs_int_in} & frac_mask;
                    shift_amt = 52 - (msb_pos - 1);
                    frac_part <<= shift_amt;
                    final_mant = frac_part[52:0];
                end
                final_exp_biased = unb_exp_out + ((output_type == FP_TYPE_FP64) ? FP64_BIAS : FP32_BIAS);
            end
        end
    end

    always_comb begin
        // --- 3. Final Result Muxing ---
        if (output_type == FP_TYPE_FP32 || output_type == FP_TYPE_FP64) result = encoder_out;
        else result = int_result;
    end
endmodule
