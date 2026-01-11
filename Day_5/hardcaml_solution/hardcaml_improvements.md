# Notes on Rough Edges I Ran Into While Learning Hardcaml

As a hobbyist Ocaml and FPGA developer, I had a great time picking up Hardcaml. It solves a lot of the unpleasantness of Verilog and VHDL. The notes below are not criticism, just some of the hurdles I ran into trying to get a design off the ground.

## Possible Bug
When I run `dune test` (including with the template project), dune seems to be rerunning my tests about 12 or 13 times. With hyperthreading I have 16 cores, so I am not sure if there is some sort of concurrency bug. This made tests which print ASCII waveforms to the terminal pretty annoying to run. I am unsure if this issue is related to OxCaml, dune, or something else. My project was based on the template linked from the Hardcaml repository, so I do not think the issue is my own project configuration.  

## Missing Memory Documentation
- Missing good way to initialize RAM, multiport primitive technically supports passing `?initialize_to`, but undocumented and not exposed from Ram module. Also clunky because the passed data has to exactly match the memory size.
- Had to look in source to find how RAM data width is determined. Possibly because everyone is using Xilinx lib, which also does not support initializing RAM.
- Also, what is size for memory? Number of words, bytes, ...?
- Likely ignorance on my part, but could not figure out how to use Read_port.t as nested interface for a module.

## Missing Documentation Related to Registers
- Missing documentation on default state in always DSL state machine
- Difference between reset and clear in reg_spec is not spelled out in an obvious place (my understanding is that reset is asynchronous).
- Registers can also be passed arguments like `?reset`, `?reset_to`, `?clear`, and `?clear_to`. Documentation does not cover these, and it is unclear (pun intended) whether these override the spec, the other way around, and what their default values are.

## Challenges with Simulation
- Handbook very confusion for creating a working simulation, does not do a great job of explaining difference between simulation and waveform. Many of the examples use different approaches without really explaining them, and the template project uses `Cyclesim_harness` which is not covered anywhere else. I would appreciate an explanation of the tradeoffs and a more standard full example without having to trawl Github. Additionally, the template project's example does not handle scopes, and it was tricky for me to figure out how to merge what it was doing in simulation setup with a hierarchical design.
- Cyclesim functions to modify memory very underdocumented, had to find random example via GitHub code search to work out intended way to initialize memory with Cyclesim.Memory.of_bits. While the type signature is a little self explanatory, that did not help me while searching, nor did it clarify a recommended or idiomatic way to initialize memory.
- I was running into trouble with getting a hierarchical design to expose all of its internal signals in my VCD waveform output, despite calling `Sim.create ~config:Cyclesim.Config.trace_all`. Some documentation with a more in-depth explanation of what signals are traced with a hierarchical design would be helpful.

## Rough Edge with Ocaml Exacerbated by Hardcaml Interface Abstraction
- General Ocaml problem, but unsure about best way to avoid unnecessary duplication between interface and implementation files, particularly for the input/output modules and any Config module I was defining to parameterize my modules (most egregious here because I need to define an actual module rather than a signature in both files). Have seen some trick involving an extra intf file to avoid this, but could not find a good explanation for it and did not find it to be particularly clean either. This could also be a product of my own ignorance.
- I ran into some issues with `dune pkg lock` due to using OxCaml. Due to the experimental nature of OxCaml, it would be nice to know what the tradeoffs are of using it vs. regular OCaml for Hardcaml development. 