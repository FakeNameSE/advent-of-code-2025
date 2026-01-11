(* We generally open Core and Hardcaml in any source file in a hardware project. For
   design source files specifically, we also open Signal. *)
open! Core
open! Hardcaml
open! Signal

(* Taken straight from hardcaml's ram.ml *)
let if_write_before_read_mode ~collision_mode (r : _ Read_port.t array) =
  match (collision_mode : Ram.Collision_mode.t) with
  | Write_before_read ->
    Array.map r ~f:(fun r ->
      Signal.reg
        (Reg_spec.create () ~clock:r.read_clock)
        ~enable:r.read_enable
        r.read_address)
  | Read_before_write -> Array.map r ~f:(fun r -> r.read_address)
;;

(* Taken straight from hardcaml's ram.ml *)
let if_read_before_write_mode
  ~collision_mode
  (r : _ Read_port.t array)
  (q : Signal.t array)
  =
  match (collision_mode : Ram.Collision_mode.t) with
  | Write_before_read -> q
  | Read_before_write ->
    Array.map2_exn r q ~f:(fun r q ->
      Signal.reg (Reg_spec.create () ~clock:r.read_clock) ~enable:r.read_enable q)
;;

let create
  ?attributes
  ?initialize_to
  ?name
  ~collision_mode
  ~size
  ~write_ports
  ~read_ports
  ()
  =
  Signal.multiport_memory
    ?attributes
    ?initialize_to
    ?name
    size
    ~write_ports
    ~read_addresses:(if_write_before_read_mode ~collision_mode read_ports)
  |> if_read_before_write_mode ~collision_mode read_ports
;;
