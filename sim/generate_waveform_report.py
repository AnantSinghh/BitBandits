#!/usr/bin/env python3
"""
VCD Waveform Trace Extractor
Parses sim/cache_integration.vcd and generates a human-readable cycle-by-cycle
timing log and timing diagrams for inclusion in the project documentation.
"""

def parse_vcd(filename):
    signals = {}
    time = 0
    signal_map = {
        "!": "fsm_state",
        "\"": "cpu_resp_valid",
        "#": "cpu_resp_data",
        "$": "cpu_ready",
        "%": "cache_miss",
        "&": "cache_hit",
        "'": "clk",
        "(": "cpu_req_addr",
        ")": "cpu_req_valid",
        ".": "rst",
        ":": "storage_write_en",
        "<": "storage_read_valid"
    }

    state_names = {
        "000": "IDLE",
        "001": "LOOKUP",
        "010": "MEM_REQ",
        "011": "MEM_WAIT",
        "100": "REFILL",
        "101": "RESPOND"
    }

    current_values = {v: "0" for v in signal_map.values()}
    traces = []

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
                    if sig_name == "fsm_state":
                        val_str = val.zfill(3)
                        current_values[sig_name] = f"{val_str} ({state_names.get(val_str, 'UNK')})"
                    elif sig_name in ("cpu_req_addr", "cpu_resp_data"):
                        current_values[sig_name] = hex(int(val, 2)) if val != 'x' else 'x'
                    else:
                        current_values[sig_name] = val
            elif len(line) >= 2 and line[1:] in signal_map:
                val = line[0]
                sym = line[1:]
                sig_name = signal_map[sym]
                current_values[sig_name] = val

            # Capture on rising clock edge
            if line == "1'":
                traces.append((time // 1000, dict(current_values)))

    return traces

def generate_report():
    traces = parse_vcd("sim/cache_integration.vcd")
    print(f"Total rising clock edges sampled: {len(traces)}")

    # Print selected key intervals
    print("\n--- Cycle-Accurate Execution Trace Sample ---")
    header = f"{'Time(ns)':<10} | {'FSM State':<18} | {'CPU_Req':<7} | {'CPU_Addr':<12} | {'Ready':<5} | {'RespVal':<7} | {'RespData':<12} | {'Hit':<4} | {'Miss':<4}"
    print(header)
    print("-" * len(header))
    
    # Filter interesting cycles: state transitions or requests
    prev_state = ""
    for t_ns, val in traces:
        state = val['fsm_state']
        req = val['cpu_req_valid']
        resp = val['cpu_resp_valid']
        hit = val['cache_hit']
        miss = val['cache_miss']
        if state != prev_state or req == '1' or resp == '1' or hit == '1' or miss == '1':
            print(f"{t_ns:<10} | {state:<18} | {req:<7} | {val['cpu_req_addr']:<12} | {val['cpu_ready']:<5} | {resp:<7} | {val['cpu_resp_data']:<12} | {hit:<4} | {miss:<4}")
            prev_state = state

if __name__ == "__main__":
    generate_report()
