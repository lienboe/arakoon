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

class type user_db =
  object
    method set : string -> string -> unit
    method get : string -> string
    method delete: string -> unit
    method test_and_set: string -> string option -> string option -> string option
    method range_entries: string option -> bool -> string option -> bool -> int
      -> (string * string) array
  end


module Registry : sig
  type f = user_db -> string option -> string option
  val register : string -> f -> unit
  val exists : string -> bool
  val lookup : string -> f
end
