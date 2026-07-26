`timescale 1ns/1ps

module tb_axi4_full_write_master;

    reg clk;
    reg rst_n;

    reg         cmd_valid;
    wire        cmd_ready;
    reg  [31:0] cmd_addr;
    reg  [7:0]  cmd_len;

    reg  [31:0] data;
    reg  [3:0]  data_strb;
    reg         data_valid;
    wire        data_ready;

    wire        busy;
    wire        done;
    wire        error;

    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;
    reg  [1:0]  m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;

    integer fail_count;
    integer write_count;
    reg [31:0] captured_data [0:3];
    reg [3:0]  captured_last;

    axi4_full_write_master dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .data(data),
        .data_strb(data_strb),
        .data_valid(data_valid),
        .data_ready(data_ready),
        .busy(busy),
        .done(done),
        .error(error),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            write_count <= 0;
        end else if (m_axi_wvalid && m_axi_wready) begin
            if (write_count < 4) begin
                captured_data[write_count] <= m_axi_wdata;
                captured_last[write_count] <= m_axi_wlast;
            end
            write_count <= write_count + 1;
        end
    end

    task issue_command;
        input [31:0] addr;
        input [7:0]  len;
        begin
            while (!cmd_ready)
                @(posedge clk);
            @(negedge clk);
            cmd_addr  = addr;
            cmd_len   = len;
            cmd_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;
        end
    endtask

    task accept_address;
        input [31:0] expected_addr;
        input [7:0]  expected_len;
        begin
            while (!m_axi_awvalid)
                @(posedge clk);

            repeat (2) begin
                @(posedge clk);
                if (!m_axi_awvalid || m_axi_awaddr !== expected_addr ||
                    m_axi_awlen !== expected_len) begin
                    $display("FAIL: AW changed while stalled");
                    fail_count = fail_count + 1;
                end
            end

            @(negedge clk);
            m_axi_awready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            m_axi_awready = 1'b0;
        end
    endtask

    task send_data_beat;
        input [31:0] beat_data;
        input [3:0]  beat_strb;
        input integer stall_cycles;
        integer j;
        begin
            @(negedge clk);
            data       = beat_data;
            data_strb  = beat_strb;
            data_valid = 1'b1;
            m_axi_wready = 1'b0;

            for (j = 0; j < stall_cycles; j = j + 1) begin
                @(posedge clk);
                if (!m_axi_wvalid || m_axi_wdata !== beat_data ||
                    m_axi_wstrb !== beat_strb) begin
                    $display("FAIL: W payload changed while stalled");
                    fail_count = fail_count + 1;
                end
            end

            @(negedge clk);
            m_axi_wready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            m_axi_wready = 1'b0;
            data_valid   = 1'b0;
        end
    endtask

    task send_response;
        input [1:0] response;
        begin
            while (!m_axi_bready)
                @(posedge clk);
            @(negedge clk);
            m_axi_bresp  = response;
            m_axi_bvalid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            m_axi_bvalid = 1'b0;
        end
    endtask

    initial begin
        fail_count    = 0;
        write_count   = 0;
        captured_last = 0;
        rst_n         = 1'b0;
        cmd_valid     = 1'b0;
        cmd_addr      = 0;
        cmd_len       = 0;
        data          = 0;
        data_strb     = 4'hF;
        data_valid    = 1'b0;
        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;
        m_axi_bresp   = 2'b00;
        m_axi_bvalid  = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Four-beat burst with address and data backpressure.
        issue_command(32'h4000_1000, 8'd3);
        accept_address(32'h4000_1000, 8'd3);

        if (m_axi_awsize !== 3'b010 || m_axi_awburst !== 2'b01) begin
            $display("FAIL: AXI burst attributes are incorrect");
            fail_count = fail_count + 1;
        end

        send_data_beat(32'hAAAA_0001, 4'hF, 2);
        send_data_beat(32'hBBBB_0002, 4'hF, 0);
        send_data_beat(32'hCCCC_0003, 4'h3, 1);
        send_data_beat(32'hDDDD_0004, 4'hF, 2);
        send_response(2'b00);

        @(posedge clk);
        if (!done || error) begin
            $display("FAIL: successful response status done=%b error=%b", done, error);
            fail_count = fail_count + 1;
        end
        if (write_count !== 4 ||
            captured_data[0] !== 32'hAAAA_0001 ||
            captured_data[1] !== 32'hBBBB_0002 ||
            captured_data[2] !== 32'hCCCC_0003 ||
            captured_data[3] !== 32'hDDDD_0004) begin
            $display("FAIL: captured write data is incorrect");
            fail_count = fail_count + 1;
        end
        if (captured_last !== 4'b1000) begin
            $display("FAIL: WLAST pattern=%b", captured_last);
            fail_count = fail_count + 1;
        end

        // Single-beat burst with an AXI error response.
        write_count   = 0;
        captured_last = 0;
        issue_command(32'h5000_0000, 8'd0);
        accept_address(32'h5000_0000, 8'd0);
        send_data_beat(32'h1234_5678, 4'hF, 0);
        send_response(2'b10);

        @(posedge clk);
        if (!done || !error) begin
            $display("FAIL: error response status done=%b error=%b", done, error);
            fail_count = fail_count + 1;
        end
        if (write_count !== 1 || captured_last[0] !== 1'b1) begin
            $display("FAIL: single-beat transaction handling");
            fail_count = fail_count + 1;
        end

        if (fail_count == 0)
            $display("PASS: axi4_full_write_master");
        else
            $display("FAIL: %0d checks failed", fail_count);

        $finish;
    end

    initial begin
        $dumpfile("axi4_full_write_master.vcd");
        $dumpvars(0, tb_axi4_full_write_master);
    end

    initial begin
        #10000;
        $display("FAIL: simulation watchdog timeout");
        $finish;
    end

endmodule
