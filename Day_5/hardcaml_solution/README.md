# Advent of FPGA 2025, Day 5 (Part 1) Solution

I had a blast learning Hardcaml to solve this challenge! Below is an overview of my thought process and design with some instructions for running it at the end.

## Architecture

### Overarching Design Principles

- Highly parallel, pipelined Multiple Instruction, Single Data (MISD) architecture for FPGA-levels of throughout.
- Scalable memory needs which do not balloon for larger problem sizes.
- Taking Hardcaml's language features out for a spin, building a cleanly parameterized solution which can be adjusted to the problem's characteristics and available resources.

### Caveat emptor (I am not sure about title capitalization conventions in Latin)

First of all, I would like to apologize for the lack of a block diagram. While this was intended as an educational weekend project, even that has limits for proper engineering discipline. Manually creating block diagrams is tedious and automatically converting Verilog into a decent looking block diagram requires working with a synthesis toolchain which is even worse. Due to my laziness, you are stuck with my prose.

## The Problem

In Advent of Code 2025's Day 5, Part 1, we are given an input file of the following form (input created by myself to respect Advent of Code Terms of Use).

```plaintext
1-5
2-6

1
4
42
```

The grouping before the empty line consists of inclusive integer ID ranges (one per-line) and the grouping under that empty line is the list of unique IDs to check. We want to determine how many IDs fall within the ranges. In this example, `1` and `4` fall within the ranges, so the correct result is two.

In software, even the optimal solution is pretty simple. If we have `m` ranges and `n` IDs, we can solve this imperatively with a nested loop that goes through each ID and checks it against each range in `O(mn)` time and `O(m + n)` space.

### Sketch of a Solution in Python

```python
num_ids_in_range = 0
for id in ids:
  for (lower, upper) in id_ranges:
    if (id >= lower) and (id <= upper):
      num_ids_in_range += 1
```

Depending on the ratio between `m` and `n`, we could speed this up further by using part of the solution for Part Two of this problem to merge the ranges into a minimal, non-overlapping set in `O(m * log(m))` time.

For the sake of my sanity, I scoped my FPGA solution to determining the number of IDs falling within ranges. I am treating parsing the input strings as something I can still do in software and populate into the circuit's memory to avoid spending most of my time on decimal to binary conversion. In fact, I chose this problem because I wanted something where the crux of the solution did not involve text parsing or creating complicated data structures which map poorly to hardware.

### Porting this to Hardware

The same basic algorithm of taking each ID and checking it against every ID range still holds and is doable with two big adders for the comparisons and some state machines (more or less a main one for the outer loop driving a state machine for the inner loop).

However, if we are going to take the time to do this, we want our solution to run fast. My perhaps incorrect understanding is that even very expensive FPGAs tend not to be clocked above a GHz (compared to the ~3GHz clock of my decent but older laptop), so we need to make up for this latency with throughput.

### The Memory Wall

