open Core.Std
open Async.Std
open Rock

module Co = Cohttp

type t = {
  port: int;
  debug: bool;
  verbose: bool;
  routes : (Co.Code.meth * Router.Route.t * Handler.t) list;
  middlewares: Middleware.t list;
  name: string;
  not_found : Handler.t;
} with fields, sexp_of

type builder = t -> t with sexp_of

type route = string -> Handler.t -> builder with sexp_of

let register app ~meth ~route ~action =
  { app with routes=(meth, route, action)::app.routes }

let app =
  { name="Opium Default Name";
    port=3000;
    debug=false;
    verbose=false;
    routes=[];
    middlewares=[];
    not_found=Handler.not_found }

let port port t = { t with port }

let middleware m app =
  { app with middlewares=m::app.middlewares }

let public_path root requested =
  let asked_path = Filename.concat root requested in
  Option.some_if (String.is_prefix asked_path ~prefix:root) asked_path

let action meth route action =
  register ~meth ~route:(Router.Route.create route) ~action

let get route action =
  register ~meth:`GET ~route:(Router.Route.create route) ~action
let post route action =
  register ~meth:`POST ~route:(Router.Route.create route) ~action
let delete route action =
  register ~meth:`DELETE ~route:(Router.Route.create route) ~action
let put route action =
  register ~meth:`PUT ~route:(Router.Route.create route) ~action

let patch route action =
  register ~meth:`PATCH ~route:(Router.Route.create route) ~action
let head route action =
  register ~meth:`HEAD ~route:(Router.Route.create route) ~action
let options route action =
  register ~meth:`OPTIONS ~route:(Router.Route.create route) ~action

let compose_builders builders t =
  builders |> List.fold_left ~f:(fun app f -> f app) ~init:t

let create_router routes =
  let router = Router.create () in
  routes
  |> List.iter ~f:(fun (meth, route, action) ->
    Router.add router ~meth ~route ~action);
  router

let create { routes ; middlewares ; not_found ; _ } =
  let router = create_router routes in
  let middlewares = (Router.m router)::middlewares in
  Rock.App.create ~middlewares ~handler:not_found

let start app =
  let router = create_router app.routes in
  let middlewares = (Router.m router)::app.middlewares in
  let middlewares =
    middlewares @ (if app.debug then [Middleware_pack.debug] else [])
  in
  if app.verbose then
    Log.Global.info "Running on port: %d%s" app.port
      (if app.debug then " (debug)" else "");
  let port = app.port in
  let app = Rock.App.create ~middlewares ~handler:app.not_found in
  app |> Rock.App.run ~port >>| ignore |> don't_wait_for;
  Scheduler.go ()

let command ?(summary="Opium Default App") app =
  let open Command.Spec in
  Command.async_basic
    ~summary
    (empty
     +> flag "-p" (optional_with_default 3000 int)
          ~doc:"port number to listen"
     +> flag "-h" (optional_with_default "0.0.0.0" string)
          ~doc:"interface to listen"
     +> flag "-m" no_arg
          ~doc:"print middleware stack"
     +> flag "-d" no_arg
          ~doc:"enable debug information"
    ) (fun port host print_middleware debug () ->
      (if print_middleware then begin
         print_endline "Active middleware:";
         app
         |> Rock.App.middlewares
         |> List.map ~f:(Fn.compose Info.to_string_hum Rock.Middleware.name)
         |> List.iter ~f:(fun name ->
           printf "> %s \n" name);
         don't_wait_for @@ Shutdown.exit 0;
       end
      );
      (if debug then
         Log.Global.info "Listening on %s:%s" host (Int.to_string port));
      let app =
        if debug then
          Rock.App.append_middleware app Middleware_pack.debug
        else app in
      app |> Rock.App.run ~port >>| ignore >>= never
    )

type body = [
  | `Html of Cow.Html.t
  | `Json of Cow.Json.t
  | `Xml of Cow.Xml.t
  | `String of string ]

module Response_helpers = struct
  open Cow

  let content_type ct = Cohttp.Header.init_with "Content-Type" ct
  let json_header = content_type "application/json"
  let xml_header = content_type "application/xml"
  let html_header = content_type "text/html"

  let respond_with_string = Response.of_string_body

  let respond ?headers ?(code=`OK) = function
    | `String s -> respond_with_string ?headers ~code s
    | `Json s ->
      respond_with_string ~headers:json_header (Json.to_string s)
    | `Html s ->
      respond_with_string ~headers:html_header (Html.to_string s)
    | `Xml s ->
      respond_with_string ~headers:xml_header (Xml.to_string s)

  let respond' ?headers ?code s =
    s |> respond ?headers ?code |> return
end

let param = Router.param
let respond = Response_helpers.respond
let respond' = Response_helpers.respond'
