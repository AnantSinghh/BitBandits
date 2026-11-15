`timescale 1ns / 1ps

module tb_controller_refill;

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

    localparam [127:0] REFILL_BLOCK = {32'hFEED_3333, 32'hFACE_2222, 32'hBABE_1111, 32'hCAFE_0000};

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

        // Request address with word_sel = 2'b10 (Word 2 -> 32'hFACE_2222)
        // tag = 22'h1ABCDE, index = 6'd12, offset = 4'h8 (word_sel = 2'b10)
        @(negedge clk);
        cpu_req_valid = 1;
        cpu_req_addr  = {22'h1ABCDE, 6'd12, 2'b10, 2'b00};
        @(negedge clk);
        cpu_req_valid = 0;

        // Controller moved IDLE -> LOOKUP at first posedge
        // Next posedge moves LOOKUP -> MEM_REQUEST (on miss)
        @(posedge clk);
        #1;
        if (fsm_state !== 3'b010) begin
            $display("[FAIL] Expected MEM_REQUEST, got state=%b", fsm_state);
            $finish;
        end

        // Transitions to MEM_WAIT
        @(posedge clk); // to MEM_WAIT
        #1;
        if (fsm_state !== 3'b011) begin
            $display("[FAIL] Expected MEM_WAIT, got state=%b", fsm_state);
            $finish;
        end

        // Memory responds with 128-bit block
        @(negedge clk);
        mem_req_ready = 1'b1;
        mem_data      = REFILL_BLOCK;

        @(posedge clk); // Transitions to REFILL
        #1;
        mem_req_ready = 1'b0;

        if (fsm_state !== 3'b100) begin // S_REFILL
            $display("[FAIL] Expected REFILL, got state=%b", fsm_state);
            $finish;
        end

        // Verify storage write control signals during REFILL
        if (storage_write_en !== 1'b1 || storage_write_valid !== 1'b1) begin
            $display("[FAIL] Storage write controls not asserted during REFILL! en=%b, valid=%b",
                     storage_write_en, storage_write_valid);
            $finish;
        end
        if (storage_write_index !== 6'd12 || storage_write_tag !== 22'h1ABCDE) begin
            $display("[FAIL] Storage write address mismatch! index=%d, tag=%h",
                     storage_write_index, storage_write_tag);
            $finish;
        end
        if (storage_write_data !== REFILL_BLOCK) begin
            $display("[FAIL] Storage write data mismatch!");
            $finish;
        end
        $display("[PASS] REFILL state: storage write signals verified accurately");

        // Clock edge to RESPOND
        @(posedge clk);
        #1;
        if (fsm_state !== 3'b101) begin // S_RESPOND
            $display("[FAIL] Expected RESPOND, got state=%b", fsm_state);
            $finish;
        end

        // Verify CPU response
        if (cpu_resp_valid !== 1'b1) begin
            $display("[FAIL] cpu_resp_valid not asserted in RESPOND!");
            $finish;
        end
        if (cpu_resp_data !== 32'hFACE_2222) begin
            $display("[FAIL] Word selection failed! Expected 32'hFACE_2222, got %h", cpu_resp_data);
            $finish;
        end else begin
            $display("[PASS] RESPOND state: cpu_resp_valid=1, word 2 correct: %h", cpu_resp_data);
        end

        // Clock edge to IDLE
        @(posedge clk);
        #1;
        if (fsm_state !== 3'b000 || cpu_ready !== 1'b1 || cpu_resp_valid !== 1'b0) begin
            $display("[FAIL] Return to IDLE failed! state=%b, ready=%b, resp_valid=%b",
                     fsm_state, cpu_ready, cpu_resp_valid);
            $finish;
        end else begin
            $display("[PASS] Return to IDLE verified: controller is ready for consecutive requests");
        end

        $display("[ALL REFILL AND RESPONSE PATH TESTS PASSED]");
        $finish;
    end

endmodule
