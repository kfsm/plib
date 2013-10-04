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
%%    alternative process communication protocol
-module(plib).

-export([
   node/1, 
   cast/2, 
   cast/3,
   emit/2, 
   emit/3, 
   send/2, 
   send/3,
   call/2, 
   call/3, 
   call/4,
   relay/3, 
   relay/4, 
   ack/2, 
   pid/1,
   tx/1,
   type/1,
   uref/1
]).

-type(process() :: pid() | {atom(), node()} | atom()).
-type(req()     :: atom()).
-type(tx()      :: {pid(), reference()}).

%%
%% return node where process is running
-spec(node/1 :: (process()) -> node()).

node(Pid)
 when is_pid(Pid) ->
   erlang:node(Pid);

node({_, Node})
 when is_atom(Node) ->
   Node;

node({global, Name}) ->
   plib:node(global:whereis_name(Name));

node(undefined) ->
   exit(noproc);

node(Name)
 when is_atom(Name) ->
   plib:node(erlang:whereis(Name)).

%%
%% cast asynchronous request to process
-spec(cast/2 :: (process(), any()) -> reference()).
-spec(cast/3 :: (process(), req(), any()) -> reference()).

cast(Pid, Msg) ->
   cast(Pid, '$req', Msg).

cast(Pid, Req, Msg) ->
   Tx = erlang:make_ref(),
   % tx signature of cast & call MUST differ due to relay feature
   % relay of call message requires re-sync of monitor object
   % relay decision making is based on tx signature 
   % for simplicity position of pid & tx is changes at cast (this is opaque to client)
   try erlang:send(Pid,  {Req, {Tx, self()}, Msg}, [noconnect]) catch _:_ -> Msg end,
   Tx.


%%
%% emit asynchronous request to process with pid of originator
-spec(emit/2 :: (process(), any()) -> reference()).
-spec(emit/3 :: (process(), req(), any()) -> reference()).

emit(Pid, Msg) ->
   emit(Pid, '$req', Msg).

emit(Pid, Req, Msg) ->
   try erlang:send(Pid,  {Req, self(), Msg}, [noconnect]) catch _:_ -> Msg end.

%%
%% send asynchronous request to process 
-spec(send/2 :: (process(), any()) -> reference()).
-spec(send/3 :: (process(), req(), any()) -> reference()).

send(Pid, Msg) ->
   send(Pid, '$req', Msg).

send(Pid, Req, Msg) ->
   try erlang:send(Pid,  {Req, undefined, Msg}, [noconnect]) catch _:_ -> Msg end.

%%
%% make synchronous request to process
-spec(call/2 :: (process(), any()) -> any()).
-spec(call/3 :: (process(), any(), timeout()) -> any()).
-spec(call/4 :: (process(), req(), any(), timeout()) -> any()).

call(Pid, Msg) ->
   plib:call(Pid, '$req', Msg, 5000).

call(Pid, Msg, Timeout) ->
   plib:call(Pid, '$req', Msg, Timeout).

call(Pid, Req, Msg, Timeout) ->
   % inspired by gen:call(...) from OTP
   try erlang:monitor(process, Pid) of
      Tx ->
         do_call(Tx, Pid, Req, Msg, Timeout)
   catch error:_ ->
      % unable to set monitor, fall-back to node monitor
      fb_call(Pid, Req, Msg, Timeout) 
   end.   

do_call(Tx, Pid, Req, Msg, Timeout) ->
   Node = plib:node(Pid),
   catch erlang:send(Pid, {Req, {self(), Tx}, Msg}, [noconnect]),
   receive
      {Tx, Reply} ->
         erlang:demonitor(Tx, [flush]),
         Reply;
      {relay, Tx, RelayPid, RelayReq, RelayMsg} ->
         erlang:demonitor(Tx, [flush]),
         call(RelayPid, RelayReq, RelayMsg, Timeout);
      {'DOWN', Tx, _, _, noconnection} ->
         exit({nodedown, Node});
      {'DOWN', Tx, _, _, Reason} ->
         exit(Reason)
   after Timeout ->
      erlang:demonitor(Tx, [flush]),
      exit(timeout)
   end.

