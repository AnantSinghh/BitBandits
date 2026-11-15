# Memory Protocol & Interface Documentation

**Designer:** Tejas  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Branch:** `feature/main-memory-interface`  
**Date:** 2026-11-15

---

## 1. System Architecture — Memory Subsystem Position

```
CPU Request
    │
    ▼
cache_controller (Manas)
    │  mem_req / mem_addr
    │  mem_req_ready / mem_data
    ▼
memory_interface (Tejas) ◄─── this document
    │  phy_mem_en / phy_mem_addr
    │  phy_mem_ready / phy_mem_rdata
    ▼
main_memory (Tejas) ◄──────── this document
```

---

## 2. Cache Configuration

| Parameter      | Value        | Notes                        |
|---------------|-------------|------------------------------|
| Cache size     | 1 KB         | 64 lines × 16 bytes          |
| Block size     | 16 bytes     | 128 bits per block           |
| Words per block| 4            | Each word = 32 bits          |
| Address width  | 32 bits      |                              |
| Tag bits       | 22           | addr[31:10]                  |
| Index bits     | 6            | addr[9:4] → 64 sets          |
| Block offset   | 4            | addr[3:0]                    |
| Word select    | 2            | addr[3:2]                    |
| Cache type     | Read-only    | No write-back / dirty logic  |

---

## 3. Signal Definitions

### 3.1 Controller ↔ Memory Interface (Manas ↔ Tejas boundary)

