`timescale 1ns / 1ps

module tb_controller_miss;

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

    // Instantiate Ronit's tag_comparator
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

    localparam [127:0] MEMORY_RETURN_BLOCK = {32'hDEAD_3333, 32'hCAFE_2222, 32'hBEEF_1111, 32'h1234_0000};

    initial begin
        clk = 0;
        rst = 1;
        cpu_req_valid = 0;
        cpu_req_addr = 0;
        storage_read_valid = 0; // Unpopulated cache line
        storage_read_tag = 0;
        storage_read_data = 0;
        mem_req_ready = 0;
        mem_data = 0;

        #20;
        rst = 0;
        #10;

        // Issue CPU request with non-aligned offset 4'hC on falling edge
        @(negedge clk);
        cpu_req_valid = 1;
        cpu_req_addr  = 32'hA123_456C;
        @(negedge clk);
        cpu_req_valid = 0;

        // In LOOKUP: valid=0 means MISS
        @(posedge clk);
        #1;
        if (fsm_state !== 3'b010) begin // S_MEM_REQUEST
            $display("[FAIL] Expected S_MEM_REQUEST (state 2), got state=%b", fsm_state);
            $finish;
        end

        // Check block-aligned memory address and single mem_req pulse
        if (mem_req !== 1'b1) begin
            $display("[FAIL] mem_req not asserted in MEM_REQUEST!");
            $finish;
        end
        if (mem_addr !== 32'hA123_4560) begin
            $display("[FAIL] Block alignment failed! Expected 32'hA123_4560, got %h", mem_addr);
            $finish;
        end else begin
            $display("[PASS] MEM_REQUEST: mem_req asserted with block-aligned address %h", mem_addr);
        end

        // Next cycle: must transition to MEM_WAIT and mem_req must be deasserted
        @(posedge clk);
        #1;
        if (fsm_state !== 3'b011) begin // S_MEM_WAIT
            $display("[FAIL] Expected S_MEM_WAIT (state 3), got state=%b", fsm_state);
            $finish;
        end
        if (mem_req !== 1'b0) begin
            $display("[FAIL] mem_req still asserted in MEM_WAIT! Protocol violation (repeated requests)");
            $finish;
        end else begin
            $display("[PASS] MEM_WAIT: entered, mem_req cleanly deasserted to 0");
        end

        // Simulate multi-cycle memory latency (wait 3 cycles)
        repeat (3) begin
            @(posedge clk);
            #1;
            if (fsm_state !== 3'b011) begin
                $display("[FAIL] FSM did not remain in MEM_WAIT during latency! state=%b", fsm_state);
                $finish;
            end
        end
        $display("[PASS] Controller held stably in MEM_WAIT during latency");

        // Now memory asserts mem_req_ready with data
        mem_data = MEMORY_RETURN_BLOCK;
        mem_req_ready = 1'b1;
        @(posedge clk);
        #1;
        mem_req_ready = 1'b0;

        // FSM must transition to REFILL
        if (fsm_state === 3'b100) begin
            $display("[PASS] Memory handshake complete: transitioned from MEM_WAIT to REFILL (state 4)");
        end else begin
            $display("[FAIL] Expected REFILL (state 4), got state=%b", fsm_state);
            $finish;
        end

        $display("[ALL MEMORY MISS PATH TESTS PASSED]");
        $finish;
    end

endmodule
