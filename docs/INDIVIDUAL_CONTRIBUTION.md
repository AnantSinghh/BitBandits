# Individual Technical Contribution & Phase II Interview Defense

**Student Name / Role:** MANAS  
**Technical Assignment:** Cache Controller FSM Architecture & Top-Level System Integration  
**Academic Project:** Design and Analysis of a Direct-Mapped Cache Controller (Phase II)  
**Five-Member Team:**
- **Sankalp:** Address Decoder (`address_decoder.v`)
- **Tejas:** Cache Storage RAM Array (`cache_storage.v`)
- **Ronit:** Tag Comparator (`tag_comparator.v`)
- **Anant:** Memory Interface & Main Memory Model (`memory_interface.v`, `main_memory.v`)
- **Manas (Me):** Cache Controller FSM & Top-Level Integration (`cache_controller.v`, `cache_top.v`)

---

## 1. Technical Ownership Statement

I was exclusively responsible for:
1. **`rtl/cache_controller.v`:**
   - 6-state finite state machine (`S_IDLE`, `S_LOOKUP`, `S_MEM_REQUEST`, `S_MEM_WAIT`, `S_REFILL`, `S_RESPOND`).
   - One-request-at-a-time handshake protocol and request address latching.
   - Cache hit/miss steering logic and multi-cycle memory handshake.
   - Block refill sequencing and write control generation for cache storage.
   - 4-word multiplexer logic for 32-bit CPU response generation.
2. **`rtl/cache_top.v`:**
   - Top-level structural integration of all 5 team members' submodules.
   - Signal routing, clock/reset tree propagation, and status flag instrumentation.
   - Clean separation of concerns ensuring no duplicate storage arrays exist at the top level.
3. **Verification Suite (`tb/tb_cache_top_integration.v`):**
   - 7 comprehensive integration test scenarios verifying hits, cold misses, spatial locality, conflict replacements, post-eviction correctness, reset invalidation, and backpressure.

---

## 2. Respecting Module Boundaries

In accordance with strict project engineering guidelines, I consumed my teammates' modules through their established interfaces without altering their internal designs:
* I took **Sankalp's** `address_decoder.v` to decode CPU addresses into Tag, Index, and Word offsets.
* I connected **Tejas's** `cache_storage.v` using its synchronous write and asynchronous read ports.
* I integrated **Ronit's** `tag_comparator.v` into the lookup data-path, relying on its `hit` and `miss` outputs to drive FSM state transitions.
* I coordinated with **Anant** to interface with his `memory_interface.v` and `main_memory.v`, obeying the single-request pulse and latency ready handshake.

---

## 3. Phase II Technical Interview Defense: Questions & Answers