| Signal           | Direction               | Width | Description                                           |
|-----------------|------------------------|-------|-------------------------------------------------------|
| `mem_req`        | Controller → Interface  | 1     | Single-cycle pulse asserted in `S_MEM_REQUEST` state  |
| `mem_addr`       | Controller → Interface  | 32    | Block-aligned address (`addr[3:0]` = 4'b0000)         |
| `mem_req_ready`  | Interface → Controller  | 1     | One-cycle pulse when 128-bit block is available       |
| `mem_data`       | Interface → Controller  | 128   | Returned cache-line block; stable when `mem_req_ready`|

### 3.2 Memory Interface ↔ Main Memory (physical bus, internal)

| Signal           | Direction              | Width | Description                                     |
|-----------------|------------------------|-------|-------------------------------------------------|
| `phy_mem_en`     | Interface → Memory     | 1     | Single-cycle enable; fires once per transaction |
| `phy_mem_addr`   | Interface → Memory     | 32    | Latched block-aligned address                   |
| `phy_mem_ready`  | Memory → Interface     | 1     | One-cycle pulse after LATENCY cycles            |
| `phy_mem_rdata`  | Memory → Interface     | 128   | Valid 128-bit block when `phy_mem_ready`         |

---

## 4. Handshake Protocol

### 4.1 Agreed Protocol (coordinated with Manas)

The memory interface follows a **single-outstanding-request** protocol:

1. `cache_controller` asserts `mem_req = 1` for **one clock cycle** while in `S_MEM_REQUEST`.
2. `memory_interface` captures the request in `MI_IDLE`, latches `mem_addr`, and enters `MI_ACCESS`.
3. `memory_interface` fires `phy_mem_en = 1` for **one clock cycle** to `main_memory`.
4. `main_memory` counts down `LATENCY` cycles then asserts `phy_mem_ready = 1` for one cycle.
5. `memory_interface` captures `phy_mem_rdata` and enters `MI_RESPONSE`.
6. `memory_interface` asserts `mem_req_ready = 1` for **one clock cycle** and returns to `MI_IDLE`.
7. `cache_controller` sees `mem_req_ready` in `S_MEM_WAIT` and transitions to `S_REFILL`.

### 4.2 Timing Diagram (MEM_LATENCY = 3, simplified)

```
Cycle:        1    2    3    4    5    6    7    8
              ─────────────────────────────────────
clk           ↑    ↑    ↑    ↑    ↑    ↑    ↑    ↑
mem_req      ▌▄▌  __   __   __   __   __   __   __
mem_addr     [addr stable while req=1]
phy_mem_en   __  ▌▄▌  __   __   __   __   __   __
phy_mem_ready __  __   __   __  ▌▄▌  __   __   __
              ← LATENCY=3 cycles →
mem_req_ready __  __   __   __  __  ▌▄▌  __   __
mem_data     [         128-bit block valid here ]
```

> **Note:** `mem_req_ready` fires one cycle after `phy_mem_ready` (the `MI_RESPONSE` state adds one pipeline stage).

### 4.3 Anti-Retriggering Guard

| Mechanism          | In `memory_interface.v`     | In `main_memory.v`    |
|-------------------|-----------------------------|-----------------------|
| State lock         | `MI_ACCESS` / `MI_RESPONSE` blocks re-entry until `MI_IDLE` | `MEM_ACCESS` state blocks until `mem_en` is a fresh pulse |
| Enable pulse       | `en_pulse_sent` flag ensures `phy_mem_en` fires for 1 cycle only | — |
| Controller guard   | `cache_controller` only asserts `mem_req` in `S_MEM_REQUEST` (1 cycle) | — |

---

## 5. Main Memory Model

### 5.1 Address Range

The memory model uses **combinational data generation** (no physical array), so the full 32-bit address space (0x0000_0000 – 0xFFFF_FFF0, block-aligned) is served without depth constraints.

### 5.2 Deterministic Data Pattern

For any block-aligned address `b_addr` (bits[3:0] = 4'h0):

```
word[0] [31: 0] = { b_addr[31:4], 4'h0, 12'hA01 }
word[1] [63:32] = { b_addr[31:4], 4'h4, 12'hB02 }
word[2] [95:64] = { b_addr[31:4], 4'h8, 12'hC03 }
word[3][127:96] = { b_addr[31:4], 4'hC, 12'hD04 }
```

**Block packing:** `mem_rdata = { word3, word2, word1, word0 }` (word0 at LSBs).

**Verification example for address `0x0000_1000`:**

| Word | Expected Value | Derivation |
|------|----------------|------------|
| w0   | `0x0001_00A01` → `0x00001_00_A01` | `{0x0000_1[27:0], 4'h0, 12'hA01}` |
| w1   | `0x00001_04_B02` | `{block_addr>>4, 4'h4, 12'hB02}` |
| w2   | `0x00001_08_C03` | suffix C03 |
| w3   | `0x00001_0C_D04` | suffix D04 |

### 5.3 Latency Configuration

| Parameter   | Value   | Range | Notes                              |
|------------|---------|-------|------------------------------------|
| `LATENCY`  | 10      | ≥ 1   | Default per project specification  |
| `CNT_WIDTH`| 4       | —     | Supports LATENCY ≤ 15; increase for larger values |

> **Important:** `LATENCY` is a **synthesisable parameter** (not a `#delay`). It maps to a counter in register logic.

---

## 6. FSM Descriptions

### 6.1 `main_memory` FSM

```
        rst
         │
         ▼
   ┌─────────────┐
   │  MEM_IDLE   │◄──────────────────────────┐
   └──────┬──────┘                           │
          │ mem_en=1                          │
          ▼                                  │
   ┌─────────────┐                           │
   │ MEM_ACCESS  │  counter-- each cycle     │
   └──────┬──────┘                           │
          │ counter==0                       │
          ▼                                  │
   ┌──────────────┐  mem_ready=1 (1 cycle)   │
   │ MEM_RESPONSE │──────────────────────────┘
   └──────────────┘
```

### 6.2 `memory_interface` FSM

```
        rst
         │
         ▼
   ┌─────────────┐
   │   MI_IDLE   │◄──────────────────────────┐
   └──────┬──────┘                           │
          │ mem_req=1                        │
          ▼                                  │
   ┌─────────────┐  phy_mem_en=1 (1 cycle)   │
   │  MI_ACCESS  │  wait phy_mem_ready        │
   └──────┬──────┘                           │
          │ phy_mem_ready=1                  │
          ▼                                  │
   ┌──────────────┐  mem_req_ready=1 (1 cyc) │
   │ MI_RESPONSE  │──────────────────────────┘
   └──────────────┘
```

---

## 7. Latency Simulation

| Access Type       | Latency   | Source                              |
|------------------|-----------|-------------------------------------|
| Cache hit         | 1 cycle   | `S_LOOKUP → S_RESPOND` (Manas FSM)  |
| Cache miss        | 10 cycles | `MEM_LATENCY` parameter (Tejas)     |
| Memory overhead   | +1 cycle  | `MI_RESPONSE` state pipeline stage  |
| Total miss cost   | ~12 cycles| Lookup + Memory + Refill + Respond  |

> Cache misses incur the full configured memory access latency demonstrating the classic miss penalty.

---

## 8. Integration Notes

### 8.1 Connecting to `cache_top.v` (Manas)

```verilog
memory_interface #(.ADDR_WIDTH(32), .BLOCK_WIDTH(128)) u_memory_interface (
    .clk           (clk),
    .rst           (rst),
    .mem_req       (ctrl_mem_req),      // from cache_controller
    .mem_addr      (ctrl_mem_addr),     // from cache_controller
    .mem_req_ready (mem_intf_ready),    // to cache_controller
    .mem_data      (mem_intf_data),     // to cache_controller
    .phy_mem_en    (phy_mem_en),
    .phy_mem_addr  (phy_mem_addr),
    .phy_mem_ready (phy_mem_ready),
    .phy_mem_rdata (phy_mem_rdata)
);

main_memory #(.ADDR_WIDTH(32), .BLOCK_WIDTH(128), .LATENCY(MEM_LATENCY)) u_main_memory (
    .clk       (clk),
    .rst       (rst),
    .mem_en    (phy_mem_en),
    .mem_addr  (phy_mem_addr),
    .mem_ready (phy_mem_ready),
    .mem_rdata (phy_mem_rdata)
);
```

### 8.2 Do Not Modify

- `cache_top.v` — integration wiring already correct for this interface
- `cache_controller.v` — Manas's ownership; handshake is compatible

---

## 9. File List

| File                             | Role                  | Designer |
|---------------------------------|-----------------------|----------|
| `rtl/main_memory.v`             | Main memory model RTL | Tejas    |
| `rtl/memory_interface.v`        | Protocol bridge RTL   | Tejas    |
| `tb/tb_memory_subsystem.v`      | Standalone testbench  | Tejas    |
| `docs/MEMORY_PROTOCOL.md`       | This document         | Tejas    |
| `docs/TEJAS_INDIVIDUAL_CONTRIBUTION.md` | Contribution report | Tejas |
