module FP_Encoder (
    input  logic        sign_in,
    input  logic [10:0] exponent_in,
    input  logic [52:0] mantissa_in,
    input  logic        is_double_precision,
    output logic [63:0] fp_out
);
    always_comb begin
        if (is_double_precision) begin
            fp_out = {sign_in, exponent_in, mantissa_in[51:0]};
        end else begin
            // For FP32, take the correct slices from the internal format
            fp_out = {32'b0, sign_in, exponent_in[7:0], mantissa_in[51:29]};
        end
    end
endmodule