The problem with achieving high throughput on a FPGA solution is memory bandwidth. To focus my design choices slightly, I opted to constrain my baseline resource requirements to fit on the only FPGA I own, a very low-end/low-power [Lattice iCE40UP5k](https://www.latticesemi.com/en/Products/FPGAandCPLD/iCE40UltraPlus).

#### Available Memory

Looking at the iCE40UP5K's datasheet, the most immediate constraints are on-chip memory. This comes in the two varieties detailed below.

|                       | Embedded Block RAM (EBR) | Single Port RAM (SPRAM)                          |
| :-------------------- | :----------------------- | :----------------------------------------------- |
| Number of Blocks      | 30                       | 4                                                |
| Block Width in Bits   | 16                       | 16                                               |
| Block Depth           | 256                      | 16K                                              |
| Number of Ports       | 2 (one read, one write)  | 1 (select read/write mode)                       |
| Latency               | 1 cycle                  | 1 cycle or asynchonous (ambiguous documentation) |
| Total Capacity in Kib | 120                      | 1024                                             |

#### Memory Needs, Pt. 1

Our problem size comes down to how many IDs and ranges we need to store, and how big these are. This is all dependent on the ID size, so we start there. The simplest solution to get a ballpark upper bound was to just sort the IDs and ranges provided by Advent of Code. The largest number looked a lot like 559794343246361 (I flipped some digits to obfuscate the actual number a bit out of respect for the Terms of Use). To represent this number in binary, we need `ceil(log2(559794343246361 + 1)) = 49 bits`. This was an arbitrary choice, but I chose to round to `64b` IDs as a general worst case. The padding seems significant, but given the 16b alignment of all the memory cells available on the iCE40UP5K, it would need to happen anyway to ensure efficient accesses.  

In the simple case, let us consider a range to consist of two IDs as given by the problem input (although encoding them as an initial ID and an offset might save space if we are willing to assume stricter things about the largest range). This means each range is `64b * 2 = 128b`.

My Advent of Code provided input had approximately 1000 IDs and 180 ranges, so `1000 * 64b = 62.5 Kib` in IDs and `180 * 128b = 22.5 Kib` worth of ranges.

At first blush, `62.5 Kib + 22.5 Kib = 85 Kib`, which fits easily in just our available EBR and leaves plenty of memory to spare.

#### Memory Needs, Pt. 2

Unfortunately, we also need to consider memory widths. If we want a fast design, ideally we cannot settle for fetching less than a full ID and a full range per cycle. However, both our EBR and SPRAM are made up of `16b` cells and can only read from one of them at a time. To read just a single `64b` ID in one clock cycle (or even the `49b` bare minimum), we need to wire up `64b / 16b = 4` blocks of either EBR or SPRAM in parallel and shard each ID and range across them in `16b` chunks (Lattice refers to this as width cascading). As we have 1000 IDs and each EBR block has a depth of 256, we need a minimum of `ceil(1000/256) = 4` sets of these four block cascades (this is called a depth cascade in Lattice terms), for a total of `4 * 4 = 16` EBR blocks just for the IDs.

For ID ranges, this means we need to width cascade `128b / 16b = 8` memory blocks. Recall that we only have 4 blocks of what once appeared to be voluminous SPRAM, so we cannot even use it for the ranges! Fortunately, with ~180 ranges, we can fit them all in just those eight EBR blocks.

Using just EBR, the IDs and ranges take up `16 + 8 = 24` blocks out of the 30 available to fit our problem size. If we want to fetch an extra ID range per cycle, we need to double the 8 blocks, putting us at `16 + 8 * 2 = 32` blocks, exceeding the 30 we have available. Doubling the number of EBR blocks dedicated to IDs is even worse, although we could consider a convoluted solution that fetches an ID from each depth cascaded block set in parallel for a total of four IDs per cycle.

While we cannot use the SPRAM for ID ranges, we could use all four blocks of it for IDs (although this would not be very efficient), freeing up those 16 EBR blocks. With all EBR blocks left for ID ranges, we could cascade our 8 block sets and duplicate them `floor(30 / 8) = 3` times to fetch three ID ranges and one ID per cycle at the expense of all our memory.

Keep in mind that should we wish to scale the number of ID ranges, the memory layouts sketched out above only leave `256 - 180 = 76` extra range entries before we need to depth cascade those 8 EBR block wide sets. We cannot accommodate more than 256 ranges with these memory resources while reading more than a single full ID range per cycle (modulo some complicated logic to squeeze out a second one by reading from each depth cascaded set in parallel as alluded to for the IDs).

#### The Moral of the Story

The takeaway from all of this back of the napkin math is that the road to solving this ID range checking problem with extreme hardware parallelism does not go through a low-end FPGA's memory. We will be limited to fetching roughly one ID and one ID range per cycle and need to extract parallelism elsewhere.

Note that we are ignoring using a nicer FPGA or external memory (which likely introduces its own latency issues which we would try to hide behind a cache made of these same resources, probably running into the same bandwidth problem).

## The Solution

The key insight behind this design is that we can fetch both an ID and a range per cycle and with a bit of pipelining can compare one range against multiple IDs in parallel.

### Overall Philosophy

At a high level, you can think of this design as a very simple and highly specialized **Multiple Instruction, Single Data (MISD)** architecture. That's right, the exotic architecture you spent maybe a couple of minutes on in a Computer Architecture class in the misty past before moving on to something that actually matters like SIMD!

In this case, the IDs to check are the instructions and the ranges to check them against are the data. I like to think of my design (only partially because it seems cooler this way) like a very stripped down CPU with multiple execution units. Instructions have varying and unknown latencies, so they are dynamically dispatched to execution units as they become available.

#### Pipeline Sequence (In lieu of a real diagram)

**ID Fetcher and Dispatcher** (Instruction Fetch Stage) --> **Execution Units** (Dispatch and Execution Stage) --> **Result Aggregator** (a little like the write-back stage, but the analogy breaks down here)

In parallel to these pipeline stages, a **Range Fetcher** controls a counter indexing into the range memory. When enabled, it continuously cycles through every range index value, rolling back to zero when it hits the maximum. The range fetcher makes the index of the currently fetched range (technically the previous index due to the cycle delay for memory reads) publicly known to the execution units.

As you can see, this a bit like your classic five stage CPU with four caveats:

- Multiple execution units (not quite super-scalar as instructions are fetched one-at-a-time, but they are executed concurrently). This is where we get the hardware parallelism.
- Instructions are so simple we do not need a decode stage.
- No write-back stage or associated data dependencies: the result aggregator is not an input for future ID comparisons.
- The Range Fetcher is what turns this into an exotic MISD architecture.

More detail:

1) **ID Fetcher**: The ID fetcher is a state machine wrapped around an incrementing counter which controls the ID/instruction memory. A little like x86, it always points towards the next ID to execute. The ID Fetcher is partially controlled by a small layer of combinational logic that tells it to fetch a new ID whenever an execution unit is ready to compute on it.
2) **Execution Units and Instruction Dispatcher**: Each execution unit is just a state machine wrapped around two adders. It more or less implements this execution loop in hardware.

