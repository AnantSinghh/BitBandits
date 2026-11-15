# Individual Technical Contribution & Phase II Interview Defense

**Student Name / Role:** SANKALP  
**Technical Ownership:** Cache Storage Subsystem & Parameterized Address Decoding  
**Academic Project:** Design and Analysis of a Direct-Mapped Cache Controller (Phase II)  
**Five-Member Team:**
- **Sankalp (Me):** Cache Storage Array & Address Decoder (`cache_data_ram.v`, `tag_ram.v`, `valid_bit_ram.v`, `address_decoder.v`, `cache_storage.v`)
- **Tejas:** Cache Storage Baseline / System Analysis
- **Ronit:** Tag Comparator (`tag_comparator.v`)
- **Anant:** Memory Interface & Main Memory Model (`memory_interface.v`, `main_memory.v`)
- **Manas:** Cache Controller FSM & Top-Level System Integration (`cache_controller.v`, `cache_top.v`)

---

## 1. Technical Ownership Statement

I was exclusively responsible for designing, implementing, and verifying the complete storage and address decoding architecture:

1. **`rtl/address_decoder.v`:**
   - Parameterized Verilog module decoding 32-bit CPU addresses into 22-bit tag, 6-bit line index, 4-bit block offset, 2-bit word select, and 2-bit byte offset.
   - Generation of 16-byte block-aligned physical base addresses (`{addr[31:4], 4'b0000}`) for main memory refill requests.
   - 100% combinational, zero-latch architecture with mathematical parameter validation.

2. **`rtl/cache_data_ram.v`:**
   - 64-entry $\times$ 128-bit storage array storing 4 words (32 bits each) per line.
   - Synchronous write gated by `write_enable` on the rising clock edge.
   - Combinational (asynchronous) read port enabling single-cycle LOOKUP data access.
   - Omission of array reset to facilitate distributed RAM (LUTRAM) inference and eliminate 8,192 flip-flops.

3. **`rtl/tag_ram.v`:**
   - 64-entry $\times$ 22-bit memory array storing high-order physical address tags.
   - Synchronous write on refill and combinational read for immediate tag comparison.
   - Omission of array reset to prevent synthesis of 1,408 flip-flops with reset nets.

4. **`rtl/valid_bit_ram.v`:**
   - 64-entry $\times$ 1-bit array maintaining line validity flags.
   - Active-high asynchronous reset clearing all 64 valid bits to `1'b0` on cold boot or hardware reset.
   - Independent write enable and `write_valid` input supporting selective line validation and invalidation.

5. **`rtl/cache_storage.v`:**
   - Top-level structural subsystem integration interconnecting `cache_data_ram`, `tag_ram`, and `valid_bit_ram`.
   - Adherence to the common team interface agreed upon by MANAS (`read_index`, `read_valid`, `read_tag`, `read_data`, `write_en`, `write_index`, `write_tag`, `write_data`, `write_valid`).
   - Asymmetric reset routing: only `valid_bit_ram` receives `rst`.

6. **Verification Suite & Automation:**
   - Authored unit testbenches: `tb/tb_address_decoder.v` (72 tests), `tb/tb_cache_data_ram.v` (68 tests), `tb/tb_tag_ram.v` (68 tests), `tb/tb_valid_bit_ram.v` (133 tests).
   - Authored subsystem testbench: `tb/tb_cache_storage.v` (205 tests covering all 8 prompt verification objectives).
   - Authored automated regression runner `sim/run_all_tests.sh` and cycle-accurate trace generator `sim/generate_storage_report.py`.
   - Validated complete interoperability with Manas's top-level integration test suite (`tb/tb_cache_top_integration.v`), achieving 7 / 7 integration passes.

---

## 2. Technical Explanation: Tag, Index, Offset, and Valid Bits in a Direct-Mapped Cache

In a direct-mapped cache architecture, each physical memory block maps to **exactly one** specific cache line. The four fields operate synchronously and combinational in unison:

```
Physical Address [31:0]
+-------------------------+-----------------+---------------------+
|       Tag [31:10]       |   Index [9:4]   |  Block Offset [3:0] |
+-------------------------+-----------------+---------------------+
             |                     |                   |
             |                     v                   v
             |               Selects 1 of 64     Selects Word & Byte
             |                 Cache Lines        Within 128-bit Block
             v                     |
       Compared against            v
      Stored Tag in line    Stored Line [Valid, Tag, 128-bit Data Block]
```

