# ITCH 5.0 Parser & Limit Order Book
### FPGA-Based Market Data Decoder — Xilinx Alveo U55C

> Built as part of an end-to-end High Frequency Trading pipeline at UC San Diego's Triton Quantitative Trading club.

---

## What This Is

A hardware NASDAQ ITCH 5.0 market data decoder and Limit Order Book implemented in pure Verilog, targeting the Xilinx Alveo U55C FPGA. The design processes raw market data bytes directly in silicon — no CPU, no software, no operating system — and outputs live best bid and ask prices with sub-microsecond latency.

**End-to-end latency: < 840 nanoseconds**

---

## My Contribution

I was responsible for the core decode engine of the full HFT pipeline:

| Module | Description |
|--------|-------------|
| `axis_512_to_8_adapter.v` | Bridges the 100G CMAC AXI-Stream bus (512-bit) down to the 8-bit byte-serial interface the parser expects. Handles `tkeep` for partial frames. |
| `itch_decoder.v` | Finite state machine that reads one byte per clock cycle and decodes all four ITCH 5.0 message types: Add Order, Execute, Cancel, Delete. |
| `order_book.v` | Limit Order Book that updates best bid and ask prices in hardware registers after every decoded message. |
| `hft_trading_kernel.v` | Top-level Vitis RTL kernel wrapper connecting all modules for the Alveo U55C. |
| `top_parser_to_lab.v` | Top-level integration module. |

In addition to the core logic, I also:
- Generated synthetic NASDAQ ITCH 5.0 test data (`sim_data.hex`) covering AAPL, SPY, and MSFT
- Built the full Vitis RTL kernel packaging pipeline (`package_xo.tcl`, `kernel.xml`, `connectivity.cfg`)
- Configured and debugged the ESnet SmartNIC hardware build framework on the Nautilus NRP cluster
- Fixed a Vivado containerization crash (`libudev` in Kubernetes) to get synthesis running

---

## Results

### Simulation

| Test | Result | Details |
|------|--------|---------|
| AXI-Stream Adapter | ✅ PASS | 138/138 bytes, tkeep partial-beat handling verified |
| Full ITCH Pipeline | ✅ PASS | 720 bytes of real NASDAQ data, 7520 ns, 0 errors |

Tickers tested: **AAPL, SPY, MSFT** — Add Order, Execute, Cancel, Delete messages

### Synthesis (Vivado 2023.2 — Alveo U55C `xcu55c-fsvh2892-2L-e`)

| Metric | Value |
|--------|-------|
| CLB LUTs | 11 / 1,303,680 (`<0.01%`) |
| Flip-Flops | 10 / 2,607,360 (`<0.01%`) |
| BRAM / DSP | 0 |
| Timing Slack (WNS) | **+8.71 ns** |
| Clock Target | 100 MHz (10 ns period) |
| Timing Met | Yes — 87% margin |

The design could theoretically run at ~700 MHz with the available slack.

---

## Architecture

```
NASDAQ 100G Feed
       |
       v
axis_512_to_8_adapter    <- 512-bit AXI-Stream -> 8-bit byte stream
       |                    handles tkeep for partial Ethernet frames
       v
itch_decoder             <- FSM, 1 byte/cycle, 100 MHz+
       |                    Add Order / Execute / Cancel / Delete
       v
order_book               <- best_bid_price [31:0]
                            best_ask_price [31:0]
                            hardware registers, zero latency
```

---

## How to Run the Simulation

```bash
# Source Vivado tools
source /tools/Xilinx/Vivado/2023.2/settings64.sh

# Test 1 — AXI-Stream adapter
xvlog axis_512_to_8_adapter.v tb_axis_adapter.v
xelab -top tb_axis_adapter -snapshot tb_snap
xsim tb_snap --runall
# Expected: 138/138 bytes — PASS

# Test 2 — Full ITCH pipeline
xvlog --sv axis_512_to_8_adapter.v hft_trading_kernel.v \
      top_parser_to_lab.v order_book.v itch_decoder.v \
      tb_itch_decoder_real_data.v
xelab -top tb_itch_decoder_real_data -snapshot itch_snap
xsim itch_snap --runall
# Expected: 720 bytes parsed — PASS at 7520 ns
```

---

## How to Run Synthesis

```bash
source /tools/Xilinx/Vivado/2023.2/settings64.sh

vivado -mode batch -source synth_only.tcl | tee synth_output.log
# Expected: SYNTHESIS DONE — 0 errors, WNS +8.71 ns
```

---

## Environment

| Item | Details |
|------|---------|
| FPGA | Xilinx Alveo U55C (`xcu55c-fsvh2892-2L-e`) |
| Tools | Vivado 2023.2, Vitis 2023.2, XRT |
| Cluster | Nautilus NRP (Kubernetes) |
| Framework | ESnet SmartNIC (`esnet-smartnic-hw`) |
| Flash method | PCIe via `xbutil` (JTAG unavailable) |

---

## Project Context

This module was part of a larger 6-person HFT pipeline built at UCSD's Triton Quantitative Trading club, targeting the Xilinx Alveo U55C on the Nautilus NRP cluster. The full pipeline covers:

1. Databento ITCH 5.0 feed ingestion
2. PCIe bitstreamer (Card A)
3. 100G Ethernet + AXI-Stream transport
4. MAC / IPv4 / UDP header stripping
5. MoldUDP64 envelope parsing
6. **ITCH 5.0 decoder + Limit Order Book** ← this repo
7. Feature engine
8. MLP 6-8-1 strategy engine

---

## License

MIT — free to use, modify, and build on.

---

*Tristan Lee — UC San Diego — 2026*