```python
while current_range_idx != starting_range_idx:
  if ID >= current_range.lower_bound and ID <= current_range.upper_bound:
    return True
  return False
```

Note that the ID is effectively the instruction here. When an execution unit is ready to receive a new ID, it raises its `ready` output signal. It in turn has `enable` and `id` input signals. When `enable` is raised, the execution unit transitions from idling to an execution state, dropping `ready` and storing in internal registers the ID and current fetched range index. On every subsequent cycle, the execution unit uses its adders to check whether the ID it is currently executing falls within the range retrieved by the Ranger Fetcher that cycle. As the Range Fetcher independently goes through all of the ranges sequentially, the execution unit simply keeps doing this until either its ID falls inside a range or it has come back around to the range index it started on, whichever happens first. It then signals that it has a valid boolean output indicating whether a match was found for its ID (using `With_valid`) and raises its `ready` output signal again.

Due to nothing being easy in hardware, in practice the state machine is a little more complicated to properly handle a memory value not being available yet, storing its inputs when enabled, and not exiting on its first iteration from seeing the same range index it started on.

While we get a little bit of parallelism out of being able to compute both bounds checks at the same time, the real magic behind this design is that these execution units are fairly light on resource requirements, so we can stamp out many of them. They circumvent our limited number of memory ports by running in parallel on different IDs but the same range data. Due to the early termination condition when a match exists, we need to dynamically dispatch IDs/instructions to an execution unit whenever it becomes available. To do so, there is what I generously called the instruction dispatcher. In reality, I snagged the `onehot_clean` circuit from [hardcaml_circuits](https://github.com/janestreet/hardcaml_circuits), a small but quite neat bit of combinational logic that takes in a bit vector of the execution units' `ready` signals and ouputs a one hot encoding selecting which available execution unit to use for the latest fetched ID.

3) **Result Aggregator**: This is just a small tree of adders (simple enough to be in my top level module) that every cycle increments a counter register by the number of execution units which found an ID. There is also some combinational logic to detect when every stage of the pipeline is empty to raise the top level circuit's output valid signal (another use of `With_valid`).

### Top Level Interface

To make things a little clearer, here is my top level interface.

```ocaml
module type Config = sig
  val id_width : int
  val id_mem_size_in_ids : int
  val id_range_mem_size_in_ranges : int
  val num_execution_units : int
end

module Make (_ : Config) : sig
  module I : sig
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; enable : 'a
      ; max_id_idx : 'a
      ; max_id_range_idx : 'a
      }
    [@@deriving hardcaml]
  end

  module O : sig
    type 'a t = { num_ids_in_range : 'a With_valid.t } [@@deriving hardcaml]
  end
```

As you can see, the design takes as inputs a clock, clear, enable, and the problem size. Making those maximum indices top level inputs was a bit of shortcut. Were I to synthesize this into hardware, I would stamp some predetermined part of memory with those values through a similar mechanism to however the memory is initialized (perhaps by a host CPU).

This top level also makes design parameters clear. The circuit can be adjusted to accommodate different ID widths (in bits), a different maximum number of IDs and ranges, and an arbitrary number of execution units (I even tested to make sure it worked with weird numbers like one or three). The address bit widths are worked out internally to fit the parameterized memory sizes.

### Memory (Again)

After all of that analysis of different ways to cascade memory, I opted for two monolithic blocks, one for IDs and one for ID ranges. Inferring the right memory blocks from behavioral Verilog is finicky enough that I did not think it was worthwhile to build something more complicated on assumptions that would change depending on the hardware. Moreover, appropriately cascading the memory blocks in width and depth is non-trivial, although I am certain it would be much easier to do in Hardcaml than Verilog or VHDL. For simplicity, I also introspect the design in the testbench to populate its memory with parsed input.

## Performance Analysis

