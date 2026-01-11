open! Core
open! Hardcaml
open! Hardcaml_waveterm
open! Hardcaml_test_harness

module Execution_unit = Hardcaml_advent_of_code_day_5.Execution_unit.Make (struct
    let id_width = 64
    let id_range_address_size = 16
  end)

(* let ( <--. ) = Bits.( <--. ) *)

module Sim = Cyclesim.With_interface (Execution_unit.I) (Execution_unit.O)

let create_sim () =
  let scope = Scope.create ~flatten_design:true () in
  Sim.create (Execution_unit.hierarchical scope)
;;

let testbench (sim : Sim.t) : Waveform.t =
  let waves, sim = Waveform.create sim in
  let i, _o = Cyclesim.inputs sim, Cyclesim.outputs sim in
  let cycle ?n () = Cyclesim.cycle ?n sim in
  i.clear := Bits.vdd;
  cycle ();
  i.clear := Bits.gnd;
  i.enable := Bits.vdd;
  (* inputs.id := With_valid.{valid = Bits.of_bool true; value = (Bits.of_unsigned_int 42 ~width:64)}; *)
  (* TODO: Figure out how to pass a With_valid here directly. *)
  i.id.value := Bits.of_unsigned_int 50 ~width:64;
  i.id.valid := Bits.of_bool true;
  cycle ();
  (* i.id_range_a <--. 80;
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
  i.id_range_valid := Bits.of_bool true; *)
  cycle ();
  waves
;;

let sim = create_sim ()

(* let waves = testbench sim;;
Waveform.print waves;; *)

let save_waves sim =
  let filename = "/tmp/waves.vcd" in
  let oc = Stdlib.Out_channel.open_text filename in
  let sim = Vcd.wrap oc sim in
  let _ = testbench sim in
  (* Closing the out channel will ensure the file is flushed to disk *)
  Out_channel.close oc;
  Stdio.print_endline ("Saved waves to " ^ filename)
;;

save_waves sim
