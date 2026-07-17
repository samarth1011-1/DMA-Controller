`timescale 1ns/1ps

module tb_axi4_lite_slave;

// ── DUT connections ────────────────────────────────────────────────────────
reg         clk;
reg         rst_n;

reg  [31:0] s_axi_awaddr;
reg         s_axi_awvalid;
wire        s_axi_awready;

reg  [31:0] s_axi_wdata;
reg  [ 3:0] s_axi_wstrb;
reg         s_axi_wvalid;
wire        s_axi_wready;

wire [ 1:0] s_axi_bresp;
wire        s_axi_bvalid;
reg         s_axi_bready;

reg  [31:0] s_axi_araddr;
reg         s_axi_arvalid;
wire        s_axi_arready;

wire [31:0] s_axi_rdata;
wire [ 1:0] s_axi_rresp;
wire        s_axi_rvalid;
reg         s_axi_rready;

wire [31:0] mm2s_src_addr, mm2s_length, mm2s_control;
wire [31:0] s2mm_dst_addr, s2mm_length, s2mm_control;
reg  [31:0] mm2s_status, s2mm_status;

// ── DUT instantiation ──────────────────────────────────────────────────────
axi4_lite_slave dut (
    .clk(clk), .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),   .s_axi_wstrb(s_axi_wstrb),    .s_axi_wvalid(s_axi_wvalid),   .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),   .s_axi_bvalid(s_axi_bvalid),  .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),   .s_axi_rresp(s_axi_rresp),    .s_axi_rvalid(s_axi_rvalid),   .s_axi_rready(s_axi_rready),
    .mm2s_src_addr(mm2s_src_addr), .mm2s_length(mm2s_length), .mm2s_control(mm2s_control),
    .s2mm_dst_addr(s2mm_dst_addr), .s2mm_length(s2mm_length), .s2mm_control(s2mm_control),
    .mm2s_status(mm2s_status), .s2mm_status(s2mm_status)
);

// ── Clock generation ───────────────────────────────────────────────────────
initial clk = 0;
always #5 clk = ~clk;   // 100 MHz

// ── FIX: Pulse monitors for auto-clear verification ───────────────────────
// These always blocks run continuously and latch a 1 the moment the
// respective control output goes high. The initial block clears them
// before each test and reads them after — catching even a 1-cycle pulse
// that axi_write would otherwise step past before returning.
reg mm2s_ctrl_pulse_seen;
reg s2mm_ctrl_pulse_seen;

always @(posedge clk) begin
    if (mm2s_control[0] || mm2s_control[1])
        mm2s_ctrl_pulse_seen <= 1'b1;
end

always @(posedge clk) begin
    if (s2mm_control[0] || s2mm_control[1])
        s2mm_ctrl_pulse_seen <= 1'b1;
end

// ── AXI helper tasks ───────────────────────────────────────────────────────

// Write transaction
task axi_write;
    input [31:0] addr;
    input [31:0] data;
    input [ 3:0] strb;
    begin
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= strb;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;

        @(posedge clk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;

        while (!s_axi_bvalid) @(posedge clk);
        @(posedge clk);
        s_axi_bready <= 1'b0;
    end
endtask

// Read transaction
task axi_read;
    input  [31:0] addr;
    output [31:0] rdata;
    output [ 1:0] rresp;
    begin
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        @(posedge clk);
        s_axi_arvalid <= 1'b0;

        while (!s_axi_rvalid) @(posedge clk);
        rdata = s_axi_rdata;
        rresp = s_axi_rresp;
        @(posedge clk);
        s_axi_rready <= 1'b0;
    end
endtask

// ── Stimulus ───────────────────────────────────────────────────────────────
reg [31:0] rd_data;
reg [ 1:0] rd_resp;
integer    fail_count;

initial begin
    fail_count           = 0;
    mm2s_ctrl_pulse_seen = 0;
    s2mm_ctrl_pulse_seen = 0;
    rst_n         = 0;
    s_axi_awvalid = 0; s_axi_wvalid  = 0; s_axi_bready  = 0;
    s_axi_arvalid = 0; s_axi_rready  = 0;
    s_axi_awaddr  = 0; s_axi_wdata   = 0; s_axi_wstrb   = 4'hF;
    s_axi_araddr  = 0;
    mm2s_status   = 32'h0000_0003;
    s2mm_status   = 32'h0000_0004;

    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // ── Test 1: Write & read-back config registers ─────────────────────────
    $display("=== Test 1: Write/Read config registers ===");
    axi_write(32'h00, 32'hDEAD_0001, 4'hF);
    axi_write(32'h04, 32'h0000_0100, 4'hF);
    axi_write(32'h10, 32'hCAFE_BABE, 4'hF);
    axi_write(32'h14, 32'h0000_0200, 4'hF);

    axi_read(32'h00, rd_data, rd_resp);
    if (rd_data !== 32'hDEAD_0001 || rd_resp !== 2'b00) begin
        $display("FAIL MM2S_SRC_ADDR: got %h resp %b", rd_data, rd_resp);
        fail_count = fail_count + 1;
    end else $display("PASS MM2S_SRC_ADDR = %h", rd_data);

    axi_read(32'h04, rd_data, rd_resp);
    if (rd_data !== 32'h0000_0100) begin
        $display("FAIL MM2S_LENGTH: got %h", rd_data);
        fail_count = fail_count + 1;
    end else $display("PASS MM2S_LENGTH = %h", rd_data);

    axi_read(32'h10, rd_data, rd_resp);
    if (rd_data !== 32'hCAFE_BABE) begin
        $display("FAIL S2MM_DST_ADDR: got %h", rd_data);
        fail_count = fail_count + 1;
    end else $display("PASS S2MM_DST_ADDR = %h", rd_data);

    // ── Test 2: Read status registers ──────────────────────────────────────
    $display("=== Test 2: Read status registers ===");
    axi_read(32'h0C, rd_data, rd_resp);
    if (rd_data[2:0] !== mm2s_status[2:0]) begin
        $display("FAIL MM2S_STATUS: got %03b", rd_data[2:0]);
        fail_count = fail_count + 1;
    end else $display("PASS MM2S_STATUS = %03b", rd_data[2:0]);

    axi_read(32'h1C, rd_data, rd_resp);
    if (rd_data[2:0] !== s2mm_status[2:0]) begin
        $display("FAIL S2MM_STATUS: got %03b", rd_data[2:0]);
        fail_count = fail_count + 1;
    end else $display("PASS S2MM_STATUS = %03b", rd_data[2:0]);

    // ── Test 3: START bit — pulse high then auto-clear ─────────────────────
    // FIX: clear the latch, perform write, then verify BOTH that the pulse
    //      was seen (bit was actually 1 for one cycle) AND that it cleared.
    //      The old testbench only checked the cleared state, which passes
    //      even if the bit was never set — a false positive.
    $display("=== Test 3: START bit pulse ===");
    mm2s_ctrl_pulse_seen = 1'b0;          // clear latch before test
    axi_write(32'h08, 32'h0000_0001, 4'hF);
    @(posedge clk);                        // one extra cycle for auto-clear to settle
    if (!mm2s_ctrl_pulse_seen) begin
        $display("FAIL: START bit never went high — write had no effect");
        fail_count = fail_count + 1;
    end else if (mm2s_control[0] !== 1'b0) begin
        $display("FAIL: START bit did not auto-clear");
        fail_count = fail_count + 1;
    end else
        $display("PASS: START bit pulsed high for 1 cycle then auto-cleared");

    // ── Test 4: RESET bit — pulse high then auto-clear ─────────────────────
    $display("=== Test 4: RESET bit pulse ===");
    mm2s_ctrl_pulse_seen = 1'b0;          // clear latch before test
    axi_write(32'h08, 32'h0000_0002, 4'hF);
    @(posedge clk);
    if (!mm2s_ctrl_pulse_seen) begin
        $display("FAIL: RESET bit never went high — write had no effect");
        fail_count = fail_count + 1;
    end else if (mm2s_control[1] !== 1'b0) begin
        $display("FAIL: RESET bit did not auto-clear");
        fail_count = fail_count + 1;
    end else
        $display("PASS: RESET bit pulsed high for 1 cycle then auto-cleared");

    // ── Test 5: Write to RO status register ────────────────────────────────
    $display("=== Test 5: Write to RO status register ===");
    axi_write(32'h0C, 32'hFFFF_FFFF, 4'hF);
    axi_read(32'h0C, rd_data, rd_resp);
    if (rd_data[2:0] === mm2s_status[2:0])
        $display("PASS: RO status unchanged after write attempt");
    else begin
        $display("FAIL: Status register was overwritten! got %h", rd_data);
        fail_count = fail_count + 1;
    end

    // ── Test 6: Invalid address → SLVERR ───────────────────────────────────
    $display("=== Test 6: Invalid address ===");
    axi_write(32'h20, 32'hABCD_1234, 4'hF);
    if (s_axi_bresp === 2'b10)
        $display("PASS: SLVERR on invalid write address");
    else begin
        $display("FAIL: Expected SLVERR on write, got %b", s_axi_bresp);
        fail_count = fail_count + 1;
    end

    axi_read(32'h20, rd_data, rd_resp);
    if (rd_resp === 2'b10)
        $display("PASS: SLVERR on invalid read address");
    else begin
        $display("FAIL: Expected SLVERR on read, got %b", rd_resp);
        fail_count = fail_count + 1;
    end

    // ── Test 7: Back-to-back writes ────────────────────────────────────────
    $display("=== Test 7: Back-to-back writes ===");
    axi_write(32'h00, 32'h1111_1111, 4'hF);
    axi_write(32'h04, 32'h2222_2222, 4'hF);
    axi_write(32'h10, 32'h3333_3333, 4'hF);
    axi_read(32'h00, rd_data, rd_resp);
    if (rd_data === 32'h1111_1111)
        $display("PASS back-to-back [0x00]");
    else begin
        $display("FAIL back-to-back [0x00] got %h", rd_data);
        fail_count = fail_count + 1;
    end

    // ── Test 8: Byte-enable ────────────────────────────────────────────────
    $display("=== Test 8: Byte enable (wstrb=0xC => upper 2 bytes only) ===");
    axi_write(32'h00, 32'h0000_0000, 4'hF);
    axi_write(32'h00, 32'hAABB_CCDD, 4'hC);
    axi_read(32'h00, rd_data, rd_resp);
    if (rd_data[31:16] === 16'hAABB && rd_data[15:0] === 16'h0000)
        $display("PASS byte-enable: %h", rd_data);
    else begin
        $display("FAIL byte-enable: got %h", rd_data);
        fail_count = fail_count + 1;
    end

    // ── Summary ────────────────────────────────────────────────────────────
    repeat(4) @(posedge clk);
    if (fail_count == 0)
        $display("\n*** ALL TESTS PASSED ***");
    else
        $display("\n*** %0d TEST(S) FAILED ***", fail_count);

    $finish;
end
    end
end
// ── Waveform dump ──────────────────────────────────────────────────────────
initial begin
    $dumpfile("tb_axi4_lite_slave.vcd");
    $dumpvars(0, tb_axi4_lite_slave);
end

// ── Timeout watchdog ───────────────────────────────────────────────────────
initial begin
    #50000;
    $display("TIMEOUT — simulation took too long");
    $finish;
end

endmodule