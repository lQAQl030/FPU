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
    // --- Decoded Inputs ---
    logic sign_a, sign_b;
    logic [10:0] exp_a, exp_b;
    logic [52:0] mant_a, mant_b; // Includes implicit bit
    logic is_zero_a, is_infinity_a, is_nan_a, is_denormal_a, is_snan_a;
    logic is_zero_b, is_infinity_b, is_nan_b, is_denormal_b, is_snan_b;

    // --- Instantiate Decoders ---
    FP_Decoder decoder_a (
        .fp_in(operand_a), .is_double_precision(is_double_precision),
        .sign_out(sign_a), .exponent_out(exp_a), .mantissa_out(mant_a),
        .is_zero(is_zero_a), .is_infinity(is_infinity_a), .is_nan(is_nan_a), .is_denormal(is_denormal_a)
    );
    FP_Decoder decoder_b (
        .fp_in(operand_b), .is_double_precision(is_double_precision),
        .sign_out(sign_b), .exponent_out(exp_b), .mantissa_out(mant_b),
        .is_zero(is_zero_b), .is_infinity(is_infinity_b), .is_nan(is_nan_b), .is_denormal(is_denormal_b)
    );
    
    // --- SNaN Detection ---
    // An SNaN is a NaN with the MSB of the *original* mantissa field being 0.
    // This is bit 51 for DP and bit 22 for SP.
    logic is_snan_a_raw, is_snan_b_raw;
    assign is_snan_a_raw = is_nan_a && !(is_double_precision ? operand_a[51] : operand_a[22]);
    assign is_snan_b_raw = is_nan_b && !(is_double_precision ? operand_b[51] : operand_b[22]);
    
    // --- Intermediate Comparison Flags ---
    logic temp_gt, temp_lt, temp_eq;

    always_comb begin
        // --- Default assignments ---
        flag_lt = 0; 
        flag_eq = 0; 
        flag_gt = 0;
        flag_unordered = 0;
        temp_gt = 0;
        temp_lt = 0;
        temp_eq = 0;
        
        // Invalid flag is set for signaling NaNs in comparison
        flag_invalid = is_snan_a_raw || is_snan_b_raw;

        // --- Comparison Logic ---
        
        // Path 1: At least one operand is NaN
        if (is_nan_a || is_nan_b) begin
            flag_unordered = 1'b1;
        end
        // Path 2: Both operands are Zero (+0 or -0)
        else if (is_zero_a && is_zero_b) begin
            // Per IEEE 754, +0 and -0 are equal in comparisons
            flag_eq = 1'b1;
        end
        // Path 3: Operands have different signs (and are not both zero)
        else if (sign_a != sign_b) begin
            if (sign_a) begin // A is negative, B is positive
                flag_lt = 1'b1; 
            end else begin // A is positive, B is negative
                flag_gt = 1'b1;
            end
        end
        // Path 4: Operands have the same sign (and are not NaN or Zero)
        else begin 
            // Compare as if they were unsigned integers (sign bit is the same)
            // The decoded format (exp, mant) allows for direct magnitude comparison.
            temp_gt = ({exp_a, mant_a} > {exp_b, mant_b});
            temp_lt = ({exp_a, mant_a} < {exp_b, mant_b});
            temp_eq = ({exp_a, mant_a} == {exp_b, mant_b});

            // If both numbers are negative, the sense of the comparison is inverted.
            // A larger magnitude negative number is "less than".
            if (sign_a) begin
                flag_lt = temp_gt;
                flag_gt = temp_lt;
                flag_eq = temp_eq;
            end else begin
                flag_lt = temp_lt;
                flag_gt = temp_gt;
                flag_eq = temp_eq;
            end
        end
    end
endmodule
