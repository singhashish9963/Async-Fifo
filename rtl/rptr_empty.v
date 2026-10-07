// =============================================================================
// Module      : rptr_empty
// Description : Read-side logic (runs entirely in the rclk domain).
//
//   - Keeps the read pointer in binary (to address memory) and in Gray code
//     (to send safely to the write domain).
//   - Generates the empty and almost-empty flags.
//
//   EMPTY: read pointer == synchronized write pointer (all bits equal).
// =============================================================================
`timescale 1ns / 1ps

module rptr_empty #(
    parameter ADDR_WIDTH      = 4,
    parameter ALMOST_EMPTY_TH = 2    // ralmost_empty when entries <= this
) (
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    input  wire [ADDR_WIDTH:0]   rq2_wptr,      // write pointer (Gray), synchronized to rclk
    output reg                   rempty,
    output reg                   ralmost_empty,
    output wire [ADDR_WIDTH-1:0] raddr,
    output reg  [ADDR_WIDTH:0]   rptr           // read pointer (Gray), sent to write domain
);

    reg  [ADDR_WIDTH:0] rbin;                   // read pointer (binary)
    wire [ADDR_WIDTH:0] rbin_next;
    wire [ADDR_WIDTH:0] rgray_next;
    wire [ADDR_WIDTH:0] wbin_sync;              // synchronized write pointer (binary)
    wire [ADDR_WIDTH:0] count_next;             // entries in FIFO after this cycle
    wire                empty_next;
    wire                almost_empty_next;

    function [ADDR_WIDTH:0] gray2bin;
        input [ADDR_WIDTH:0] gray;
        integer i;
        begin
            for (i = 0; i <= ADDR_WIDTH; i = i + 1)
                gray2bin[i] = ^(gray >> i);
        end
    endfunction

    // Pointer only moves on an accepted read (never while empty)
    assign rbin_next  = rbin + (rinc & ~rempty);
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;          // binary -> Gray

    assign empty_next = (rgray_next == rq2_wptr);

    // Occupancy seen from the read side (pessimistic, like almost-full)
    assign wbin_sync         = gray2bin(rq2_wptr);
    assign count_next        = wbin_sync - rbin_next;
    assign almost_empty_next = (count_next <= ALMOST_EMPTY_TH);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin          <= 0;
            rptr          <= 0;
            rempty        <= 1'b1;
            ralmost_empty <= 1'b1;
        end else begin
            rbin          <= rbin_next;
            rptr          <= rgray_next;
            rempty        <= empty_next;
            ralmost_empty <= almost_empty_next;
        end
    end

    assign raddr = rbin[ADDR_WIDTH-1:0];

endmodule
