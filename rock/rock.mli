(** A tiny clone of ruby's Rack protocol in OCaml. Which is slightly
    more general and inspired by Finagle. It's not imperative to have
    this to for such a tiny framework but it makes extensions a lot
    more straightforward *)

open Core.Std
open Async.Std

(** A service is simply a function that returns it's result
    asynchronously *)
module Service : sig
  type ('req, 'rep) t = 'req -> 'rep Deferred.t with sexp

  val id : ('a, 'a) t
  val const : 'rep -> (_, 'rep) t
end

(** A filter is a higher order function that transforms a service into
    another service. *)
module Filter : sig
  type ('req, 'rep, 'req', 'rep') t =
    ('req, 'rep) Service.t -> ('req', 'rep') Service.t
  with sexp

  (** A filter is simple when it preserves the type of a service *)
  type ('req, 'rep) simple = ('req, 'rep, 'req, 'rep) t
  with sexp

  val id : ('req, 'rep) simple

  val (>>>) : ('q1, 'p1, 'q2, 'p2) t
    -> ('q2, 'p2, 'q3, 'p3) t
    -> ('q1, 'p1, 'q3, 'p3) t

  val apply_all : ('req, 'rep) simple list
    -> ('req, 'rep) Service.t
    -> ('req, 'rep) Service.t

  val apply_all' : ('req, 'rep) simple array
    -> ('req, 'rep) Service.t
    -> ('req, 'rep) Service.t
end

module Request : sig
  type t = {
    request : Cohttp.Request.t;
    body: Cohttp_async.Body.t;
    env : Univ_map.t;
  } with fields, sexp_of

  val create : ?body:Cohttp_async.Body.t
    -> ?env:Univ_map.t
    -> Cohttp.Request.t -> t
  (** Convenenice accessors on the request field  *)
  val uri : t -> Uri.t
  val meth : t -> Cohttp.Code.meth
  val headers : t -> Cohttp.Header.t
end

module Response : sig
  type t = {
    code : Cohttp.Code.status_code;
    headers : Cohttp.Header.t;
    body : Cohttp_async.Body.t;
    env: Univ_map.t
  } with fields, sexp_of

  val create :
    ?env: Univ_map.t ->
    ?body:Cohttp_async.Body.t ->
    ?headers:Cohttp.Header.t ->
    ?code:Cohttp.Code.status_code ->
    unit -> t

  val of_string_body :
    ?env: Univ_map.t ->
    ?headers:Cohttp.Header.t ->
    ?code:Cohttp.Code.status_code ->
    string -> t
end

(** A handler is a rock specific service *)
module Handler : sig
  type t = (Request.t, Response.t) Service.t with sexp_of
  val default : t
  val not_found : t
end

(** Middleware is a named, simple filter, that only works on rock
    requests/response *)
module Middleware : sig
  type t with sexp_of

  val filter : t -> (Request.t, Response.t) Filter.simple

  val name : t -> Info.t

  val create : filter:(Request.t, Response.t) Filter.simple
    -> name:Info.t -> t
end

module App : sig
  type t with sexp_of

  val middlewares : t -> Middleware.t list

  (** This is a type from core that is only here because we need to refer
     to it in a couple of places *)
  type error_handler = [
    | `Call of Socket.Address.Inet.t -> exn -> unit
    | `Ignore
    | `Raise ] with sexp_of

  val append_middleware : t -> Middleware.t -> t

  val create : ?middlewares:Middleware.t list -> handler:Handler.t -> t

  val run :
    ?on_handler_error:error_handler ->
    t -> port:int ->
    (Socket.Address.Inet.t, int) Cohttp_async.Server.t
      Deferred.t
end
