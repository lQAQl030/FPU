module FP_Compare (
    input logic [63:0] operand_a,
    input logic [63:0] operand_b,
    input logic        is_double_precision,
    output logic       flag_lt,
    output logic       flag_eq,
    output logic       flag_gt,
    output logic       flag_unordered,
    output logic       flag_invalid
);
    // Declarations moved to module scope
    logic        sign_a, sign_b;
    logic [10:0] exp_a, exp_b;
    logic [52:0] mant_a, mant_b;
    logic is_zero_a, is_infinity_a, is_nan_a;
    logic is_zero_b, is_infinity_b, is_nan_b;

    logic [7:0]  raw_exp_a_fp32, raw_exp_b_fp32;
    logic [22:0] raw_mant_a_fp32, raw_mant_b_fp32;
    logic [10:0] raw_exp_a_fp64, raw_exp_b_fp64;
    logic [51:0] raw_mant_a_fp64, raw_mant_b_fp64;
    logic implicit_a, implicit_b;

    always_comb begin
        flag_lt = 1'b0; flag_eq = 1'b0; flag_gt = 1'b0;
        flag_unordered = 1'b0; flag_invalid = 1'b0;

        if (is_double_precision) begin
            sign_a = operand_a[63]; raw_exp_a_fp64 = operand_a[62:52]; raw_mant_a_fp64 = operand_a[51:0];
            sign_b = operand_b[63]; raw_exp_b_fp64 = operand_b[62:52]; raw_mant_b_fp64 = operand_b[51:0];
            is_nan_a = (raw_exp_a_fp64 == 11'h7FF) && (raw_mant_a_fp64 != '0);
            is_nan_b = (raw_exp_b_fp64 == 11'h7FF) && (raw_mant_b_fp64 != '0);
            is_zero_a = (raw_exp_a_fp64 == 11'h0) && (raw_mant_a_fp64 == '0);
            is_zero_b = (raw_exp_b_fp64 == 11'h0) && (raw_mant_b_fp64 == '0);
            exp_a = raw_exp_a_fp64; mant_a = {raw_exp_a_fp64 != 0, raw_mant_a_fp64};
            exp_b = raw_exp_b_fp64; mant_b = {raw_exp_b_fp64 != 0, raw_mant_b_fp64};
        end else begin
            sign_a = operand_a[31]; raw_exp_a_fp32 = operand_a[30:23]; raw_mant_a_fp32 = operand_a[22:0];
            sign_b = operand_b[31]; raw_exp_b_fp32 = operand_b[30:23]; raw_mant_b_fp32 = operand_b[22:0];
            is_nan_a = (raw_exp_a_fp32 == 8'hFF) && (raw_mant_a_fp32 != '0);
            is_nan_b = (raw_exp_b_fp32 == 8'hFF) && (raw_mant_b_fp32 != '0);
            is_zero_a = (raw_exp_a_fp32 == 8'h0) && (raw_mant_a_fp32 == '0);
            is_zero_b = (raw_exp_b_fp32 == 8'h0) && (raw_mant_b_fp32 == '0);
            exp_a = {3'b0, raw_exp_a_fp32}; mant_a = {raw_exp_a_fp32 != 0, raw_mant_a_fp32, 29'b0};
            exp_b = {3'b0, raw_exp_b_fp32}; mant_b = {raw_exp_b_fp32 != 0, raw_mant_b_fp32, 29'b0};
        end
        
        if (is_nan_a || is_nan_b) begin
            flag_unordered = 1'b1;
            flag_invalid = 1'b1;
        end
        else if (is_zero_a && is_zero_b) begin flag_eq = 1'b1;
        end
        else if (sign_a != sign_b) begin if (sign_a) flag_lt = 1'b1; else flag_gt = 1'b1;
        end
        else begin // Same sign
            if (exp_a > exp_b) flag_gt = 1'b1;
            else if (exp_a < exp_b) flag_lt = 1'b1;
            else begin // Same exponent, check mantissa
                if (mant_a > mant_b) flag_gt = 1'b1;
                else if (mant_a < mant_b) flag_lt = 1'b1;
                else flag_eq = 1'b1;
            end
            if (sign_a) {flag_lt, flag_gt} = {flag_gt, flag_lt}; // Invert for negative
        end
    end
endmodule