1. **Index (`address[9:4]`):**
   - The 6-bit index acts as the direct lookup address into the storage arrays ($2^6 = 64$ lines).
   - In hardware, the index drives the address decoders of the data RAM, tag RAM, and valid-bit RAM simultaneously.
   - Because every block in memory whose address shares the same bits `[9:4]` maps to this identical line, no associative searching or multi-way hardware multiplexers are needed, resulting in the smallest silicon area and lowest power dissipation of any cache topology.

2. **Tag (`address[31:10]`):**
   - Multiple memory blocks across the 4 GB address space share the exact same 6-bit index. For example, addresses `0x0000_1200`, `0x0010_1200`, and `0x0020_1200` all have index `6'h20` (line 32).
   - To distinguish which of these blocks currently occupies line 32, the upper 22 bits are recorded in `tag_ram` when the line is refilled.
   - During a cache access, the tag comparator compares `read_tag` from `tag_ram` against `cpu_req_addr[31:10]`. If they match, the cached block belongs to the requested memory block.

3. **Valid Bit (`valid_bit_ram`):**
   - At power-on or system reset, SRAM cells contain arbitrary high/low electrical charges. Without a validity indicator, garbage bits in tag RAM matching the CPU's request tag would falsely indicate a cache hit and return corrupted data.
   - The 1-bit valid flag indicates whether the line contains legitimate data refilled from main memory (`1'b1`) or is uninitialized/invalid (`1'b0`).
   - The tag comparator gates the tag comparison with this flag:
     $$\text{Cache Hit} = \text{read\_valid} \ \& \ (\text{read\_tag} == \text{req\_tag})$$
     If `read_valid == 0`, a miss is unconditionally declared, forcing memory refill.

4. **Block Offset & Word Select (`address[3:0]`):**
   - Main memory transfers data in atomic 16-byte (128-bit) blocks to exploit spatial locality.
   - Once a cache hit is confirmed, the CPU does not need the entire 128-bit block simultaneously; it requests a 32-bit word.
   - Bits `address[3:2]` (Word Select) route through a 4-to-1 32-bit multiplexer to extract Word 0, 1, 2, or 3 from the 128-bit line for delivery on `cpu_resp_data`. Bits `address[1:0]` denote the byte position within that word.

---

## 3. Phase II Technical Interview Defense: Questions & Answers

### Q1: Why did you choose combinational reads for the RAM modules rather than registering the read outputs?
**Defense Answer:**  
"In our architecture, the cache controller FSM relies on a single-cycle `S_LOOKUP` state. When the processor issues a request, the FSM transitions from `S_IDLE` to `S_LOOKUP` on the first clock edge.  
If we had implemented synchronous reads (registered outputs, typical of dedicated FPGA Block RAMs), presenting the index address to the RAM in `S_LOOKUP` would require waiting until the **next** clock edge for `read_tag`, `read_valid`, and `read_data` to emerge. This would force the insertion of a pipeline bubble or wait state (`S_LOOKUP_WAIT`), penalizing every cache hit with an additional clock cycle (2 cycles total, a 100% latency penalty).  
By implementing combinational (asynchronous) reads, the storage arrays behave like distributed LUTRAM (SLICEM LUTs): the moment `read_index` is applied, the stored tag, valid bit, and data propagate through the array in under 2 ns. The tag comparator evaluates hit/miss within the same clock period, allowing cache hits to transition directly to `S_RESPOND` on the very next cycle.  
The engineering trade-off is that combinational read paths form part of the critical timing path (`index` $\rightarrow$ LUTRAM $\rightarrow$ 22-bit comparator $\rightarrow$ FSM next-state logic), which sets the upper limit on $F_{\text{max}}$. For a 1 KB cache at 100 MHz, this path easily satisfies timing."

---

### Q2: Why is it bad engineering practice to reset data RAM and tag RAM, but critical to reset valid-bit RAM?
**Defense Answer:**  
"This is a fundamental principle of production digital ASIC and FPGA memory design:
1. **Silicon Area & Flip-Flop Overhead:**  
   Our data RAM contains 64 entries of 128 bits = **8,192 bits**.  
   Our tag RAM contains 64 entries of 22 bits = **1,408 bits**.  
   If we wrote an `always @(posedge clk or posedge rst)` block that resets all lines, synthesis tools cannot map these arrays to memory macros or LUTRAMs because hardware RAM primitives lack synchronous/asynchronous reset pins on memory cells. Synthesis would be forced to infer **9,600 discrete flip-flops**, each requiring reset routing and multiplexers. This inflates cell count and causes massive routing congestion.
2. **Architectural Redundancy:**  
   In computer architecture, data and tag entries are meaningless unless the line's valid bit is set. The tag comparator computes:
   $$\text{Hit} = \text{valid} \ \& \ (\text{tag} == \text{req\_tag})$$
   When `valid == 0`, the hit signal is mathematically guaranteed to be `0` regardless of whatever garbage bits exist in data or tag RAM.
