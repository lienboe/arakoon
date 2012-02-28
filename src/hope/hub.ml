open Lwt
open Pq

open Core

let _log f = Printf.kprintf Lwt_io.printl f


open One
module X = ONE;;


module HUB(S:STORE) = struct
  type t = {msgs : X.msg PQ.q; 
            reqs : (X.id * update * result Lwt.u) PQ.q;
            mapping : (X.id, result Lwt.u) Hashtbl.t;
            store : S.t;
           }
  let create () = 
    let r = 
      {msgs = PQ.create (); reqs = PQ.create (); 
       mapping= Hashtbl.create 7;
       store = S. create ();
      } 
    in 
    let () = PQ.push r.msgs (X.M_TIMEOUT X.start) in 
    r

  let wait_for_msg t s d = 
    let maybe_timeout () = Lwt_unix.sleep d >>= fun () -> Lwt.return (X.M_TIMEOUT s) in
    let maybe_client  () = PQ.wait_for t.reqs >>= fun () -> Lwt.return (X.M_CLIENT )   in
    if PQ.is_empty t.msgs
    then 
      begin
        Lwt.pick [maybe_timeout () ;maybe_client ();] >>= fun m -> 
        PQ.push t.msgs m; 
        Lwt.return () 
      end
    else
      Lwt.return ()


  let do_action t s a = 
    match a with
      | X.A_DIE -> Lwt.fail (Failure "aaargh!!!")
      | X.A_CHOOSE -> 
        begin
          let (id,r,u) = PQ.pop t.reqs in
          let () = Hashtbl.add t.mapping id u in
          let m = X.M_CHOICE(X.V_C (id,r)) in
          let () = PQ.push t.msgs m in
          Lwt.return ()        
        end
      | X.A_PUSH v -> 
        begin
          PQ.push t.msgs (X.M_PUSHED v) ; 
          Lwt.return ()
        end
      | X.A_STORE_RETURN v -> 

        begin
          match v with
            | X.V_D -> (* do something special here *) Lwt.return ()
            | X.V_C (id,r) -> 
              S.write t.store r >>= fun () ->
              let u = Hashtbl.find t.mapping id in
              let () = Hashtbl.remove t.mapping id in
              Lwt.wakeup u UNIT;
              Lwt.return ()
        end
          
  let serve hub = 
    let dump m a s s' = 
      let c0 = X.tick_of s in
      let sn = X.sn_of s in
      let sn' = X.sn_of s' in
      _log "%s|%-10s|%-50s|%-10s|%-30s" (X.tick2s c0) (X.state_name2s sn) (X.msg2s m) 
        (X.state_name2s sn')
        (X.action2s a)
    in
    let rec loop s = 
      wait_for_msg hub s 10.0 >>= fun () ->
      let m = PQ.pop hub.msgs in
      let a, s' = X.step m s in
      dump m a s s' >>= fun () ->
      do_action hub s a >>= fun () ->
      loop s'
    in
    loop X.start

  let update hub id r = (* ID should be on inside *)
    let (w,u) = Lwt.wait () in
    let () = PQ.push hub.reqs (id, r, u) in
    w
  
  let push_msg t m = PQ.push t.msgs m 

  let get hub k = S.get hub.store k

end

