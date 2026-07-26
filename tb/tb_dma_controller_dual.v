`timescale 1ns/1ps

module tb_dma_controller_dual;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam integer TRANSFER_LEN = 37;
    localparam [31:0] SRC_ADDR = 32'h0000_0FF9;
    localparam [31:0] DST_ADDR = 32'h0000_1FFB;

    reg clk;
    reg rst_n;

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

    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;

    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    reg  [1:0]  m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;

    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rlast;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    wire [31:0] mm2s_status;
    wire [31:0] s2mm_status;
    wire        mm2s_done;
    wire        s2mm_done;

    reg [7:0] memory [0:16383];
    reg write_active;
    reg [31:0] write_addr;
    reg [8:0] write_beats_left;
    reg read_active;
    reg [31:0] read_addr;
    reg [8:0] read_beats_left;

    integer fail_count;
    integer mm2s_byte_count;
    integer write_beat_count;
    integer read_beat_count;
    integer i;
    integer lane;
    reg mm2s_done_seen;
    reg s2mm_done_seen;
    reg concurrent_busy_seen;
    reg concurrent_bus_seen;

    dma_controller_dual #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_MAX(4)
    ) dut (
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
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
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
        .m_axi_rready(m_axi_rready),
        .mm2s_status(mm2s_status),
        .s2mm_status(s2mm_status),
        .mm2s_done(mm2s_done),
        .s2mm_done(s2mm_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    assign m_axi_awready = !write_active && !m_axi_bvalid;
    assign m_axi_wready  = write_active;
    assign m_axi_arready = !read_active;

    assign m_axi_rvalid = read_active;
    assign m_axi_rresp  = 2'b00;
    assign m_axi_rlast  = read_active && (read_beats_left == 1);
    assign m_axi_rdata = {
        memory[read_addr + 3],
        memory[read_addr + 2],
        memory[read_addr + 1],
        memory[read_addr]
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_active     <= 1'b0;
            write_addr       <= 32'd0;
            write_beats_left <= 9'd0;
            m_axi_bvalid     <= 1'b0;
            m_axi_bresp      <= 2'b00;
            write_beat_count <= 0;
        end else begin
            if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 1'b0;

            if (m_axi_awvalid && m_axi_awready) begin
                write_active     <= 1'b1;
                write_addr       <= m_axi_awaddr;
                write_beats_left <= {1'b0, m_axi_awlen} + 1'b1;
                if (m_axi_awaddr[1:0] != 0 ||
                    m_axi_awsize != 3'b010 ||
                    m_axi_awburst != 2'b01) begin
                    $display("FAIL: invalid AXI write command");
                    fail_count = fail_count + 1;
                end
            end

            if (m_axi_wvalid && m_axi_wready) begin
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (m_axi_wstrb[lane])
                        memory[write_addr + lane]
                            <= m_axi_wdata[lane*8 +: 8];

                write_beat_count <= write_beat_count + 1;
                write_beats_left <= write_beats_left - 1'b1;

                if (m_axi_wlast) begin
                    if (write_beats_left != 1) begin
                        $display("FAIL: early WLAST");
                        fail_count = fail_count + 1;
                    end
                    write_active <= 1'b0;
                    m_axi_bvalid <= 1'b1;
                    m_axi_bresp  <= 2'b00;
                end else begin
                    write_addr <= write_addr + 4;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_active     <= 1'b0;
            read_addr       <= 32'd0;
            read_beats_left <= 9'd0;
            read_beat_count <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                read_active     <= 1'b1;
                read_addr       <= m_axi_araddr;
                read_beats_left <= {1'b0, m_axi_arlen} + 1'b1;
                if (m_axi_araddr[1:0] != 0 ||
                    m_axi_arsize != 3'b010 ||
                    m_axi_arburst != 2'b01) begin
                    $display("FAIL: invalid AXI read command");
                    fail_count = fail_count + 1;
                end
            end

            if (m_axi_rvalid && m_axi_rready) begin
                read_beat_count <= read_beat_count + 1;
                if (read_beats_left == 1) begin
                    read_active <= 1'b0;
                end else begin
                    read_addr       <= read_addr + 4;
                    read_beats_left <= read_beats_left - 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (mm2s_status[0] && s2mm_status[0])
                concurrent_busy_seen <= 1'b1;
            if (m_axi_rvalid && m_axi_rready &&
                m_axi_wvalid && m_axi_wready)
                concurrent_bus_seen <= 1'b1;
            if (mm2s_done)
                mm2s_done_seen <= 1'b1;
            if (s2mm_done)
                s2mm_done_seen <= 1'b1;

            if (m_axis_tvalid && m_axis_tready) begin
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (m_axis_tkeep[lane]) begin
                        if (m_axis_tdata[lane*8 +: 8] !==
                            ((8'hA0 + mm2s_byte_count) & 8'hFF)) begin
                            $display(
                                "FAIL: MM2S byte %0d got=%02h expected=%02h",
                                mm2s_byte_count,
                                m_axis_tdata[lane*8 +: 8],
                                ((8'hA0 + mm2s_byte_count) & 8'hFF)
                            );
                            fail_count = fail_count + 1;
                        end
                        mm2s_byte_count = mm2s_byte_count + 1;
                    end
                end

                if (m_axis_tlast !=
                    (mm2s_byte_count == TRANSFER_LEN)) begin
                    $display("FAIL: incorrect MM2S TLAST");
                    fail_count = fail_count + 1;
                end
            end
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

    task send_s2mm_stream;
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

    reg [3:0] ready_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_counter  <= 0;
            m_axis_tready <= 1'b0;
        end else begin
            ready_counter <= ready_counter + 1'b1;
            m_axis_tready <= (ready_counter[2:0] != 3'b011);
        end
    end

    initial begin
        fail_count          = 0;
        mm2s_byte_count     = 0;
        write_beat_count    = 0;
        read_beat_count     = 0;
        mm2s_done_seen      = 1'b0;
        s2mm_done_seen      = 1'b0;
        concurrent_busy_seen = 1'b0;
        concurrent_bus_seen  = 1'b0;

        rst_n         = 1'b0;
        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 4'hF;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;
        s_axis_tdata  = 0;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;

        for (i = 0; i < 16384; i = i + 1)
            memory[i] = 8'h55;
        for (i = 0; i < TRANSFER_LEN; i = i + 1)
            memory[SRC_ADDR + i] = 8'hA0 + i;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        axi_lite_write(32'h00, SRC_ADDR);
        axi_lite_write(32'h04, TRANSFER_LEN);
        axi_lite_write(32'h10, DST_ADDR);
        axi_lite_write(32'h14, TRANSFER_LEN);

        fork
            send_s2mm_stream();
        join_none

        axi_lite_write(32'h08, 32'h0000_0001);
        axi_lite_write(32'h18, 32'h0000_0001);

        i = 0;
        while ((!mm2s_done_seen || !s2mm_done_seen) && i < 1000) begin
            @(posedge clk);
            i = i + 1;
        end

        if (!mm2s_done_seen || !s2mm_done_seen) begin
            $display("FAIL: dual transfer timeout");
            fail_count = fail_count + 1;
        end
        if (mm2s_status[2:0] != 3'b010 ||
            s2mm_status[2:0] != 3'b010) begin
            $display(
                "FAIL: status MM2S=%h S2MM=%h",
                mm2s_status, s2mm_status
            );
            fail_count = fail_count + 1;
        end
        if (mm2s_byte_count != TRANSFER_LEN) begin
            $display(
                "FAIL: MM2S byte count=%0d expected=%0d",
                mm2s_byte_count, TRANSFER_LEN
            );
            fail_count = fail_count + 1;
        end
        for (i = 0; i < TRANSFER_LEN; i = i + 1) begin
            if (memory[DST_ADDR + i] !== ((8'hD0 + i) & 8'hFF)) begin
                $display(
                    "FAIL: S2MM byte %0d got=%02h expected=%02h",
                    i, memory[DST_ADDR + i], ((8'hD0 + i) & 8'hFF)
                );
                fail_count = fail_count + 1;
            end
        end
        if (memory[DST_ADDR-1] !== 8'h55 ||
            memory[DST_ADDR+TRANSFER_LEN] !== 8'h55) begin
            $display("FAIL: S2MM modified bytes outside transfer range");
            fail_count = fail_count + 1;
        end
        if (!concurrent_busy_seen) begin
            $display("FAIL: channels were never busy simultaneously");
            fail_count = fail_count + 1;
        end
        if (!concurrent_bus_seen) begin
            $display("FAIL: no simultaneous AXI read/write data cycle");
            fail_count = fail_count + 1;
        end
        if (read_beat_count !=
            ((SRC_ADDR[1:0] + TRANSFER_LEN + 3) / 4)) begin
            $display("FAIL: unexpected aligned read beat count");
            fail_count = fail_count + 1;
        end
        if (write_beat_count !=
            ((DST_ADDR[1:0] + TRANSFER_LEN + 3) / 4)) begin
            $display("FAIL: unexpected aligned write beat count");
            fail_count = fail_count + 1;
        end

        if (fail_count == 0)
            $display("PASS: concurrent unaligned dual-channel DMA");
        else
            $display("FAIL: %0d dual-channel checks failed", fail_count);

        $finish;
    end

    initial begin
        $dumpfile("dma_controller_dual.vcd");
        $dumpvars(0, tb_dma_controller_dual);
    end

    initial begin
        #100000;
        $display("FAIL: simulation watchdog timeout");
        $finish;
    end

endmodule
