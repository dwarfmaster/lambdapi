(** Toplevel commands. *)

open! Lplib
open Common
open Error
open Pos
open Parsing
open Syntax
open Core
open Term
open Proof
open Print
open Timed
open Debug
open Extra

(** Logging function for tactics. *)
let log_tact = new_logger 't' "tact" "tactics"
let log_tact = log_tact.logger

(** Number of admitted axioms in the current signature. Used to name the
    generated axioms. This reference is reset in {!module:Compile} for each
    new compiled module. *)
let admitted : int Stdlib.ref = Stdlib.ref (-1)

(** [add_axiom ss m] adds in signature state [ss] a new axiom symbol of type
   [!(m.meta_type)] and instantiate [m] with it. It does not check whether the
   type of [m] contains metavariables. *)
let add_axiom : Sig_state.t -> Meta.t -> Sig_state.t = fun ss m ->
  let name =
    let m_name = match m.meta_name with Some n -> "_" ^ n | _ -> "" in
    Printf.sprintf "_ax%i%s" Stdlib.(incr admitted; !admitted) m_name
  in
  (* Create a symbol with the same type as the metavariable *)
  let ss, sym =
    Console.out 3 (red "(symb) add axiom %a: %a\n")
      pp_uid name pp_term !(m.meta_type);
    Sig_state.add_symbol
      ss Public Const Eager true (Pos.none name) !(m.meta_type) [] None
  in
  (* Create the value which will be substituted for the metavariable. This
     value is [sym x0 ... xn] where [xi] are variables that will be
     substituted by the terms of the explicit substitution of the
     metavariable. *)
  let meta_value =
    let vars =
      let mk_var i = Bindlib.new_var mkfree (Printf.sprintf "x%i" i) in
      Array.init m.meta_arity mk_var
    in
    let ax = _Appl_symb sym (Array.to_list vars |> List.map _Vari) in
    Bindlib.(bind_mvar vars ax |> unbox)
  in
  Meta.set m meta_value; ss

(** [admit_meta ss m] adds as many axioms as needed in the signature state
   [ss] to instantiate the metavariable [m] by a fresh axiom added to the
   signature [ss]. *)
let admit_meta : Sig_state.t -> meta -> Sig_state.t = fun ss m ->
  let ss = Stdlib.ref ss in
  (* [ms] records the metas that we are instantiating. *)
  let rec admit ms m =
    (* This assertion should be ensured by the typechecking algorithm. *)
    assert (not (MetaSet.mem m ms));
    LibTerm.Meta.iter true (admit (MetaSet.add m ms)) !(m.meta_type);
    Stdlib.(ss := add_axiom !ss m)
  in
  admit MetaSet.empty m; Stdlib.(!ss)

(** [tac_admit pos ps gt] admits typing goal [gt]. *)
let tac_admit :
      Sig_state.t -> proof_state -> goal_typ -> Sig_state.t * proof_state =
  fun ss ps gt ->
  let ss = admit_meta ss gt.goal_meta in
  ss, remove_solved_goals ps

(** [tac_solve pos ps] tries to simplify the unification goals of the proof
   state [ps] and fails if constraints are unsolvable. *)
let tac_solve : popt -> proof_state -> proof_state = fun pos ps ->
  if !log_enabled then log_tact "solve %a" pp_goals ps;
  try
    let gs_typ, gs_unif = List.partition is_typ ps.proof_goals in
    let to_solve = List.map get_constr gs_unif in
    let new_cs = Unif.solve {empty_problem with to_solve} in
    let new_gs_unif = List.map (fun c -> Unif c) new_cs in
    (* remove in [gs_typ] the goals that have been instantiated. *)
    let goal_has_no_meta_value = function
      | Unif _ -> true
      | Typ gt ->
          match !(gt.goal_meta.meta_value) with
          | Some _ -> false
          | None -> true
    in
    let gs_typ = List.filter goal_has_no_meta_value gs_typ in
    {ps with proof_goals = new_gs_unif @ gs_typ}
  with Unif.Unsolvable -> fatal pos "Unification goals are unsatisfiable."

