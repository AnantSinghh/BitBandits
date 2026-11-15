// =============================================================================
// File:        tb_cache_top.sv
// Author:      Anant (Senior Hardware Verification Engineer)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Comprehensive SystemVerilog self-checking testbench for top-level
//              direct-mapped cache controller subsystem:
//              - Clock and reset generation
//              - CPU request driver & handshake monitor
//              - Independent reference memory model
//              - Independent golden cache state tracking
//              - Hit/Miss detection and cycle latency measurement
//              - SystemVerilog assertion checks
//              - Functional coverage tracking & reporting
// =============================================================================

`timescale 1ns / 1ps

module tb_cache_top;

    // Cache & Architectural Parameters
    localparam int ADDR_WIDTH   = 32;
    localparam int DATA_WIDTH   = 32;
    localparam int BLOCK_WIDTH  = 128;
    localparam int TAG_WIDTH    = 22;
    localparam int INDEX_WIDTH  = 6;
    localparam int OFFSET_WIDTH = 4;
    localparam int NUM_LINES    = 64;
    localparam int MEM_LATENCY  = 2;

    // Clock and Reset
    logic clk;
    logic rst;

    // CPU Interface Signals
    logic                  cpu_req_valid;
    logic [ADDR_WIDTH-1:0] cpu_req_addr;
    wire                   cpu_ready;
    wire                   cpu_resp_valid;
    wire  [DATA_WIDTH-1:0] cpu_resp_data;

    // Status / Observability Signals
    wire  [2:0]            fsm_state;
    wire                   cache_hit;
    wire                   cache_miss;

    // Verification Bookkeeping
    int total_tests    = 0;
    int passed_tests   = 0;
    int failed_tests   = 0;

    int total_requests = 0;
    int hit_count      = 0;
    int miss_count     = 0;
    int comp_miss_cnt  = 0;
    int conf_miss_cnt  = 0;

    // Flag monitors during LOOKUP state
    logic saw_hit;
    logic saw_miss;

    // =========================================================================
    // Independent Reference Memory Model
    // Deterministic address-based pattern matching Anant's main_memory model:
    //   w0 = { block_addr[31:4], 4'h0, 12'hA01 }
    //   w1 = { block_addr[31:4], 4'h4, 12'hB02 }
    //   w2 = { block_addr[31:4], 4'h8, 12'hC03 }
    //   w3 = { block_addr[31:4], 4'hC, 12'hD04 }
    // =========================================================================
    function automatic [31:0] ref_mem_word(input [31:0] addr);
        logic [1:0]  w_sel;
        logic [31:0] b_addr;
        begin
            b_addr = {addr[31:4], 4'h0};
            w_sel  = addr[3:2];
            case (w_sel)
                2'b00: ref_mem_word = {b_addr[31:4], 4'h0, 12'hA01};
                2'b01: ref_mem_word = {b_addr[31:4], 4'h4, 12'hB02};
                2'b10: ref_mem_word = {b_addr[31:4], 4'h8, 12'hC03};
                2'b11: ref_mem_word = {b_addr[31:4], 4'hC, 12'hD04};
            endcase
        end
    endfunction

    // =========================================================================
    // Independent Reference Cache State Model
    // Tracks valid bits and tags to independently predict hits and misses
    // =========================================================================
    bit                   ref_valid [NUM_LINES];
    logic [TAG_WIDTH-1:0] ref_tag   [NUM_LINES];

    function automatic bit predict_hit(input [31:0] addr);
        logic [INDEX_WIDTH-1:0] idx;
        logic [TAG_WIDTH-1:0]   tag_val;
        begin
            idx     = addr[9:4];
            tag_val = addr[31:10];
            predict_hit = (ref_valid[idx] && (ref_tag[idx] == tag_val));
        end
    endfunction

    task automatic reset_ref_cache();
        begin
            for (int i = 0; i < NUM_LINES; i++) begin
                ref_valid[i] = 1'b0;
                ref_tag[i]   = '0;
            end
        end
    endtask

    task automatic update_ref_cache(input [31:0] addr);
        logic [INDEX_WIDTH-1:0] idx;
        logic [TAG_WIDTH-1:0]   tag_val;
        begin
            idx     = addr[9:4];
            tag_val = addr[31:10];
            ref_valid[idx] = 1'b1;
            ref_tag[idx]   = tag_val;
        end
    endtask

    // =========================================================================
    // Clock Generation: 100 MHz (10ns clock period)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // Monitor hit/miss outputs during S_LOOKUP state (3'b001)
    always @(posedge clk) begin
        if (fsm_state == 3'b001) begin
            if (cache_hit)  saw_hit  <= 1'b1;
            if (cache_miss) saw_miss <= 1'b1;
        end
    end

    // =========================================================================
    // Device Under Test (DUT) Instantiation
    // =========================================================================
    cache_top #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .BLOCK_WIDTH  (BLOCK_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .OFFSET_WIDTH (OFFSET_WIDTH),
        .NUM_LINES    (NUM_LINES),
        .MEM_LATENCY  (MEM_LATENCY)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .cpu_req_valid  (cpu_req_valid),
        .cpu_req_addr   (cpu_req_addr),
        .cpu_ready      (cpu_ready),
        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_data  (cpu_resp_data),
        .fsm_state      (fsm_state),
        .cache_hit      (cache_hit),
        .cache_miss     (cache_miss)
    );

    // =========================================================================
    // CPU Read Transaction Task
    // =========================================================================
    task automatic cpu_read(
        input  [31:0] addr,
        output [31:0] data,
        output        hit,
        output        miss,
        output int    lat_cycles
    );
        int cycle_count;
        bit exp_hit;
        logic [31:0] exp_data;
        logic [INDEX_WIDTH-1:0] idx;
        logic [TAG_WIDTH-1:0]   tag_val;
        begin
            idx         = addr[9:4];
            tag_val     = addr[31:10];
            exp_hit     = predict_hit(addr);
            exp_data    = ref_mem_word(addr);
            cycle_count = 0;
            saw_hit     = 1'b0;
            saw_miss    = 1'b0;

            // Wait until cache controller is ready
            while (!cpu_ready) begin
                @(posedge clk);
            end

            // Drive request on negedge for clean setup time
            @(negedge clk);
            cpu_req_valid = 1'b1;
            cpu_req_addr  = addr;
            @(negedge clk);
            cpu_req_valid = 1'b0;

            // Wait for response and count latency cycles
            while (!cpu_resp_valid) begin
                @(posedge clk);
                cycle_count++;
                if (cycle_count > 100) begin
                    $error("[FATAL] CPU request timed out waiting for response! Addr=0x%08h", addr);
                    $finish;
                end
            end

            data       = cpu_resp_data;
            hit        = saw_hit;
            miss       = saw_miss;
            lat_cycles = cycle_count;

            // Transaction statistics
            total_requests++;
            if (hit) begin
                hit_count++;
            end else if (miss) begin
                miss_count++;
                if (!ref_valid[idx])
                    comp_miss_cnt++;
                else
                    conf_miss_cnt++;
            end

            // Update reference cache model on miss
            if (miss) begin
                update_ref_cache(addr);
            end

            @(posedge clk); // Allow transition back to S_IDLE
        end
    endtask

    // =========================================================================
    // Modular Test Scenarios Inclusion
    // =========================================================================
    `include "test_scenarios.sv"

    // =========================================================================
    // Main Simulation Process
    // =========================================================================
    initial begin
        $dumpfile("sim/cache_top_sv.vcd");
        $dumpvars(0, tb_cache_top);

        $display("===============================================================================");
        $display("   DIRECT-MAPPED CACHE CONTROLLER - SYSTEMVERILOG TESTBENCH (ANANT)           ");
        $display("===============================================================================");

        // Initialize signals
        clk           = 0;
        rst           = 1;
        cpu_req_valid = 0;
        cpu_req_addr  = 0;
        saw_hit       = 0;
        saw_miss      = 0;
        reset_ref_cache();

        // Apply reset pulse
        #25;
        @(negedge clk);
        rst = 0;
        #15;

        // Run Basic Sanity Check
        run_basic_sanity_check();

        // TEST 1: Cold Cache Test
        run_test_cold_cache();

        // Print Summary
        $display("\n===============================================================================");
        $display("   TESTBENCH INITIALIZATION SUMMARY                                           ");
        $display("===============================================================================");
        $display("Total Tests Executed : %0d", total_tests);
        $display("Total Tests Passed   : %0d", passed_tests);
        $display("Total Tests Failed   : %0d", failed_tests);
        $display("===============================================================================");

        if (failed_tests == 0) begin
            $display(">>> BASIC TESTBENCH VERIFICATION PASSED <<<");
        end else begin
            $display(">>> BASIC TESTBENCH VERIFICATION FAILED <<<");
        end

        $finish;
    end

endmodule
