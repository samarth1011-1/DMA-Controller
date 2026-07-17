module axi4_full_write_master #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,

    // Burst command. cmd_len uses AXI AWLEN encoding--> beats-1
    input wire cmd_valid,
    output wire cmd_ready,
    input wire [ADDR_WIDTH-1:0] cmd_addr,
    input wire [7:0] cmd_len,

    // Write-data stream
    input wire [DATA_WIDTH-1:0] data,
    input wire [(DATA_WIDTH/8)-1:0] data_strb,
    input wire data_valid,
    output wire data_ready,

    // Command status
    output wire busy,
    output reg done,
    output reg error,

    // AXI4-Full write address channel
    output wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,

    // AXI4-Full write data channel
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [(DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input  wire m_axi_wready,

    // AXI4-FUll write response channel
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);

    localparam [1:0]IDLE = 2'd0,WRITE_ADDR = 2'd1,WRITE_DATA = 2'd2,WRITE_RESP = 2'd3;

    localparam integer BYTE_WIDTH =DATA_WIDTH / 8;
    localparam [2:0] AXI_SIZE =$clog2(BYTE_WIDTH);

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [7:0] len_reg;
    reg [7:0] beat_count;

    assign cmd_ready = (state == IDLE);
    assign busy = (state != IDLE);

    assign m_axi_awaddr = addr_reg;
    assign m_axi_awlen = len_reg;
    assign m_axi_awsize =AXI_SIZE;
    assign m_axi_awburst =2'b01;
    assign m_axi_awvalid = (state == WRITE_ADDR);

    assign m_axi_wdata = data;
    assign m_axi_wstrb = data_strb;
    assign m_axi_wvalid = (state == WRITE_DATA) && data_valid;
    assign m_axi_wlast = (state == WRITE_DATA) && (beat_count == len_reg);
    assign data_ready =(state == WRITE_DATA) && m_axi_wready;

    assign m_axi_bready = (state == WRITE_RESP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            addr_reg <= {ADDR_WIDTH{1'b0}};
            len_reg <= 8'd0;
            beat_count <= 8'd0;
            done <= 1'b0;
            error <= 1'b0;
        end else begin
            done <= 1'b0;
            error <= 1'b0;

            case (state)
                IDLE: begin
                    if (cmd_valid && cmd_ready) begin
                        addr_reg <= cmd_addr;
                        len_reg <= cmd_len;
                        beat_count <= 8'd0;
                        state <= WRITE_ADDR;
                    end
                end

                WRITE_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) state <= WRITE_DATA;
                end

                WRITE_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (beat_count == len_reg) state <= WRITE_RESP;
                        else beat_count <= beat_count + 1'b1;
                    end
                end

                WRITE_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        done <= 1'b1;
                        error <= (m_axi_bresp != 2'b00);
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
