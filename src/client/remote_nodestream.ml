(*
Copyright (2010-2014) INCUBAID BVBA

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*)



open Value
open Interval
open Routing
open Common
open Lwt
open Client_cfg
open Ncfg

let section = Logger.Section.main

class type nodestream = object
  method iterate:
    Sn.t -> (Sn.t * Value.t -> unit Lwt.t) ->
    Tlogcollection.tlog_collection ->
    head_saved_cb:(string -> unit Lwt.t) -> unit Lwt.t

  method collapse: int -> unit Lwt.t

  method set_routing: Routing.t -> unit Lwt.t
  method set_routing_delta: string -> string -> string -> unit Lwt.t
  method get_routing: unit -> Routing.t Lwt.t

  method optimize_db: unit -> unit Lwt.t
  method defrag_db: unit -> unit Lwt.t
  method get_db: string -> unit Lwt.t

  method pinch_fringe: Routing.range_direction ->
                       ((string * string) list * (string * string option)) Lwt.t
  method accept_fringe: string -> string option -> (string * string) list -> unit Lwt.t
  method remove_fringe: string -> string option -> unit Lwt.t
  method get_interval : unit -> Interval.t Lwt.t

  method store_cluster_cfg : string -> ClientCfg.t -> unit Lwt.t

  method get_nursery_cfg: unit -> NCFG.t Lwt.t

  method drop_master: unit -> unit Lwt.t
end

class remote_nodestream ((ic,oc) as conn) = object(self :# nodestream)
  method iterate (i:Sn.t) (f: Sn.t * Value.t -> unit Lwt.t)
           (tlog_coll: Tlogcollection.tlog_collection)
           ~head_saved_cb
    =
    let outgoing buf =
      command_to buf LAST_ENTRIES2;
      Sn.sn_to buf i
    in
    let incoming ic =
      let save_head () = tlog_coll # save_head ic in
      let last_seen = ref None in
      let rec loop_entries () =
        Sn.input_sn ic >>= fun i2 ->
        begin
          if i2 = (-1L)
          then
            begin
              Logger.info_f_ "remote_nodestream :: last_seen = %s"
                (Log_extra.option2s Sn.string_of !last_seen)
            end
          else
            begin
              last_seen := Some i2;
              Llio.input_int32 ic >>= fun chksum ->
              Llio.input_string ic >>= fun entry ->
              let value = Value.value_from (Llio.make_buffer entry 0) in
              f (i2, value) >>= fun () ->
              loop_entries ()
            end
        end
      in
      let rec loop_parts () =
        Llio.input_int ic >>= function
        | (-2) -> Logger.info_f_ "loop_parts done"
        | 1 ->
          begin
            Logger.debug_f_ "loop_entries" >>= fun () ->
            loop_entries () >>= fun () ->
            loop_parts ()
          end
        | 2 ->
          begin
            Logger.info_f_ "save_head" >>= fun ()->
            save_head () >>= fun () ->
            let hf_name = tlog_coll # get_head_name () in
            head_saved_cb hf_name >>= fun () ->
            loop_parts ()
          end
        | 3 ->
          begin
            Logger.debug_f_ "save_file" >>= fun () ->
            Llio.input_string ic >>= fun name ->
            Llio.input_int64 ic >>= fun length ->
            Logger.info_f_ "got %s (%Li bytes)" name length >>= fun () ->
            tlog_coll # save_tlog_file name length ic >>= fun () ->
            loop_parts ()
          end
        | x  -> Llio.lwt_failfmt "don't know what %i means" x
      in
      loop_parts()
    in
    request  oc outgoing >>= fun () ->
    response ic incoming


  method collapse n =
    let outgoing buf =
      command_to buf COLLAPSE_TLOGS;
      Llio.int_to buf n
    in
    let incoming ic =
      Llio.input_int ic >>= fun collapse_count ->
      let rec loop i =
        if i = 0
        then Lwt.return ()
        else
          begin
            Llio.input_int ic >>= function
            | 0 ->
              Llio.input_int64 ic >>= fun took ->
              Logger.debug_f_ "collapsing one file took %Li" took >>= fun () ->
              loop (i-1)
            | e ->
              Llio.input_string ic >>= fun msg ->
              Llio.lwt_failfmt "%s (EC: %d)" msg e
          end
      in
      loop collapse_count
    in
    request  oc outgoing >>= fun () ->
    response ic incoming


  method get_interval () = Common.get_interval conn

  method get_routing () = Common.get_routing conn

  method set_routing r = Common.set_routing conn r

  method set_routing_delta left sep right = Common.set_routing_delta conn left sep right

  method optimize_db () = Common.optimize_db conn

  method defrag_db () = Common.defrag_db conn
  method get_db db_location =

    let outgoing buf =
      command_to buf GET_DB;
    in
    let incoming ic =
      Llio.input_int64 ic >>= fun length ->
      Lwt_io.with_file ~mode:Lwt_io.output db_location (fun oc -> Llio.copy_stream ~length ~ic ~oc)
    in
    request  oc outgoing >>= fun () ->
    response ic incoming

  method pinch_fringe direction= Common.pinch_fringe conn direction

  method accept_fringe left right kvs = Common.accept_fringe conn left right kvs

  method remove_fringe left right = Common.remove_fringe conn left right

  method store_cluster_cfg cluster_id cfg =
    Common.set_nursery_cfg (ic,oc) cluster_id cfg

  method get_nursery_cfg () =
    Common.get_nursery_cfg (ic,oc)

  method drop_master () =
    Common.drop_master conn
end

let make_remote_nodestream cluster connection =
  prologue cluster connection >>= fun () ->
  let rns = new remote_nodestream connection in
  let a = (rns :> nodestream) in
  Lwt.return a
