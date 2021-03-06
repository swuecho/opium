(** Simple cookie module.  Cookies are base64'd and percent encoded.
*)

(** Fetch all cookies from a rock request *)
val cookies : Rock.Request.t -> (string * string) list
(** Get the follow of a cookie with a certain key *)
val get : Rock.Request.t -> key:string -> string option
(** Set the value of a cookie with a certain key in a response *)
val set : Rock.Response.t -> key:string -> data:string -> Rock.Response.t
(** Like set but will do multiple cookies at once *)
val set_cookies : Rock.Response.t -> (string * string) list -> Rock.Response.t
(** Rock middleware to add the the functionality above *)
val m : Rock.Middleware.t
