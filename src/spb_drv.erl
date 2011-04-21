%%  The contents of this file are subject to the Mozilla Public License
%%  Version 1.1 (the "License"); you may not use this file except in
%%  compliance with the License. You may obtain a copy of the License
%%  at http://www.mozilla.org/MPL/
%%
%%  Software distributed under the License is distributed on an "AS IS"
%%  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%  the License for the specific language governing rights and
%%  limitations under the License.
%%
%%  The Original Code is SPB.
%%
%%  The Initial Developer of the Original Code is VMware, Inc.
%%  Copyright (c) 2009-2011 VMware, Inc.  All rights reserved.
%%

-module(spb_drv).

-export([start/0, stop/1, listen/3, close/2, accept/2, recv/3]).
-export([spawn_test/1, test/1]).

-define(LIBNAME, "libspb").

-define(SPB_LISTEN, 0). %% KEEP IN SYNC WITH SPB.H
-define(SPB_CLOSE,  1).
-define(SPB_ACCEPT, 2).
-define(SPB_RECV,   3).

spawn_test(IpPort) ->
    spawn(fun () -> test(IpPort) end).

test(IpPort) ->
    {ok, Port} = spb_drv:start(),
    {ok, Fd} = spb_drv:listen("0.0.0.0", IpPort, Port),
    {ok, Fd} = spb_drv:accept(Fd, Port),
    receive
        {spb_event, Port, {ok, Fd1}} ->
            ok = spb_drv:recv(all, Fd1, Port),
            Result = drain(Fd1, Port, now(), 0, 0),
            {closed, Fd} = spb_drv:close(Fd, Port),
            ok = spb_drv:stop(Port),
            Result
    end.
drain(Fd, Port, Start, Count, Size) ->
    receive
        {spb_event, Port, {data, Fd, Data}} ->
            %%ok = spb_drv:recv(once, Fd, Port),
            drain(Fd, Port, Start, Count+1, Size + size(Data));
        {spb_event, Port, Event} ->
            Elapsed = timer:now_diff(now(), Start),
            io:format("received ~p bytes, in ~p msgs, in ~p microseconds (~p bytes/sec)~n",
                      [Size, Count, Elapsed, (Size*1000000)/Elapsed]),
            {ClosedOrBadArg, Fd} = spb_drv:close(Fd, Port),
            %% ASSERTION: badarg if it's already been closed
            true = ClosedOrBadArg =:= closed orelse ClosedOrBadArg =:= badarg,
            {Event, Count, Size}
    end.

start() ->
    erl_ddll:start(),
    {file, Path} = code:is_loaded(?MODULE),
    Dir = filename:join(filename:dirname(Path), "../priv"),
    ok = erl_ddll:load_driver(Dir, ?LIBNAME),
    Port = open_port({spawn_driver, ?LIBNAME}, [binary, stream]),
    %% The reply here actually comes up from the ev loop thread, and
    %% is worth waiting for.
    {simple_reply(Port), Port}.

stop(Port) ->
    true = port_close(Port),
    ok.

listen(IpAddress, IpPort, Port) ->
    AddressStr = address_str(IpAddress),
    true = port_command(
             Port, <<?SPB_LISTEN, (length(AddressStr)):64/native,
                     (list_to_binary(AddressStr))/binary, IpPort:16/native>>),
    simple_reply(Port).

close(Fd, Port) ->
    true = port_command(Port, <<?SPB_CLOSE, Fd:64/native-signed>>),
    simple_reply(Port).

accept(Fd, Port) ->
    true = port_command(Port, <<?SPB_ACCEPT, Fd:64/native-signed>>),
    simple_reply(Port).

recv(all, Fd, Port) ->
    recv1(-2, Fd, Port);
recv(once, Fd, Port) ->
    recv1(-1, Fd, Port);
recv(Bytes, Fd, Port) ->
    recv1(Bytes, Fd, Port).

recv1(N, Fd, Port) ->
    true = port_command(
             Port, <<?SPB_RECV, Fd:64/native-signed, N:64/native-signed>>),
    ok.

%% ---------------------------------------------------------------------------

simple_reply(Port) ->
    receive {spb_event, Port, Result} -> Result end.

address_str({A,B,C,D}) ->
    tl(lists:flatten([[$., integer_to_list(X)] || X <- [A,B,C,D]]));
address_str(List) when is_list(List) ->
    List.
