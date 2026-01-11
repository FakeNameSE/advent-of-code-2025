(** Random access memories described using RTL inference.

    Can be specified with arbitrary numbers of read and write ports, though in reality
    only up to 1 of each can be inferred by a synthesizer.

    Slightly extended from Hardcaml library version to expose the initialize_to argument
    while keeping the nice synchronous read for realism. *)

open! Core
open! Hardcaml

val create
  :  ?attributes:Rtl_attribute.t list
  -> ?initialize_to:Bits.t array
  -> ?name:string
  -> collision_mode:Ram.Collision_mode.t
  -> size:int
  -> write_ports:Signal.t Write_port.t array
  -> read_ports:Signal.t Read_port.t array
  -> unit
  -> Signal.t array
