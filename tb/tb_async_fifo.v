// =============================================================================
// Testbench   : tb_async_fifo
// Description : Self-checking testbench for async_fifo.
//
//   Structure
//   ---------
//   1. Clock / reset generation  : two independent clocks, period set per test
//   2. Stimulus tasks            : write_items(), read_items()
//   3. Reference model           : array used as a queue. Every accepted write
//                                  is stored; every accepted read is compared
//                                  against the oldest stored value.
//   4. CDC checkers              : Gray pointers change 1 bit per clock,
//                                  no pointer movement on overflow/underflow
//   5. Coverage counters         : full, empty, almost flags, overflow and
//                                  underflow attempts, wrap-around, ...
//   6. Test sequence             : 3 clock ratios x 4 traffic patterns
//
//   Stimulus is driven on the NEGATIVE clock edge and everything is checked on
//   the POSITIVE edge, so the testbench never races with the design.
// =============================================================================
`timescale 1ns / 1ps

module tb_async_fifo;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 4;
    localparam DEPTH      = 1 << ADDR_WIDTH;
    localparam MODEL_SIZE = 256;     // reference queue size (must be > DEPTH)

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg                   wclk, rclk;
    reg                   wrst_n, rrst_n;
    reg                   winc, rinc;
    reg  [DATA_WIDTH-1:0] wdata;
    wire [DATA_WIDTH-1:0] rdata;
    wire                  wfull, walmost_full;
    wire                  rempty, ralmost_empty;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .ALMOST_FULL_TH  (2),
        .ALMOST_EMPTY_TH (2)
    ) dut (
        .wclk          (wclk),
        .wrst_n        (wrst_n),
        .winc          (winc),
        .wdata         (wdata),
        .wfull         (wfull),
        .walmost_full  (walmost_full),
        .rclk          (rclk),
        .rrst_n        (rrst_n),
        .rinc          (rinc),
        .rdata         (rdata),
        .rempty        (rempty),
        .ralmost_empty (ralmost_empty)
    );

    // -------------------------------------------------------------------------
    // 1. Clocks (half periods can be changed while the simulation runs)
    // -------------------------------------------------------------------------
    integer wclk_half = 5;
    integer rclk_half = 5;

    initial wclk = 1'b0;
    initial rclk = 1'b0;
    always #(wclk_half) wclk = ~wclk;
    always #(rclk_half) rclk = ~rclk;

    // -------------------------------------------------------------------------
    // 3. Reference model (a queue built from an array + two counters)
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] model [0:MODEL_SIZE-1];
    integer wr_count   = 0;      // accepted writes
    integer rd_count   = 0;      // accepted reads (checked)
    integer data_errors = 0;

    // store every accepted write
    always @(posedge wclk) begin
        if (wrst_n && winc && !wfull) begin
            model[wr_count % MODEL_SIZE] = wdata;
            wr_count = wr_count + 1;
        end
    end

    // check every accepted read (first-word fall-through: rdata is valid now)
    always @(posedge rclk) begin
        if (rrst_n && rinc && !rempty) begin
            if (rd_count >= wr_count) begin
                $display("[%0t] ERROR: read while reference model is empty", $time);
                data_errors = data_errors + 1;
            end else if (rdata !== model[rd_count % MODEL_SIZE]) begin
                $display("[%0t] ERROR: read #%0d expected 0x%0h, got 0x%0h",
                         $time, rd_count, model[rd_count % MODEL_SIZE], rdata);
                data_errors = data_errors + 1;
            end
            rd_count = rd_count + 1;
        end
    end

    // -------------------------------------------------------------------------
    // 4. CDC checkers (look inside the DUT at the Gray pointers)
    // -------------------------------------------------------------------------
    integer check_errors = 0;
    reg [ADDR_WIDTH:0] last_wptr, last_rptr;
    reg                last_overflow_try, last_underflow_try;

    function integer count_ones;
        input [ADDR_WIDTH:0] value;
        integer i;
        begin
            count_ones = 0;
            for (i = 0; i <= ADDR_WIDTH; i = i + 1)
                count_ones = count_ones + value[i];
        end
    endfunction

    always @(posedge wclk) begin
        if (wrst_n) begin
            if (count_ones(dut.wptr ^ last_wptr) > 1) begin
                $display("[%0t] CHECK FAILED: write Gray pointer changed more than 1 bit", $time);
                check_errors = check_errors + 1;
            end
            if (last_overflow_try && (dut.wptr !== last_wptr)) begin
                $display("[%0t] CHECK FAILED: write pointer moved on a write while full", $time);
                check_errors = check_errors + 1;
            end
        end
        last_wptr         = dut.wptr;
        last_overflow_try = wrst_n && winc && wfull;
    end

    always @(posedge rclk) begin
        if (rrst_n) begin
            if (count_ones(dut.rptr ^ last_rptr) > 1) begin
                $display("[%0t] CHECK FAILED: read Gray pointer changed more than 1 bit", $time);
                check_errors = check_errors + 1;
            end
            if (last_underflow_try && (dut.rptr !== last_rptr)) begin
                $display("[%0t] CHECK FAILED: read pointer moved on a read while empty", $time);
                check_errors = check_errors + 1;
            end
        end
        last_rptr          = dut.rptr;
        last_underflow_try = rrst_n && rinc && rempty;
    end

    // -------------------------------------------------------------------------
    // 5. Coverage counters
    // -------------------------------------------------------------------------
    integer cov_full          = 0;   // cycles with FIFO full
    integer cov_empty         = 0;   // cycles with FIFO empty
    integer cov_almost_full   = 0;
    integer cov_almost_empty  = 0;
    integer cov_overflow_try  = 0;   // write attempted while full
    integer cov_underflow_try = 0;   // read attempted while empty
    integer cov_simultaneous  = 0;   // read accepted while writer is writing

    always @(posedge wclk) begin
        if (wrst_n) begin
            if (wfull)          cov_full         = cov_full + 1;
            if (walmost_full)   cov_almost_full  = cov_almost_full + 1;
            if (winc && wfull)  cov_overflow_try = cov_overflow_try + 1;
        end
    end

    always @(posedge rclk) begin
        if (rrst_n) begin
            if (rempty)                   cov_empty         = cov_empty + 1;
            if (ralmost_empty)            cov_almost_empty  = cov_almost_empty + 1;
            if (rinc && rempty)           cov_underflow_try = cov_underflow_try + 1;
            if (rinc && !rempty && winc)  cov_simultaneous  = cov_simultaneous + 1;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Stimulus tasks
    // -------------------------------------------------------------------------

    // Write 'count' random values. Before each write, wait 0..max_idle cycles.
    // winc is held until the write is accepted, so writing into a full FIFO
    // automatically produces overflow attempts.
    task write_items;
        input integer count;
        input integer max_idle;
        integer n, idle;
        begin
            for (n = 0; n < count; n = n + 1) begin
                idle = (max_idle == 0) ? 0 : ({$random} % (max_idle + 1));
                repeat (idle) begin
                    @(negedge wclk) winc = 1'b0;
                end
                @(negedge wclk);
                winc  = 1'b1;
                wdata = $random;
                @(posedge wclk);
                while (wfull) @(posedge wclk);   // wait until accepted
            end
            @(negedge wclk) winc = 1'b0;
        end
    endtask

    // Keep reading (each cycle with probability read_pct %) until 'total'
    // values have been read in total. Reading while empty is allowed and
    // produces underflow attempts.
    task read_items;
        input integer total;
        input integer read_pct;
        begin
            while (rd_count < total) begin
                @(negedge rclk);
                rinc = (({$random} % 100) < read_pct);
            end
            @(negedge rclk) rinc = 1'b0;
        end
    endtask

    // Read with rinc=1 for a few cycles while the FIFO is empty
    task underflow_attempts;
        begin
            @(negedge rclk) rinc = 1'b1;
            repeat (5) @(negedge rclk);
            rinc = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // 6. Test sequence
    // -------------------------------------------------------------------------
    task run_clock_ratio;
        input integer w_half;
        input integer r_half;
        begin
            wclk_half = w_half;
            rclk_half = r_half;
            $display("[%0t] ---- write clock %0d ns, read clock %0d ns ----",
                     $time, 2*w_half, 2*r_half);

            // A) Fill the FIFO with no reads, keep writing while full
            //    (overflow), then drain it completely and read while empty
            //    (underflow).
            fork
                write_items(DEPTH + 4, 0);
                begin
                    wait (wfull);
                    repeat (8) @(posedge wclk);
                    read_items(wr_count + 4, 100);
                end
            join
            underflow_attempts;

            // B) Random traffic
            fork
                write_items(200, 3);
                read_items(wr_count + 200, 50);
            join

            // C) Writer faster than reader -> FIFO often full
            fork
                write_items(200, 0);
                read_items(wr_count + 200, 30);
            join

            // D) Reader faster than writer -> FIFO often empty
            fork
                write_items(200, 4);
                read_items(wr_count + 200, 90);
            join
        end
    endtask

    initial begin
        $dumpfile("tb_async_fifo.vcd");
        $dumpvars(0, tb_async_fifo);

        winc   = 1'b0;
        rinc   = 1'b0;
        wdata  = 0;
        wrst_n = 1'b0;
        rrst_n = 1'b0;

        // release the two resets at different times
        #53 wrst_n = 1'b1;
        #11 rrst_n = 1'b1;
        repeat (3) @(posedge wclk);

        run_clock_ratio(5, 5);     // same frequency (100 MHz / 100 MHz)
        run_clock_ratio(5, 13);    // fast writer    (100 MHz / ~38 MHz)
        run_clock_ratio(17, 4);    // fast reader    (~29 MHz / 125 MHz)

        repeat (10) @(posedge rclk);
        report;
        $finish;
    end

    // safety net in case the design gets stuck (e.g. FIFO never becomes full)
    reg timed_out = 1'b0;
    initial begin
        #5_000_000;
        $display("ERROR: simulation timeout - the design or the test got stuck");
        timed_out = 1'b1;
        report;
        $finish;
    end

    // -------------------------------------------------------------------------
    // Final report
    // -------------------------------------------------------------------------
    task report;
        integer coverage_ok;
        begin
            coverage_ok = (cov_full > 0) && (cov_empty > 0) &&
                          (cov_almost_full > 0) && (cov_almost_empty > 0) &&
                          (cov_overflow_try > 0) && (cov_underflow_try > 0) &&
                          (cov_simultaneous > 0) && (wr_count > 2*DEPTH);

            $display("");
            $display("==================== TEST SUMMARY ====================");
            $display(" Writes accepted            : %0d", wr_count);
            $display(" Reads checked              : %0d", rd_count);
            $display(" Data mismatches            : %0d", data_errors);
            $display(" CDC check failures         : %0d", check_errors);
            $display("------------------------------------------------------");
            $display(" Coverage");
            $display("   cycles full              : %0d", cov_full);
            $display("   cycles empty             : %0d", cov_empty);
            $display("   cycles almost full       : %0d", cov_almost_full);
            $display("   cycles almost empty      : %0d", cov_almost_empty);
            $display("   overflow attempts        : %0d", cov_overflow_try);
            $display("   underflow attempts       : %0d", cov_underflow_try);
            $display("   simultaneous read/write  : %0d", cov_simultaneous);
            $display("   pointer wrap-arounds     : %0d", wr_count / DEPTH);
            $display("------------------------------------------------------");
            if (data_errors == 0 && check_errors == 0 && !timed_out &&
                rd_count == wr_count && coverage_ok)
                $display(" RESULT : *** TEST PASSED ***");
            else
                $display(" RESULT : *** TEST FAILED ***");
            $display("======================================================");
        end
    endtask

endmodule
