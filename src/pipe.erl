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
%%   pipeline protocol defines message semantic 
%%
%%   a pipeline is a series of Erlang processes through which messages flows.
%%   the pipeline organizes complex processing tasks through several simple 
%%   Erlang processes, which are called 'stages'. Each stage in a pipeline 
%%   receives message from the pipeline, processes them in some way, and
%%   sends transformed message back to the pipeline. 
%%
%%   the pipe is defined as a tuple containing either identities of
%%   predecessor / source (a) and successor / sink (b) stages or 
%%   computation to discover them based on message content.
%%   (a)--(stage)-->(b)
-module(pipe).

-export([
   make/1, make/2, make/3,
   a/2, '<'/2,  b/2, '>'/2, send/2
]).

-type(pipe() :: {pipe, any(), any()}).

%%
%% make pipe
-spec(make/1 :: (pid()) -> pipe()).
-spec(make/2 :: (pid(), pid()) -> pipe()).

make(P) 
 when is_list(P) ->
   lists:foldl(fun(B, A) -> make(A, B), B end, hd(P), tl(P));

make(B) ->
   make(self(), B).

make(A, B) ->
   try erlang:send(B, {'$pipe', '$a', A}, [noconnect]) catch _:_ -> ok end,
   try erlang:send(A, {'$pipe', '$b', B}, [noconnect]) catch _:_ -> ok end,
   {pipe, A, B}.

make(Src, A, B)
 when Src =:= A ->
   {pipe, A, B};
make(Src, A, B)
 when Src =:= B ->
   {pipe, B, A};
make(Src, undefined, B) ->
   {pipe, Src, B};
make(Src, A, _B) ->
   {pipe, Src, A}.


%%
%% send message through pipeline 
-spec(a/2 :: (pipe(), any()) -> ok).
-spec(b/2 :: (pipe(), any()) -> ok).

'<'(Pipe, Msg) -> a(Pipe, Msg).
'>'(Pipe, Msg) -> b(Pipe, Msg).

a({pipe, A, _}, Msg) 
 when not is_function(A) ->
   send(A, Msg);
a({pipe, A, _}, Msg)
 when is_function(A) ->
   send(A(Msg), Msg).

b({pipe, _, B}, Msg) 
 when not is_function(B) ->
   send(B, Msg);
b({pipe, _, B}, Msg)
 when is_function(B) ->
   send(B(Msg), Msg).

send(Pid, Msg)
 when is_pid(Pid) ->
   try erlang:send(Pid,  {'$pipe', self(), Msg}, [noconnect]) catch _:_ -> Msg end;

send({Pid, Tx}, Msg) ->
   % gen_server backward compatibility
   try erlang:send(Pid,  {'$pipe', self(), {Tx, Msg}}, [noconnect]) catch _:_ -> Msg end.

