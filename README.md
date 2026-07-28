# Dual-Channel DMA Controller with Unaligned Transfer Support

## Project overview

This project implements a 32-bit, dual-channel Direct Memory Access
(DMA) controller for FPGA systems. It contains:

- An MM2S channel that reads data from memory and produces an AXI4-Stream.
- An S2MM channel that accepts an AXI4-Stream and writes data to memory.
- Independent AXI read and write paths that can operate simultaneously.
- AXI4-Lite control and status registers.
- Barrel-shifter-based handling of unaligned source and destination
  addresses.

The intended target is a Zynq-7000 FPGA/SoC, where the ARM processor
configures the DMA through an AXI4-Lite interface and the DMA accesses
DDR through a high-performance AXI port.

## Objective

The main objective is to handle unaligned DMA transfers with less
temporary memory than designs that buffer large portions of a transfer.

This design aligns every data beat through combinational barrel-shifter
logic. Each alignment datapath retains only one previous 32-bit word
when bytes must cross a word boundary. Therefore, the alignment logic
does not require a transfer-sized FIFO or memory buffer.

In this project, "single-cycle alignment" means that alignment is
performed in one combinational stage for each transferred beat. The
complete DMA transaction can still require multiple clock cycles,
depending on its length and AXI backpressure.

## How it works

1. Software writes the source address, destination address, transfer
   length, and start commands through AXI4-Lite.
2. MM2S reads aligned words from memory.
3. Its barrel shifter removes the unwanted bytes caused by an unaligned
   source address and produces a packed AXI stream.
4. S2MM accepts stream data and uses another barrel shifter to place the
   bytes at the requested destination offset.
5. AXI write strobes protect bytes outside the destination range.
6. Both channels use independent AXI read and write channels, allowing
   memory reads and writes to occur concurrently.

In short:

```text
Memory → MM2S aligner → AXI stream → S2MM aligner → Memory
```

## Main modules

| Module | Purpose |
|---|---|
| `dma_controller_dual` | Top-level dual-channel DMA controller |
| `axi4_lite_slave` | Software-visible configuration and status registers |
| `mm2s_channel` | Memory-to-stream channel |
| `s2mm_channel` | Stream-to-memory channel |
| `axi4_full_read_master` | AXI burst-read engine |
| `axi4_full_write_master` | AXI burst-write engine |
| `mm2s_datapath` | MM2S byte-alignment datapath |
| `s2mm_datapath` | S2MM byte-alignment and write-strobe datapath |
| `barrel_shifter` | Combinational data-shifting logic |
| `arbitration_unit` | Channel-start policy with simultaneous mode |

## Register map

| Offset | Register | Description |
|---:|---|---|
| `0x00` | MM2S source address | Memory address read by MM2S |
| `0x04` | MM2S length | Number of bytes to transfer |
| `0x08` | MM2S control | Bit 0: start, bit 1: clear status |
| `0x0C` | MM2S status | Bit 0: busy, bit 1: done, bit 2: error |
| `0x10` | S2MM destination address | Memory address written by S2MM |
| `0x14` | S2MM length | Number of bytes to transfer |
| `0x18` | S2MM control | Bit 0: start, bit 1: clear status |
| `0x1C` | S2MM status | Bit 0: busy, bit 1: done, bit 2: error |

## Verification

The test suite covers:

- All byte-address offsets from 0 to 3.
- Aligned and unaligned lengths.
- First- and last-word write strobes.
- AXI backpressure and response errors.
- Burst splitting at the configured maximum length.
- AXI 4 KB boundary handling.
- Simultaneous MM2S and S2MM activity.
- A 136-case alignment matrix.

Run the complete Icarus Verilog regression from the repository root:

```powershell
tclsh run.tcl
```

A successful run ends with:

```text
ALL REGRESSION TESTS PASSED
```

## FPGA evaluation

For the Zynq-7000 implementation:

- Connect the DMA AXI4-Lite slave to a PS `M_AXI_GP` port.
- Connect its AXI memory master to a PS `S_AXI_HP` port through
  SmartConnect.
- Use `FCLK_CLK0` and a synchronized active-low peripheral reset.
- Initially loop `M_AXIS` to `S_AXIS` for a DDR-to-DDR hardware test.

To demonstrate the intended improvement, synthesize this design and the
reference buffered design using the same FPGA part, clock, bus width,
burst length, and Vivado settings. Compare the DMA hierarchy's BRAM,
distributed RAM, LUT, flip-flop, and timing results. Debug ILA storage
and test-memory BRAM must be excluded from the alignment-memory
comparison.
