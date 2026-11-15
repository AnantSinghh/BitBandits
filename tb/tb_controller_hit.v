`timescale 1ns / 1ps

module tb_controller_hit;

    reg clk;
    reg rst;
    reg cpu_req_valid;
    reg [31:0] cpu_req_addr;
    wire cpu_ready;
    wire cpu_resp_valid;
    wire [31:0] cpu_resp_data;

    wire [5:0] storage_read_index;
    reg storage_read_valid;
    reg [21:0] storage_read_tag;
    reg [127:0] storage_read_data;

    wire storage_write_en;
    wire [5:0] storage_write_index;
    wire [21:0] storage_write_tag;
    wire [127:0] storage_write_data;
    wire storage_write_valid;

    wire [21:0] comp_stored_tag;
    wire [21:0] comp_req_tag;
    wire comp_stored_valid;
    wire comp_hit;
    wire comp_miss;

    // Instantiate Ronit's actual tag_comparator
    tag_comparator #(
        .TAG_WIDTH(22)
    ) u_comp (
        .tag_stored(comp_stored_tag),
        .tag_req(comp_req_tag),
        .valid_stored(comp_stored_valid),
        .hit(comp_hit),
        .miss(comp_miss)
    );

    wire mem_req;
    wire [31:0] mem_addr;
    reg mem_req_ready;
    reg [127:0] mem_data;

    wire [2:0] fsm_state;
    wire cache_hit_flag;
    wire cache_miss_flag;

    cache_controller uut (
        .clk(clk),
        .rst(rst),
        .cpu_req_valid(cpu_req_valid),
        .cpu_req_addr(cpu_req_addr),
        .cpu_ready(cpu_ready),
        .cpu_resp_valid(cpu_resp_valid),
        .cpu_resp_data(cpu_resp_data),
        .storage_read_index(storage_read_index),
        .storage_read_valid(storage_read_valid),
        .storage_read_tag(storage_read_tag),
        .storage_read_data(storage_read_data),
        .storage_write_en(storage_write_en),
        .storage_write_index(storage_write_index),
        .storage_write_tag(storage_write_tag),
        .storage_write_data(storage_write_data),
        .storage_write_valid(storage_write_valid),
        .comp_stored_tag(comp_stored_tag),
        .comp_req_tag(comp_req_tag),
        .comp_stored_valid(comp_stored_valid),
        .comp_hit(comp_hit),
        .comp_miss(comp_miss),
        .mem_req(mem_req),
        .mem_addr(mem_addr),
        .mem_req_ready(mem_req_ready),
        .mem_data(mem_data),
        .fsm_state(fsm_state),
        .cache_hit_flag(cache_hit_flag),
        .cache_miss_flag(cache_miss_flag)
    );

    always #5 clk = ~clk;

    // Test block: 4 distinct words
    // Word 0 = 32'hAAAA_0000
    // Word 1 = 32'hBBBB_1111
    // Word 2 = 32'hCCCC_2222
    // Word 3 = 32'hDDDD_3333
    localparam [127:0] TEST_BLOCK = {32'hDDDD_3333, 32'hCCCC_2222, 32'hBBBB_1111, 32'hAAAA_0000};

    task test_hit;
        input [1:0] word_sel;
        input [31:0] expected_word;
        begin
            @(posedge clk);
            while (!cpu_ready) @(posedge clk);

            // Present valid cache line matching requested tag
            storage_read_valid = 1'b1;
            storage_read_tag   = 22'h102030 >> 10;
            storage_read_data  = TEST_BLOCK;

            // Issue request
            cpu_req_valid = 1'b1;
            cpu_req_addr  = {22'h102030 >> 10, 6'd5, word_sel, 2'b00};
            @(posedge clk);
            cpu_req_valid = 1'b0;

            // Wait for RESPOND
            while (!cpu_resp_valid) @(posedge clk);

            if (cpu_resp_data === expected_word) begin
                $display("[PASS] Hit test for word_sel=%b: received %h matching expected %h",
                         word_sel, cpu_resp_data, expected_word);
            end else begin
                $display("[FAIL] Hit test for word_sel=%b: expected %h, got %h",
                         word_sel, expected_word, cpu_resp_data);
                $finish;
            end
        end
    endtask

    initial begin
        $monitor("Time=%0t state=%b req_valid=%b req_addr=%h ready=%b resp_valid=%b comp_hit=%b stored_valid=%b",
                 $time, fsm_state, cpu_req_valid, cpu_req_addr, cpu_ready, cpu_resp_valid, comp_hit, storage_read_valid);
    end

    initial begin
        clk = 0;
        rst = 1;
        cpu_req_valid = 0;
        cpu_req_addr = 0;
        storage_read_valid = 0;
        storage_read_tag = 0;
        storage_read_data = 0;
        mem_req_ready = 0;
        mem_data = 0;

        #20;
        rst = 0;
        #10;

        // Test words 0, 1, 2, 3 on hit
        test_hit(2'b00, 32'hAAAA_0000);
        test_hit(2'b01, 32'hBBBB_1111);
        test_hit(2'b10, 32'hCCCC_2222);
        test_hit(2'b11, 32'hDDDD_3333);

        // Test false hit prevention when valid=0
        @(posedge clk);
        while (!cpu_ready) @(posedge clk);
        storage_read_valid = 1'b0; // INVALID
        storage_read_tag   = 22'h102030 >> 10; // Tag matches, but valid is 0!
        storage_read_data  = TEST_BLOCK;
        cpu_req_valid = 1'b1;
        cpu_req_addr  = {22'h102030 >> 10, 6'd5, 2'b00, 2'b00};
        @(posedge clk);
        cpu_req_valid = 1'b0;
        @(posedge clk);
        #1; // Allow registered state to settle

        // Must transition to MEM_REQUEST (state 2), NOT RESPOND!
        if (fsm_state === 3'b010) begin
            $display("[PASS] False hit prevented: valid=0 correctly identified as MISS (MEM_REQUEST state)");
        end else begin
            $display("[FAIL] False hit occurred with valid=0! State = %b", fsm_state);
            $finish;
        end

        $display("[ALL HIT TESTS PASSED]");
        $finish;
    end

endmodule
