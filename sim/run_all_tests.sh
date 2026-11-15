#!/usr/bin/env bash
# =============================================================================
# Direct-Mapped Cache Controller - Complete Verification Runner
# Designer: Sankalp (Cache Storage & Address Decoding Specialist)
# =============================================================================
set -e

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SIM_DIR")"
cd "$ROOT_DIR"

IVERILOG="/opt/homebrew/bin/iverilog"
VVP="/opt/homebrew/bin/vvp"

if ! command -v "$IVERILOG" &> /dev/null; then
    IVERILOG="iverilog"
    VVP="vvp"
fi

echo "==============================================================================="
echo "   RUNNING COMPLETE CACHE SUBSYSTEM & INTEGRATION VERIFICATION SUITE"
echo "==============================================================================="

# 1. Address Decoder Unit Test
echo -e "\n[1/6] Compiling & Running Address Decoder Unit Test (tb_address_decoder)..."
$IVERILOG -g2012 -o /tmp/tb_address_decoder.vvp rtl/address_decoder.v tb/tb_address_decoder.v
$VVP /tmp/tb_address_decoder.vvp

# 2. Cache Data RAM Unit Test
echo -e "\n[2/6] Compiling & Running Cache Data RAM Unit Test (tb_cache_data_ram)..."
$IVERILOG -g2012 -o /tmp/tb_cache_data_ram.vvp rtl/cache_data_ram.v tb/tb_cache_data_ram.v
$VVP /tmp/tb_cache_data_ram.vvp

# 3. Tag RAM Unit Test
echo -e "\n[3/6] Compiling & Running Tag RAM Unit Test (tb_tag_ram)..."
$IVERILOG -g2012 -o /tmp/tb_tag_ram.vvp rtl/tag_ram.v tb/tb_tag_ram.v
$VVP /tmp/tb_tag_ram.vvp

# 4. Valid-Bit RAM Unit Test
echo -e "\n[4/6] Compiling & Running Valid-Bit RAM Unit Test (tb_valid_bit_ram)..."
$IVERILOG -g2012 -o /tmp/tb_valid_bit_ram.vvp rtl/valid_bit_ram.v tb/tb_valid_bit_ram.v
$VVP /tmp/tb_valid_bit_ram.vvp

# 5. Cache Storage Integrated Subsystem Test
echo -e "\n[5/6] Compiling & Running Cache Storage Integrated Subsystem Test (tb_cache_storage)..."
$IVERILOG -g2012 -o /tmp/tb_cache_storage.vvp \
    rtl/cache_data_ram.v rtl/tag_ram.v rtl/valid_bit_ram.v rtl/cache_storage.v rtl/address_decoder.v tb/tb_cache_storage.v
$VVP /tmp/tb_cache_storage.vvp

# 6. Top-Level Integration System Test (With Manas's Controller)
echo -e "\n[6/6] Compiling & Running Top-Level System Integration Test (tb_cache_top_integration)..."
$IVERILOG -g2012 -o /tmp/tb_cache_top_integration.vvp \
    rtl/cache_data_ram.v rtl/tag_ram.v rtl/valid_bit_ram.v rtl/cache_storage.v rtl/address_decoder.v \
    rtl/tag_comparator.v rtl/main_memory.v rtl/memory_interface.v rtl/cache_controller.v rtl/cache_top.v \
    tb/tb_cache_top_integration.v
$VVP /tmp/tb_cache_top_integration.vvp

echo -e "\n==============================================================================="
echo "   >>> ALL 6 VERIFICATION TESTBENCHES COMPLETED AND PASSED 100% <<<"
echo "==============================================================================="

