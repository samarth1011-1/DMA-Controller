`timescale 1ns/1ps

module axi4_lite_slave (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire [31:0] mm2s_src_addr,
    output wire [31:0] mm2s_length,
    output wire [31:0] mm2s_control,
    output wire [31:0] s2mm_dst_addr,
    output wire [31:0] s2mm_length,
    output wire [31:0] s2mm_control,

    input  wire [31:0] mm2s_status,
    input  wire [31:0] s2mm_status
);

    reg [31:0] reg_mm2s_src_addr;
    reg [31:0] reg_mm2s_length;
    reg [31:0] reg_mm2s_control;
    reg [31:0] reg_s2mm_dst_addr;
    reg [31:0] reg_s2mm_length;
    reg [31:0] reg_s2mm_control;

    reg        aw_pending;
    reg [31:0] awaddr_reg;
    reg        w_pending;
    reg [31:0] wdata_reg;
    reg [3:0]  wstrb_reg;

    wire aw_accept = s_axi_awvalid && s_axi_awready;
    wire w_accept  = s_axi_wvalid  && s_axi_wready;
    wire have_aw   = aw_pending || aw_accept;
    wire have_w    = w_pending  || w_accept;
    wire [31:0] selected_awaddr = aw_pending ? awaddr_reg : s_axi_awaddr;
    wire [31:0] selected_wdata  = w_pending  ? wdata_reg  : s_axi_wdata;
    wire [3:0]  selected_wstrb  = w_pending  ? wstrb_reg  : s_axi_wstrb;
    wire write_address_valid =
        (selected_awaddr[31:5] == 27'd0) &&
        (selected_awaddr[1:0] == 2'b00);

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending  && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    assign mm2s_src_addr = reg_mm2s_src_addr;
    assign mm2s_length   = reg_mm2s_length;
    assign mm2s_control  = reg_mm2s_control;
    assign s2mm_dst_addr = reg_s2mm_dst_addr;
    assign s2mm_length   = reg_s2mm_length;
    assign s2mm_control  = reg_s2mm_control;

    task write_register;
        input [2:0]  address;
        input [31:0] data;
        input [3:0]  strobe;
        integer byte_index;
        begin
            case (address)
                3'b000:
                    for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                        if (strobe[byte_index])
                            reg_mm2s_src_addr[byte_index*8 +: 8]
                                <= data[byte_index*8 +: 8];
                3'b001:
                    for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                        if (strobe[byte_index])
                            reg_mm2s_length[byte_index*8 +: 8]
                                <= data[byte_index*8 +: 8];
                3'b010:
                    if (strobe[0])
                        reg_mm2s_control <= {30'd0, data[1:0]};
                3'b100:
                    for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                        if (strobe[byte_index])
                            reg_s2mm_dst_addr[byte_index*8 +: 8]
                                <= data[byte_index*8 +: 8];
                3'b101:
                    for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                        if (strobe[byte_index])
                            reg_s2mm_length[byte_index*8 +: 8]
                                <= data[byte_index*8 +: 8];
                3'b110:
                    if (strobe[0])
                        reg_s2mm_control <= {30'd0, data[1:0]};
                default: begin end
            endcase
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_mm2s_src_addr <= 32'd0;
            reg_mm2s_length   <= 32'd0;
            reg_mm2s_control  <= 32'd0;
            reg_s2mm_dst_addr <= 32'd0;
            reg_s2mm_length   <= 32'd0;
            reg_s2mm_control  <= 32'd0;

            aw_pending <= 1'b0;
            awaddr_reg <= 32'd0;
            w_pending  <= 1'b0;
            wdata_reg  <= 32'd0;
            wstrb_reg  <= 4'd0;
            s_axi_bresp  <= 2'b00;
            s_axi_bvalid <= 1'b0;
        end else begin
            // Control writes are one-cycle command pulses.
            reg_mm2s_control <= 32'd0;
            reg_s2mm_control <= 32'd0;

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (!s_axi_bvalid) begin
                if (have_aw && have_w) begin
                    s_axi_bresp  <= write_address_valid ? 2'b00 : 2'b10;
                    s_axi_bvalid <= 1'b1;
                    aw_pending   <= 1'b0;
                    w_pending    <= 1'b0;
                    if (write_address_valid)
                        write_register(
                            selected_awaddr[4:2],
                            selected_wdata,
                            selected_wstrb
                        );
                end else begin
                    if (aw_accept) begin
                        aw_pending <= 1'b1;
                        awaddr_reg <= s_axi_awaddr;
                    end
                    if (w_accept) begin
                        w_pending <= 1'b1;
                        wdata_reg <= s_axi_wdata;
                        wstrb_reg <= s_axi_wstrb;
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rdata  <= 32'd0;
            s_axi_rresp  <= 2'b00;
            s_axi_rvalid <= 1'b0;
        end else begin
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                if ((s_axi_araddr[31:5] != 27'd0) ||
                    (s_axi_araddr[1:0] != 2'b00)) begin
                    s_axi_rresp <= 2'b10;
                    s_axi_rdata <= 32'hDEAD_BEEF;
                end else begin
                    s_axi_rresp <= 2'b00;
                    case (s_axi_araddr[4:2])
                        3'b000: s_axi_rdata <= reg_mm2s_src_addr;
                        3'b001: s_axi_rdata <= reg_mm2s_length;
                        3'b010: s_axi_rdata <= {30'd0, reg_mm2s_control[1:0]};
                        3'b011: s_axi_rdata <= {29'd0, mm2s_status[2:0]};
                        3'b100: s_axi_rdata <= reg_s2mm_dst_addr;
                        3'b101: s_axi_rdata <= reg_s2mm_length;
                        3'b110: s_axi_rdata <= {30'd0, reg_s2mm_control[1:0]};
                        3'b111: s_axi_rdata <= {29'd0, s2mm_status[2:0]};
                    endcase
                end
            end
        end
    end

endmodule
