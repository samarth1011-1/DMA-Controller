module s2mm_control_fsm #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter BURST_MAX   = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Control
    input  wire [31:0]            s2mm_ctrl,   // bit[0]=start
    input  wire [ADDR_WIDTH-1:0]  dst_addr,
    input  wire [31:0]            s2mm_len,    // bytes (must be multiple of 4)

    // FIFO (synchronous)
    input  wire                   fifo_empty,
    input  wire [4:0]             fifo_count,
    input  wire [DATA_WIDTH-1:0]  fifo_rdata,
    output reg                    fifo_rd_en,

    // AXI AW
    input  wire                   m_axi_awready,
    output reg                    m_axi_awvalid,
    output reg  [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output reg  [7:0]             m_axi_awlen,
    output wire [2:0]             m_axi_awsize,
    output wire [1:0]             m_axi_awburst,

    // AXI W
    input  wire                   m_axi_wready,
    output reg                    m_axi_wvalid,
    output reg  [DATA_WIDTH-1:0]  m_axi_wdata,
    output reg  [3:0]             m_axi_wstrb,
    output reg                    m_axi_wlast,

    // AXI B
    input  wire                   m_axi_bvalid,
    input  wire [1:0]             m_axi_bresp,
    output reg                    m_axi_bready,

    // Status
    output reg  [31:0]            s2mm_status, // [0]=busy [1]=done [2]=error
    output reg                    s2mm_done
);

    // =========================================================
    // AXI constants
    // =========================================================
    assign m_axi_awsize  = 3'b010; // 4 bytes
    assign m_axi_awburst = 2'b01;  // INCR

    // =========================================================
    // Start edge detection (pulse-safe + level-safe)
    // =========================================================
    reg start_d;
    wire start_edge = s2mm_ctrl[0] & ~start_d;

    always @(posedge clk) begin
        if (!rst_n)
            start_d <= 1'b0;
        else
            start_d <= s2mm_ctrl[0];
    end

    // =========================================================
    // FSM states
    // =========================================================
    localparam [2:0]
        IDLE         = 3'd0,
        WAIT_DATA    = 3'd1,
        WRITE_ADDR   = 3'd2,
        READ_FIFO    = 3'd3,
        CAPTURE_DATA = 3'd4,
        WRITE_DATA   = 3'd5,
        WRITE_RESP   = 3'd6,
        DONE         = 3'd7;

    reg [2:0] state;

    // =========================================================
    // Registers
    // =========================================================
    reg [ADDR_WIDTH-1:0] addr;
    reg [31:0]           bytes_remaining;
    reg [7:0]            burst_beats;
    reg [7:0]            beat_count;
    reg                  error_flag;

    // FIFO pipeline (for synchronous read)
    reg [DATA_WIDTH-1:0] data_reg;
    reg                  data_valid;

    // =========================================================
    // Helpers
    // =========================================================
    wire [31:0] words_remaining = bytes_remaining >> 2;

    wire [7:0] next_burst =
        (words_remaining >= BURST_MAX) ? BURST_MAX : words_remaining[7:0];

    wire fifo_ready = (fifo_count >= next_burst);

    // =========================================================
    // FSM
    // =========================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;

            m_axi_awvalid <= 0;
            m_axi_wvalid  <= 0;
            m_axi_bready  <= 0;

            m_axi_wlast   <= 0;
            m_axi_wstrb   <= 4'hF;

            fifo_rd_en    <= 0;
            data_valid    <= 0;

            s2mm_done     <= 0;
            s2mm_status   <= 0;

            error_flag    <= 0;
            bytes_remaining <= 0;
            beat_count    <= 0;
        end
        else begin
            // defaults
            fifo_rd_en <= 0;
            s2mm_done  <= 0;

            case (state)

            // =================================================
            IDLE: begin
                m_axi_awvalid <= 0;
                m_axi_wvalid  <= 0;
                m_axi_bready  <= 0;
                data_valid    <= 0;

                if (start_edge && s2mm_len != 0) begin
                    addr            <= dst_addr;
                    bytes_remaining <= s2mm_len;
                    error_flag      <= 0;

                    s2mm_status <= 32'd1; // busy
                    state <= WAIT_DATA;
                end
            end

            // =================================================
            WAIT_DATA: begin
                burst_beats <= next_burst;

                if (!fifo_empty && fifo_ready)
                    state <= WRITE_ADDR;
            end

            // =================================================
            WRITE_ADDR: begin
                m_axi_awvalid <= 1;
                m_axi_awaddr  <= addr;
                m_axi_awlen   <= burst_beats - 1;

                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 0;
                    beat_count <= 0;
                    data_valid <= 0;
                    state <= READ_FIFO;
                end
            end

            // =================================================
            READ_FIFO: begin
                m_axi_wvalid <= 0;
                m_axi_wlast  <= 0;

                if (!fifo_empty) begin
                    fifo_rd_en <= 1;
                    state <= CAPTURE_DATA;
                end
            end

            // =================================================
            CAPTURE_DATA: begin
                data_reg     <= fifo_rdata;
                m_axi_wdata  <= fifo_rdata;
                m_axi_wvalid <= 1;
                m_axi_wlast  <= (beat_count == burst_beats - 1);
                data_valid   <= 1;
                state <= WRITE_DATA;
            end

            // =================================================
            WRITE_DATA: begin
                if (m_axi_wvalid && m_axi_wready) begin
                    data_valid <= 0;
                    m_axi_wvalid <= 0;

                    beat_count <= beat_count + 1;
                    bytes_remaining <= bytes_remaining - 4;
                    addr <= addr + 4;

                    if (beat_count == burst_beats - 1) begin
                        m_axi_wlast <= 0;
                        state <= WRITE_RESP;
                    end
                    else begin
                        state <= READ_FIFO;
                    end
                end
            end

            // =================================================
            WRITE_RESP: begin
                m_axi_bready <= 1;

                if (m_axi_bvalid) begin
                    m_axi_bready <= 0;

                    if (m_axi_bresp != 2'b00)
                        error_flag <= 1;

                    if (bytes_remaining == 0 || m_axi_bresp != 2'b00)
                        state <= DONE;
                    else
                        state <= WAIT_DATA;
                end
            end

            // =================================================
            DONE: begin
                s2mm_done <= 1;
                s2mm_status <= {29'd0, error_flag, 1'b1, 1'b0};

                state <= IDLE;
            end

            endcase
        end
    end

endmodule
