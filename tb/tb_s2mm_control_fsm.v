`timescale 1ns/1ps

module tb_s2mm_control_fsm;

    localparam ADDR_WIDTH = 32;
    localparam BURST_MAX  = 8;

    reg                  clk;
    reg                  rst_n;
    reg  [31:0]          s2mm_ctrl;
    reg  [ADDR_WIDTH-1:0] dst_addr;
    reg  [31:0]          s2mm_len;
    wire                 cmd_valid;
    reg                  cmd_ready;
    wire [ADDR_WIDTH-1:0] cmd_addr;
    wire [7:0]           cmd_len;
    reg                  write_done;
    reg                  write_error;
    wire                 align_start;
    wire [1:0]           align_offset;
    wire [31:0]          align_length;
    reg                  align_error;
    wire [31:0]          s2mm_status;
    wire                 s2mm_done;

    integer cmd_count;
    integer align_count;
    integer fail_count;
    integer pass_count;
    integer cycles;
    reg [ADDR_WIDTH-1:0] captured_addr [0:7];
    reg [7:0]            captured_len  [0:7];
    reg [1:0]            captured_offset;
    reg [31:0]           captured_length;
    reg                  done_seen;
    reg [31:0]           done_status;

    s2mm_control_fsm #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_MAX(BURST_MAX)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s2mm_ctrl(s2mm_ctrl),
        .dst_addr(dst_addr),
        .s2mm_len(s2mm_len),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .write_done(write_done),
        .write_error(write_error),
        .align_start(align_start),
        .align_offset(align_offset),
        .align_length(align_length),
        .align_error(align_error),
        .s2mm_status(s2mm_status),
        .s2mm_done(s2mm_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            cmd_count       <= 0;
            align_count     <= 0;
            done_seen       <= 1'b0;
            done_status     <= 32'd0;
            captured_offset <= 2'd0;
            captured_length <= 32'd0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                captured_addr[cmd_count] <= cmd_addr;
                captured_len[cmd_count]  <= cmd_len;
                cmd_count <= cmd_count + 1;
            end

            if (align_start) begin
                captured_offset <= align_offset;
                captured_length <= align_length;
                align_count <= align_count + 1;
            end

            if (s2mm_done) begin
                done_seen   <= 1'b1;
                done_status <= s2mm_status;
            end
        end
    end

    task reset_dut;
        begin
            rst_n       = 1'b0;
            s2mm_ctrl   = 32'd0;
            dst_addr    = 32'd0;
            s2mm_len    = 32'd0;
            cmd_ready   = 1'b1;
            write_done  = 1'b0;
            write_error = 1'b0;
            align_error = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task pulse_start;
        input [31:0] address;
        input [31:0] length;
        begin
            @(negedge clk);
            dst_addr  = address;
            s2mm_len  = length;
            s2mm_ctrl = 32'd1;
            @(negedge clk);
            s2mm_ctrl = 32'd0;
        end
    endtask

    task pulse_write_done;
        input response_error;
        begin
            @(negedge clk);
            write_error = response_error;
            write_done  = 1'b1;
            @(negedge clk);
            write_done  = 1'b0;
            write_error = 1'b0;
        end
    endtask

    task wait_for_commands;
        input integer expected;
        begin
            cycles = 0;
            while (cmd_count < expected && cycles < 100) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    task wait_for_done;
        begin
            cycles = 0;
            while (!done_seen && cycles < 100) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    task report_case;
        input condition;
        input [8*40-1:0] name;
        begin
            if (condition) begin
                $display("PASS: %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display(
                    "FAIL: %0s commands=%0d align=%0d status=%h",
                    name, cmd_count, align_count, done_status
                );
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        reset_dut();
        pulse_start(32'h8000_0000, 32'd16);
        wait_for_commands(1);
        pulse_write_done(1'b0);
        wait_for_done();
        report_case(
            done_seen &&
            done_status[2:0] == 3'b010 &&
            cmd_count == 1 &&
            captured_addr[0] == 32'h8000_0000 &&
            captured_len[0] == 8'd3 &&
            align_count == 1 &&
            captured_offset == 2'd0 &&
            captured_length == 32'd16,
            "aligned single burst"
        );

        reset_dut();
        pulse_start(32'h9000_0003, 32'd35);
        wait_for_commands(1);
        pulse_write_done(1'b0);
        wait_for_commands(2);
        pulse_write_done(1'b0);
        wait_for_done();
        report_case(
            done_seen &&
            done_status[2:0] == 3'b010 &&
            cmd_count == 2 &&
            captured_addr[0] == 32'h9000_0000 &&
            captured_len[0] == 8'd7 &&
            captured_addr[1] == 32'h9000_0020 &&
            captured_len[1] == 8'd1 &&
            captured_offset == 2'd3 &&
            captured_length == 32'd35,
            "unaligned multi-burst"
        );

        reset_dut();
        pulse_start(32'h0000_0FFB, 32'd20);
        wait_for_commands(1);
        pulse_write_done(1'b0);
        wait_for_commands(2);
        pulse_write_done(1'b0);
        wait_for_done();
        report_case(
            done_seen &&
            done_status[2:0] == 3'b010 &&
            cmd_count == 2 &&
            captured_addr[0] == 32'h0000_0FF8 &&
            captured_len[0] == 8'd1 &&
            captured_addr[1] == 32'h0000_1000 &&
            captured_len[1] == 8'd3,
            "4KB boundary split"
        );

        reset_dut();
        pulse_start(32'hA000_0001, 32'd8);
        wait_for_commands(1);
        pulse_write_done(1'b1);
        wait_for_done();
        report_case(
            done_seen &&
            done_status[2:0] == 3'b110 &&
            cmd_count == 1,
            "write response error"
        );

        reset_dut();
        pulse_start(32'hB000_0002, 32'd9);
        wait_for_commands(1);
        align_error = 1'b1;
        pulse_write_done(1'b0);
        wait_for_done();
        report_case(
            done_seen &&
            done_status[2:0] == 3'b110 &&
            cmd_count == 1,
            "alignment error"
        );

        if (fail_count == 0)
            $display(
                "PASS: tb_s2mm_control_fsm (%0d cases)",
                pass_count
            );
        else
            $display(
                "FAIL: tb_s2mm_control_fsm errors=%0d",
                fail_count
            );
        $finish;
    end

    initial begin
        #50000;
        $display("FAIL: tb_s2mm_control_fsm watchdog timeout");
        $finish;
    end

endmodule
