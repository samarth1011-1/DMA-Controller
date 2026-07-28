`timescale 1ns/1ps

module tb_s2mm_datapath;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [1:0]  dst_offset;
    reg  [31:0] transfer_len;
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    wire        s_axis_tready;
    wire [31:0] data;
    wire [3:0]  data_strb;
    wire        data_valid;
    reg         data_ready;
    wire        active;
    wire        done;
    wire        error;

    reg [7:0] write_image [0:63];
    integer beat_count;
    integer fail_count;
    integer pass_count;
    integer lane;
    integer i;
    reg done_seen;

    s2mm_datapath dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .dst_offset(dst_offset),
        .transfer_len(transfer_len),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .data(data),
        .data_strb(data_strb),
        .data_valid(data_valid),
        .data_ready(data_ready),
        .active(active),
        .done(done),
        .error(error)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            beat_count <= 0;
            done_seen  <= 1'b0;
        end else begin
            if (data_valid && data_ready) begin
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (data_strb[lane])
                        write_image[beat_count*4 + lane]
                            <= data[lane*8 +: 8];
                beat_count <= beat_count + 1;
            end

            if (done)
                done_seen <= 1'b1;
        end
    end

    task reset_dut;
        begin
            rst_n         = 1'b0;
            start         = 1'b0;
            dst_offset    = 2'd0;
            transfer_len  = 32'd0;
            s_axis_tdata  = 32'd0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            data_ready    = 1'b1;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task pulse_start;
        input [1:0]  offset;
        input [31:0] length;
        begin
            @(negedge clk);
            dst_offset   = offset;
            transfer_len = length;
            start        = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task send_word;
        input [31:0] word_data;
        input        word_last;
        begin
            @(negedge clk);
            s_axis_tdata  = word_data;
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = word_last;
            @(posedge clk);
            while (!s_axis_tready)
                @(posedge clk);
            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    task wait_for_done;
        integer cycles;
        begin
            cycles = 0;
            while (!done_seen && cycles < 100) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    task run_case;
        input integer case_offset;
        input integer case_length;
        input         insert_backpressure;
        integer word_index;
        integer byte_index;
        integer input_words;
        integer expected_beats;
        integer case_errors;
        reg [31:0] packed_word;
        begin
            reset_dut();
            for (i = 0; i < 64; i = i + 1)
                write_image[i] = 8'hEE;

            pulse_start(case_offset[1:0], case_length);

            if (insert_backpressure) begin
                data_ready = 1'b0;
                repeat (3) @(posedge clk);
                if (s_axis_tready !== 1'b0) begin
                    $display(
                        "FAIL: TREADY ignored downstream backpressure"
                    );
                    fail_count = fail_count + 1;
                end
                data_ready = 1'b1;
            end

            input_words = (case_length + 3) / 4;
            for (word_index = 0; word_index < input_words;
                 word_index = word_index + 1) begin
                packed_word = 32'd0;
                for (byte_index = 0; byte_index < 4;
                     byte_index = byte_index + 1)
                    if ((word_index*4 + byte_index) < case_length)
                        packed_word[byte_index*8 +: 8] =
                            8'h20 + word_index*4 + byte_index;

                send_word(
                    packed_word,
                    word_index == input_words - 1
                );
            end

            wait_for_done();
            case_errors = 0;
            expected_beats = (case_offset + case_length + 3) / 4;

            if (!done_seen || active || error) begin
                $display(
                    "FAIL: completion offset=%0d length=%0d done=%0d active=%0d error=%0d",
                    case_offset, case_length, done_seen, active, error
                );
                case_errors = case_errors + 1;
            end

            if (beat_count != expected_beats) begin
                $display(
                    "FAIL: beat count offset=%0d length=%0d got=%0d expected=%0d",
                    case_offset, case_length, beat_count, expected_beats
                );
                case_errors = case_errors + 1;
            end

            for (i = 0; i < 64; i = i + 1) begin
                if (i >= case_offset &&
                    i < case_offset + case_length) begin
                    if (write_image[i] !==
                        ((8'h20 + i - case_offset) & 8'hFF)) begin
                        $display(
                            "FAIL: data offset=%0d length=%0d byte=%0d got=%02h",
                            case_offset, case_length, i, write_image[i]
                        );
                        case_errors = case_errors + 1;
                    end
                end else if (write_image[i] !== 8'hEE) begin
                    $display(
                        "FAIL: strobe offset=%0d length=%0d byte=%0d",
                        case_offset, case_length, i
                    );
                    case_errors = case_errors + 1;
                end
            end

            if (case_errors == 0) begin
                $display(
                    "PASS: S2MM datapath offset=%0d length=%0d",
                    case_offset, case_length
                );
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + case_errors;
            end
        end
    endtask

    task run_tlast_error_case;
        begin
            reset_dut();
            pulse_start(2'd0, 32'd8);
            send_word(32'h4433_2211, 1'b1);
            send_word(32'h8877_6655, 1'b1);
            wait_for_done();

            if (done_seen && error) begin
                $display("PASS: early TLAST detected");
                pass_count = pass_count + 1;
            end else begin
                $display(
                    "FAIL: early TLAST not detected done=%0d error=%0d",
                    done_seen, error
                );
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        fail_count = 0;
        pass_count = 0;

        run_case(0, 16, 1'b0);
        run_case(1, 1,  1'b0);
        run_case(2, 7,  1'b0);
        run_case(3, 17, 1'b0);
        run_case(3, 5,  1'b1);
        run_tlast_error_case();

        if (fail_count == 0)
            $display(
                "PASS: tb_s2mm_datapath (%0d cases)",
                pass_count
            );
        else
            $display(
                "FAIL: tb_s2mm_datapath errors=%0d",
                fail_count
            );
        $finish;
    end

    initial begin
        #50000;
        $display("FAIL: tb_s2mm_datapath watchdog timeout");
        $finish;
    end

endmodule