### Q1: Why did you choose a 6-state FSM rather than collapsing LOOKUP and RESPOND into a single state?
**Defense Answer:**  
"In a synthesizable cache controller, separating `S_LOOKUP` and `S_RESPOND` provides critical timing and signal integrity advantages:
1. **Clock Period & Critical Path:** In `S_LOOKUP`, the critical path involves driving the cache index, propagating through the storage SRAM array, and passing through the 22-bit tag comparator. If we immediately multiplexed and drove the CPU response in the same cycle, the combined combinational delay (SRAM read delay + comparator delay + 4-to-1 word mux delay + CPU bus setup time) would drastically lower maximum clock frequency ($F_{\text{max}}$).
2. **Glitch-Free Registered CPU Bus:** By capturing the 128-bit block into `cached_block` and asserting `cpu_resp_valid` in `S_RESPOND`, the CPU data bus is driven from stable flip-flops, preventing glitches on the processor interface.
3. **Unified Response Path:** Both cache hits (from `S_LOOKUP`) and cache misses (from `S_REFILL`) converge cleanly on `S_RESPOND`, keeping CPU response logic modular and DRY (Don't Repeat Yourself)."

---

### Q2: How does the controller avoid making repeated memory requests during high memory latency?
**Defense Answer:**  
"A classic error in hardware cache design is keeping `mem_req` high while waiting for memory, which causes memory controllers to interpret every clock cycle as a new read transaction.  
In my FSM design:
* `mem_req` is asserted **only** in `S_MEM_REQUEST`, which lasts for exactly **one clock cycle**.
* The FSM unconditionally transitions to `S_MEM_WAIT` on the next clock cycle.
* In `S_MEM_WAIT`, `mem_req` is driven to `1'b0`.
* The controller remains in `S_MEM_WAIT` until `mem_req_ready` asserts. This strictly adheres to a single-pulse request/acknowledge handshake protocol regardless of how many cycles memory latency takes."

---

### Q3: Why is address latching in IDLE necessary? What happens if the CPU changes its address while the cache is refilling?
**Defense Answer:**  
"In pipelined processors, the address bus might change on every clock cycle. When the cache controller suffers a miss and spends 5 to 10 cycles waiting for DRAM refill:
* If the address was not latched, the controller would decode whatever new address was currently on `cpu_req_addr`, resulting in:
  1. Refilling the wrong cache line in `cache_storage`.
  2. Overwriting the wrong tag.
  3. Extracting the wrong word for the CPU response.
* In `cache_controller.v`, as soon as `cpu_req_valid` is detected in `S_IDLE`, the full 32-bit address is captured into the internal `latched_addr` register.
* All internal operations (`req_tag`, `req_index`, `req_word_sel`, and `mem_addr`) are derived strictly from `latched_addr`.
* Concurrently, `cpu_ready` is deasserted to `0`, instructing the processor that the controller is busy and cannot accept new addresses until the current transaction finishes."

---

### Q4: How is a cold-start false hit prevented after system reset?
**Defense Answer:**  
"Upon power-up or system reset, SRAM storage arrays contain random bit values. If a line happened to contain tag bits matching the CPU request address, a naive tag match would falsely declare a hit and return garbage data.  
In our architecture:
* Each of the 64 lines possesses an explicit 1-bit `valid` flag.
* The hardware reset signal (`rst`) triggers a loop inside `cache_storage.v` that clears all 64 valid bits to `1'b0`.
* In `tag_comparator.v`, Ronit's logic computes:
  $$\text{hit} = \text{valid\_stored} \ \& \ (\text{tag\_stored} == \text{tag\_req})$$
* Because `valid_stored` is `0`, `hit` is guaranteed to be `0` and `miss` is `1`. This forces the controller to execute a compulsory miss and fetch true data from main memory."

---

### Q5: How does the design support consecutive CPU requests without requiring a manual reset?
**Defense Answer:**  
"In `S_RESPOND`, after presenting `cpu_resp_valid = 1'b1` and `cpu_resp_data` for exactly one cycle, the FSM transitions directly to `S_IDLE` on the next clock edge.  
In `S_IDLE`:
* `cpu_ready` automatically re-asserts to `1'b1`.
* `cpu_resp_valid` drops to `0`.
* The state register is fully receptive to a new `cpu_req_valid` pulse.  
This was experimentally proven in Test 7 of our integration testbench, where three consecutive requests (`0x5000`, `0x5004`, `0x6000`) completed back-to-back without any external reset intervention."

---

### Q6: Can you walk through the geometry calculations for this 1 KB direct-mapped cache?
**Defense Answer:**  
"Certainly:
1. **Cache Capacity:** $1\text{ KB} = 1024\text{ Bytes}$.
2. **Block Size:** $16\text{ Bytes}$.
3. **Block Offset:** $2^{\text{offset}} = 16 \implies \text{Offset Width} = 4\text{ bits}$ (`addr[3:0]`).
4. **Word Select:** Since each word is 32 bits (4 bytes), there are $\frac{16}{4} = 4\text{ words}$ per block. The word is selected by `addr[3:2]`. The lower 2 bits `addr[1:0]` are byte offsets within the word.
5. **Number of Cache Lines:** $\frac{1024\text{ Bytes}}{16\text{ Bytes/Line}} = 64\text{ Lines}$.
6. **Index Width:** $2^{\text{index}} = 64 \implies \text{Index Width} = 6\text{ bits}$ (`addr[9:4]`).
7. **Tag Width:**
   $$\text{Tag Width} = \text{Total Address Width} - \text{Index Width} - \text{Offset Width} = 32 - 6 - 4 = 22\text{ bits} \ (\text{addr}[31:10])$$
This accounts for all 32 bits with zero overlap."

---

## 4. Progressive Git History Proof

The implementation on branch `feature/cache-controller-integration` followed the prescribed 8-stage progressive development methodology:

1. `f747f8a`: Initialize controller FSM with 6-state Moore-Mealy architecture.
2. `711400a`: Implement request latching and busy interlocking.
3. `4d04608`: Implement cache lookup, tag comparison, and hit response path.
4. `c536e69`: Implement memory miss path, block-aligned address generation, and non-repeating handshake.
5. `f6d6c03`: Implement refill sequencing, storage update, and word response generation.
6. `4f96b53`: Integrate storage and memory modules into `cache_top` system integration.
7. `78c71ff`: Fix integration issues and implement comprehensive 7-scenario integration test suite.
8. `[Current]`: Add complete architectural documentation, FSM diagrams, and test results.
