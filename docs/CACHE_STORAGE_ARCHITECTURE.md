# Direct-Mapped Cache Storage & Address Decoding Architecture

**Subsystem:** Cache Storage Subsystem & Parameterized Address Decoder  
**Author / Specialist:** Sankalp  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Git Branch:** `feature/cache-storage`  

---

## 1. Architectural Overview & Configuration Parameters

The cache storage subsystem constitutes the primary on-chip memory hierarchy for the direct-mapped cache controller. It maintains the cached data blocks, address tags for validation, and line valid flags, while providing single-cycle combinational lookup capability to the controller FSM and tag comparator.

### Architectural Parameters
| Parameter | Value | Description |
| :--- | :--- | :--- |
| **Total Cache Capacity** | 1024 Bytes (1 KB) | Total high-speed on-chip cache data storage |
| **Block / Line Size** | 16 Bytes (128 bits) | Data transferred per memory transaction |
| **Address Width** | 32 bits | Flat byte-addressable system physical address |
| **Number of Cache Lines** | 64 lines | $1024 \text{ Bytes} / 16 \text{ Bytes} = 64 \text{ entries}$ |
| **Words per Block** | 4 words | 4 $\times$ 32-bit words per 16-byte block |
| **Word Width** | 32 bits (4 bytes) | Native processor data bus width |
| **Tag Width** | 22 bits | High-order address bits ($32 - 6 - 4 = 22$) |
| **Index Width** | 6 bits | Line addressing ($\log_2(64) = 6$) |
| **Block Offset Width** | 4 bits | Byte addressing within block ($\log_2(16) = 4$) |
| **Word Select Width** | 2 bits | Word selection within line ($\log_2(4) = 2$) |
| **Byte Offset Width** | 2 bits | Byte selection within word ($\log_2(4) = 2$) |

---

## 2. Address Decomposition & Bit Slicing

A 32-bit physical memory address issued by the CPU is decoded by `address_decoder.v` into five constituent fields:

```
+---------------------------+-------------------+-----------------------+
|        Tag [31:10]        |    Index [9:4]    |   Block Offset [3:0]  |
|          22 bits          |      6 bits       |         4 bits        |
+---------------------------+-------------------+-----------------------+
                                                | Word [3:2] | Byte[1:0]|
                                                +------------+----------+
```

### Mathematical Bit Slicing Formulas
1. **Tag Field (`addr[31:10]`, 22 bits):**
   $$\text{Tag} = \text{addr}[\text{ADDR\_WIDTH}-1 : \text{ADDR\_WIDTH} - \text{TAG\_WIDTH}]$$
   Uniquely identifies the physical memory frame mapped to the designated cache line.
2. **Index Field (`addr[9:4]`, 6 bits):**
   $$\text{Index} = \text{addr}[\text{OFFSET\_WIDTH} + \text{INDEX\_WIDTH} - 1 : \text{OFFSET\_WIDTH}]$$
   Directly selects 1 of the 64 cache lines ($2^6 = 64$).
3. **Block Offset (`addr[3:0]`, 4 bits):**
   $$\text{Block Offset} = \text{addr}[\text{OFFSET\_WIDTH}-1 : 0]$$
   Specifies the exact byte position within the 16-byte block ($2^4 = 16$).
4. **Word Select (`addr[3:2]`, 2 bits):**
   $$\text{Word Select} = \text{addr}[\text{OFFSET\_WIDTH}-1 : \text{OFFSET\_WIDTH} - \text{WORD\_SEL\_WIDTH}]$$
   Selects 1 of the 4 words:
   - `2'b00`: Word 0 (`data[31:0]`)
   - `2'b01`: Word 1 (`data[63:32]`)
   - `2'b10`: Word 2 (`data[95:64]`)
   - `2'b11`: Word 3 (`data[127:96]`)
5. **Byte Offset (`addr[1:0]`, 2 bits):**
   $$\text{Byte Offset} = \text{addr}[\text{BYTE\_OFFSET\_WIDTH}-1 : 0]$$
   Identifies byte alignment within the selected 32-bit word.
