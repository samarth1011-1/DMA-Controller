module fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 16
)(
    input wire clk,
    input wire rst_n, // active low reset
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] wr_data,
    input wire rd_en,
    output reg [DATA_WIDTH-1:0] rd_data,
    output reg full,
    output reg empty,
    output [$clog2(DEPTH+1)-1:0]  count
);
    localparam PTR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0] wr_ptr, rd_ptr;
    reg [$clog2(DEPTH+1)-1:0] cnt;

    wire do_write = wr_en && !full;
    wire do_read = rd_en && !empty;

    always @(posedge clk) begin
        if (!rst_n) begin 
            wr_ptr <= 0;rd_ptr <= 0;cnt <= 0;
            full <= 0; empty <=1;
            rd_data <=0;
        end else begin
            if (do_write) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end
            if (do_read) begin
                rd_data <= mem[rd_ptr];
                rd_ptr  <= rd_ptr + 1;
            end
            case ({do_write, do_read})
                2'b10: cnt <= cnt+1;
                2'b01: cnt <= cnt-1;
                default: cnt <= cnt;
            endcase
            full <= (cnt + do_write - do_read) == DEPTH;
            empty <= (cnt + do_write - do_read) == 0;
        end
    end
    assign count = cnt;
endmodule