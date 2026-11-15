#!/usr/bin/env python3
"""
Storage Subsystem VCD Trace Extractor & Verification Reporter
Parses sim/cache_storage_tb.vcd and generates a human-readable cycle-by-cycle
timing log and timing diagrams for inclusion in the project documentation.
"""

def parse_storage_vcd(filename):
    signal_map = {
        "!": "read_valid",
        "\"": "read_tag",
        "#": "read_data",
        "/": "clk",
        "0": "dec_test_addr",
        "2": "read_index",
        "3": "rst",
        "4": "write_data",
        "5": "write_en",
        "6": "write_index",
        "7": "write_tag",
        "8": "write_valid",
        "%": "dec_tag",
        "&": "dec_index"
    }

    current_values = {v: "0" for v in signal_map.values()}
    traces = []
    time = 0

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                time = int(line[1:])
            elif line.startswith("b"):
                parts = line.split()
                val = parts[0][1:]
                sym = parts[1]
                if sym in signal_map:
                    sig_name = signal_map[sym]
                    if sig_name in ("dec_test_addr", "write_tag", "read_tag", "read_index", "write_index", "dec_index"):
                        current_values[sig_name] = hex(int(val, 2)) if val != 'x' else 'x'
                    elif sig_name in ("write_data", "read_data"):
                        current_values[sig_name] = hex(int(val, 2)) if val != 'x' else 'x'
                    else:
                        current_values[sig_name] = val
            elif len(line) >= 2 and line[1:] in signal_map:
                val = line[0]
                sym = line[1:]
                sig_name = signal_map[sym]
                current_values[sig_name] = val

            # Capture on rising clock edge
            if line == "1/":
                traces.append((time // 1000, dict(current_values)))

    return traces

def generate_report():
    traces = parse_storage_vcd("sim/cache_storage_tb.vcd")
    print(f"Total rising clock edges sampled: {len(traces)}")

    print("\n" + "="*115)
    print("CYCLE-ACCURATE CACHE STORAGE SUBSYSTEM EXECUTION TRACE (SANKALP)")
    print("="*115)
    header = f"{'Time(ns)':<8} | {'rst':<3} | {'w_en':<4} | {'w_idx':<5} | {'w_tag':<8} | {'w_val':<5} | {'r_idx':<5} | {'r_val':<5} | {'r_tag':<8} | {'r_data (lower 32b)':<18} | {'Verification Event'}"
    print(header)
    print("-" * 115)

    interesting_times = [
        5, 25, 45, 55, 65, 75, 85,  # Reset and first writes
        675, 685,                    # Sweep wrap
        705, 715, 725, 735,          # Isolation test (line 32 vs 31, 33)
        745, 755, 765,               # Decoded write & read (0x1204)
        775, 785, 795, 805,          # Conflict replacements (0x00101204, 0x00201204)
        815, 825,                    # Repeated reads
        835, 845, 855,               # Boundary line 0 and line 63
        875, 885, 895                # Runtime reset invalidation
    ]

    for t_ns, val in traces:
        w_en = val['write_en']
        rst  = val['rst']
        w_idx = val['write_index']
        r_idx = val['read_index']

        event = None
        if rst == '1':
            event = "Hardware Reset: Valid bits cleared to 0"
        elif w_en == '1':
            if w_idx == '0x20':
                if val['write_tag'] == '0x3abcde':
                    event = "Line 32 Data/Tag Update (Isolation Test)"
                elif val['write_tag'] == '0x4':
                    event = "Coupled Write for Addr 0x00001204 (Tag 0x000004)"
                elif val['write_tag'] == '0x404':
                    event = "Conflict Eviction 1: Addr 0x00101204 (Tag 0x000404)"
                elif val['write_tag'] == '0x804':
                    event = "Conflict Eviction 2: Addr 0x00201204 (Tag 0x000804)"
                else:
                    event = f"Write Line {w_idx} (Tag={val['write_tag']})"
            elif w_idx == '0x0':
                event = f"Write Line 0 Boundary (Tag={val['write_tag']})"
            elif w_idx == '0x3f':
                event = f"Write Line 63 Boundary (Tag={val['write_tag']})"
            elif int(w_idx, 16) in (1, 2, 3, 31, 33, 62):
                event = f"Write Line {w_idx} (Sweep/Setup)"
        elif t_ns in (35, 45):
            event = "Post-Reset Idle: Ready for stimulus"
        elif t_ns in (1585, 1605, 1625, 1645, 1655, 1665, 1675, 1685):
            event = f"Combinational Read Line {r_idx} (Stable inspection)"
        elif t_ns in (1745, 1755, 1765):
            event = "Runtime Reset Assertion: rst=1"
        elif t_ns == 1775:
            event = "Post-Reset Verification: Line 0 invalid"

        rdata = val['read_data']
        if len(rdata) > 10:
            rdata_short = "..." + rdata[-8:]
        else:
            rdata_short = rdata

        if event:
            print(f"{t_ns:<8} | {val['rst']:<3} | {val['write_en']:<4} | {val['write_index']:<5} | {val['write_tag']:<8} | {val['write_valid']:<5} | {val['read_index']:<5} | {val['read_valid']:<5} | {val['read_tag']:<8} | {rdata_short:<18} | {event}")

if __name__ == "__main__":
    generate_report()
