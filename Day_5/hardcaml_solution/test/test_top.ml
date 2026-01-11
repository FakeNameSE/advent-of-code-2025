open! Core
open! Hardcaml
open! Hardcaml_waveterm
open! Hardcaml_test_harness

(* let ( <--. ) = Bits.( <--. ) *)

module Top = Hardcaml_advent_of_code_day_5.Top.Make (struct
    let id_width = 64
    let id_mem_size_in_ids = 2000
    let id_range_mem_size_in_ranges = 500
  end)

module Sim = Cyclesim.With_interface (Top.I) (Top.O)

let create_sim () =
  let scope = Scope.create ~flatten_design:true () in
  (* trace_all needed to get more (but not all) useful signals in waveform. *)
  Sim.create ~config:Cyclesim.Config.trace_all (Top.hierarchical scope)
;;

let assign_mem dst ~address src = Cyclesim.Memory.of_bits dst ~address src

let initialize_memories id_ram id_range_ram =
  let parsed_input = Parse_input.Parse.parse_challenge_input "inputs/input.txt" in
  (* let Bits.of_unsigned_int ~width:(Cyclesim.Memory.width_in_bits dst) *)
  let id_ram_width = Cyclesim.Memory.width_in_bits id_ram in
  (* Seq.iter (fun Id id-> assign_mem id_ram ~address) parsed_input.ids *)
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

let step fetched_id_node sim =
  (* Cyclesim.lookup_mem_by_name  *)
  let fetched_id = Cyclesim.Node.to_int fetched_id_node in
  Stdio.print_s [%message "" ~_:(fetched_id : int)];
  Cyclesim.cycle sim
;;

let testbench (sim : Sim.t) : Waveform.t =
  let waves, sim = Waveform.create sim in
  let traced = Cyclesim.traced sim in
  print_endline "test...";
  print_endline (Sexp.to_string_hum (Cyclesim.Traced.sexp_of_t traced));
  let id_ram = Cyclesim.lookup_mem_by_name sim "id_ram" |> Option.value_exn in
  let id_range_ram = Cyclesim.lookup_mem_by_name sim "id_range_ram" |> Option.value_exn in
  let fetched_id =
    Cyclesim.lookup_node_or_reg_by_name sim "top$fetched_id" |> Option.value_exn
  in
  let _fetched_id_range =
    Cyclesim.lookup_node_or_reg_by_name sim "top$fetched_id_range" |> Option.value_exn
  in
  let i, o = Cyclesim.inputs sim, Cyclesim.outputs sim in
  Cyclesim.reset sim;
  i.clear := Bits.vdd;
  initialize_memories id_ram id_range_ram;
  step fetched_id sim;
  i.clear := Bits.gnd;
  step fetched_id sim;
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
  waves
;;

(* i.enable := Bits.vdd;
  (* inputs.id := With_valid.{valid = Bits.of_bool true; value = (Bits.of_unsigned_int 42 ~width:64)}; *)
  (* TODO: Figure out how to pass a With_valid here directly. *)
  i.id.value := Bits.of_unsigned_int 50 ~width:64;
  i.id.valid := Bits.of_bool true;
  cycle ();
  i.id_range_a <--. 80;
  i.id_range_b <--. 100;
  i.id_range_idx <--. 0;
  i.id_range_valid := Bits.of_bool true;
  cycle ();
  i.id_range_a <--. 50;
  i.id_range_b <--. 100;
  i.id_range_idx <--. 1;
  i.id_range_valid := Bits.of_bool true;
  cycle ();
  i.id_range_a <--. 55;
  i.id_range_b <--. 80;
  i.id_range_idx <--. 2;
  i.id_range_valid := Bits.of_bool true;
  cycle ();
  i.id_range_a <--. 80;
  i.id_range_b <--. 100;
  i.id_range_idx <--. 0;
  i.id_range_valid := Bits.of_bool true;
  cycle ();
  i.id_range_a <--. 50;
  i.id_range_b <--. 100;
  i.id_range_idx <--. 1;
  i.id_range_valid := Bits.of_bool true;
  cycle ();
  i.id_range_a <--. 55;
  i.id_range_b <--. 180;
  i.id_range_idx <--. 2;
  i.id_range_valid := Bits.of_bool true;
  cycle ();
  waves *)

let sim = create_sim ()

(* let waves = testbench sim;;
Waveform.print waves;; *)

let save_waves sim =
  let filename = "/tmp/top_waves.vcd" in
  let oc = Stdlib.Out_channel.open_text filename in
  let sim = Vcd.wrap oc sim in
  let _ = testbench sim in
  (* Closing the out channel will ensure the file is flushed to disk *)
  Out_channel.close oc;
  Stdio.print_endline ("Saved waves to " ^ filename)
;;

save_waves sim
