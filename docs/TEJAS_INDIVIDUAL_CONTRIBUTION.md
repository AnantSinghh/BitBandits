# Individual Contribution Report — Tejas

**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Team:** BitBandits  
**Branch:** `feature/main-memory-interface`  
**Date:** 2026-11-15

---

## 1. Technical Ownership Summary

I am responsible for the **main memory subsystem and cache-to-memory communication layer**, comprising:

| Deliverable                    | File                              | Status    |
|-------------------------------|-----------------------------------|-----------|
| Main memory behavioral model  | `rtl/main_memory.v`               | Complete  |
| Memory interface protocol FSM | `rtl/memory_interface.v`          | Complete  |
| Memory subsystem testbench    | `tb/tb_memory_subsystem.v`        | Complete  |
| Memory protocol documentation | `docs/MEMORY_PROTOCOL.md`         | Complete  |
| Individual contribution report| `docs/TEJAS_INDIVIDUAL_CONTRIBUTION.md` | This file |

**Not in scope:** `cache_top.v`, `cache_controller.v`, `cache_storage.v`, `address_decoder.v`, `tag_comparator.v`.

---

## 2. Design Decisions and Rationale

### 2.1 Combinational Data Generation vs. Physical Array

**Decision:** Use a `generate_block_data()` function instead of a `reg [127:0] mem [0:N]` array.

**Rationale:**
- Eliminates depth constraints — any 32-bit block-aligned address can be served.
- Deterministic: expected values can be computed by the testbench without shared state.
- Avoids `$readmemh` (simulation-only construct) in what is otherwise synthesisable RTL.
- The function uses only bit-select and concatenation — both synthesisable.

### 2.2 FSM-Based Latency (not `#delay`)

**Decision:** Implement latency via a countdown counter inside a 3-state FSM.

**Rationale:**
- `#delay` constructs are forbidden in synthesisable RTL.
- An FSM counter is synthesisable, cycle-accurate, and verifiable.
- The `LATENCY` parameter maps cleanly to counter initial load value.

### 2.3 en_pulse_sent Guard in memory_interface

**Decision:** Use a `en_pulse_sent` register to ensure `phy_mem_en` fires for exactly one clock cycle.

**Rationale:**
- `main_memory` starts a new transaction whenever `mem_en` rises while in `MEM_IDLE`.
- If `phy_mem_en` were held high, main_memory's `MEM_IDLE` state would re-trigger.
- One-cycle pulse + FSM state lock guarantees single-transaction semantics.

### 2.4 Separate Module Boundaries

**Decision:** `main_memory.v` and `memory_interface.v` are separate modules.

**Rationale:**
- Clear ownership boundary: memory model is replaceable (e.g., with DRAM model).
- Interface FSM can be unit-tested without a physical memory.
- Aligns with team responsibility split.

---

## 3. Data Pattern Specification

For block address `B` (block-aligned, bits[3:0] = 4'h0):

```
word[0] = { B[31:4], 4'h0, 12'hA01 }   → bits [31: 0] of 128-bit block
word[1] = { B[31:4], 4'h4, 12'hB02 }   → bits [63:32]
word[2] = { B[31:4], 4'h8, 12'hC03 }   → bits [95:64]
word[3] = { B[31:4], 4'hC, 12'hD04 }   → bits [127:96]
```

**Unique block guarantee:** Since `B[31:4]` is embedded in each word's MSBs, two different block addresses always produce different blocks. The 12-bit suffix marker (`A01`, `B02`, `C03`, `D04`) uniquely identifies each word's position within the block.

---

## 4. Verification Test Coverage

| TC   | Description                                          | Assertion |
|------|------------------------------------------------------|-----------|
| TC1  | Correct 128-bit response for address 0x0000_1000     | `got_block === exp_block` |
| TC2  | All 4 words of 0x0000_2000 individually verified     | 4 × word-level `!==` checks |
| TC3  | Three different addresses produce distinct blocks    | `A !== B && B !== C && A !== C` |
| TC4+8| No `mem_req_ready` before LATENCY cycles expire     | `early_ready == 0` |
| TC5  | Sustained `mem_req` does not retrigger transaction   | `ready_count == 1` |
| TC6  | `mem_req_ready` and `phy_mem_en` clear after reset   | Direct signal checks |
| TC7  | 3 consecutive back-to-back requests all correct      | 3 × `got === exp` |

---

## 5. Interface Contract with Cache Controller (Manas)

The following contract was established before implementation:

| Parameter          | Agreed Value |
|-------------------|-------------|
| `mem_req` pulse width | 1 cycle (from `S_MEM_REQUEST`) |
| `mem_req_ready` pulse width | 1 cycle |
| Latency (default) | 10 cycles |
| Address alignment | bits[3:0] = 0 (block-aligned) |
| Data format       | `{word3, word2, word1, word0}` (word0 at LSBs) |

---

## 6. Git Commit History

| Commit | Message |
|--------|---------|
| `a1f91eb` | Create main memory model with FSM-based latency and deterministic data generation |
| `7d7ca6e` | Add deterministic memory initialization: address-embedded data pattern |
| *(pending)* | Implement memory latency counter |
| *(pending)* | Implement memory interface FSM |
| `c223b4b` | Create memory subsystem testbench: 8 test cases |
| *(pending)* | Verify handshake behavior |
| *(pending)* | Document interface and latency |

---

## 7. Key Architectural Insight

> **Cache misses incur the full configured memory access latency.**
>
> When the cache controller detects a miss in `S_LOOKUP`, it asserts `mem_req` and waits in `S_MEM_WAIT`. The memory interface counts exactly `LATENCY = 10` cycles before asserting `mem_req_ready`. This demonstrates the fundamental miss-penalty cost — a cache hit costs 1 cycle (direct SRAM read), while a miss costs ~12 cycles (lookup + 10-cycle DRAM latency + refill pipeline). This gap motivates the entire cache hierarchy in computer architecture.
