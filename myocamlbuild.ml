open Ocamlbuild_pack
open Ocamlbuild_plugin
open Unix

let run_cmd cmd =
  try
    let ch = Unix.open_process_in cmd in
    let line = input_line ch in
    let () = close_in ch in
    line
  with | End_of_file -> "Not available"

let output_cmd cmd =
  let acc = ref [] in
  let ch = Unix.open_process_in cmd in
  try
    let rec loop () =
      let line = input_line ch in
      let () = acc := line :: !acc in
      loop ()
    in
    loop ()
  with | End_of_file ->
    let () = close_in ch in
    List.rev (!acc)

let git_revision = run_cmd "git describe --all --long --always --dirty"
let tag_version = run_cmd "git describe --tags --exact-match --dirty"
let branch_version = run_cmd "git describe --all"

let machine = run_cmd "uname -mnrpio"

let compiler_version = run_cmd "ocamlopt -version"

let dependencies = output_cmd "opam list -i | grep 'lwt\\|ounit\\|camltc\\|snappy\\|ssl\\|camlbz2'"

let time =
  let tm = Unix.gmtime (Unix.time()) in
  Printf.sprintf "%02d/%02d/%04d %02d:%02d:%02d UTC"
    (tm.tm_mday) (tm.tm_mon + 1) (tm.tm_year + 1900)
    tm.tm_hour tm.tm_min tm.tm_sec

let make_version _ _ =
  let cmd =
    let template = "let git_revision = %S\n" ^^
                     "let compile_time = %S\n" ^^
                     "let machine = %S\n" ^^
                     "let compiler_version = %S\n" ^^
                     "let major = %i\n" ^^
                     "let minor = %i\n" ^^
                     "let patch = %i\n" ^^
                     "let dependencies = %S\n"
    in
    let major,minor,patch =
      try
        Scanf.sscanf tag_version "%i.%i.%i" (fun ma mi p -> (ma,mi,p))
      with _ ->
        try Scanf.sscanf branch_version "heads/%i.%i" (fun ma mi -> (ma,mi,-1))
        with _ ->
          (* This one matches what's on Jenkins slaves *)
          try Scanf.sscanf branch_version "remotes/origin/%i.%i" (fun ma mi -> (ma, mi, -1))
          with _ -> (-1,-1,-1)
    in
    Printf.sprintf template git_revision time machine compiler_version major minor patch
      (String.concat "\\n" dependencies)
  in
  Cmd (S [A "echo"; Quote(Sh cmd); Sh ">"; P "arakoon_version.ml"])

let path_to_bisect () =
  try
    let bisect_pkg = Findlib.query "bisect" in
    bisect_pkg.Findlib.location
  with Findlib.Findlib_error _ -> "__could_not_find_bisect__"

let _ = dispatch & function
    | After_rules ->
      rule "arakoon_version.ml" ~prod: "arakoon_version.ml" make_version;

      (* how to compile C stuff that needs tc *)
      flag ["compile"; "c";]
        (S[
            A"-ccopt";A"-I../src/tools";
          ]);
      flag ["compile";"c";]
        (S[
            A"-ccopt";A"-msse4.2";
          ]);

      dep ["ocaml";"link";"is_main"]["src/libcutil.a"];

      flag ["ocaml";"link";"is_main"](
        S[A"-thread";
          A"-linkpkg";
          A"src/libcutil.a";
         ]);
      flag ["ocaml";"compile";] (S[A"-thread"]);

      flag ["ocaml";"byte";"link"] (S[A"-custom";]);

      flag ["ocaml";"compile";"warn_error"]
        (S[A"-w"; A"+A"; A"-warn-error"; A"+A-4-6-27-34-44"]);

      flag ["pp";"ocaml";"use_log_macro"] (A"logger_macro.cmo");
      dep ["ocaml"; "ocamldep"; "use_log_macro"] ["logger_macro.cmo"];

      flag ["ocaml"; "compile"; "use_bisect"]
        (S[A"-package"; A"bisect"]);
      flag ["ocaml"; "link"; "use_bisect"]
        (S[A"-package"; A"bisect"]);
      flag ["pp"; "ocaml"; "use_bisect"; "maybe_use_bisect"]
        (S[A"str.cma"; A(path_to_bisect () ^ "/bisect_pp.cmo")]);

      flag ["pp";"use_macro";"small_tlogs";
            "file:src/tlog/tlogcommon.ml"] (S[A"-DSMALLTLOG"]);
      flag ["library";"use_thread"](S[A"-thread"]);
    | _ -> ()