fb_call(Pid, Req, Msg, Timeout) ->
   Node = plib:node(Pid),
   monitor_node(Node, true),
   receive
      {nodedown, Node} -> 
         monitor_node(Node, false),
         exit({nodedown, Node})
   after 0 -> 
      Tx = erlang:make_ref(),
      catch erlang:send(Pid, {Req, {self(), Tx}, Msg}, [noconnect]),
      receive
         {Tx, Reply} ->
            monitor_node(Node, false),
            Reply;
         {relay, Tx, RelayPid, RelayReq, RelayMsg} ->
            erlang:demonitor(Tx, [flush]),
            call(RelayPid, RelayReq, RelayMsg, Timeout);
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
-spec(relay/4 :: (process(), req(), tx(), any()) -> any()). 

relay(Pid, Tx, Msg) ->
   relay(Pid, '$req', Tx, Msg).

relay(Pid, Req, {Cli, Tx}, Msg)
 when is_pid(Cli), is_reference(Tx) ->
   %% synchronous message relay requires re-sync of Tx Reference at client-side
   %% otherwise death of destination process remain unnoticeable by client 
   %% Tx monitor has to be re-set
   try erlang:send(Cli, {relay, Tx, Pid, Req, Msg}) catch _:_ -> Msg end;

relay(Pid, Req, Tx, Msg) ->   
   try erlang:send(Pid,  {Req, Tx, Msg}, [noconnect]) catch _:_ -> Msg end.

%%
%% acknowledge transaction
-spec(ack/2 :: (tx(), any()) -> any()).

ack({pipe, A, _}, Msg) ->
   plib:ack(A, Msg);
   
ack({Pid, Tx}, Msg)
 when is_pid(Pid), is_reference(Tx) ->
   % backward compatible with gen_server:reply
   Msg0 = {Tx, Msg},
   try erlang:send(Pid, Msg0) catch _:_ -> Msg0 end;

ack({Tx, Pid}, Msg)
 when is_pid(Pid), is_reference(Tx) ->
   % backward compatible with gen_server:reply
   Msg0 = {Tx, Msg},
   try erlang:send(Pid, Msg0) catch _:_ -> Msg0 end;

ack(Pid, Msg)
 when is_pid(Pid) ->
   try erlang:send(Pid, Msg) catch _:_ -> Msg end;

ack(_, _Msg) ->
   undefined.

%%
%% extract transaction pid
-spec(pid/1 :: (tx()) -> pid() | undefined).

pid({Pid, _Tx})
 when is_pid(Pid) ->
   Pid;

pid({_Tx, Pid})
 when is_pid(Pid) ->
   Pid;

pid(Pid)
 when is_pid(Pid) ->
   Pid; 

pid(_) ->
   undefined.

%%
%% extract transaction reference
-spec(tx/1 :: (tx()) -> reference() | undefined).

tx({_Pid, Tx})
 when is_reference(Tx) ->
   Tx;

tx({Tx, _Pid})
 when is_reference(Tx) ->
   Tx;

tx(Tx)
 when is_reference(Tx) ->
   Tx;

tx(_) ->
   undefined.

%%
%% check transaction type
-spec(type/1 :: (tx()) -> call | cast | emit | send).

type({Pid, _Tx})
 when is_pid(Pid) ->
   call;

type({_Tx, Pid})
 when is_pid(Pid) ->
   cast;

type(Pid)
 when is_pid(Pid) ->
   emit; 

type(_) ->
   send.

%%
%% universal transaction reference
-spec(uref/1 :: (tx()) -> binary()).
uref(Tx) ->
   btoh(
      crypto:sha(
         erlang:term_to_binary({plib:pid(Tx), plib:tx(Tx)})
      )
   ).


btoh(X) ->
   << <<(if A < 10 -> $0 + A; A >= 10 -> $a + (A - 10) end):8>> || <<A:4>> <=X >>.