(** [tac_refine pos ps t] refines the focused typing goal with [t]. *)
let tac_refine : popt -> proof_state -> goal_typ -> goal list -> term
                 -> proof_state = fun pos ps gt gs t ->
  if !log_enabled then
    log_tact "refine %a ≔ %a" pp_meta gt.goal_meta pp_term t;
  if LibTerm.Meta.occurs gt.goal_meta t then fatal pos "Circular refinement.";
  (* Check that [t] is well-typed. *)
  let gs_typ, gs_unif = List.partition is_typ gs in
  let to_solve = List.map get_constr gs_unif in
  let c = Env.to_ctxt gt.goal_hyps in
  match Infer.check_noexn to_solve c t gt.goal_type with
  | None -> fatal pos "[%a] cannot have type [%a]."
              pp_term t pp_term gt.goal_type
  | Some cs ->
      (* Instantiation. Use Unif.instantiate instead ? *)
      Meta.set gt.goal_meta
        (Bindlib.unbox (Bindlib.bind_mvar (Env.vars gt.goal_hyps) (lift t)));
      (* Convert the metas of [t] not in [gs] into new goals. *)
      let gs_typ = add_goals_of_metas (LibTerm.Meta.get true t) gs_typ in
      let proof_goals = List.rev_map (fun c -> Unif c) cs @ gs_typ in
      tac_solve pos {ps with proof_goals}

(** [ind_data t] returns the [ind_data] structure of [s] if [t] is of the
   form [s t1 .. tn] with [s] an inductive type. Fails otherwise. *)
let ind_data : popt -> Env.t -> term -> Sign.ind_data = fun pos env a ->
  let h, ts = LibTerm.get_args (Eval.whnf (Env.to_ctxt env) a) in
  match h with
  | Symb s ->
      let sign = Path.Map.find s.sym_path Sign.(!loaded) in
      begin
        try
          let ind = SymMap.find s !(sign.sign_ind) in
          let ctxt = Env.to_ctxt env in
          if LibTerm.distinct_vars ctxt (Array.of_list ts) = None
          then fatal pos "%a is not applied to distinct variables." pp_sym s
          else ind
        with Not_found -> fatal pos "%a is not an inductive type." pp_sym s
      end
  | _ -> fatal pos "%a is not headed by an inductive type." pp_term a

(** [tac_induction pos ps gt] tries to apply the induction tactic on the
   typing goal [gt]. *)
let tac_induction : popt -> proof_state -> goal_typ -> goal list
    -> proof_state = fun pos ps ({goal_type;goal_hyps;_} as gt) gs ->
  match unfold goal_type with
  | Prod(a,_) ->
      let ind = ind_data pos goal_hyps a in
      let n = ind.ind_nb_params + ind.ind_nb_types + ind.ind_nb_cons in
      let t = Env.add_fresh_metas goal_hyps (Symb ind.ind_prop) n in
      tac_refine pos ps gt gs t
  | _ -> fatal pos "[%a] is not a product." pp_term goal_type

(** [handle ss expo ps tac] applies tactic [tac] in the proof state [ps] and
   returns the new proof state. *)
