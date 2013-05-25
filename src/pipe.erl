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
%%   process pipe protocol
-module(pipe).

-export([
   '<<'/1, '>>'/1, cast/2, send/2
]).
-type(process() :: pid() | {atom(), node()} | atom()).
-type(tx()      :: {pid(), reference()}).


'<<'({pipe, A, _}) ->
   A.
'>>'({pipe, _, B}) ->
   B.

%%
%% cast asynchronous request to piped-process
-spec(cast/2 :: (process() | tx(), any()) -> reference()).

cast({Pid, TxA}, Msg)
 when is_pid(Pid), is_reference(TxA) ->
   TxB = erlang:make_ref(),
   try erlang:send(Pid, {'$pipe', {self(), TxB}, {TxA, Msg}}, [noconnect]) catch _:_ -> Msg end,
   TxB;

cast(Pid, Msg) ->
   Tx = erlang:make_ref(),
   try erlang:send(Pid,  {'$pipe', {self(), Tx}, Msg}, [noconnect]) catch _:_ -> Msg end,
   Tx.

%%
%% send asynchronous request to process 
-spec(send/2 :: (process() | tx(), any()) -> reference()).

send({Pid, Tx}, Msg) ->
   try erlang:send(Pid,  {'$pipe', self(), {Tx, Msg}}, [noconnect]) catch _:_ -> Msg end;

send(Pid, Msg) ->
   try erlang:send(Pid,  {'$pipe', self(), Msg}, [noconnect]) catch _:_ -> Msg end.


