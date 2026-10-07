// =============================================================================
// Module      : sync_2ff
// Description : Two flip-flop synchronizer.
//
//   The first flop may go metastable if 'd' changes close to the destination
//   clock edge. The second flop gives it one full clock period to settle, so
//   'q' is a clean value in the destination clock domain.
//
//   Only use this for single bits or Gray-coded buses, where at most one bit
//   changes at a time.
// =============================================================================
`timescale 1ns / 1ps

module sync_2ff #(
    parameter WIDTH = 1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);

    reg [WIDTH-1:0] meta;   // first stage (may be metastable)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta <= {WIDTH{1'b0}};
            q    <= {WIDTH{1'b0}};
        end else begin
            meta <= d;
            q    <= meta;
        end
    end

endmodule
