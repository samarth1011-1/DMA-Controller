`timescale 1ns/1ps

module tb_axi4_full_read_master;

    reg clk;
    reg rst_n;
    reg cmd_valid;
    wire cmd_ready;
    reg [31:0] cmd_addr;
    reg [7:0] cmd_len;
    wire [31:0] data;
    wire data_valid;
    reg data_ready;
    wire data_last;
    wire busy;
    wire done;
    wire error;
    wire [31:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid;
    reg m_axi_arready;
    reg [31:0] m_axi_rdata;
    reg [1:0] m_axi_rresp;
    reg m_axi_rlast;
    reg m_axi_rvalid;
    wire m_axi_rready;

    integer fail_count;
    integer beat_count;

    axi4_full_read_master dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .data(data),
        .data_valid(data_valid),
        .data_ready(data_ready),
        .data_last(data_last),
        .busy(busy),
        .done(done),
        .error(error),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task issue_command;
        input [31:0] address;
        input [7:0] length;
        begin
            while (!cmd_ready)
                @(posedge clk);
            @(negedge clk);
            cmd_addr  = address;
            cmd_len   = length;
            cmd_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;

            while (!m_axi_arvalid)
                @(posedge clk);
            repeat (2) begin
                @(posedge clk);
                if (m_axi_araddr != address || m_axi_arlen != length) begin
                    $display("FAIL: AR changed under backpressure");
                    fail_count = fail_count + 1;
                end
            end
            @(negedge clk);
            m_axi_arready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            m_axi_arready = 1'b0;
        end
    endtask

    task send_beat;
        input [31:0] value;
        input [1:0] response;
        input last;
        input integer stalls;
        integer j;
        begin
            @(negedge clk);
            m_axi_rdata  = value;
            m_axi_rresp  = response;
            m_axi_rlast  = last;
            m_axi_rvalid = 1'b1;
            data_ready   = 1'b0;
            for (j = 0; j < stalls; j = j + 1)
                @(posedge clk);
            @(negedge clk);
            data_ready = 1'b1;
            @(posedge clk);
            if (!data_valid || data != value) begin
                $display("FAIL: read data handshake");
                fail_count = fail_count + 1;
            end
            if (data_last != last) begin
                $display("FAIL: expected-last indication");
                fail_count = fail_count + 1;
            end
            beat_count = beat_count + 1;
            @(negedge clk);
            data_ready   = 1'b0;
            m_axi_rvalid = 1'b0;
            m_axi_rlast  = 1'b0;
        end
    endtask

    initial begin
        rst_n         = 1'b0;
        cmd_valid     = 1'b0;
        cmd_addr      = 0;
        cmd_len       = 0;
        data_ready    = 1'b0;
        m_axi_arready = 1'b0;
        m_axi_rdata   = 0;
        m_axi_rresp   = 0;
        m_axi_rlast   = 1'b0;
        m_axi_rvalid  = 1'b0;
        fail_count    = 0;
        beat_count    = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        issue_command(32'h1000_0000, 8'd2);
        if (m_axi_arsize != 3'b010 || m_axi_arburst != 2'b01) begin
            $display("FAIL: read burst attributes");
            fail_count = fail_count + 1;
        end
        send_beat(32'h1111_0001, 2'b00, 1'b0, 2);
        send_beat(32'h2222_0002, 2'b00, 1'b0, 0);
        send_beat(32'h3333_0003, 2'b00, 1'b1, 1);
        @(posedge clk);
        if (!done || error || beat_count != 3) begin
            $display("FAIL: successful read completion");
            fail_count = fail_count + 1;
        end

        beat_count = 0;
        issue_command(32'h2000_0000, 8'd0);
        send_beat(32'hDEAD_BEEF, 2'b10, 1'b1, 0);
        @(posedge clk);
        if (!done || !error) begin
            $display("FAIL: read error response");
            fail_count = fail_count + 1;
        end

        if (fail_count == 0)
            $display("PASS: axi4_full_read_master");
        else
            $display("FAIL: read-master checks=%0d", fail_count);
        $finish;
    end

    initial begin
        #10000;
        $display("FAIL: read-master watchdog timeout");
        $finish;
    end

endmodule
