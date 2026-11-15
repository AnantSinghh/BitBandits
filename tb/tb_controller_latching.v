`timescale 1ns / 1ps

module tb_controller_latching;

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
    reg comp_hit;
    reg comp_miss;

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

    initial begin
        clk = 0;
        rst = 1;
        cpu_req_valid = 0;
        cpu_req_addr = 32'h0;
        storage_read_valid = 0;
        storage_read_tag = 22'h0;
        storage_read_data = 128'h0;
        comp_hit = 0;
        comp_miss = 1;
        mem_req_ready = 0;
        mem_data = 128'h0;

        #20;
        rst = 0;
        #10;

        // Verify IDLE and cpu_ready
        if (cpu_ready !== 1'b1 || fsm_state !== 3'b000) begin
            $display("[FAIL] Controller not in IDLE or cpu_ready != 1 after reset");
            $finish;
        end else begin
            $display("[PASS] Reset verified: Controller in IDLE, cpu_ready = 1");
        end

        // Issue request
        cpu_req_valid = 1;
        cpu_req_addr = 32'h1234_5678; // tag = 22'h048D15, index = 6'h27, offset = 4'h8
        #10;
        cpu_req_valid = 0;
        cpu_req_addr = 32'hDEAD_BEEF; // Change immediately to ensure address was latched

        // Controller should now be in LOOKUP (state 1) and cpu_ready must be 0
        if (fsm_state === 3'b001 && cpu_ready === 1'b0) begin
            $display("[PASS] State transitioned to LOOKUP, cpu_ready deasserted (busy)");
        end else begin
            $display("[FAIL] Expected LOOKUP and busy, got state=%b, ready=%b", fsm_state, cpu_ready);
            $finish;
        end

        // Check if latched tag was routed to comparator
        if (comp_req_tag === 22'h048D15) begin
            $display("[PASS] Request address correctly latched: comp_req_tag matches 22'h048D15");
        end else begin
            $display("[FAIL] Latched tag mismatch: expected 22'h048D15, got %h", comp_req_tag);
            $finish;
        end

        $display("[ALL TESTS PASSED for Request Latching]");
        $finish;
    end

endmodule
