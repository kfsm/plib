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
%%    alternative process communication, support asynchronous communication
-module(plib).

-export([
   node/1, cast/2, call/2, call/3, emit/2, send/2, relay/3, ack/2
]).

-type(process() :: pid() | {atom(), node()} | atom()).
-type(tx()      :: {pid(), reference()}).

%%
%% return node where process is running
-spec(node/1 :: (process()) -> node()).

node(Pid)
 when is_pid(Pid) ->
   erlang:node(Pid);

node({global, _}=RegName) ->
   case erlang:whereis(RegName) of
      undefined -> throw(noproc);
      Pid       -> erlang:node(Pid)
   end;

node({_, Node})
 when is_atom(Node) ->
   Node;

node(RegName)
 when is_atom(RegName) ->
   case erlang:whereis(RegName) of
      undefined -> throw(noproc);
      Pid       -> erlang:node(Pid)
   end.

%%
%% cast asynchronous request to process
-spec(cast/2 :: (process(), any()) -> reference()).

cast(Pid, Msg) ->
   Tx = erlang:make_ref(),
   try erlang:send(Pid,  {'$req', {self(), Tx}, Msg}, [noconnect]) catch _:_ -> Msg end,
   Tx.

%%
%% emit asynchronous request to process with pid of originator
-spec(emit/2 :: (process(), any()) -> reference()).

emit(Pid, Msg) ->
   try erlang:send(Pid,  {'$req', self(), Msg}, [noconnect]) catch _:_ -> Msg end.

%%
%%
-spec(send/2 :: (process(), any()) -> reference()).

send(Pid, Msg) ->
   try erlang:send(Pid,  {'$req', undefined, Msg}, [noconnect]) catch _:_ -> Msg end.

%%
%% make synchronous request to process
-spec(call/2 :: (process(), any()) -> any()).
-spec(call/3 :: (process(), any(), timeout()) -> any()).

call(Pid, Msg) ->
   call(Pid, Msg, 5000).

call(Pid, Msg, Timeout) ->
   % inspired by gen:call(...) from OTP
   try erlang:monitor(process, Pid) of
      Tx ->
         do_call(Tx, Pid, Msg, Timeout)
   catch error:_ ->
      % unable to set monitor, fall-back to node monitor
      fb_call(Pid, Msg, Timeout) 
   end.   

do_call(Tx, Pid, Msg, Timeout) ->
   Node = plib:node(Pid),
   catch erlang:send(Pid, {'$req', {self(), Tx}, Msg}, [noconnect]),
   receive
      {Tx, Reply} ->
         erlang:demonitor(Tx, [flush]),
         Reply;
      {'DOWN', Tx, _, _, noconnection} ->
         exit({nodedown, Node});
      {'DOWN', Tx, _, _, Reason} ->
         exit(Reason)
   after Timeout ->
      erlang:demonitor(Tx, [flush]),
      exit(timeout)
   end.

fb_call(Pid, Msg, Timeout) ->
   Node = plib:node(Pid),
   monitor_node(Node, true),
   receive
      {nodedown, Node} -> 
         monitor_node(Node, false),
         exit({nodedown, Node})
   after 0 -> 
      Tx = erlang:make_ref(),
      catch erlang:send(Pid, {'$req', {self(), Tx}, Msg}, [noconnect]),
      receive
         {Tx, Reply} ->
            monitor_node(Node, false),
            Reply;
         {nodedown, Node} ->
            monitor_node(Node, false),
            exit({nodedown, Node})
      after Timeout ->
         monitor_node(Node, false),
         exit(timeout)
      end
   end.

%%
%% relay on-going request to other process
-spec(relay/3 :: (process(), tx(), any()) -> any()). 

relay(Pid, Tx, Msg) ->
   try erlang:send(Pid,  {'$req', Tx, Msg}, [noconnect]) catch _:_ -> Msg end.

%%
%% acknowledge transaction
-spec(ack/2 :: (tx(), any()) -> any()).

ack({Pid, Tx}, Msg)
 when is_pid(Pid) ->
   % backward compatible with gen_server:reply
   Msg0 = {Tx, Msg},
   try erlang:send(Pid, Msg0) catch _:_ -> Msg0 end;

ack(Pid, Msg)
 when is_pid(Pid) ->
   try erlang:send(Pid, Msg) catch _:_ -> Msg end;

ack(_, _Msg) ->
   undefined.




