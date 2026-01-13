open! Core
open! Hardcaml
open! Hardcaml_waveterm
open! Hardcaml_test_harness

(* TODO: Clean this up a lot. *)
(* TODO: Consider property testing with randomized generation of larger inputs.  *)

let ( <--. ) = Bits.( <--. )

module Top = Hardcaml_advent_of_code_day_5.Top.Make (struct
    let id_width = 64
    let id_mem_size_in_ids = 2000
    let id_range_mem_size_in_ranges = 500
    let num_execution_units = 128
  end)

module Sim = Cyclesim.With_interface (Top.I) (Top.O)

let create_sim () =
  let scope = Scope.create ~flatten_design:true () in
  (* trace_all needed to get more (but not all) useful signals in waveform. *)
  Sim.create ~config:Cyclesim.Config.trace_all (Top.hierarchical scope)
;;

let assign_mem dst ~address src = Cyclesim.Memory.of_bits dst ~address src

let initialize_memories
  (parsed_input : Parse_input.Parse.Parsed_input.t)
  id_ram
  id_range_ram
  =
  let id_ram_width = Cyclesim.Memory.width_in_bits id_ram in
  List.iteri parsed_input.ids ~f:(fun i (Id id) ->
    assign_mem id_ram ~address:i (Bits.of_unsigned_int ~width:id_ram_width id));
  List.iteri parsed_input.bounds ~f:(fun i bound ->
    let { lower_bound = Id a; upper_bound = Id b } = bound in
    let concatenated =
      Bits.concat_msb (List.map [ a; b ] ~f:(Bits.of_unsigned_int ~width:64))
    in
    assign_mem id_range_ram ~address:i concatenated)
;;

(* Seq.iter
    (fun i -> assign_mem id_ram ~address:i (i))
    (Seq.init 1000 (fun x -> x));
  Seq.iter
    (fun i -> assign_mem id_range_ram ~address:i (i + 400))
    (Seq.init 1000 (fun x -> x)) *)

let testbench (sim : Sim.t) (parsed_input : Parse_input.Parse.Parsed_input.t) =
  let waves, sim = Waveform.create sim in
  (* Useful for getting the mangled names of internal signals. *)
  (* let traced = Cyclesim.traced sim in
  print_endline "test...";
  print_endline (Sexp.to_string_hum (Cyclesim.Traced.sexp_of_t traced)); *)
  let id_ram = Cyclesim.lookup_mem_by_name sim "id_ram" |> Option.value_exn in
  let id_range_ram = Cyclesim.lookup_mem_by_name sim "id_range_ram" |> Option.value_exn in
  let _fetched_id_range =
    Cyclesim.lookup_node_or_reg_by_name sim "top$fetched_id_range" |> Option.value_exn
  in
  let i, o = Cyclesim.inputs sim, Cyclesim.outputs sim in
  Cyclesim.reset sim;
  i.enable := Bits.gnd;
  i.clear := Bits.vdd;
  initialize_memories parsed_input id_ram id_range_ram;
  Cyclesim.cycle sim;
  i.clear := Bits.gnd;
  i.max_id_idx <--. List.length parsed_input.ids - 1;
  i.max_id_range_idx <--. List.length parsed_input.bounds - 1;
  Cyclesim.cycle sim;
  i.enable := Bits.vdd;
  Cyclesim.cycle sim;
  (* Run until design says we are done. *)
  let num_cycles = ref 0 in
  while not (Bits.to_bool !(o.num_ids_in_range.valid)) do
    Cyclesim.cycle sim;
    num_cycles := !num_cycles + 1
  done;
  (* Wait one more cycle to be safe. *)
  Cyclesim.cycle sim;
  printf
    "Number of ids in range: %d, computation took roughly %d cycles.\n"
    (Bits.to_unsigned_int !(o.num_ids_in_range.value))
    !num_cycles;
  o, waves
;;

let sim = create_sim ()

let run_and_save_waves sim parsed_input =
  let filename = "/tmp/top_waves.vcd" in
  let oc = Stdlib.Out_channel.open_text filename in
  let sim = Vcd.wrap oc sim in
  let o, _waves = testbench sim parsed_input in
  (* Closing the out channel will ensure the file is flushed to disk *)
  Out_channel.close oc;
  Stdio.print_endline ("Saved waves to " ^ filename);
  o
;;

let test input_path =
  (* Compare module output to software solution. *)
  let parsed_input = Parse_input.Parse.parse_challenge_input input_path in
  let output, _ = testbench sim parsed_input in
  let num_ids_in_range = Bits.to_unsigned_int !(output.num_ids_in_range.value) in
  let expected_num_ids_in_range = Software_solution.Solution.solve_part_1 parsed_input in
  num_ids_in_range = expected_num_ids_in_range
;;

let%test "smallest_input" = test "inputs/small_input.txt"
let%test "fairly_small_input" = test "inputs/own_input.txt"

(* Change path here to generate waveform for a given input. 
You will needs to edit the deps clause in the test dune file if you want to reference a new file here. *)
let _ =
  Parse_input.Parse.parse_challenge_input "inputs/own_input.txt" |> run_and_save_waves sim
;;

(* let waves = testbench sim;;
Waveform.print waves;; *)
