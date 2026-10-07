// =============================================================================
// Module      : async_fifo  (top level)
// Description : Asynchronous FIFO for passing data between two unrelated
//               clock domains.
//
//   Depth = 2**ADDR_WIDTH entries of DATA_WIDTH bits (ADDR_WIDTH >= 2).
//
//     wclk domain                                       rclk domain
//   +------------+  wptr (Gray)  +----------+ rq2_wptr +------------+
//   | wptr_full  |-------------->| sync_2ff |--------->| rptr_empty |
//   |            |<--------------| sync_2ff |<---------|            |
//   +------------+  wq2_rptr     +----------+  rptr    +------------+
//        | waddr                                           | raddr
//        +------------------->  fifo_mem  <----------------+
//
//   Write : drive wdata and winc=1. The write happens at posedge wclk if !wfull.
//   Read  : rdata shows the oldest entry. rinc=1 removes it at posedge rclk
//           if !rempty.
// =============================================================================
`timescale 1ns / 1ps

module async_fifo #(
    parameter DATA_WIDTH      = 8,
    parameter ADDR_WIDTH      = 4,
    parameter ALMOST_FULL_TH  = 2,
    parameter ALMOST_EMPTY_TH = 2
) (
    // write clock domain
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [DATA_WIDTH-1:0] wdata,
    output wire                  wfull,
    output wire                  walmost_full,

    // read clock domain
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    output wire [DATA_WIDTH-1:0] rdata,
    output wire                  rempty,
    output wire                  ralmost_empty
);

    wire [ADDR_WIDTH-1:0] waddr, raddr;
    wire [ADDR_WIDTH:0]   wptr, rptr;           // Gray pointers
    wire [ADDR_WIDTH:0]   wq2_rptr, rq2_wptr;   // synchronized Gray pointers

    // ---------------- clock domain crossing ----------------
    // read pointer  -> write clock domain
    sync_2ff #(.WIDTH(ADDR_WIDTH+1)) u_sync_r2w (
        .clk   (wclk),
        .rst_n (wrst_n),
        .d     (rptr),
        .q     (wq2_rptr)
    );

    // write pointer -> read clock domain
    sync_2ff #(.WIDTH(ADDR_WIDTH+1)) u_sync_w2r (
        .clk   (rclk),
        .rst_n (rrst_n),
        .d     (wptr),
        .q     (rq2_wptr)
    );

    // ---------------- storage ----------------
    fifo_mem #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_fifo_mem (
        .wclk  (wclk),
        .wen   (winc & ~wfull),
        .waddr (waddr),
        .wdata (wdata),
        .raddr (raddr),
        .rdata (rdata)
    );

    // ---------------- write side ----------------
    wptr_full #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .ALMOST_FULL_TH (ALMOST_FULL_TH)
    ) u_wptr_full (
        .wclk         (wclk),
        .wrst_n       (wrst_n),
        .winc         (winc),
        .wq2_rptr     (wq2_rptr),
        .wfull        (wfull),
        .walmost_full (walmost_full),
        .waddr        (waddr),
        .wptr         (wptr)
    );

    // ---------------- read side ----------------
    rptr_empty #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .ALMOST_EMPTY_TH (ALMOST_EMPTY_TH)
    ) u_rptr_empty (
        .rclk          (rclk),
        .rrst_n        (rrst_n),
        .rinc          (rinc),
        .rq2_wptr      (rq2_wptr),
        .rempty        (rempty),
        .ralmost_empty (ralmost_empty),
        .raddr         (raddr),
        .rptr          (rptr)
    );

endmodule
