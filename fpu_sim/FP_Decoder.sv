module FP_Decoder (
    input  logic [63:0] fp_in,
    input  logic        is_double_precision,

    output logic        sign_out,
    // Note: This outputs the raw, BIASED exponent.
    output logic [10:0] exponent_out,
    // Note: This is always a 53-bit value with an explicit leading bit (1.F or 0.F).
    output logic [52:0] mantissa_out,

    // Flags for identifying the number type
    output logic is_zero,
    output logic is_infinity,
    output logic is_nan,
    output logic is_denormal
);

    // --- Internal Signals for raw components ---
    logic [10:0] raw_exponent;
    logic [51:0] raw_mantissa;
    logic        is_exp_max;
    logic        is_exp_zero;
    logic        is_mant_zero;
    logic        implicit_bit;

    always_comb begin
        // --- 1. Extract Raw Components based on precision ---
        if (is_double_precision) begin
            sign_out     = fp_in[63];
            raw_exponent = fp_in[62:52];
            raw_mantissa = fp_in[51:0];
            is_exp_max   = (raw_exponent == 11'h7FF);
        end else begin // Single Precision
            sign_out     = fp_in[31];
            raw_exponent = {3'b0, fp_in[30:23]}; // Zero-extend to 11 bits
            // Pad FP32's 23-bit mantissa to fit the internal 52-bit field
            raw_mantissa = {fp_in[22:0], 29'b0}; 
            is_exp_max   = (raw_exponent[7:0] == 8'hFF);
        end

        // --- 2. Determine Number Type from Raw Components ---
        is_exp_zero  = (raw_exponent == 0);
        is_mant_zero = (raw_mantissa == 0);

        is_zero      = is_exp_zero && is_mant_zero;
        is_infinity  = is_exp_max  && is_mant_zero;
        is_nan       = is_exp_max  && !is_mant_zero;
        is_denormal  = is_exp_zero && !is_mant_zero;
        
        // --- 3. Format Outputs Consistently ---
        
        // Output the raw biased exponent directly.
        exponent_out = raw_exponent;
        
        // Format the mantissa with the explicit bit (1.F for normal, 0.F for others)
        // The implicit bit is 1 IFF the number is Normal.
        implicit_bit = (!is_exp_zero && !is_exp_max);
        
        if (is_zero || is_infinity) begin
            // For Zero and Infinity, the mantissa part is all zeros.
            mantissa_out = '0;
        end else begin
            // For Normal, Denormal, and NaN, combine the implicit bit and raw mantissa.
            mantissa_out = {implicit_bit, raw_mantissa};
        end
    end

endmodule