3. **Targeted Reset of Valid-Bit RAM:**  
   By routing the reset signal exclusively to `valid_bit_ram.v`, we reset only **64 flip-flops**. This consumes negligible area, guarantees zero false hits on startup, and permits `cache_data_ram.v` and `tag_ram.v` to synthesize cleanly into high-density memory macros."

---

### Q3: What is a conflict miss, and how does your storage array handle it when multiple addresses map to index 32?
**Defense Answer:**  
"A conflict miss occurs in direct-mapped caches when multiple distinct memory blocks compete for the same cache line. Because mapping is fixed by the index bits (`addr[9:4]`), two addresses whose bits `[9:4]` are identical will collide on the same line, even if the rest of the 64 cache lines are completely empty.  
In Test 5 of our storage verification suite:
1. We first wrote Address A (`0x0000_1204`: Index `6'h20`, Tag `22'h000004`) to line 32.
2. We then simulated a CPU request for Address B (`0x0010_1204`: Index `6'h20`, Tag `22'h000404`).
3. During lookup, `read_index = 6'h20` returned Stored Tag `0x000004`. The tag comparator compared Stored Tag (`0x000004`) with Requested Tag (`0x000404`). Because the tags did not match, it signaled `comp_miss = 1`.
4. The controller FSM fetched the 16-byte block for Address B from main memory and entered `S_REFILL`.
5. In `S_REFILL`, `write_en = 1`, `write_index = 6'h20`, `write_tag = 22'h000404`, and `write_data = mem_block_B`. On the clock edge, line 32 was overwritten atomically:
   - `tag_ram` committed `0x000404`.
   - `cache_data_ram` committed Address B's 128-bit block.
   - `valid_bit_ram` committed `1'b1`.
6. Address A was evicted. When Address A was subsequently re-requested in Test 5 of the top-level integration suite, it experienced a miss and had to be re-fetched from memory, confirming correct replacement behavior."

---

### Q4: How does `address_decoder.v` support the memory controller during a cache miss?
**Defense Answer:**  
"When a cache miss occurs, the cache controller must request a full 16-byte block from main memory, not just the single 32-bit word requested by the CPU.  
Main memory addresses must be aligned to 16-byte boundaries (i.e., the lowest 4 bits must be `4'b0000`). If the CPU requested byte address `0x0000_1207`, issuing that exact address to a block memory controller would violate alignment or fetch misaligned words.  
`address_decoder.v` computes:
```verilog
assign block_addr = {addr[ADDR_WIDTH-1 : OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
```
For `addr = 0x0000_1204` or `0x0000_1207`, `block_addr` masks the lower 4 bits to output `0x0000_1200`. The cache controller forwards `dec_cpu_block_addr` directly to `mem_addr` in `S_MEM_REQUEST`, ensuring memory transfers always begin at the exact block boundary."

---

### Q5: How did you verify that updating one cache line does not corrupt adjacent lines?
**Defense Answer:**  
"Memory array addressing bugs often manifest as off-by-one decoder errors, where writing to line $k$ accidentally overwrites line $k-1$ or $k+1$.  
To verify line isolation:
1. In Stage 2 of `tb_cache_storage.v`, we initialized all 64 lines with unique data and tags derived from their index ($i$).
2. In Stage 3, we wrote an aggressive test pattern (`0xFFFF_EEEE_DDDD_CCCC_BBBB_AAAA_9999_8888` and tag `0x3ABCDE`) specifically to line 32.
3. We then combinationally read back line 32 and verified it held the new pattern.
4. Immediately following, we read back line 31 (`read_index = 6'd31`) and line 33 (`read_index = 6'd33`) and compared their outputs against their original mathematical expected values.
5. Lines 31 and 33 remained 100% intact with zero corruption, proving perfect address decoding and independent line isolation."

---

## 4. Verification Summary
- **Address Decoder Unit Test (`tb_address_decoder`):** 72 / 72 tests passed (zero failures).
- **Cache Data RAM Unit Test (`tb_cache_data_ram`):** 68 / 68 tests passed (zero failures).
- **Tag RAM Unit Test (`tb_tag_ram`):** 68 / 68 tests passed (zero failures).
- **Valid-Bit RAM Unit Test (`tb_valid_bit_ram`):** 133 / 133 tests passed (zero failures).
- **Cache Storage Integrated Subsystem Test (`tb_cache_storage`):** 205 / 205 tests passed (zero failures).
- **Top-Level System Integration Test (`tb_cache_top_integration`):** 7 / 7 system integration scenarios passed (zero failures).