let handle : Sig_state.t -> Tags.expo -> proof_state -> p_tactic
             -> proof_state = fun ss expo ps {elt;pos} ->
  match ps.proof_goals with
  | [] -> assert false (* done before *)
  | g::gs ->
  match elt with
  | P_tac_fail
  | P_tac_query _ -> assert false (* done before *)
  | P_tac_focus(i) ->
      (try {ps with proof_goals = List.swap i ps.proof_goals}
       with Invalid_argument _ -> fatal pos "Invalid goal index.")
  | P_tac_simpl None ->
      {ps with proof_goals = Goal.simpl (Eval.snf []) g :: gs}
  | P_tac_simpl (Some qid) ->
      let s = Sig_state.find_sym ~prt:true ~prv:true ss qid in
      {ps with proof_goals = Goal.simpl (Eval.unfold_sym s) g :: gs}
  | P_tac_solve -> tac_solve pos ps
  | _ ->
  match g with
  | Unif _ -> fatal pos "Not a typing goal."
  | Typ ({goal_hyps=env;_} as gt) ->
  let scope = Scope.scope_term expo ss env (lazy (Proof.sys_metas ps)) in
  let check_idopt = function
    | None -> ()
    | Some id -> if List.mem_assoc id.elt env then
                   fatal id.pos "Identifier already in use."
  in
  match elt with
  | P_tac_admit
  | P_tac_fail
  | P_tac_focus _
  | P_tac_query _
  | P_tac_simpl _
  | P_tac_solve -> assert false (* done before *)
  | P_tac_apply pt ->
      let t = scope pt in
      (* Compute the product arity of the type of [t]. *)
      (* FIXME: this does not take into account implicit arguments. *)
      let n =
        match Infer.infer_noexn [] (Env.to_ctxt env) t with
        | None -> fatal pos "[%a] is not typable." pp_term t
        | Some (a, _) -> LibTerm.count_products a
      in
      let t = if n <= 0 then t else scope (P.appl_wild pt n) in
      tac_refine pos ps gt gs t
  | P_tac_assume idopts ->
      List.iter check_idopt idopts;
      tac_refine pos ps gt gs (scope (P.abst_list idopts P.wild))
  | P_tac_have(id, pt) ->
      (* From a goal [e ⊢ ?[e] : u], generates two new goals [e ⊢ ?1[e] : t]
         and [e,x:t ⊢ ?2[e,x] : u], and instantiate [?[e]] by [?2[e,?1[e]]. *)
      check_idopt (Some id);
      let t = scope pt in
      let n = List.length env in
      let bt = lift t in
      let mt = Meta.fresh (Env.to_prod env bt) n in
      let v = Bindlib.new_var mkfree id.elt in
      let env' = Env.add v bt None env in
      let m = Meta.fresh (Env.to_prod env' (lift gt.goal_type)) (n+1) in
      let gs = Goal.of_meta mt :: Goal.of_meta m :: gs in
      let vs = Env.vars env in
      let ts = Array.map (fun v -> Vari v) vs in
      let mts = Meta(mt,ts) in
      let u = Meta(m, Array.append ts [|mts|]) in
      tac_refine pos ps gt gs u
  | P_tac_induction -> tac_induction pos ps gt gs
  | P_tac_refine t -> tac_refine pos ps gt gs (scope t)
  | P_tac_refl -> tac_refine pos ps gt gs (Rewrite.reflexivity ss pos gt)
  | P_tac_rewrite(l2r,pat,eq) ->
      let pat = Option.map (Scope.scope_rw_patt ss env) pat in
      tac_refine pos ps gt gs (Rewrite.rewrite ss pos gt l2r pat (scope eq))
  | P_tac_sym -> tac_refine pos ps gt gs (Rewrite.symmetry ss pos gt)
  | P_tac_why3 cfg ->
      tac_refine pos ps gt gs (Why3_tactic.handle ss pos cfg gt)

(** [handle ss expo ps tac] applies tactic [tac] in the proof state [ps] and
   returns the new proof state. *)
let handle : Sig_state.t -> Tags.expo -> proof_state -> p_tactic
             -> Sig_state.t * proof_state * Query.result =
  fun ss expo ps ({elt;pos} as tac) ->
  match elt with
  | P_tac_fail -> fatal pos "Call to tactic \"fail\""
  | P_tac_query(q) ->
      if !log_enabled then log_tact "%a" Pretty.tactic tac;
      ss, ps, Query.handle ss (Some ps) q
  | _ ->
  match ps.proof_goals with
  | [] -> fatal pos "No remaining goals."
  | Typ gt::_ when elt = P_tac_admit ->
      let ss, ps = tac_admit ss ps gt in ss, ps, None
  | g::_ ->
      if !log_enabled then
        log_tact "%a\n%a" Proof.Goal.pp g Pretty.tactic tac;
      ss, handle ss expo ps tac, None

let handle : Sig_state.t -> Tags.expo -> proof_state -> p_tactic
             -> Sig_state.t * proof_state * Query.result =
  fun ss expo ps tac ->
  try handle ss expo ps tac
  with Fatal(_,_) as e -> Console.out 1 "%a" pp_goals ps; raise e
