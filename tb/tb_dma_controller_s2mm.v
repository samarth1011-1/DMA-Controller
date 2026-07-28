`timescale 1ns/1ps

module tb_dma_controller_s2mm;

    localparam [31:0] DST_ADDR     = 32'h0000_0103;
    localparam integer TRANSFER_LEN = 17;

    reg         clk;
    reg         rst_n;
    reg  [31:0] s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [31:0] s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    wire        s_axis_tready;
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
    wire [31:0] s2mm_status;
    wire        s2mm_done;

    reg [7:0] memory [0:1023];
    reg [31:0] write_addr;
    reg [8:0]  write_beats_left;
    reg        write_active;
    reg        response_pending;
    reg        done_seen;
    integer    aw_count;
    integer    write_count;
    integer    fail_count;
    integer    lane;
    integer    i;

    dma_controller_s2mm dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
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
        .m_axi_bready(m_axi_bready),
        .s2mm_status(s2mm_status),
        .s2mm_done(s2mm_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr        <= 32'd0;
            write_beats_left  <= 9'd0;
            write_active      <= 1'b0;
            response_pending  <= 1'b0;
            m_axi_bvalid      <= 1'b0;
            m_axi_bresp       <= 2'b00;
            aw_count          <= 0;
            write_count       <= 0;
            done_seen         <= 1'b0;
        end else begin
            if (m_axi_awvalid && m_axi_awready) begin
                write_addr       <= m_axi_awaddr;
                write_beats_left <= {1'b0, m_axi_awlen} + 1'b1;
                write_active     <= 1'b1;
                aw_count         <= aw_count + 1;

                if (m_axi_awaddr[1:0] != 2'b00 ||
                    m_axi_awsize != 3'b010 ||
                    m_axi_awburst != 2'b01) begin
                    $display("FAIL: invalid AXI write command");
                    fail_count = fail_count + 1;
                end
            end

            if (m_axi_wvalid && m_axi_wready) begin
                if (!write_active) begin
                    $display("FAIL: write data without active command");
                    fail_count = fail_count + 1;
                end

                for (lane = 0; lane < 4; lane = lane + 1)
                    if (m_axi_wstrb[lane])
                        memory[write_addr[9:0] + lane]
                            <= m_axi_wdata[lane*8 +: 8];

                write_count      <= write_count + 1;
                write_beats_left <= write_beats_left - 1'b1;

                if (m_axi_wlast != (write_beats_left == 1)) begin
                    $display("FAIL: incorrect WLAST");
                    fail_count = fail_count + 1;
                end

                if (m_axi_wlast) begin
                    write_active     <= 1'b0;
                    response_pending <= 1'b1;
                end else begin
                    write_addr <= write_addr + 4;
                end
            end

            if (response_pending && !m_axi_bvalid) begin
                m_axi_bvalid     <= 1'b1;
                m_axi_bresp      <= 2'b00;
                response_pending <= 1'b0;
            end

            if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 1'b0;

            if (s2mm_done)
                done_seen <= 1'b1;
        end
    end

    task axi_lite_write;
        input [31:0] address;
        input [31:0] value;
        reg aw_done;
        reg w_done;
        begin
            aw_done = 1'b0;
            w_done  = 1'b0;
            @(negedge clk);
            s_axi_awaddr  = address;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = value;
            s_axi_wstrb   = 4'hF;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (s_axi_awvalid && s_axi_awready)
                    aw_done = 1'b1;
                if (s_axi_wvalid && s_axi_wready)
                    w_done = 1'b1;
                @(negedge clk);
                if (aw_done)
                    s_axi_awvalid = 1'b0;
                if (w_done)
                    s_axi_wvalid = 1'b0;
            end

            while (!s_axi_bvalid)
                @(posedge clk);
            if (s_axi_bresp != 2'b00) begin
                $display("FAIL: AXI-Lite write response");
                fail_count = fail_count + 1;
            end
            @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    task send_stream;
        integer word_index;
        integer byte_index;
        reg [31:0] packed_word;
        begin
            for (word_index = 0;
                 word_index < ((TRANSFER_LEN + 3) / 4);
                 word_index = word_index + 1) begin
                packed_word = 32'd0;
                for (byte_index = 0; byte_index < 4;
                     byte_index = byte_index + 1)
                    if ((word_index*4 + byte_index) < TRANSFER_LEN)
                        packed_word[byte_index*8 +: 8] =
                            8'hD0 + word_index*4 + byte_index;

                @(negedge clk);
                s_axis_tdata  = packed_word;
                s_axis_tvalid = 1'b1;
                s_axis_tlast  =
                    (word_index == ((TRANSFER_LEN + 3) / 4) - 1);
                @(posedge clk);
                while (!s_axis_tready)
                    @(posedge clk);
                @(negedge clk);
                s_axis_tvalid = 1'b0;
                s_axis_tlast  = 1'b0;
            end
        end
    endtask

    initial begin
        fail_count    = 0;
        rst_n         = 1'b0;
        s_axi_awaddr  = 32'd0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'd0;
        s_axi_wstrb   = 4'hF;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = 32'd0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        s_axis_tdata  = 32'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axi_awready = 1'b1;
        m_axi_wready  = 1'b1;

        for (i = 0; i < 1024; i = i + 1)
            memory[i] = 8'h55;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        axi_lite_write(32'h10, DST_ADDR);
        axi_lite_write(32'h14, TRANSFER_LEN);

        /*
         * Start the channel before presenting stream data. The current
         * datapath intentionally keeps TREADY low while it is inactive.
         */
        axi_lite_write(32'h18, 32'h0000_0001);
        send_stream();

        i = 0;
        while (!done_seen && i < 300) begin
            @(posedge clk);
            i = i + 1;
        end

        if (!done_seen) begin
            $display("FAIL: transfer timed out");
            fail_count = fail_count + 1;
        end

        if (aw_count != 1 || write_count != 5) begin
            $display(
                "FAIL: AXI counts AW=%0d W=%0d",
                aw_count, write_count
            );
            fail_count = fail_count + 1;
        end

        for (i = 0; i < TRANSFER_LEN; i = i + 1)
            if (memory[DST_ADDR[9:0] + i] !==
                ((8'hD0 + i) & 8'hFF)) begin
                $display(
                    "FAIL: destination byte=%0d got=%02h",
                    i, memory[DST_ADDR[9:0] + i]
                );
                fail_count = fail_count + 1;
            end

        if (memory[DST_ADDR[9:0] - 1] !== 8'h55 ||
            memory[DST_ADDR[9:0] + TRANSFER_LEN] !== 8'h55) begin
            $display("FAIL: bytes outside destination range changed");
            fail_count = fail_count + 1;
        end

        if (s2mm_status[2:0] !== 3'b010) begin
            $display("FAIL: status=%h", s2mm_status);
            fail_count = fail_count + 1;
        end

        if (fail_count == 0)
            $display(
                "PASS: dma_controller_s2mm unaligned integration"
            );
        else
            $display(
                "FAIL: dma_controller_s2mm errors=%0d",
                fail_count
            );
        $finish;
    end

    initial begin
        #50000;
        $display("FAIL: dma_controller_s2mm watchdog timeout");
        $finish;
    end

endmodule
