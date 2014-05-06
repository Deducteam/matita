(* elpi: embedded lambda prolog interpreter                                  *)
(* copyright: 2014 - Enrico Tassi <enrico.tassi@inria.fr>                    *)
(* license: GNU Lesser General Public License Version 2.1                    *)
(* ------------------------------------------------------------------------- *)

module L : sig (* {{{ Lists *)


  type 'a t
  val empty : 'a t
  val singl : 'a -> 'a t
  val init : int -> (int -> 'a) -> 'a t
  val get : int -> 'a t -> 'a
  val len : 'a t -> int
  val sub : int -> int -> 'a t -> 'a t
  val tl : 'a t -> 'a t
  val hd : 'a t -> 'a
  val map : ('a -> 'b) -> 'a t -> 'b t
  val mapi : (int -> 'a -> 'b) -> 'a t -> 'b t
  val fold_map : ('a -> 'b -> 'a * 'b) -> 'a t -> 'b -> 'a t * 'b
  val fold : ('a -> 'b -> 'b) -> 'a t -> 'b -> 'b
  val fold2 : ('a -> 'b -> 'c -> 'c) -> 'a t -> 'b t -> 'c -> 'c
  val for_all : ('a -> bool) -> 'a t -> bool
  val for_alli : (int -> 'a -> bool) -> 'a t -> bool
  val for_all2 : ('a -> 'b -> bool) -> 'a t -> 'b t -> bool
  val of_list : 'a list-> 'a t
  val to_list : 'a t -> 'a list
  val filter : ('a -> bool) -> 'a t -> 'a t
  val append : 'a t -> 'a t -> 'a t
  val cons : 'a -> 'a t -> 'a t
  val uniq : ('a -> 'a -> bool) -> 'a t -> bool

  (* }}} *)
end  = struct (* {{{ *)
  
  type 'a t = 'a list
  let empty = []
  let singl a = [a]
  let init i f =
    let rec aux j = if i = j then [] else f j :: aux (j+1) in aux 0
  let get i l = List.nth l i
  let len l = List.length l
  let sub i j l =
    let rec aux n l = if n = j + i then [] else
    match l with
    | [] -> assert false
    | x :: xs when n < i -> aux (n+1) xs
    | x :: xs -> x :: aux (n+1) xs
    in aux 0 l
  let tl l = List.tl l
  let hd l = List.hd l
  let map f l = List.map f l
  let mapi f l =
    let rec aux n = function
      | [] -> []
      | x::xs -> f n x :: aux (n+1) xs
    in aux 0 l
  let rec fold_map f l a =
    match l with
    | [] -> l, a
    | x::xs -> let x, a = f x a in let xs, a = fold_map f xs a in x::xs, a
  let rec fold f l a =
    match l with
    | [] -> a
    | x::xs -> fold f xs (f x a)
  let rec fold2 f l1 l2 a =
    match l1, l2 with
    | [], [] -> a
    | x::xs,y::ys -> fold2 f xs ys (f x y a)
    | _ -> assert false
  let for_all f l = List.for_all f l
  let for_alli f l =
    let rec aux n = function
      | [] -> true
      | x::xs -> f n x && aux (n+1) xs
    in aux 0 l
  let rec for_all2 f l1 l2 =
    match l1, l2 with
    | [], [] -> true
    | x::xs, y::ys -> f x y && for_all2 f xs ys
    | _ -> false
  let of_list l = l
  let to_list l = l
  let filter f l = List.filter f l
  let append l1 l2 = l1 @ l2
  let cons x l = x :: l
  let rec uniq equal = function
    | [] -> true
    | x::xs -> List.for_all (fun y -> not(equal x y)) xs && uniq equal xs

end (* }}} *)

module C : sig (* {{{ External, user defined, datatypes *)

  type t
  type ty
  type data = {
    t : t;
    ty : ty;
  }

  val declare : ('a -> string) -> ('a -> 'a -> bool) -> ('a -> data) * (data -> bool) * (data -> 'a)
  
  val print : data -> string
  val equal : data -> data -> bool

(* }}} *)
end = struct (* {{{ *)

type t = Obj.t
type ty = int

type data = {
  t : Obj.t;
  ty : int
}

module M = Int.Map
let m : ((data -> string) * (data -> data -> bool)) M.t ref = ref M.empty

let cget x = Obj.obj x.t
let print x = fst (M.find x.ty !m) x
let equal x y = x.ty = y.ty && snd (M.find x.ty !m) x y

let fresh_tid =
  let tid = ref 0 in
  fun () -> incr tid; !tid

let declare print cmp =
  let tid = fresh_tid () in
  m := M.add tid ((fun x -> print (cget x)),
                  (fun x y -> cmp (cget x) (cget y))) !m;
  (fun v -> { t = Obj.repr v; ty = tid }),
  (fun c -> c.ty = tid),
  (fun c -> assert(c.ty = tid); cget c)

end (* }}} *)

let mkString, isString, getString = C.declare (fun x -> "\""^x^"\"") (=)

module PPLIB = struct (* {{{ auxiliary lib for PP *)

let on_buffer f x =
  let b = Buffer.create 1024 in
  let fmt = Format.formatter_of_buffer b in
  f fmt x;
  Format.pp_print_flush fmt ();
  Buffer.contents b
let iter_sep spc pp fmt l =
  let rec aux n = function
    | [] -> ()
    | [x] -> pp fmt x
    | _ when n = 0 ->
         Format.fprintf fmt "%s" (Format.pp_get_ellipsis_text fmt ())
    | x::tl -> pp fmt x; spc fmt (); aux (n-1) tl in
  aux (Format.pp_get_max_boxes fmt ()) l


end (* }}} *)
open PPLIB

module LP = struct

(* Based on "A Simplified Suspension Calculus and its Relationship to Other
   Explicit Substitution Calculi", Andrew Gacek and Gopalan Nadathur.
   Research Report 2007/39, Digital Technology Center, University of Minnesota.
*)

type var = int
type level = int
type name = string

type olam = int
type nlam = int

type kind_of_data =
  | Uv of var * level
  | Con of name * level
  | DB of int
  | Bin of int * data
  | App of data L.t
  | Seq of data L.t * data
  | Nil
  | Ext of C.data
and data =
  | XUv of var * level
  | XCon of name * level
  | XDB of int
  | XBin of int * data
  | XApp of data L.t
  | XSeq of data L.t * data
  | XNil
  | XExt of C.data
  | XSusp of suspended_job ref
and suspended_job = Done of data | Todo of data * olam * nlam * env
and env =
  | XEmpty
  | XArgs of data L.t * int * env
  | XMerge of env * nlam * olam * env
  | XSkip of int * nlam * env

module PP = struct (* {{{ pretty printer for data *)

let small_digit = function
  | 0 -> "⁰" | 1 -> "¹" | 2 -> "²" | 3 -> "³" | 4 -> "⁴" | 5 -> "⁵"
  | 6 -> "⁶" | 7 -> "⁷" | 8 -> "⁸" | 9 -> "⁹" | _ -> assert false

let rec digits_of n = n mod 10 :: if n > 10 then digits_of (n / 10) else []

let string_of_level lvl = if !Trace.dverbose then "^" ^ string_of_int lvl
  else if lvl = 0 then ""
  else String.concat "" (List.map small_digit (List.rev (digits_of lvl)))

let pr_cst x lvl = x ^ if !Trace.dverbose then string_of_level lvl else ""
let pr_var x lvl =
  "X" ^ string_of_int x ^ if !Trace.dverbose then string_of_level lvl else ""

let rec fresh_names w k = function
  | 0 -> []
  | n -> (w ^ string_of_int k) :: fresh_names w (k+1) (n-1)

module P = Format

let rec prf_data ctx fmt t =
  let rec print ?(pars=false) ctx = function
    | XBin (n,x) ->
       P.pp_open_hovbox fmt 2;
       let names = fresh_names "w" (List.length ctx) n in
       if pars then P.pp_print_string fmt "(";
       P.pp_print_string fmt (String.concat "\\ " names ^ "\\");
       P.pp_print_space fmt ();
       print (List.rev names @ ctx) x;
       if pars then P.pp_print_string fmt ")";
       P.pp_close_box fmt ()
    | XDB x -> P.pp_print_string fmt 
        (try (if !Trace.dverbose then "'" else "") ^List.nth ctx (x-1)
        with Failure _ | Invalid_argument _ ->
          "_" ^ string_of_int (x-List.length ctx))
    | XCon (x,lvl) -> P.pp_print_string fmt (pr_cst x lvl)
    | XUv (x,lvl) -> P.pp_print_string fmt (pr_var x lvl)
    | XApp xs ->
        P.pp_open_hovbox fmt 2;
        if pars then P.pp_print_string fmt "(";
        iter_sep P.pp_print_space (fun _ -> print ~pars:true ctx)
          fmt (L.to_list xs);
        if pars then P.pp_print_string fmt ")";
        P.pp_close_box fmt ()
    | XSeq (xs, XNil) ->
        P.fprintf fmt "@[<hov 2>[";
        iter_sep (fun fmt () -> P.fprintf fmt ",@ ") (fun _ -> print ctx)
          fmt (L.to_list xs);
        P.fprintf fmt "]@]";
    | XSeq (xs, t) ->
        P.fprintf fmt "@[<hov 2>[";
        iter_sep (fun fmt () -> P.fprintf fmt ",@ ") (fun _ -> print ctx)
          fmt (L.to_list xs);
        P.fprintf fmt "|@ ";
        print ctx t;
        P.fprintf fmt "]@]";
    | XNil -> P.fprintf fmt "[]";
    | XExt x ->
        P.pp_open_hbox fmt ();
        P.pp_print_string fmt (C.print x);
        P.pp_close_box fmt ()
    | XSusp ptr ->
        match !ptr with
        | Done t -> P.fprintf fmt ".(@["; print ctx t; P.fprintf fmt ")@]"
        | Todo(t,ol,nl,e) ->
            P.fprintf fmt "@[<hov 2>⟦";
            print ctx t;
            P.fprintf fmt ",@ %d, %d,@ " ol nl;
            prf_env ctx fmt e;
            P.fprintf fmt "⟧@]";
  in
    print ctx t

and prf_env ctx fmt e =
  let rec print_env = function
    | XEmpty -> P.pp_print_string fmt "nil"
    | XArgs(a,n,e) ->
        P.fprintf fmt "(@[<hov 2>";
        iter_sep (fun fmt () -> P.fprintf fmt ",@ ")
          (prf_data ctx) fmt (L.to_list a);
        P.fprintf fmt "@]|%d)@ :: " n;
        print_env e
    | XMerge(e1,nl1,ol2,e2) ->
        P.fprintf fmt "@[<hov 2>⦃";
        print_env e1;
        P.fprintf fmt ",@ %d, %d,@ " nl1 ol2;
        print_env e2;
        P.fprintf fmt "⦄@]";
    | XSkip(n,m,e) ->
        P.fprintf fmt "@@(%d,%d)@ :: " n m;
        print_env e;
  in
    P.pp_open_hovbox fmt 2;
    print_env e;
    P.pp_close_box fmt ()

let string_of_data ?(ctx=[]) t = on_buffer (prf_data ctx) t
let string_of_env ?(ctx=[]) e = on_buffer (prf_env ctx) e

end (* }}} *)
include PP

let (--) x y = max 0 (x - y)
let mkXSusp t n o e = XSusp(ref(Todo(t,n,o,e)))

let rule s = SPY "rule" Format.pp_print_string s

let rec epush e = TRACE "epush" (fun fmt -> prf_env [] fmt e)
  match e with
  | (XEmpty | XArgs _ | XSkip _) as x -> x
  | XMerge(e1,nl1,ol2,e2) -> let e1 = epush e1 in let e2 = epush e2 in
  match e1, e2 with
  | e1, XEmpty when ol2 = 0 -> (*m2*) e1
  | XEmpty, e2 when nl1 = 0 -> (*m3*) e2
  | XEmpty, XArgs(a,l,e2) -> rule"m4";
      let nargs = L.len a in
      if nl1 = nargs then e2 (* repeat m4, end m3 *)
      else if nl1 > nargs then epush (XMerge(XEmpty,nl1 -nargs, ol2 -nargs, e2))
      else XArgs(L.sub nl1 (nargs-nl1) a,l,e2) (* repeast m4 + m3 *)
  | XEmpty, XSkip(a,l,e2) -> rule"m4";
      if nl1 = a then e2 (* repeat m4, end m3 *)
      else if nl1 > a then epush (XMerge(XEmpty,nl1 - a, ol2 - a, e2))
      else XSkip(a-nl1,l-nl1,e2) (* repeast m4 + m3 *)
  | (XArgs(_,n,_) | XSkip(_,n,_)) as e1, XArgs(b,l,e2) when nl1 > n -> rule"m5";
      let drop = min (L.len b) (nl1 - n) in
      if drop = L.len b then
        epush (XMerge(e1,nl1 - drop, ol2 - drop, e2))
      else   
        epush (XMerge(e1,nl1 - drop, ol2 - drop,
          XArgs(L.sub drop (L.len b - drop) b,l,e2)))
  | (XArgs(_,n,_) | XSkip(_,n,_)) as e1, XSkip(b,l,e2) when nl1 > n -> rule"m5";
      let drop = min b (nl1 - n) in
      if drop = b then epush (XMerge(e1,nl1 - drop, ol2 - drop, e2))
      else epush (XMerge(e1,nl1 - drop, ol2 - drop, XSkip(b - drop,l-drop,e2)))
  | XArgs(a,n,e1), ((XArgs(_,l,_) | XSkip(_,l,_)) as e2) -> rule"m6";
      assert(nl1 = n);
      let m = l + (n -- ol2) in
      let t = L.hd a in
      let e1 = if L.len a > 1 then XArgs(L.tl a,n,e1) else e1 in
      (* ugly *)
      XArgs(L.singl (mkXSusp t ol2 l e2), m, XMerge(e1,n,ol2,e2))
  | XSkip(a,n,e1), ((XArgs(_,l,_) | XSkip(_,l,_)) as e2) -> rule"m6";
      assert(nl1 = n);
      let m = l + (n -- ol2) in
      let e1 = if a > 1 then XSkip(a-1,n-1,e1) else e1 in
      (* ugly *)
      XArgs(L.singl (mkXSusp (XDB 1) 0 l e2), m, XMerge(e1,n,ol2,e2))
  | XArgs _, XEmpty -> assert false
  | XEmpty, XEmpty -> assert false
  | XSkip _, XEmpty -> assert false
  | ((XMerge _, _) | (_, XMerge _)) -> assert false

let mkBin n t =
  if n = 0 then t
  else match t with
    | XBin(n',t) -> XBin(n+n',t)
    | _ -> XBin(n,t)

let store ptr v = ptr := Done v; v
let rec psusp ptr t ol nl e =
  TRACE "psusp ptr"
    (fun fmt -> prf_data [] fmt (XSusp { contents = Todo(t,ol,nl,e) }))
  match t with
  | XSusp { contents = Done t } -> psusp ptr t ol nl e
  | XSusp { contents = Todo (t,ol1,nl1,e1) } -> rule"m1";
      psusp ptr t (ol1 + (ol -- nl1)) (nl + (nl1 -- ol))
        (XMerge(e1,nl1,ol,e))
  | (XCon _ | XExt _ | XNil) as x -> rule"r1"; x
  | XUv _ as x -> store ptr x
  | XBin(n,t) -> rule"r6";
      assert(n > 0);
      store ptr (mkBin 1 (mkXSusp (mkBin (n-1) t) (ol+1) (nl+1)
                           (XArgs (L.singl (XDB 1),nl+1,e))))
  | XApp a -> rule"r5";
      store ptr (XApp(L.map (fun t -> mkXSusp t ol nl e) a))
  | XSeq(a,tl) ->
      store ptr (XSeq(L.map (fun t -> mkXSusp t ol nl e) a,
                      mkXSusp tl ol nl e))
  | XDB i -> (* r2, r3, r4 *)
      let e = epush e in
      SPY "epushed" (prf_env []) e;
      match e with
      | XMerge _ -> assert false
      | XEmpty -> rule"r2"; assert(ol = 0); store ptr (XDB(i+nl))
      | XArgs(a,l,e) ->
          let nargs = L.len a in
          if i <= nargs
          then (rule"r3"; psusp ptr (L.get (nargs - i) a) 0 (nl - l) XEmpty)
          else (rule"r4"; psusp ptr (XDB(i - nargs)) (ol - nargs) nl e)
      | XSkip(n,l,e) -> 
          if (i <= n)
          then (rule"r3"; store ptr (XDB (i + nl - l)))
          else (rule"r4"; psusp ptr (XDB(i - n)) (ol - n) nl e)
let push t =
  match t with
  | (XUv _ | XCon _ | XDB _ | XBin _ | XApp _ | XExt _ | XSeq _ | XNil) -> t
  | XSusp { contents = Done t } -> t
  | XSusp ({ contents = Todo (t,ol,nl,e) } as ptr) -> psusp ptr t ol nl e

let isSubsp = function XSusp _ -> true | _ -> false

let look x =
  let x = push x in
  SPY "pushed" (prf_data []) x;
  Obj.magic x
(*
  match x with
  | XUv (v,l) -> Uv(v,l)
  | XCon (n,l) -> Con(n,l)
  | XDB i -> DB i
  | XBin (n,t) -> Bin(n,t)
  | XApp a -> App a
  | XSeq (a,tl) -> Seq (a,tl)
  | XNil -> Nil
  | XExt e -> Ext e
  | XSusp _ -> assert false
*)
let mkUv v l = XUv(v,l)
let mkCon n l = XCon(n,l)
let mkDB i = XDB i
let mkExt x = XExt x
let rec mkSeq xs tl =
  match tl with
  | XSeq (ys,tl) -> mkSeq (L.append xs ys) tl
  | _ -> XSeq(xs,tl)
let mkNil = XNil
let kool = Obj.magic (*function
  | Uv (v,l) -> XUv(v,l)
  | Con (n,l) -> XCon(n,l)
  | DB i -> XDB i
  | Bin (n,t) -> XBin(n,t)
  | App a -> XApp a
  | Seq (a,tl) -> XSeq (a,tl)
  | Nil -> XNil
  | Ext e -> XExt e*)

let mkBin n t =
  if n = 0 then t
  else match t with
    | XBin(n',t) -> XBin(n+n',t)
    | _ -> XBin(n,t)

let mkApp xs = if L.len xs = 1 then L.hd xs else XApp xs
let mkAppv t v start stop =
  if start = stop then t else
  match t with
  | XApp xs -> XApp(L.append xs (L.sub start (stop-start) v))
  | _ -> XApp(L.cons t (L.sub start (stop-start) v))

let fixApp xs =
  match push (L.hd xs) with
  | XApp ys -> XApp (L.append ys (L.tl xs))
  | _ -> XApp xs

let isDB i = function XDB j when j = i -> true | _ -> false

let rec equal a b = match push a, push b with
 | XUv (x,_), XUv (y,_) -> x = y
 | XCon (x,_), XCon (y,_) -> x = y
 | XDB x, XDB y -> x = y
 | XBin (n1,x), XBin (n2,y) -> n1 = n2 && equal x y
 | XApp xs, XApp ys -> L.for_all2 equal xs ys
 | XExt x, XExt y -> C.equal x y
 | XSeq(xs,s), XSeq(ys,t) -> L.for_all2 equal xs ys && equal s t
 | XNil, XNil -> true
 | ((XBin(n,x), y) | (y, XBin(n,x))) -> begin (* eta *)
     match push x with
     | XApp xs ->
        let nxs = L.len xs in
        let eargs = nxs - n in
           eargs > 0
        && L.for_alli (fun i t -> isDB (n-i) t) (L.sub eargs n xs)
        && equal (mkApp (L.sub 0 eargs xs)) (mkXSusp y 0 n XEmpty)
     | _ -> false
   end
 | _ -> false

let isBin x = match push x with XBin _ -> true | _ -> false

let rec fold f x a = match push x with
  | (XDB _ | XCon _ | XUv _ | XExt _) as x -> f x a
  | XBin (_,x) -> fold f x a
  | XApp xs -> L.fold (fold f) xs a
  | XSeq (xs, t) -> fold f t (L.fold (fold f) xs a)
  | XNil -> a
  | XSusp _ -> assert false

let rec map f x = match push x with
  | (XDB _ | XCon _ | XUv _ | XExt _ | XNil) as x -> f x
  | XBin (ns,x) -> XBin(ns, map f x)
  | XApp xs -> XApp(L.map (map f) xs)
  | XSeq (xs, tl) -> XSeq(L.map (map f) xs, map f tl)
  | XSusp _ -> assert false

let max_uv x a = match push x with XUv (i,_) -> max a i | _ -> a

let rec fold_map i f x a = match push x with
  | (XDB _ | XCon _ | XUv _ | XExt _ | XNil) as x -> f i x a
  | XBin (n,x) -> let x, a = fold_map i f x a in XBin(n,x), a
  | XApp xs -> let xs, a = L.fold_map (fold_map i f) xs a in XApp xs, a
  | XSeq (xs, tl) ->
      let xs, a = L.fold_map (fold_map i f) xs a in
      let tl, a = fold_map i f tl a in
      XSeq(xs, tl), a
  | XSusp _ -> assert false
 
(* PROGRAM *)
type builtin = BIUnif of data * data | BICustom of string * data | BICut

let map_builtin f = function
  | BIUnif(a,b) -> BIUnif(f a, f b)
  | BICustom(n,t) -> BICustom(n,f t)
  | BICut -> BICut
let fold_builtin f x a = match x with
  | BIUnif(x,y) -> f y (f x a)
  | BICustom(_,x) -> f x a
  | BICut -> a
let fold_map_builtin i f x a = match x with
  | BIUnif(x,y) ->
      let x, a = f i x a in
      let y, a = f i y a in
      BIUnif(x,y), a
  | BICustom(n,x) ->
      let x, a = f i x a in
      BICustom(n,x), a
  | BICut -> BICut, a

type key = Key of data | Flex

type program = annot_clause list
and annot_clause = int * data list * key * clause (* level, subst, key, clause *)
and clause = premise
and premise =
  | Atom of data
  | AtomBI of builtin
  | Conj of premise list
  | Impl of clause * premise
  | Pi of int * premise
  | Sigma of int * premise
  | Not of premise
and goal = premise

let mkPi n = function Pi(m,t) -> Pi(m+n,t) | t -> Pi(n,t)
let mkSigma n = function Sigma(m,t) -> Sigma(m+n,t) | t -> Sigma(n,t)
let mkConj l =
  let rec aux acc = function
    | [] -> Conj(List.flatten (List.rev acc))
    | Conj l::rest -> aux (l :: acc) rest
    | p::rest -> aux ([p] :: acc) rest
  in
    aux [] l

let rec map_premise f = function
  | Atom x -> Atom(f x)
  | AtomBI bi -> AtomBI (map_builtin f bi)
  | Conj xs -> Conj(List.map (map_premise f) xs)
  | Impl(x,y) -> Impl(map_premise f x, map_premise f y)
  | Pi(n,x)  -> Pi(n,map_premise f x)
  | Sigma(n,x)  -> Sigma(n,map_premise f x)
  | Not x -> Not(map_premise f x)

let rec fold_premise f x a = match x with
  | Atom x -> f x a
  | AtomBI bi -> fold_builtin f bi a
  | Conj xs -> List.fold_left (fun a x -> fold_premise f x a) a xs
  | Impl(x,y) -> fold_premise f y (fold_premise f x a)
  | Pi(_,x) -> fold_premise f x a
  | Sigma(_,x) -> fold_premise f x a
  | Not x -> fold_premise f x a

let rec fold_map_premise i f p a = match p with
  | Atom x -> let x, a = f i x a in Atom x, a
  | AtomBI bi -> let bi, a = fold_map_builtin i f bi a in AtomBI bi, a
  | Conj xs ->
      let xs, a =
        List.fold_left (fun (l,a) x ->
          let x, a = fold_map_premise i f x a in
          x::l, a)
        ([],a) xs in
      Conj(List.rev xs), a
  | Impl(x,y) ->
      let x, a = fold_map_premise i f x a in
      let y, a = fold_map_premise i f y a in
      Impl(x,y), a
  | Pi(n,y) -> let y, a = fold_map_premise (i+n) f y a in Pi(n,y), a
  | Sigma(n,y) -> let y, a = fold_map_premise (i+n) f y a in Sigma(n,y), a
  | Not x -> let x, a = fold_map_premise i f x a in Not x, a

module PPP = struct (* {{{ pretty printer for programs *)

let prf_builtin ctx fmt = function
  | BIUnif (a,b) -> 
      Format.fprintf fmt "@[<hv 2>%a@ = %a@]" (prf_data ctx) a (prf_data ctx) b;
  | BICustom(name,t) ->
      Format.fprintf fmt "@[<hov 2>%s %a@]" name (prf_data ctx) t
  | BICut -> Format.fprintf fmt "!"

let rec prf_premise ?(pars=false) ?(positive=false) ctx fmt p =
  match p with
  | Atom p -> prf_data ctx fmt p
  | AtomBI bi -> prf_builtin ctx fmt bi
  | Conj [] -> Format.fprintf fmt ""
  | Conj [p] -> prf_premise ~positive ~pars ctx fmt p
  | Conj l ->
       Format.pp_open_hvbox fmt 0;
       if pars then Format.pp_print_string fmt "(";
       iter_sep (fun fmt () ->
         Format.pp_print_string fmt ","; Format.pp_print_space fmt ())
         (prf_premise ~positive ctx) fmt l;
       if pars then Format.pp_print_string fmt ")";
       Format.pp_close_box fmt ()
  | Pi(n,p) ->
       let names = fresh_names "y" (List.length ctx) n in
       Format.pp_open_hvbox fmt 2;
       Format.pp_print_string fmt ("pi "^String.concat "\\ " names ^ "\\");
       Format.pp_print_space fmt ();
       prf_premise ~positive ~pars (List.rev names @ ctx) fmt p;
       Format.pp_close_box fmt ()
  | Sigma(n,p) ->
       let names = fresh_names "X" (List.length ctx) n in
       Format.pp_open_hvbox fmt 2;
       Format.pp_print_string fmt ("sigma "^String.concat "\\ " names ^ "\\");
       Format.pp_print_space fmt ();
       prf_premise ~positive ~pars (List.rev names @ ctx) fmt p;
       Format.pp_close_box fmt ()
  | Impl (x,p) ->
       let l, r, sep, neg_pars =
         if positive then x, p, "=> ",true else p, x, ":- ", false in
       Format.pp_open_hvbox fmt 2;
       if pars then Format.pp_print_string fmt "(";
       prf_premise ~pars:neg_pars ~positive:(not positive) ctx fmt l;
       if r <> Conj [] then begin
         if l <> Conj [] then begin
           Format.pp_print_space fmt ();
           Format.pp_open_hovbox fmt 0;
           Format.pp_print_string fmt sep;
         end;
         prf_premise ~pars:false ~positive:true ctx fmt r;
         if l <> Conj [] then Format.pp_close_box fmt ();
       end;
       if pars then Format.pp_print_string fmt ")";
       Format.pp_close_box fmt ()
  | Not p ->
       Format.fprintf fmt "not @[";
       prf_premise ~pars ~positive ctx fmt p;
       Format.pp_close_box fmt ()

let prf_clause ?(dot=true) ?positive ctx fmt c =
  let c, ctx = match c with
    | Sigma(n,c) -> c, fresh_names "X" 0 n @ ctx
    | c -> c, ctx in
  Format.pp_open_hbox fmt ();
  prf_premise ?positive ctx fmt c;
  if dot then Format.pp_print_string fmt ".";
  Format.pp_close_box fmt ()

let prf_premise ctx fmt = prf_premise ctx fmt
let string_of_premise p = on_buffer (prf_premise []) p
let string_of_goal = string_of_premise
let prf_goal ctx = prf_clause ~dot:false ~positive:true ctx
let prf_clause ctx fmt c = prf_clause ctx fmt c

let string_of_head = string_of_data

let string_of_clause c = on_buffer (prf_clause []) c

let prf_program fmt p =
  let p = List.map (fun _, _, _, p -> p) p in
  Format.pp_open_vbox fmt 0;
  iter_sep (Format.pp_print_space) (prf_clause []) fmt p;
  Format.pp_close_box fmt ()
let string_of_program p = on_buffer prf_program p

let rec key_of = function
  | AtomBI _ -> assert false
  | Conj _ -> assert false
  | Impl(_,p) | Pi(_,p) | Sigma(_,p) | Not p -> key_of p
  | Atom t ->
      match look t with
      | Con _ -> Key t
      | App xs -> Key(L.hd xs)
      | _ -> Flex

end (* }}} *)
include PPP

module Parser : sig (* {{{ parser for LP programs *)

  val parse_program : string -> program
  val parse_goal : string -> goal
  val parse_data : string -> data

(* }}} *)
end = struct (* {{{ *)

let rec number = lexer [ '0'-'9' number | ]
let rec ident =
  lexer [ [ 'a'-'z' | 'A'-'Z' | '\'' | '_' | '-' | '0'-'9' ] ident
        | '^' '0'-'9' number | ]

let rec string = lexer [ '"' | _ string ]

let lvl_name_of s =
  match Str.split (Str.regexp_string "^") s with
  | [ x ] -> x, 0
  | [ x;l ] -> x, int_of_string l
  | _ -> raise (Token.Error ("<name> ^ <number> expected.  Got: " ^ s))

let tok = lexer
  [ 'A'-'Z' ident -> "UVAR", $buf 
  | 'a'-'z' ident -> "CONSTANT", $buf
  | '_' '0'-'9' number -> "REL", $buf
  |  ":-"  -> "ENTAILS",$buf
  |  "::"  -> "CONS",$buf
  | ',' -> "COMMA",","
  | '.' -> "FULLSTOP","."
  | '\\' -> "BIND","\\"
  | '/' -> "BIND","/"
  | '(' -> "LPAREN","("
  | ')' -> "RPAREN",")"
  | '[' -> "LBRACKET","["
  | ']' -> "RBRACKET","]"
  | '|' -> "PIPE","|"
  | "=>" -> "IMPL", $buf
  | '=' -> "EQUAL","="
  | '$' 'a'-'z' ident -> "BUILTIN",$buf
  | '!' -> "BANG", $buf
  | '"' string -> "LITERAL", let b = $buf in String.sub b 1 (String.length b-2)
]

let spy f s = if !Trace.dverbose then begin
  Printf.eprintf "<- %s\n"
    (match Stream.peek s with None -> "EOF" | Some x -> String.make 1 x);
  let t, v as tok = f s in
  Printf.eprintf "-> %s = %s\n" t v;
  tok
  end else f s

let rec lex c = parser bp
  | [< '( ' ' | '\n' | '\t' ); s >] -> lex c s
  | [< '( '%' ); s >] -> comment c s
  | [< '( '/' ); s >] ep ->
       if Stream.peek s = Some '*' then comment2 c s
       else ("BIND", "/"), (bp,ep)
  | [< s >] ep ->
       (match spy (tok c) s with
       | "CONSTANT","pi" -> "PI", "pi"
       | "CONSTANT","sigma" -> "SIGMA", "sigma"
       | "CONSTANT","nil" -> "NIL", "nil"
       | "CONSTANT","not" -> "NOT","not"
       | x -> x), (bp, ep)
and comment c = parser
  | [< '( '\n' ); s >] -> lex c s
  | [< '_ ; s >] -> comment c s
and comment2 c = parser
  | [< '( '*' ); s >] ->
       if Stream.peek s = Some '/' then (Stream.junk s; lex c s)
       else comment2 c s
  | [< '_ ; s >] -> comment2 c s


open Plexing

let lex_fun s =
  let tab = Hashtbl.create 207 in
  let last = ref Ploc.dummy in
  (Stream.from (fun id ->
     let tok, loc = lex Lexbuf.empty s in
     last := Ploc.make_unlined loc;
     Hashtbl.add tab id !last;
     Some tok)),
  (fun id -> try Hashtbl.find tab id with Not_found -> !last)

let tok_match (s1,_) = (); function
  | (s2,v) when s1=s2 ->
      if !Trace.dverbose then Printf.eprintf "%s = %s = %s\n" s1 s2 v;
      v
  | (s2,v) ->
      if !Trace.dverbose then Printf.eprintf "%s <> %s = %s\n" s1 s2 v;
      raise Stream.Failure

let lex = {
  tok_func = lex_fun;
  tok_using = (fun _ -> ());
  tok_removing = (fun _ -> ());
  tok_match = tok_match;
  tok_text = (function (s,_) -> s);
  tok_comm = None;
}

let g = Grammar.gcreate lex
let lp = Grammar.Entry.create g "lp"
let premise = Grammar.Entry.create g "premise"
let atom = Grammar.Entry.create g "atom"

let uvmap = ref []
let conmap = ref []
let reset () = uvmap := []; conmap := []
let uvlist () = List.map snd !uvmap

let get_uv u =
  if List.mem_assoc u !uvmap then List.assoc u !uvmap
  else
    let n = List.length !uvmap in
    uvmap := (u,n) :: !uvmap;
    n
let check_con n l =
  try
    let l' = List.assoc n !conmap in
    if l <> l' then
      raise (Token.Error ("Constant "^n^" used at different levels"))
  with Not_found -> conmap := (n,l) :: !conmap

let rec binders c n = function
    | (XCon _ | XUv _) as x when equal x c -> XDB n
    | (XCon _ | XUv _ | XExt _ | XDB _ | XNil) as x -> x
    | XBin(w,t) -> XBin(w,binders c (n+w) t)
    | XApp xs -> XApp (L.map (binders c n) xs)
    | XSeq (xs,tl) -> XSeq(L.map (binders c n) xs, binders c n tl)
    | XSusp _ -> assert false
and binders_premise c n = function
    | Pi(m,t) -> Pi(m,binders_premise c (n+m) t)
    | Sigma(m,t) -> Sigma(m,binders_premise c (n+m) t)
    | Atom t -> Atom(binders c n t)
    | AtomBI bi -> AtomBI (binders_builtin c n bi)
    | Conj l -> Conj(List.map (binders_premise c n) l)
    | Impl(p,t) -> Impl(binders_premise c n p, binders_premise c n t)
    | Not p -> Not(binders_premise c n p)
and binders_builtin c n = function
    | BIUnif (a,b) -> BIUnif(binders c n a, binders c n b)
    | BICustom(s,t) -> BICustom(s,binders c n t)
    | BICut -> BICut

let sigma_abstract t =
  let uvl = List.rev (uvlist ()) in
  List.fold_left (fun p uv -> mkSigma 1 (binders_premise (mkUv uv 0) 1 p)) t uvl

EXTEND
  GLOBAL: lp premise atom;
  lp: [ [ cl = LIST1 clause -> cl ] ];
  clause :
    [ [ hd = atom; hyp = OPT [ ENTAILS; hyp = premise -> hyp ]; FULLSTOP ->
         let hyp = match hyp with None -> Conj [] | Some h -> h in
         let clause = sigma_abstract (Impl(hyp,Atom hd)) in
         reset (); 
         0, [], key_of clause, clause ]
    ];
  atom :
    [ "0"
      [ l = LIST1 atom LEVEL "1" SEP CONS ->
          if List.length l = 1 then List.hd l
          else
            let l = List.rev l in
            let last = List.hd l in
            let rest = List.rev (List.tl l) in
            mkSeq (L.of_list rest) last ]
    | "1"
      [ hd = atom LEVEL "2"; args = LIST0 atom LEVEL "2" ->
          if args = [] then hd else mkApp (L.of_list (hd :: args)) ]
    | "2" 
      [ c = CONSTANT; b = OPT [ BIND; a = atom LEVEL "1" -> a ] ->
          let c, lvl = lvl_name_of c in 
          let x = mkCon c lvl in
          (match b with
          | None -> check_con c lvl; x
          | Some b ->  mkBin 1 (binders x 1 b))
      | u = UVAR -> let u, lvl = lvl_name_of u in mkUv (get_uv u) lvl
      | i = REL -> mkDB (int_of_string (String.sub i 1 (String.length i - 1)))
      | NIL -> mkNil
      | s = LITERAL -> mkExt (mkString s)
      | LBRACKET; xs = LIST0 atom LEVEL "1" SEP COMMA;
          tl = OPT [ PIPE; u = UVAR -> u ]; RBRACKET ->
            let tl = match tl with
              | None -> XNil
              | Some u ->
                  let u, lvl = lvl_name_of u in mkUv (get_uv u) lvl in
          if List.length xs = 0 && tl <> XNil then 
            raise (Token.Error ("List with not elements cannot have a tail"));
          if List.length xs = 0 then mkNil
          else mkSeq (L.of_list xs) tl
      | LPAREN; a = atom LEVEL "0"; RPAREN -> a ]
    ];

  premise :
    [ "1"
      [ conj = LIST1 premise LEVEL "2" SEP COMMA ->
         if List.length conj = 1 then List.hd conj else mkConj conj ]
    | "2"
      [ a = atom; IMPL; p = premise -> Impl(Atom a,p)
      | a = atom; EQUAL; b = atom -> AtomBI (BIUnif(a,b))
      | a = atom -> Atom a
      | a = atom; ENTAILS; hyp = LIST1 premise LEVEL "2" SEP COMMA ->
         Impl(mkConj hyp,Atom a)
      | bt = BUILTIN; a = atom -> AtomBI(BICustom(bt,a))
      | BANG -> AtomBI BICut
      | NOT; p = premise LEVEL "2" -> Not p
      | binder = [PI -> fst | SIGMA -> snd]; x = bound; BIND; p = premise LEVEL "1" ->
         let x, is_uv = x in
         let bind = if is_uv then mkSigma else binder (mkPi,mkSigma) in
         bind 1 (binders_premise x 1 p)
      | LPAREN; p = premise; RPAREN -> p
      | LPAREN; p = premise; RPAREN; IMPL; q = premise -> Impl(p,q)]
    ];
  bound : 
    [ [ c = CONSTANT -> let c, lvl = lvl_name_of c in mkCon c lvl, false
      | u = UVAR -> let u, lvl = lvl_name_of u in mkUv (get_uv u) lvl, true ]
    ];
END

let parse e s =
  reset ();
  try Grammar.Entry.parse e (Stream.of_string s)
  with Ploc.Exc(l,(Token.Error msg | Stream.Error msg)) ->
    let last = Ploc.last_pos l in
    let ctx_len = 70 in
    let ctx =
      let start = max 0 (last - ctx_len) in
      let len = min (String.length s - start) ctx_len in
      "…" ^ String.sub s start len in
    raise (Stream.Error(Printf.sprintf "%s\nnear: %s" msg ctx))
  | Ploc.Exc(_,e) -> raise e

let parse_program s : program = parse lp s 
let parse_goal s : goal = sigma_abstract (parse premise s)
let parse_data s : data = parse atom s

end (* }}} *)
include Parser

end

module Subst = struct (* {{{ LP.Uv |-> data mapping *)
open LP

module M = Int.Map

type subst = { assign : data M.t; top_uv : int }
let empty n = { assign = M.empty; top_uv = n }

let last_sub_lookup = ref (XDB 0)
let in_sub i { assign = assign } =
  try last_sub_lookup := M.find i assign; true
  with Not_found -> false
let set_sub i t s = { s with assign = M.add i t s.assign }

let prf_subst fmt s =
  Format.pp_open_hovbox fmt 2;
  Format.pp_print_string fmt "{ ";
  iter_sep 
    (fun fmt () -> Format.pp_print_string fmt ";";Format.pp_print_space fmt ())
    (fun fmt (i,t) ->
       Format.pp_open_hvbox fmt 0;
       Format.pp_print_string fmt (pr_var i 0);
       Format.pp_print_space fmt ();
       Format.pp_print_string fmt ":= ";
       prf_data [] fmt (map (fun x -> kool (look x)) t);
       Format.pp_close_box fmt ()) fmt
    (List.rev (M.bindings s.assign));
  Format.pp_print_string fmt " }";
  Format.pp_close_box fmt ()
let string_of_subst s = on_buffer prf_subst s

let apply_subst s t =
  let rec subst x = match look x with
    | Uv(i,_) when in_sub i s -> map subst !last_sub_lookup
    | _ -> x in
  map subst t
let apply_subst_goal s = map_premise (apply_subst s)

let top s = s.top_uv
let raise_top i s = { s with top_uv = s.top_uv + i + 1 }

let fresh_uv lvl s = XUv(s.top_uv,lvl), { s with top_uv = s.top_uv + 1 }

end (* }}} *)

module Red = struct (* {{{ beta reduction, whd, and nf (for tests) *) 

open LP
open Subst


let lift ?(from=0) k t =
  if k = 0 then t
  else if from = 0 then mkXSusp t 0 k XEmpty
  else mkXSusp t from (from+k) (XSkip(k,from,XEmpty))

let beta t start len v =
  let rdx = mkXSusp t len 0 (XArgs(L.sub start len v, 0, XEmpty)) in
  SPY "rdx" (prf_data []) rdx;
  rdx

let rec mkskip n e = match n with
  | 0 -> e
  | n -> XArgs(L.singl (XDB 1),n,mkskip (n-1) e)

let beta_under depth t l =
  if l = [] then t
  else
    let len = List.length l in
    mkXSusp t (len+depth) depth
      (mkskip depth
          (XArgs(L.of_list l, 0, XEmpty)))

let rec whd s t =
  TRACE "whd" (fun fmt -> prf_data [] fmt t)
  match look t with
  | (Ext _ | Con _ | DB _ | Bin _ | Nil) as x -> kool x, s
  | Uv (i,_) when in_sub i s ->
      let t = !last_sub_lookup in
      let t', s = whd s t in
      t', if t == t' then s else set_sub i t' s
  | Uv _ -> t, s
  | Seq(xs,tl) as x -> kool x, s
  | App v as x ->
      let hd = L.hd v in
      let hd', s = whd s hd in
      match look hd' with
      | Bin (n_lam,b) ->
        let n_args = L.len v - 1 in
        if n_lam = n_args then
          whd s (beta b 1 n_args v)
        else if n_lam < n_args then
          whd s (mkAppv (beta b 1 n_lam v) v (n_lam+1) (n_args+1))
        else
          let diff = n_lam - n_args in
          (beta (mkBin diff b) 1 n_args v), s
      | _ ->
          if hd == hd' then kool x, s
          else mkAppv hd' (L.tl v) 0 (L.len v-1), s
          
let rec nf s x = match look x with
  | (Ext _ | Con _ | DB _ | Nil) as x -> kool x
  | Bin(n,t) -> mkBin n (nf s t)
  | Seq(xs,t) -> mkSeq (L.map (nf s) xs) (nf s t)
  | (App _ | Uv _) as xf ->
      let x', _ = whd s x in 
      match look x' with
      | App xs -> mkApp (L.map (nf s) xs)
      | _ -> if x == x' then kool xf else nf s x'

end (* }}} *)

(* vim:set foldmethod=marker: *)