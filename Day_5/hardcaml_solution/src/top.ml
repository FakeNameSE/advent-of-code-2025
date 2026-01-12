(* We generally open Core and Hardcaml in any source file in a hardware project. For
   design source files specifically, we also open Signal. *)
open! Core
open! Hardcaml
open! Signal

module type Config = sig
  val id_width : int
  val id_mem_size_in_ids : int
  val id_range_mem_size_in_ranges : int
end

module Make (Config : Config) = struct
  let id_address_size = address_bits_for Config.id_mem_size_in_ids
  let id_range_address_size = address_bits_for Config.id_range_mem_size_in_ranges
  let num_ids_in_range_size = num_bits_to_represent Config.id_mem_size_in_ids

  module I = struct
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; enable : 'a
      ; max_id_idx : 'a [@bits id_address_size]
      ; max_id_range_idx : 'a [@bits id_range_address_size]
      }
    [@@deriving hardcaml]
  end

  module O = struct
    (* TODO: Set output counter to the minimum number of bits required to represent all of the ids. 
    Consider setting it to the next power of two up if that would play nicer with the hardware target.  *)
    type 'a t = { num_ids_in_range : 'a With_valid.t [@bits num_ids_in_range_size] }
    [@@deriving hardcaml]
  end

  module Id_fetcher = Id_fetcher.Make (struct
      let id_address_size = id_address_size
    end)

  module Id_range_fetcher = Id_range_fetcher.Make (struct
      let id_range_address_size = id_range_address_size
    end)

  module Execution_unit = Execution_unit.Make (struct
      let id_width = Config.id_width
      let id_range_address_size = id_range_address_size
    end)

  let create scope (i : _ I.t) : _ O.t =
    let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
    let fetch_next_id = wire 1 in
    (* TODO: Parameterize width of this. *)
    let id_fetcher =
      Id_fetcher.hierarchical
        scope
        { Id_fetcher.I.clock = i.clock
        ; clear = i.clear
        ; enable = fetch_next_id
        ; max_id_idx = i.max_id_idx
        }
    in
    let id_ram_read_port =
      { Read_port.read_clock = id_fetcher.read_clock
      ; read_address = id_fetcher.read_address
      ; read_enable = id_fetcher.read_enable
      }
    in
    (* Write size used to determine data width in memory. Parameterize instead of hardcoding. *)
    let id_ram_write_port =
      { Write_port.write_clock = i.clock
      ; write_address = zero id_address_size
      ; write_enable = gnd
      ; write_data = zero Config.id_width
      }
    in
    (* TODO: Parameterize size of this, intelligently break up according to block size. *)
    let id_ram =
      (Ram.create
         ~name:"id_ram"
         ~collision_mode:Write_before_read
         ~size:Config.id_mem_size_in_ids
         ~write_ports:[| id_ram_write_port |]
         ~read_ports:[| id_ram_read_port |])
        ()
    in
    let%hw fetched_id = id_ram.(0) in
    let id_range_fetcher =
      Id_range_fetcher.hierarchical
        scope
        { Id_range_fetcher.I.clock = i.clock; clear = i.clear; enable = i.enable; max_id_range_idx = i.max_id_range_idx }
    in
    let id_range_ram_read_port =
      { Read_port.read_clock = id_range_fetcher.read_clock
      ; read_address = id_range_fetcher.read_address
      ; read_enable = id_range_fetcher.read_enable
      }
    in
    (* Used to determine data width in memory. Parameterize instead of hardcoding. *)
    let id_range_ram_write_port =
      { Write_port.write_clock = i.clock
      ; write_address = zero id_range_address_size
      ; write_enable = gnd
      ; write_data = zero (2 * Config.id_width)
      }
    in
    (* TODO: Parameterize size of this, intelligently break up according to block size. *)
    let id_range_ram =
      (Ram.create
         ~name:"id_range_ram"
         ~collision_mode:Write_before_read
         ~size:Config.id_range_mem_size_in_ranges
         ~write_ports:[| id_range_ram_write_port |]
         ~read_ports:[| id_range_ram_read_port |])
        ()
    in
    let%hw fetched_id_range = id_range_ram.(0) in
    let lower, upper = split_in_half_msb fetched_id_range in
    let execution_unit_1 =
      Execution_unit.hierarchical
        scope
        { Execution_unit.I.clock = i.clock
        ; clear = i.clear
        ; enable = i.enable
        ; id = { With_valid.valid = id_fetcher.id_is_valid; value = fetched_id }
        ; id_range =
            { valid = id_range_fetcher.id_range_is_valid
            ; value = { lower; upper; idx = id_range_fetcher.curr_id_range_idx }
            }
        }
    in
    Signal.(fetch_next_id <-- (execution_unit_1.ready &: i.enable));
    let next_num_ids_in_range old_num_ids_in_range =
      mux
        (execution_unit_1.is_in_range.valid &: execution_unit_1.is_in_range.value)
        [ old_num_ids_in_range; old_num_ids_in_range +:. 1 ]
    in
    let%hw num_ids_in_range =
      reg_fb ~width:num_ids_in_range_size ~f:next_num_ids_in_range spec
    in
    (* let next_num_ids_in_range = mux execution_unit_1.is_in_range.valid [] in *)
    { O.num_ids_in_range =
        { value = num_ids_in_range
        ; valid = id_fetcher.all_ids_fetched &: execution_unit_1.ready
        }
    }
  ;;

  (* The [hierarchical] wrapper is used to maintain module hierarchy in the generated
   waveforms and (optionally) the generated RTL. *)
  let hierarchical scope =
    let module Scoped = Hierarchy.In_scope (I) (O) in
    Scoped.hierarchical ~scope ~name:"top" create
  ;;
end
