`timescale 1ns/1ps

module tb_s2mm_control_fsm;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    parameter BURST_MAX  = 8;
    parameter CLK_PERIOD = 10;

    reg clk, rst_n;

    // DUT inputs
    reg  [31:0]           s2mm_ctrl;
    reg  [ADDR_WIDTH-1:0] dst_addr;
    reg  [31:0]           s2mm_len;

    reg                   fifo_empty;
    reg  [4:0]            fifo_count;
    reg  [DATA_WIDTH-1:0] fifo_rdata;
    wire                  fifo_rd_en;

    reg                   m_axi_awready;
    wire                  m_axi_awvalid;
    wire [ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [7:0]            m_axi_awlen;
    wire [2:0]            m_axi_awsize;
    wire [1:0]            m_axi_awburst;

    reg                   m_axi_wready;
    wire                  m_axi_wvalid;
    wire [DATA_WIDTH-1:0] m_axi_wdata;
    wire [3:0]            m_axi_wstrb;
    wire                  m_axi_wlast;

    reg                   m_axi_bvalid;
    reg  [1:0]            m_axi_bresp;
    wire                  m_axi_bready;

    wire [31:0]           s2mm_status;
    wire                  s2mm_done;

    // ---------------------------------------------------------
    // DUT
    // ---------------------------------------------------------
    s2mm_control_fsm dut (
        .clk(clk),
        .rst_n(rst_n),

        .s2mm_ctrl(s2mm_ctrl),
        .dst_addr(dst_addr),
        .s2mm_len(s2mm_len),

        .fifo_empty(fifo_empty),
        .fifo_count(fifo_count),
        .fifo_rdata(fifo_rdata),
        .fifo_rd_en(fifo_rd_en),

        .m_axi_awready(m_axi_awready),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),

        .m_axi_wready(m_axi_wready),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),

        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bready(m_axi_bready),

        .s2mm_status(s2mm_status),
        .s2mm_done(s2mm_done)
    );

    // ---------------------------------------------------------
    // Clock
    // ---------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---------------------------------------------------------
    // Simple FIFO model with 1-cycle read timing
    // ---------------------------------------------------------
    reg [31:0] mem [0:63];
    integer rd_ptr;
    integer fill;
    reg [1:0] tb_bresp;
    reg b_pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_bvalid <= 1'b0;
            m_axi_bresp  <= 2'b00;
            b_pending    <= 1'b0;
        end else begin
            // generate BVALID one cycle after WLAST handshake
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
                b_pending <= 1'b1;

            if (b_pending && !m_axi_bvalid) begin
                m_axi_bvalid <= 1'b1;
                m_axi_bresp  <= tb_bresp;
                b_pending    <= 1'b0;
            end

            if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 1'b0;
        end
    end

    // FIFO read side: advance after the DUT has sampled the current word
    always @(posedge clk) begin
        if (rst_n && fifo_rd_en && fill > 0) begin
            #1 begin
                rd_ptr = rd_ptr + 1;
                fill   = fill - 1;

                fifo_count = fill[4:0];
                fifo_empty = (fill == 0);

                if (fill > 0)
                    fifo_rdata = mem[rd_ptr];
                else
                    fifo_rdata = 32'h0000_0000;
            end
        end
    end

    // ---------------------------------------------------------
    // Capture / trace
    // ---------------------------------------------------------
    integer aw_seen;
    reg [ADDR_WIDTH-1:0] cap_awaddr [0:7];
    reg [7:0]            cap_awlen  [0:7];

    reg done_seen;
    reg [31:0] done_status;
    reg timed_out;

    always @(posedge clk) begin
        if (rst_n) begin
            if (m_axi_awvalid && m_axi_awready) begin
                #1 begin
                    cap_awaddr[aw_seen] = m_axi_awaddr;
                    cap_awlen[aw_seen]   = m_axi_awlen;
                    $display("[%0t] AW  handshake %0d: AWADDR=%h AWLEN=%0d",
                             $time, aw_seen, m_axi_awaddr, m_axi_awlen);
                    aw_seen = aw_seen + 1;
                end
            end

            if (m_axi_wvalid && m_axi_wready) begin
                #1 $display("[%0t] W   handshake: WDATA=%h WLAST=%b",
                            $time, m_axi_wdata, m_axi_wlast);
            end

            if (m_axi_bvalid && m_axi_bready) begin
                #1 $display("[%0t] B   handshake: BRESP=%b",
                            $time, m_axi_bresp);
            end

            if (s2mm_done) begin
                #1 begin
                    done_seen   = 1'b1;
                    done_status = s2mm_status;
                    $display("[%0t] DONE: STATUS=%h", $time, s2mm_status);
                end
            end
        end
    end

    // ---------------------------------------------------------
    // Tasks
    // ---------------------------------------------------------
    task clear_captures;
        begin
            aw_seen     = 0;
            done_seen   = 0;
            done_status = 0;
            timed_out   = 0;
        end
    endtask

    task reset_dut;
        begin
            rst_n        = 0;
            s2mm_ctrl    = 0;
            dst_addr     = 0;
            s2mm_len     = 0;

            fifo_empty   = 1;
            fifo_count   = 0;
            fifo_rdata   = 0;

            m_axi_awready = 0;
            m_axi_wready  = 0;
            m_axi_bvalid  = 0;
            m_axi_bresp   = 0;
            tb_bresp      = 2'b00;
            b_pending     = 0;

            rd_ptr        = 0;
            fill          = 0;

            clear_captures();

            repeat (3) @(posedge clk);

            rst_n = 1;
            m_axi_awready = 1;
            m_axi_wready  = 1;

            @(posedge clk);
        end
    endtask

    task load_fifo;
        input integer n;
        input [31:0] base;
        integer i;
        begin
            rd_ptr = 0;
            fill   = n;

            for (i = 0; i < n; i = i + 1)
                mem[i] = base + i;

            if (n > 0)
                fifo_rdata = mem[0];
            else
                fifo_rdata = 32'h0000_0000;

            fifo_count = n[4:0];
            fifo_empty  = (n == 0);
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk);
            s2mm_ctrl = 32'd1;
            @(posedge clk);
            s2mm_ctrl = 32'd0;
        end
    endtask

    task wait_done;
        input integer limit;
        integer i;
        begin
            timed_out = 1'b1;
            for (i = 0; i < limit; i = i + 1) begin
                @(posedge clk);
                if (done_seen) begin
                    timed_out = 1'b0;
                    i = limit;
                end
            end
        end
    endtask

    // ---------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------
    integer pass_count, fail_count;

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_s2mm_control_fsm);

        pass_count = 0;
        fail_count = 0;

        // -----------------------------------------------------
        // TC1: 32 bytes = 8 words, single burst
        // -----------------------------------------------------
        $display("\n=== TC1: 32 bytes, single burst ===");
        reset_dut();
        load_fifo(8, 32'hA000_0000);
        tb_bresp = 2'b00;

        dst_addr = 32'hC000_0000;
        s2mm_len = 32'd32;

        pulse_start();
        wait_done(500);

        if (!timed_out &&
            done_seen &&
            done_status[1] == 1'b1 &&
            done_status[2] == 1'b0 &&
            done_status[0] == 1'b0 &&
            aw_seen == 1 &&
            cap_awaddr[0] == 32'hC000_0000 &&
            cap_awlen[0]  == 8'd7 &&
            m_axi_awsize  == 3'b010 &&
            m_axi_awburst == 2'b01) begin
            $display("[PASS] TC1");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TC1: timed_out=%0d done_seen=%0d status=%h aw_seen=%0d awaddr0=%h awlen0=%0d",
                     timed_out, done_seen, done_status, aw_seen, cap_awaddr[0], cap_awlen[0]);
            fail_count = fail_count + 1;
        end

        // -----------------------------------------------------
        // TC2: 48 bytes = 12 words, multi-burst (8 + 4)
        // -----------------------------------------------------
        $display("\n=== TC2: 48 bytes, multi-burst ===");
        reset_dut();
        load_fifo(12, 32'hB000_0000);
        tb_bresp = 2'b00;

        dst_addr = 32'hD000_0000;
        s2mm_len = 32'd48;

        pulse_start();
        wait_done(800);

        if (!timed_out &&
            done_seen &&
            done_status[1] == 1'b1 &&
            done_status[2] == 1'b0 &&
            done_status[0] == 1'b0 &&
            aw_seen == 2 &&
            cap_awaddr[0] == 32'hD000_0000 &&
            cap_awlen[0]  == 8'd7 &&
            cap_awaddr[1] == 32'hD000_0020 &&
            cap_awlen[1]  == 8'd3) begin
            $display("[PASS] TC2");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TC2: timed_out=%0d done_seen=%0d status=%h aw_seen=%0d",
                     timed_out, done_seen, done_status, aw_seen);
            $display("      burst0: addr=%h len=%0d", cap_awaddr[0], cap_awlen[0]);
            $display("      burst1: addr=%h len=%0d", cap_awaddr[1], cap_awlen[1]);
            fail_count = fail_count + 1;
        end

        // -----------------------------------------------------
        // TC3: SLVERR response -> error bit set
        // -----------------------------------------------------
        $display("\n=== TC3: error response ===");
        reset_dut();
        load_fifo(4, 32'hC000_0000);
        tb_bresp = 2'b10;

        dst_addr = 32'hE000_0000;
        s2mm_len = 32'd16;

        pulse_start();
        wait_done(500);

        if (!timed_out &&
            done_seen &&
            done_status[1] == 1'b1 &&
            done_status[2] == 1'b1 &&
            done_status[0] == 1'b0 &&
            aw_seen == 1 &&
            cap_awaddr[0] == 32'hE000_0000 &&
            cap_awlen[0]  == 8'd3) begin
            $display("[PASS] TC3");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TC3: timed_out=%0d done_seen=%0d status=%h aw_seen=%0d awaddr0=%h awlen0=%0d",
                     timed_out, done_seen, done_status, aw_seen, cap_awaddr[0], cap_awlen[0]);
            fail_count = fail_count + 1;
        end

        $display("\n========================================");
        $display("RESULTS: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("CHECK THE WAVEFORM / LOG ABOVE");

        #20;
        $finish;
    end

endmodule