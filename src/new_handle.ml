(** Toplevel commands. *)

open Extra
open Timed
open Console
open Terms
open Print
open Sign
open Pos
open Files
open Syntax
open New_scope
open New_parser

(** [handle_symdecl m x a] extends the current signature with a  fresh  symbol
    named [x] and with type [a]. If [a] does not have sort [Type]  or  [Kind],
    then the program fails gracefully. *)
let handle_symdecl : sym_mode -> strloc -> term -> sym * popt = fun m x a ->
  (* We check that [s] is not already used. *)
  let sign = current_sign () in
  if Sign.mem sign x.elt then fatal x.pos "Symbol [%s] already exists." x.elt;
  (* We check that [a] is typable by a sort. *)
  Solve.sort_type Ctxt.empty a;
  (*FIXME: check that [a] contains no uninstantiated metavariables.*)
  (Sign.add_symbol sign m x a, x.pos)


let rec new_handle_cmd : sig_state -> p_cmd loc -> sig_state = fun ss cmd ->
  let scope_basic ss t = New_scope.scope_term StrMap.empty ss Env.empty t in 
  let handle ss =
    match cmd.elt with
    | P_require(o, m)           ->
        ignore (o, m);
        assert false (* TODO *)
    | P_require_as(m, a)        ->
        ignore (m, a);
        assert false (* FIXME *)
    | P_open(m)                 ->
        ignore m;
        assert false (* FIXME *)
    | P_symbol(ts, x, a)        ->
        let m =
          match ts with
          | []              -> Defin
          | Sym_const :: [] -> Const
          | Sym_inj   :: [] -> Injec
          | _               -> fatal cmd.pos "Multiple symbol tags."
        in
        let a = fst (scope_basic ss a) in
        let s = handle_symdecl m x a in
        {ss with in_scope = StrMap.add x.elt s ss.in_scope}
    | P_rules(rs)               ->
        ignore rs;
        assert false (* TODO *)
    | P_definition(s, xs, a, t) ->
        ignore (s, xs, a, t);
        assert false (* TODO *)
    | P_theorem(s, a, ts, pe)   ->
        ignore (s, a, ts, pe);
        assert false (* TODO *)
    | P_assert(mf, asrt)        ->
        ignore (mf, asrt);
        assert false (* TODO *)
    | P_set(P_debug(e,s))       -> Console.set_debug e s; ss
    | P_set(P_verbose(i))       -> Console.verbose := i; ss
  in
  handle ss

(** [compile force path] compiles the file corresponding to [path], when it is
    necessary (the corresponding object file does not exist,  must be updated,
    or [force] is [true]).  In that case,  the produced signature is stored in
    the corresponding object file. *)
and new_compile : bool -> Files.module_path -> unit =
  fun force path ->
  let base = String.concat "/" path in
  let src = base ^ Files.new_src_extension in
  let obj = base ^ Files.new_obj_extension in
  if not (Sys.file_exists src) then fatal_no_pos "File [%s] not found." src;
  if List.mem path !loading then
    begin
      fatal_msg "Circular dependencies detected in [%s].\n" src;
      fatal_msg "Dependency stack for module [%a]:\n" Files.pp_path path;
      List.iter (fatal_msg "  - [%a]\n" Files.pp_path) !loading;
      fatal_no_pos "Build aborted."
    end;
  if PathMap.mem path !loaded then
    out 2 "Already loaded [%s]\n%!" src
  else if force || Files.more_recent src obj then
    begin
      let forced = if force then " (forced)" else "" in
      out 2 "Loading [%s]%s\n%!" src forced;
      loading := path :: !loading;
      let sign = Sign.create path in
      loaded := PathMap.add path sign !loaded;
      ignore (List.fold_left new_handle_cmd empty_sig_state (parse_file src));
      Handle.check_end_proof (); Proofs.theorem := None;
      if Pervasives.(!Handle.gen_obj) then Sign.write sign obj;
      loading := List.tl !loading;
      out 1 "Checked [%s]\n%!" src;
    end
  else
    begin
      out 2 "Loading [%s]\n%!" src;
      let sign = Sign.read obj in
      PathMap.iter (fun mp _ -> new_compile false mp) !(sign.deps);
      loaded := PathMap.add path sign !loaded;
      Sign.link sign;
      out 2 "Loaded  [%s]\n%!" obj;
    end


