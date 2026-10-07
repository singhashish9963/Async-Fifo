// =============================================================================
// Module      : wptr_full
// Description : Write-side logic (runs entirely in the wclk domain).
//
//   - Keeps the write pointer in binary (to address memory) and in Gray code
//     (to send safely to the read domain).
//   - Generates the full and almost-full flags.
//
//   Pointers are ADDR_WIDTH+1 bits. The extra MSB counts "laps" around the
//   memory, which lets us tell FULL apart from EMPTY.
//
//   FULL (in Gray code): write pointer == synchronized read pointer with its
//   two MSBs inverted and all other bits equal.
// =============================================================================
`timescale 1ns / 1ps

module wptr_full #(
    parameter ADDR_WIDTH     = 4,
    parameter ALMOST_FULL_TH = 2     // walmost_full when free slots <= this
) (
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [ADDR_WIDTH:0]   wq2_rptr,      // read pointer (Gray), synchronized to wclk
    output reg                   wfull,
    output reg                   walmost_full,
    output wire [ADDR_WIDTH-1:0] waddr,
    output reg  [ADDR_WIDTH:0]   wptr           // write pointer (Gray), sent to read domain
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg  [ADDR_WIDTH:0] wbin;                   // write pointer (binary)
    wire [ADDR_WIDTH:0] wbin_next;
    wire [ADDR_WIDTH:0] wgray_next;
    wire [ADDR_WIDTH:0] rbin_sync;              // synchronized read pointer (binary)
    wire [ADDR_WIDTH:0] count_next;             // entries in FIFO after this cycle
    wire                full_next;
    wire                almost_full_next;

    // Gray -> binary: each binary bit is the XOR of all Gray bits above it
    function [ADDR_WIDTH:0] gray2bin;
        input [ADDR_WIDTH:0] gray;
        integer i;
        begin
            for (i = 0; i <= ADDR_WIDTH; i = i + 1)
                gray2bin[i] = ^(gray >> i);
        end
    endfunction

    // Pointer only moves on an accepted write (never while full)
    assign wbin_next  = wbin + (winc & ~wfull);
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;          // binary -> Gray

    assign full_next  = (wgray_next == {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1],
                                         wq2_rptr[ADDR_WIDTH-2:0]});

    // Occupancy seen from the write side. The read pointer is 2+ cycles old,
    // so this is pessimistic (may show more entries than really exist): safe.
    assign rbin_sync        = gray2bin(wq2_rptr);
    assign count_next       = wbin_next - rbin_sync;
    assign almost_full_next = (count_next >= DEPTH - ALMOST_FULL_TH);

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin         <= 0;
            wptr         <= 0;
            wfull        <= 1'b0;
            walmost_full <= 1'b0;
        end else begin
            wbin         <= wbin_next;
            wptr         <= wgray_next;
            wfull        <= full_next;
            walmost_full <= almost_full_next;
        end
    end

    assign waddr = wbin[ADDR_WIDTH-1:0];

endmodule
