// =============================================================================
// Module      : fifo_mem
// Description : Dual-port memory used as FIFO storage.
//
//   - Write port : synchronous, clocked by wclk
//   - Read port  : asynchronous (combinational)
//
//   The combinational read makes the FIFO "first-word fall-through":
//   rdata always shows the oldest entry while the FIFO is not empty.
// =============================================================================
`timescale 1ns / 1ps

module fifo_mem #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,
    input  wire                  wen,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output wire [DATA_WIDTH-1:0] rdata
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge wclk) begin
        if (wen)
            mem[waddr] <= wdata;
    end

    assign rdata = mem[raddr];

endmodule
