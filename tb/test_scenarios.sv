// =============================================================================
// File:        test_scenarios.sv
// Author:      Anant (Senior Hardware Verification Engineer)
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Modular test scenario implementations for cache verification.
//              Included within tb_cache_top to execute structured test sequences:
//              - TEST 1: Cold Cache Test
//              - TEST 2: Temporal Locality
//              - TEST 3: Spatial Locality
//              - TEST 4: Sequential Access
//              - TEST 5: Conflict Miss
//              - TEST 6: Random Access Workload
//              - TEST 7: Reset Behavior
//              - TEST 8: Consecutive Requests & Backpressure
// =============================================================================

// -----------------------------------------------------------------------------
// Baseline Test Scenario Framework
// -----------------------------------------------------------------------------
task automatic run_basic_sanity_check();
    logic [31:0] test_addr;
    logic [31:0] rdata;
    logic        hit;
    logic        miss;
    int          lat;
    logic [31:0] exp_data;

    $display("\n===============================================================================");
    $display("   [SANITY CHECK] Executing Basic Cache Initialization & Read Check           ");
    $display("===============================================================================");

    test_addr = 32'h0000_1000;
    exp_data  = ref_mem_word(test_addr);

    cpu_read(test_addr, rdata, hit, miss, lat);

    total_tests++;
    if (miss && !hit && (rdata === exp_data)) begin
        passed_tests++;
        $display("   [PASS] Sanity read successful: Addr=0x%08h -> Data=0x%08h (Miss detected, latency=%0d cyc)",
                 test_addr, rdata, lat);
    end else begin
        failed_tests++;
        $error("   [FAIL] Sanity read failed: Addr=0x%08h -> Got Data=0x%08h, Exp Data=0x%08h, Hit=%b, Miss=%b",
               test_addr, rdata, exp_data, hit, miss);
    end
endtask
