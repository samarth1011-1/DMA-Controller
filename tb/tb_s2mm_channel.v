`timescale 1ns/1ps

module tb_s2mm_channel;
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    parameter FIFO_DEPTH = 16;
    parameter BURST_MAX  = 8;
    parameter CLK_PERIOD = 10;
    reg clk;
    reg rst_n;

    // AXI-Stream slave side
    reg [DATA_WIDTH-1:0] s_axis_tdata;
    reg s_axis_tvalid;
    reg s_axis_tlast;
    wire s_axis_tready;

    // AXI4 write master side
    reg m_axi_awready;
    reg m_axi_wready;
    reg m_axi_bvalid;
    reg  [1:0] m_axi_bresp;
    wire  m_axi_awvalid;
    wire [ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [7:0] m_axi_awlen;
    wire [2:0] m_axi_awsize;
    wire [1:0] m_axi_awburst;
    wire m_axi_wvalid;
    wire [DATA_WIDTH-1:0] m_axi_wdata;
    wire [3:0] m_axi_wstrb;
    wire m_axi_wlast;
    wire m_axi_bready;

    // Control / status
    reg [31:0] s2mm_ctrl;
    reg [ADDR_WIDTH-1:0] dst_addr;
    reg [31:0] s2mm_len;
    wire [31:0] s2mm_status;
    wire s2mm_done;

    s2mm_channel #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .BURST_MAX(BURST_MAX)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axi_awready(m_axi_awready),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bready(m_axi_bready),
        .s2mm_ctrl(s2mm_ctrl),
        .dst_addr(dst_addr),
        .s2mm_len(s2mm_len),
        .s2mm_status(s2mm_status),
        .s2mm_done(s2mm_done)
    );
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    integer pass_count;
    integer fail_count;
    integer aw_count;
    integer w_count;
    integer last_count;
    integer data_errors;
    integer timed_out;
    integer done_seen;
    reg [ADDR_WIDTH-1:0] cap_awaddr [0:7];
    reg [7:0]            cap_awlen  [0:7];
    reg [DATA_WIDTH-1:0] cap_wdata  [0:63];
    reg                  cap_wlast  [0:63];
    reg [1:0] next_bresp;
    reg       b_pending;
    // B channel model: return one response after each accepted WLAST.
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_bvalid <= 1'b0;
            m_axi_bresp  <= 2'b00;
            b_pending    <= 1'b0;
        end else begin
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
                b_pending <= 1'b1;
            if (b_pending && !m_axi_bvalid) begin
                m_axi_bvalid <= 1'b1;
                m_axi_bresp  <= next_bresp;
                b_pending    <= 1'b0;
            end
            if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 1'b0;
        end
    end
    always @(posedge clk) begin
        if (rst_n) begin
            if (m_axi_awvalid && m_axi_awready) begin
                cap_awaddr[aw_count] <= m_axi_awaddr;
                cap_awlen[aw_count]  <= m_axi_awlen;
                aw_count <= aw_count + 1;
            end
            if (m_axi_wvalid && m_axi_wready) begin
                cap_wdata[w_count] <= m_axi_wdata;
                cap_wlast[w_count] <= m_axi_wlast;
                if (m_axi_wlast)
                    last_count <= last_count + 1;
                w_count <= w_count + 1;
            end
            if (s2mm_done)
                done_seen <= 1'b1;
        end
    end
    task reset_dut;
        begin
            rst_n = 1'b0;
            s_axis_tdata = 0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
            m_axi_awready = 1'b0;
            m_axi_wready = 1'b0;
            m_axi_bvalid = 1'b0;
            m_axi_bresp = 2'b00;
            s2mm_ctrl = 32'd0;
            dst_addr = 0;
            s2mm_len = 0;
            next_bresp = 2'b00;
            b_pending = 1'b0;
            aw_count = 0;
            w_count = 0;
            last_count = 0;
            data_errors = 0;
            timed_out = 0;
            done_seen = 0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            m_axi_awready = 1'b1;
            m_axi_wready  = 1'b1;
            @(posedge clk);
        end
    endtask
    task pulse_start;
        begin
            @(negedge clk);
            s2mm_ctrl = 32'd1;
            @(negedge clk);
            s2mm_ctrl = 32'd0;
        end
    endtask
    task send_stream;
        input integer words;
        input [31:0] base;
        integer i;
        begin
            for (i = 0; i < words; i = i + 1) begin
                @(negedge clk);
                s_axis_tdata  = base + i;
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (i == words - 1);

                while (!s_axis_tready)
                    @(negedge clk);
            end
            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tdata  = 0;
        end
    endtask
    task wait_done;
        input integer max_cycles;
        integer i;
        begin
            timed_out = 1;
            for (i = 0; i < max_cycles; i = i + 1) begin
                @(posedge clk);
                if (done_seen) begin
                    timed_out = 0;
                    i = max_cycles;
                end
            end
        end
    endtask
    task check_data;
        input integer words;
        input [31:0] base;
        integer i;
        begin
            data_errors = 0;
            for (i = 0; i < words; i = i + 1) begin
                if (cap_wdata[i] !== base + i) begin
                    $display("[DATA FAIL] word %0d expected=%h got=%h",
                             i, base + i, cap_wdata[i]);
                    data_errors = data_errors + 1;
                end
            end
        end
    endtask
    task report_result;
        input pass;
        input [8*24-1:0] name;
        begin
            if (pass) begin
                $display("[PASS] %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s", name);
                $display("       timed_out=%0d done=%0d status=%h aw_count=%0d w_count=%0d last_count=%0d data_errors=%0d",
                         timed_out, done_seen, s2mm_status, aw_count, w_count,
                         last_count, data_errors);
                fail_count = fail_count + 1;
            end
        end
    endtask
    initial begin
        $dumpfile("tb_s2mm_channel.vcd");
        $dumpvars(0, tb_s2mm_channel);
        pass_count = 0;
        fail_count = 0;
        $display("\n=== TC1: 8-word S2MM transfer ===");
        reset_dut();
        dst_addr   = 32'h8000_0000;
        s2mm_len   = 32'd32;
        next_bresp = 2'b00;
        pulse_start();
        send_stream(8, 32'hA500_0000);
        wait_done(500);
        check_data(8, 32'hA500_0000);
        report_result(!timed_out &&
                      done_seen &&
                      s2mm_status[1] &&
                      !s2mm_status[2] &&
                      aw_count == 1 &&
                      cap_awaddr[0] == 32'h8000_0000 &&
                      cap_awlen[0] == 8'd7 &&
                      m_axi_awsize == 3'b010 &&
                      m_axi_awburst == 2'b01 &&
                      w_count == 8 &&
                      last_count == 1 &&
                      cap_wlast[7] == 1'b1 &&
                      data_errors == 0,
                      "TC1 single burst");
        $display("\n=== TC2: 12-word transfer split into 8 + 4 ===");
        reset_dut();
        dst_addr   = 32'h9000_0000;
        s2mm_len   = 32'd48;
        next_bresp = 2'b00;
        pulse_start();
        send_stream(12, 32'hB600_0000);
        wait_done(800);
        check_data(12, 32'hB600_0000);
        report_result(!timed_out &&
                      done_seen &&
                      s2mm_status[1] &&
                      !s2mm_status[2] &&
                      aw_count == 2 &&
                      cap_awaddr[0] == 32'h9000_0000 &&
                      cap_awlen[0] == 8'd7 &&
                      cap_awaddr[1] == 32'h9000_0020 &&
                      cap_awlen[1] == 8'd3 &&
                      w_count == 12 &&
                      last_count == 2 &&
                      cap_wlast[7] == 1'b1 &&
                      cap_wlast[11] == 1'b1 &&
                      data_errors == 0,
                      "TC2 multi burst");
        $display("\n=== TC3: write response error sets status[2] ===");
        reset_dut();
        dst_addr   = 32'hA000_0000;
        s2mm_len   = 32'd16;
        next_bresp = 2'b10;
        pulse_start();
        send_stream(4, 32'hC700_0000);
        wait_done(500);
        check_data(4, 32'hC700_0000);
        report_result(!timed_out &&
                      done_seen &&
                      s2mm_status[1] &&
                      s2mm_status[2] &&
                      aw_count == 1 &&
                      cap_awaddr[0] == 32'hA000_0000 &&
                      cap_awlen[0] == 8'd3 &&
                      w_count == 4 &&
                      last_count == 1 &&
                      data_errors == 0,
                      "TC3 error response");
        $display("\nRESULTS: PASS=%0d FAIL=%0d", pass_count, fail_count);
        #20;
        $finish;
    end
endmodule
