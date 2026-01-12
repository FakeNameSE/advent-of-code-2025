(* We generally open Core and Hardcaml in any source file in a hardware project. For
   design source files specifically, we also open Signal. *)
open! Core
open! Hardcaml
open! Signal

module type Config = sig
  val id_width : int
  val id_mem_size_in_ids : int
  val id_range_mem_size_in_ranges : int
  val num_execution_units : int
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
    (* TODO: Output counter is currently sized to the minimum number of bits required to represent all of the ids. 
    Consider setting it to the next power of two up if that would play nicer with the hardware target. *)
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
    let%hw execution_units_ready = wire Config.num_execution_units in
    (* Use this circuit from hardcaml_circuits to pick the next available execution unit to use. 
    Takes a bit vector of available execution units and returns a one hot encoding with that bit corresponding to one of the available ones. *)
    let Onehot_clean.
          { any_bit_set = any_execution_unit_ready; data = execution_unit_enables }
      =
      Onehot_clean.scan_from_msb (module Signal) execution_units_ready
    in
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
    (* Write size used to determine data width in memory. *)
    let id_ram_write_port =
      { Write_port.write_clock = i.clock
      ; write_address = zero id_address_size
      ; write_enable = gnd
      ; write_data = zero Config.id_width
      }
    in
    (* TODO: Intelligently break up according to block size. *)
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
        { Id_range_fetcher.I.clock = i.clock
        ; clear = i.clear
        ; enable = i.enable
        ; max_id_range_idx = i.max_id_range_idx
        }
    in
    let id_range_ram_read_port =
      { Read_port.read_clock = id_range_fetcher.read_clock
      ; read_address = id_range_fetcher.read_address
      ; read_enable = id_range_fetcher.read_enable
      }
    in
    (* Used to determine data width in memory. *)
    let id_range_ram_write_port =
      { Write_port.write_clock = i.clock
      ; write_address = zero id_range_address_size
      ; write_enable = gnd
      ; write_data = zero (2 * Config.id_width)
      }
    in
    (* TODO: Intelligently break up according to block size. *)
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
    (* Stamp out the configured number of execution units and wire them up. *)
    let create_execution_unit exec_unit_idx =
      Execution_unit.hierarchical
        scope
        { Execution_unit.I.clock = i.clock
        ; clear = i.clear
        ; enable =
            i.enable
            &: ~:(id_fetcher.all_ids_fetched)
            &: execution_unit_enables.:(exec_unit_idx)
        ; id = { With_valid.valid = id_fetcher.id_is_valid; value = fetched_id }
        ; id_range =
            { valid = id_range_fetcher.id_range_is_valid
            ; value = { lower; upper; idx = id_range_fetcher.curr_id_range_idx }
            }
        }
    in
    let execution_units = List.init Config.num_execution_units ~f:create_execution_unit in
    Signal.(
      execution_units_ready
      <-- concat_lsb (List.map execution_units ~f:(fun exec_unit -> exec_unit.ready)));
    let execution_units_in_range =
      List.map execution_units ~f:(fun exec_unit -> exec_unit.is_in_range)
    in
    Signal.(fetch_next_id <-- (any_execution_unit_ready &: i.enable));
    (* TODO: Parameterize arity? *)
    (* TODO: More intelligently build adder tree with different bit widths at each level. *)
    (* Compute the number of ids we found in range this cycle. *)
    (* The final stage in our pipeline is adding the number of ids found in range this cycle by all of our execution units.
    First, we and each result with its valid bit to mask out those which are not ready, 
    then we use an adder tree to add all of these bits up, resizing the counter to avoid overflow. *)
    let%hw next_num_ids_in_range_increment =
      List.map execution_units_in_range ~f:(fun With_valid.{ valid; value } ->
        uresize ~width:(num_bits_to_represent Config.num_execution_units) (valid &: value))
      |> tree ~arity:4 ~f:(reduce ~f:( +: ))
    in
    let next_num_ids_in_range old_num_ids_in_range =
      old_num_ids_in_range
      +: uresize ~width:(width old_num_ids_in_range) next_num_ids_in_range_increment
    in
    let%hw num_ids_in_range =
      reg_fb ~width:num_ids_in_range_size ~f:next_num_ids_in_range spec
    in
    (* Delay valid signal by one cycle to allow the counter register to catch up. *)
    let finished =
      pipeline ~n:1 spec (id_fetcher.all_ids_fetched &: all_bits_set execution_units_ready)
    in
    { O.num_ids_in_range = { value = num_ids_in_range; valid = finished } }
  ;;

  (* The [hierarchical] wrapper is used to maintain module hierarchy in the generated
   waveforms and (optionally) the generated RTL. *)
  let hierarchical scope =
    let module Scoped = Hierarchy.In_scope (I) (O) in
    Scoped.hierarchical ~scope ~name:"top" create
  ;;
end