6. **Block-Aligned Address (`{addr[31:4], 4'b0000}`, 32 bits):**
   $$\text{Block Addr} = \{\text{addr}[\text{ADDR\_WIDTH}-1 : \text{OFFSET\_WIDTH}], \{\text{OFFSET\_WIDTH}\{1'b0\}\}\}$$
   Zeros out the lower 4 offset bits to generate the 16-byte base address transmitted to main memory during refill.

---

## 3. Subsystem Architecture & Modular Decomposition

The subsystem is partitioned into five clean, synthesizable Verilog modules:

```
                            +-----------------------------------------------+
                            |                 cache_storage                 |
                            |                                               |
  read_index [5:0] -------->+-----+--------------+----------------+         |
  write_en ---------------->+--+  |              |                |         |
  write_index [5:0] ------->+--+  |              |                |         |
                            |  |  |              |                |         |
                            |  v  v              v                v         |
                            | +--------------+ +------------+ +-----------+ |
  write_data [127:0] ------>+>|cache_data_ram| |  tag_ram   | |valid_bit_ | |
                            | |  (64x128b)   | |  (64x22b)  | |   ram     | |
  write_tag [21:0] -------->+>|              | |            | |  (64x1b)  | |
  write_valid ------------->+>|              | |            | |           | |
  clk --------------------->+>|              | |            | |           | |
  rst --------------------->+-------------------------------->| (Reset)  | |
                            | +------+-------+ +----+-------+ +-----+-----+ |
                            |        |              |               |       |
                            +--------|--------------|---------------|-------+
                                     |              |               |
                                     v              v               v
                                 read_data       read_tag       read_valid
                                 [127:0]          [21:0]           [1b]
```

### Module Descriptions
1. **`address_decoder.v`:** Combinational address slicer with parameterized bit ranges and block-alignment calculation.
2. **`cache_data_ram.v`:** 64-entry $\times$ 128-bit synchronous-write, combinational-read SRAM block.
3. **`tag_ram.v`:** 64-entry $\times$ 22-bit synchronous-write, combinational-read address tag array.
4. **`valid_bit_ram.v`:** 64-entry $\times$ 1-bit line validity register array with active-high asynchronous reset.
5. **`cache_storage.v`:** Top-level structural wrapper interconnecting data, tag, and valid-bit RAMs to MANAS's controller interface.

---

## 4. Advanced Engineering Design Decisions

### 4.1 RAM Inference: Distributed RAM (LUTRAM) vs. Block RAM (BRAM)
In FPGA and ASIC synthesis, the choice between distributed memory (LUTRAM) and embedded block memory (BRAM) is governed by read latency requirements:
- **Synchronous Read (BRAM):** Requires an address register or output register, imposing a minimum 1-clock-cycle read latency.
- **Combinational / Asynchronous Read (LUTRAM):** Provides immediate data output as soon as the index address stabilizes (`assign read_data = ram[index]`).

**Why Combinational Read Was Chosen for This Direct-Mapped Cache:**
In Manas's 6-state cache controller FSM, the `S_LOOKUP` state evaluates tag equality within a **single clock cycle**. The address is placed on the bus, and in that same clock cycle:
1. `cache_storage` outputs `read_tag`, `read_valid`, and `read_data`.
2. `tag_comparator` checks `comp_hit = read_valid & (read_tag == req_tag)`.
3. If hit, the controller transitions directly to `S_RESPOND` on the next clock edge.

If a synchronous Block RAM were used, a wait state (`S_LOOKUP_WAIT`) would be required simply to wait for the BRAM read pipeline, increasing cache hit latency from 1 cycle to 2 cycles (a 100% latency penalty on hits). By inferring distributed RAM (SLICEM LUTRAM in modern FPGAs), single-cycle lookup is achieved.

**Trade-Off Analysis:**
- *Advantages:* Minimal hit latency (1 cycle), simplified controller FSM, no pipeline stalls during tag check.
- *Disadvantages:* Consumes LUT resources rather than dedicated BRAM; long combinational path (`index` $\rightarrow$ LUTRAM read $\rightarrow$ 22-bit comparator $\rightarrow$ FSM next-state logic) sets a limit on maximum operating frequency ($F_{\text{max}}$).

### 4.2 Asymmetric Reset Design (Zero Reset Overhead on Data/Tag Arrays)
A fundamental engineering flaw in naive Verilog cache designs is adding `if (rst)` reset loops to all storage arrays:
```verilog
// ANTI-PATTERN: Forces 9,600 flip-flops with reset routing
always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < 64; i = i + 1) begin
            data_mem[i] <= 128'b0;  // 8,192 flip-flops!
            tag_mem[i]  <= 22'b0;   // 1,408 flip-flops!
            valid_mem[i]<= 1'b0;    //    64 flip-flops
        end
    end
end
```

**Why Data and Tag RAMs Must NOT Have Resets:**
1. **Synthesis Macro Prevention:** Hardware RAM blocks (BRAMs and LUTRAMs) do not possess hardware reset pins for their storage cells. Adding a reset signal prevents the synthesis tool from inferring RAM macros, forcing it to decompose the array into **9,600 discrete flip-flops** ($8192 + 1408 = 9600$).
2. **Routing Congestion & Timing:** Routing a global reset net to 9,600 registers severely degrades place-and-route timing and increases silicon area by $>400\%$.
3. **Correct Architectural Invalidation:** In computer architecture, a cache line is valid **if and only if** its corresponding valid bit is `1'b1`. If `valid_mem[index] == 1'b0`, any random or garbage bits residing in `data_mem` and `tag_mem` are completely ignored by the tag comparator:
   $$\text{Hit} = \text{Valid} \ \& \ (\text{Stored Tag} == \text{Requested Tag})$$
   Since `Valid == 0`, $\text{Hit} \equiv 0$, guaranteeing a compulsory cold miss.

Therefore, our architecture applies `rst` **exclusively** to `valid_bit_ram.v` (only 64 flip-flops), achieving $100\%$ reliable reset invalidation with negligible silicon overhead.

---

## 5. Verification & Cycle-Accurate Execution Trace

The subsystem was verified using a standalone 205-assertion testbench (`tb/tb_cache_storage.v`) and an address decoder unit suite (`tb/tb_address_decoder.v`), followed by top-level integration validation with Manas's cache controller.

### 5.1 Verification Matrix
| Objective | Test Scenario | Mechanism | Result |
| :--- | :--- | :--- | :---: |
| **1. Cold Reset Invalidation** | Sweep lines 0–63 after reset | Verify all 64 `read_valid` bits are 0 | **PASS** (64/64) |
| **2. Full Line Write/Read** | Write unique 128-bit patterns & tags | Read back combinationally across all 64 lines | **PASS** (64/64) |
| **3. Line Isolation** | Overwrite line 32; inspect lines 31 & 33 | Verify neighbors retain original data/tags | **PASS** |
| **4. Address Decoder Coupling** | Decode `0x00001204` into tag/index/offset | Verify storage refill matches decoded fields | **PASS** |
| **5. Conflict Miss Replacement** | Stream same index `0x20` with tags `0x000004`, `0x000404`, `0x000804` | Verify line replacement and eviction | **PASS** |
| **6. Combinational Stability** | Hold read index steady for 50ns | Confirm 0 glitches, 0 drift on output bus | **PASS** |
| **7. Boundary Addresses** | Test min address `0x00000000` and max address `0xFFFFFFFF` | Verify lines 0 and 63 access | **PASS** |
| **8. Runtime Hardware Reset** | Assert `rst` pulse during active operation | Verify all 64 lines invalidated immediately | **PASS** (64/64) |

### 5.2 Cycle-Accurate Execution Log (Sampled from `sim/cache_storage_tb.vcd`)

```
===================================================================================================================
CYCLE-ACCURATE CACHE STORAGE SUBSYSTEM EXECUTION TRACE (SANKALP)
===================================================================================================================
Time(ns) | rst | w_en | w_idx | w_tag    | w_val | r_idx | r_val | r_tag    | r_data (lower 32b) | Verification Event
-------------------------------------------------------------------------------------------------------------------
5        | 1   | 0    | 0x0   | 0x0      | 0     | 0x0   | 0     | x        | x                  | Hardware Reset: Valid bits cleared to 0
25       | 1   | 0    | 0x0   | 0x0      | 0     | 0x0   | 0     | x        | x                  | Hardware Reset: Valid bits cleared to 0
35       | 0   | 0    | 0x0   | 0x0      | 0     | 0x0   | 0     | x        | x                  | Post-Reset Idle: Ready for stimulus
175      | 0   | 1    | 0x0   | 0x100000 | 1     | 0x3f  | 0     | x        | x                  | Write Line 0 Boundary (Tag=0x100000)
195      | 0   | 1    | 0x1   | 0x100004 | 1     | 0x3f  | 0     | x        | x                  | Write Line 0x1 (Sweep/Setup)
815      | 0   | 1    | 0x20  | 0x100080 | 1     | 0x3f  | 0     | x        | x                  | Write Line 0x20 (Tag=0x100080)
1435     | 0   | 1    | 0x3f  | 0x1000fc | 1     | 0x3f  | 0     | x        | x                  | Write Line 63 Boundary (Tag=0x1000fc)
1575     | 0   | 1    | 0x20  | 0x3abcde | 1     | 0x3f  | 1     | 0x100080 | ...dddd0020        | Line 32 Data/Tag Update (Isolation Test)
1585     | 0   | 0    | 0x20  | 0x3abcde | 1     | 0x3f  | 1     | 0x1000fc | ...dddd003f        | Combinational Read Line 0x3f (Stable inspection)
1595     | 0   | 1    | 0x20  | 0x4      | 1     | 0x21  | 1     | 0x3abcde | ...99998888        | Coupled Write for Addr 0x00001204 (Tag 0x000004)
1605     | 0   | 0    | 0x20  | 0x4      | 1     | 0x21  | 1     | 0x100084 | ...dddd0021        | Combinational Read Line 0x21 (Stable inspection)
1615     | 0   | 1    | 0x20  | 0x404    | 1     | 0x20  | 1     | 0x4      | ...01200a01        | Conflict Eviction 1: Addr 0x00101204 (Tag 0x000404)
1625     | 0   | 0    | 0x20  | 0x404    | 1     | 0x20  | 1     | 0x404    | ...33334444        | Combinational Read Line 0x20 (Stable inspection)
1635     | 0   | 1    | 0x20  | 0x804    | 1     | 0x20  | 1     | 0x404    | ...33334444        | Conflict Eviction 2: Addr 0x00201204 (Tag 0x000804)
1645     | 0   | 0    | 0x20  | 0x804    | 1     | 0x20  | 1     | 0x804    | ...33332222        | Combinational Read Line 0x20 (Stable inspection)
1705     | 0   | 1    | 0x0   | 0x0      | 1     | 0x20  | 1     | 0x100000 | ...dddd0000        | Write Line 0 Boundary (Tag=0x0)
1725     | 0   | 1    | 0x3f  | 0x3fffff | 1     | 0x0   | 1     | 0x1000fc | ...dddd003f        | Write Line 63 Boundary (Tag=0x3fffff)
1745     | 1   | 0    | 0x3f  | 0x3fffff | 1     | 0x3f  | 0     | 0x3fffff | ...ffffffff        | Hardware Reset: Valid bits cleared to 0
1775     | 0   | 0    | 0x3f  | 0x3fffff | 1     | 0x3f  | 0     | 0x0      | 0x0                | Post-Reset Verification: Line 0 invalid
```

---

## 6. ASCII Timing Diagrams

### 6.1 Combinational Read During Cache LOOKUP
```
Clock (clk)         : __/--\__/--\__/--\__/--\__
read_index          : ==<  6'h20  >=============
read_valid (asynch) : ______/------------------- (valid bit immediately asserted)
read_tag (asynch)   : =====< 22'h000004 >======= (stored tag immediately driven)
read_data (asynch)  : =====< 128-bit block >==== (data available for word selection)
                      |<- combinational delay ->|
```

### 6.2 Synchronous Write During Cache REFILL
```
Clock (clk)         : __/--\__/--\__/--\__/--\__
write_en            : _____/-----------\________ (asserted during S_REFILL)
write_index         : =====<   6'h20   >========
write_tag           : =====< 22'h000404>========
write_data          : =====< 128b data >========
write_valid         : _____/-----------\________
RAM Storage State   : === Old Line ===><=== New Block Committed on Edge ===
```

