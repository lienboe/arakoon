(*
This file is part of Arakoon, a distributed key-value store. Copyright
(C) 2010 Incubaid BVBA

Licensees holding a valid Incubaid license may use this file in
accordance with Incubaid's Arakoon commercial license agreement. For
more information on how to enter into this agreement, please contact
Incubaid (contact details can be found on www.arakoon.org/licensing).

Alternatively, this file may be redistributed and/or modified under
the terms of the GNU Affero General Public License version 3, as
published by the Free Software Foundation. Under this license, this
file is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.

See the GNU Affero General Public License for more details.
You should have received a copy of the
GNU Affero General Public License along with this program (file "COPYING").
If not, see <http://www.gnu.org/licenses/>.
*)

open OUnit
open Update
open Range
let _b2b u = 
  let b = Buffer.create 1024 in
  let () = Update.to_buffer b u in
  let flat = Buffer.contents b in
  let u',_ = Update.from_buffer flat 0 in
  u'

let _cmp = OUnit.assert_equal ~printer:Update.string_of 
let test_sequence () =
  let s = Update.Sequence [
    Update.make_master_set "Zen" None;
    Update.Set ("key", "value");
    Update.Delete "key";
    Update.TestAndSet ("key",None, Some "X")
  ] in
  let s' = _b2b s in
  _cmp s s'

let test_range() = 
  let r0 = Range.max in
  let u0 = Update.SetRange r0 in
  let u0' = _b2b u0 in
  _cmp u0 u0';
  let r1 = ((Some "b",Some "k"),(Some "a",Some "z")) in
  let u1 = Update.SetRange r1 in
  let u1' = _b2b u1 in
  _cmp u1 u1'

let suite = "update" >:::[
  "sequence" >:: test_sequence;
  "range" >:: test_range;
]
