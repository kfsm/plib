%%
%%   Copyright (c) 2012 - 2013, Dmitry Kolesnikov
%%   Copyright (c) 2012 - 2013, Mario Cardona
%%   All Rights Reserved.
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%% @description
%%
-module(plib_tests).
-include_lib("eunit/include/eunit.hrl").

kfsm_test_() ->
   {
      setup,
      fun init/0,
      fun free/1,
      [
          {"call", fun call/0}
         ,{"cast", fun cast/0}
         ,{"send", fun send/0}
      ]
   }.

init()  ->
   spawn(fun echo/0).

free(Pid) -> 
   erlang:exit(Pid, shutdown).

call() ->
   ping = plib:call(echo, ping).

cast() ->
   Ref = plib:cast(echo, ping),
   receive {Ref, ping} -> ok end.

send() ->
   Ref = plib:send(echo, ping),
   receive ping -> ok end.


echo() ->
   erlang:register(echo, self()),
   loop().

loop() ->
   receive
      {call, Tx, Msg} -> 
         plib:ack(Tx, Msg),
         loop();
      {cast, Tx, Msg} ->
         plib:ack(Tx, Msg),
         loop();
      {send, Tx, Msg} ->
         plib:ack(Tx, Msg),
         loop()
   end.




