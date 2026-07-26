`timescale 1ns/1ps

module tb_alignment_matrix;

    reg clk;
    reg rst_n;

    reg         s_start;
    reg  [1:0]  s_offset;
    reg  [31:0] s_length;
    reg  [31:0] s_tdata;
    reg         s_tvalid;
    reg         s_tlast;
    wire        s_tready;
    wire [31:0] s_data;
    wire [3:0]  s_strb;
    wire        s_valid;
    reg         s_ready;
    wire        s_done;
    wire        s_error;

    reg         m_start;
    reg  [1:0]  m_offset;
    reg  [31:0] m_length;
    reg  [31:0] m_raw_beats;
    reg  [31:0] m_data;
    reg         m_data_valid;
    wire        m_data_ready;
    wire [31:0] m_tdata;
    wire [3:0]  m_tkeep;
    wire        m_tvalid;
    reg         m_tready;
    wire        m_tlast;
    wire        m_done;

    reg [7:0] write_image [0:31];
    reg [7:0] read_image  [0:31];
    integer write_beat_index;
    integer mm2s_byte_index;
    integer fail_count;
    integer offset;
    integer length;
    integer i;
    integer lane;
    reg s_done_seen;
    reg m_done_seen;

    s2mm_datapath u_s2mm (
        .clk(clk),
        .rst_n(rst_n),
        .start(s_start),
        .dst_offset(s_offset),
        .transfer_len(s_length),
        .s_axis_tdata(s_tdata),
        .s_axis_tvalid(s_tvalid),
        .s_axis_tlast(s_tlast),
        .s_axis_tready(s_tready),
        .data(s_data),
        .data_strb(s_strb),
        .data_valid(s_valid),
        .data_ready(s_ready),
        .active(),
        .done(s_done),
        .error(s_error)
    );

    mm2s_datapath u_mm2s (
        .clk(clk),
        .rst_n(rst_n),
        .start(m_start),
        .src_offset(m_offset),
        .transfer_len(m_length),
        .raw_beats(m_raw_beats),
        .data(m_data),
        .data_valid(m_data_valid),
        .data_ready(m_data_ready),
        .m_axis_tdata(m_tdata),
        .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast),
        .active(),
        .done(m_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n) begin
            if (s_valid && s_ready) begin
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (s_strb[lane])
                        write_image[write_beat_index*4 + lane]
                            = s_data[lane*8 +: 8];
                write_beat_index = write_beat_index + 1;
            end
            if (s_done)
                s_done_seen = 1'b1;

            if (m_tvalid && m_tready) begin
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (m_tkeep[lane]) begin
                        if (m_tdata[lane*8 +: 8] !==
                            ((8'h40 + mm2s_byte_index) & 8'hFF)) begin
                            $display(
                                "FAIL MM2S offset=%0d len=%0d byte=%0d",
                                offset, length, mm2s_byte_index
                            );
                            fail_count = fail_count + 1;
                        end
                        mm2s_byte_index = mm2s_byte_index + 1;
                    end
                end
                if (m_tlast != (mm2s_byte_index == length)) begin
                    $display(
                        "FAIL MM2S TLAST offset=%0d len=%0d",
                        offset, length
                    );
                    fail_count = fail_count + 1;
                end
            end
            if (m_done)
                m_done_seen = 1'b1;
        end
    end

    task run_s2mm_case;
        input integer case_offset;
        input integer case_length;
        integer word_index;
        integer byte_index;
        integer expected_beats;
        reg [31:0] packed_word;
        begin
            offset = case_offset;
            length = case_length;
            write_beat_index = 0;
            s_done_seen = 1'b0;
            for (i = 0; i < 32; i = i + 1)
                write_image[i] = 8'hEE;

            @(negedge clk);
            s_offset = case_offset;
            s_length = case_length;
            s_start  = 1'b1;
            @(negedge clk);
            s_start = 1'b0;

            for (word_index = 0; word_index < ((case_length+3)/4);
                 word_index = word_index + 1) begin
                packed_word = 32'd0;
                for (byte_index = 0; byte_index < 4;
                     byte_index = byte_index + 1)
                    if ((word_index*4 + byte_index) < case_length)
                        packed_word[byte_index*8 +: 8] =
                            8'h20 + word_index*4 + byte_index;

                @(negedge clk);
                s_tdata  = packed_word;
                s_tvalid = 1'b1;
                s_tlast  =
                    (word_index == ((case_length+3)/4)-1);
                @(posedge clk);
                while (!s_tready)
                    @(posedge clk);
                @(negedge clk);
                s_tvalid = 1'b0;
                s_tlast  = 1'b0;
            end

            i = 0;
            while (!s_done_seen && i < 30) begin
                @(posedge clk);
                i = i + 1;
            end
            if (!s_done_seen || s_error) begin
                $display(
                    "FAIL S2MM completion offset=%0d len=%0d",
                    case_offset, case_length
                );
                fail_count = fail_count + 1;
            end

            expected_beats = (case_offset + case_length + 3) / 4;
            if (write_beat_index != expected_beats) begin
                $display(
                    "FAIL S2MM beats offset=%0d len=%0d got=%0d exp=%0d",
                    case_offset, case_length,
                    write_beat_index, expected_beats
                );
                fail_count = fail_count + 1;
            end

            for (i = 0; i < 32; i = i + 1) begin
                if (i >= case_offset &&
                    i < (case_offset + case_length)) begin
                    if (write_image[i] !==
                        ((8'h20 + i - case_offset) & 8'hFF)) begin
                        $display(
                            "FAIL S2MM offset=%0d len=%0d index=%0d",
                            case_offset, case_length, i
                        );
                        fail_count = fail_count + 1;
                    end
                end else if (write_image[i] !== 8'hEE) begin
                    $display(
                        "FAIL S2MM strobe offset=%0d len=%0d index=%0d",
                        case_offset, case_length, i
                    );
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    task run_mm2s_case;
        input integer case_offset;
        input integer case_length;
        integer raw_index;
        integer raw_count;
        reg [31:0] raw_word;
        begin
            offset = case_offset;
            length = case_length;
            mm2s_byte_index = 0;
            m_done_seen = 1'b0;
            raw_count = (case_offset + case_length + 3) / 4;

            for (i = 0; i < 32; i = i + 1)
                read_image[i] = 8'hCC;
            for (i = 0; i < case_length; i = i + 1)
                read_image[case_offset+i] = 8'h40 + i;

            @(negedge clk);
            m_offset    = case_offset;
            m_length    = case_length;
            m_raw_beats = raw_count;
            m_start     = 1'b1;
            @(negedge clk);
            m_start = 1'b0;

            for (raw_index = 0; raw_index < raw_count;
                 raw_index = raw_index + 1) begin
                raw_word = {
                    read_image[raw_index*4+3],
                    read_image[raw_index*4+2],
                    read_image[raw_index*4+1],
                    read_image[raw_index*4]
                };
                @(negedge clk);
                m_data       = raw_word;
                m_data_valid = 1'b1;
                @(posedge clk);
                while (!m_data_ready)
                    @(posedge clk);
                @(negedge clk);
                m_data_valid = 1'b0;
            end

            i = 0;
            while (!m_done_seen && i < 30) begin
                @(posedge clk);
                i = i + 1;
            end
            if (!m_done_seen || mm2s_byte_index != case_length) begin
                $display(
                    "FAIL MM2S completion offset=%0d len=%0d bytes=%0d",
                    case_offset, case_length, mm2s_byte_index
                );
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        rst_n       = 1'b0;
        s_start     = 1'b0;
        s_offset    = 0;
        s_length    = 0;
        s_tdata     = 0;
        s_tvalid    = 0;
        s_tlast     = 0;
        s_ready     = 1'b1;
        m_start     = 1'b0;
        m_offset    = 0;
        m_length    = 0;
        m_raw_beats = 0;
        m_data      = 0;
        m_data_valid = 0;
        m_tready    = 1'b1;
        fail_count  = 0;
        offset      = 0;
        length      = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        for (offset = 0; offset < 4; offset = offset + 1)
            for (length = 1; length <= 17; length = length + 1)
                run_s2mm_case(offset, length);

        for (offset = 0; offset < 4; offset = offset + 1)
            for (length = 1; length <= 17; length = length + 1)
                run_mm2s_case(offset, length);

        if (fail_count == 0)
            $display("PASS: alignment matrix (136 cases)");
        else
            $display("FAIL: alignment matrix errors=%0d", fail_count);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: alignment matrix watchdog timeout");
        $finish;
    end

endmodule