To demonstrate that this design is actually highly parallel, below is the rough number of cycles (excluding two or three cycles for resetting and providing the input signals) it took to compute the solution to my Advent of Code provided input. In this table, `Speedup = Old num cycles / New num cycles`

| Number of Execution Units | Rough Number of Cycles | Speedup Compared to Single Execution Unit |
| :------------------------ | :--------------------- | :---------------------------------------- |
| 1                         | 105516                 | 1                                         |
| 2                         | 52593                  | 2                                         |
| 8                         | 13490                  | 7.8                                       |
| 32                        | 3403                   | 31                                        |
| 64                        | 1821                   | 57.9                                      |
| 128                       | 1179                   | 89.5                                      |
| 1000                      | 1179                   | 89.5                                      |

As you can see, we start off very strongly with a linear and then near linear speedup through 32 execution units. We get a slight drop off at 64, but hit a real plateau by 128 execution units.

The fact that 128 and 1000 execution units take the exact same number of cycles is revelatory for how the problem size and memory bandwidth directly impact throughput. You may recall that this input has roughly 1000 IDs. If we could fetch all of these IDs in a single cycle, then we would saturate 1000 execution units and our execution time upper bound would be the number of cycles to read every range. However, in the real world we can only fetch one ID per cycle, so it takes roughly 1000 cycles just to feed every execution unit. Feeding the execution units becomes our bottleneck with just 128 of them, where those 1000 cycles make up nearly 85% of the total runtime. Adding more past the point stops helping us because each execution units takes at most the 180 cycles to check every ID range for a given ID. You may have even noticed that the total number of cycles taken comes down to pretty much exactly that: The 1179 cycles total is 1000 cycles of ID fetching plus 179 cycles of execution.

The reason we see this number at 128 is that over the 1000 cycles of pipeline fill time it takes to fetch these IDs, the first execution unit fed has the time to check $1000 / 180 \approx 5.56$ IDs. If the IDs are not pathologically distributed to require checking every range, checking a single ID is even quicker in practice.

While the ability to fetch more IDs per cycle would alleviate this bottleneck, it is worth pointing out the 1000 IDs is still a rather small number. The 128 cycles it takes to saturate 128 execution units with just a single ID per execution unit make up a significant percentage of the 1000 cycles to fill our pipeline. Checking a larger number of IDs shrinks this ratio in our favor and would prolong the gorgeous linear speedup trend.

## Neat Hardcaml Language Features

As I implemented my design in Hardcaml, I thought it useful to highlight a few of the language features that I appreciated:

- The type system made things quite clean in some cases. In particular, defining nested interfaces with records and wrapping some signals in `With_valid` was aesthetically pleasing and helped a bit with maintaining correctness while gluing together some of my modules which output results after an unknown delay.
- OCaml's general functional programming features made it a lot more enjoyable than it would have been in SystemVerilog to stamp out and wire together parallel components like the execution units.

In [hardcaml_improvements.md](hardcaml_improvements.md), I also included some very half baked notes on gaps in the Hardcaml documentation and other rough edges I encountered.

## Ideas for Future Improvements

- Make this design super-scalar by building a crazy fetching mechanism to read one ID from each depth cascaded memory block every cycle.
- Power/heat savings by putting the ID fetcher into a lower power state when not needed.
- I have some invariants I would love to formally prove about portions of this design.
- Investigate the performance benefits (or lack thereof) of encoding ranges as `start + offset`.

## Running the Design

### Setup

Follow the instructions from the [Hardcaml template](https://github.com/janestreet/hardcaml_template_project/tree/with-extensions) to install an OxCaml switch with the Hardcaml libraries.

### Simulation and Generation

```shell
dune build
dune test

# Run to generate Verilog of my design, note that it is parameterized separately in `generate.ml` and `test_top.ml`
dune exec hardcaml_solution top 
```

As Advent of Code does not like participants sharing their provided inputs, you are unfortunately stuck with my small, handcrafted test inputs. I do promise that I validated my results against my actual, much larger input.

### Waveforms

The testbench writes to `/tmp/top_waves.vcd`. You can change the input used for this waveform by editing the last line of my admittedly sloppy testbench `test_top.ml` (don't worry, there is a comment explaining the rough edge with `dune`).

## Acknowledgements

I relied very heavily on the [Hardcaml Manual](https://www.janestreet.com/web-app/hardcaml-docs/), so thank you for making this project and all of that documentation available! As I mentioned above, the `onehot_cleaner.(ml|mli)` files were taken straight from [hardcaml_circuits](https://github.com/janestreet/hardcaml_circuits) and are themselves a very cool and clever example of defining a circuit generator recursively.
