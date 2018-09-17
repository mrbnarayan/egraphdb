%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%%
%%% @end
%%% %CopyrightBegin%
%%%
%%% Copyright Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in> 2017.
%%% All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% %CopyrightEnd%
%%%-------------------------------------------------------------------
-module(egraph_generic_model).
%% -behaviour(egraph_callback).
-export([init/0, init/2, terminate/1, % CRUD
         validate/2, create/3, read/2, update/3, delete/2]).
-export([create/4, update/4]).
-export_type([egraph_k/0]).

-include("egraph_constants.hrl").

-type egraph_k() :: map().
-type state() :: term().

-define(LAGER_ATTRS, [{type, model}]).

%%%===================================================================
%%% API
%%%===================================================================

%%%===================================================================
%%% Callbacks
%%%===================================================================

%% @doc Initialize the state that the handler will carry for
%% a specific request throughout its progression. The state
%% is then passed on to each subsequent call to this model.
-spec init() -> state().
init() ->
    nostate.

init(_, _) ->
    init().

%% @doc At the end of a request, the state is passed back in
%% to allow for clean up.
-spec terminate(state()) -> term().
terminate(_State) ->
    ok.

%% @doc Return, via a boolean value, whether the user-submitted
%% data structure is considered to be valid by this model's standard.
-spec validate(egraph_k() | term(), state()) -> {boolean(), state()}.
validate(V, State) ->
    {is_map(V) orelse is_list(V) orelse is_boolean(V), State}.

%% @doc Create a new entry. If the id is `undefined', the user
%% has not submitted an id under which to store the resource:
%% the id needs to be generated by the model, and (if successful),
%% returned via `{true, GeneratedId}'.
%% Otherwise, a given id will be passed, and a simple `true' or
%% `false' value may be returned to confirm the results.
%%
%% The created resource is validated before this function is called.
-spec create(egraph_callback:id() | undefined, egraph_k(), state()) ->
        {false | true | {true, egraph_callback:id()}, state()}.
create(undefined, _V, State) ->
    NewId = create_id(),
    %% directly read and write binary(), but then this will break the
    %% generic abstraction of json resource.
    %% this is just for demo, so doing nothing
    { {true, NewId}, State};
create(_Id, _V, State) ->
    {true, State}.

%% @doc Create a new entry along with an expiry of some seconds.
-spec create(egraph_callback:id() | undefined, egraph_k(),
             [{binary(), binary()}], state()) ->
    {false | true | {true, egraph_callback:id()}, state()}.
create(Id, V, QsProplist, State) ->
    {Resp, State2} = create(Id, V, State),
    case proplists:get_value(<<"e">>, QsProplist, undefined) of
        ExpiryBin when is_binary(ExpiryBin) ->
            ExpirySeconds = binary_to_integer(ExpiryBin),
            lager:debug(?LAGER_ATTRS, "[~p] ~p create(~p, ~p, ~p, ~p) -> ~p",
                        [self(), ?MODULE, Id, V, ExpirySeconds, State, Resp]),
            {Resp, State2};
        _ ->
            {Resp, State2}
    end.

%% @doc Read a given entry from the store based on its Id.
-spec read(egraph_callback:id(), state()) ->
        { {ok, egraph_k()} | {error, not_found}, state()}.
read(_Id, State) ->
    Resp = {error, not_found},
    {Resp, State}.

%% @doc Update an existing resource.
%%
%% The modified resource is validated before this function is called.
-spec update(egraph_callback:id(), egraph_k(), state()) -> {boolean(), state()}.
update(_Id, _V, State) ->
    {false, State}.

%% @doc Update an existing resource with some expiry seconds.
-spec update(egraph_callback:id(), egraph_k(), integer(), state()) ->
    {boolean(), state()}.
update(Id, V, _QsProplist, State) ->
    update(Id, V, State).

%% @doc Delete an existing resource.
-spec delete(egraph_callback:id(), state()) -> {boolean(), state()}.
delete(_Id, State) ->
    {false, State}.

%%%===================================================================
%%% Internal
%%%===================================================================

-spec create_id() -> egraph_callback:id().
create_id() ->
    TsMicro = erlang:system_time(micro_seconds),
    egraph_util:bin_to_hex_binary(<<TsMicro:64>>).
