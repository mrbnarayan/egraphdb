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
-module(egraph_function_model).
%% -behaviour(egraph_callback).
-export([init/0, init/2, terminate/1, % CRUD
         validate/2, create/3, read/2, update/3, delete/2]).
-export([create/4, update/4]).
-export([read_all_resource/3]).
-export([delete_resource/1]).
-export([read_resource/1]).
-export([read_resource/2]).
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

init(_, QsProplist) ->
    [{proplist, QsProplist}].

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
create(undefined, V, State) ->
    create_or_update_info(V, State);
create(Key, V, State) ->
    Info2 = V#{<<"source">> => Key},
    create_or_update_info(Info2, State).

%% @doc Create a new entry along with an expiry of some seconds.
-spec create(egraph_callback:id() | undefined, egraph_k(),
             [{binary(), binary()}], state()) ->
    {false | true | {true, egraph_callback:id()}, state()}.
create(Key, V, _QsProplist, State) ->
    create(Key, V, State).

%% @doc Read a given entry from the store based on its Key.
-spec read(egraph_callback:id(), state()) ->
        { {ok, egraph_k()} |
          {function, Fun :: function()},
          {error, not_found}, state()}.
read(undefined, State) ->
    %% return everthing you have
    {{function, fun read_all_resource/3}, State};
read(Key, State) ->
    QsProplists = proplists:get_value(proplist, State, []),
    Arity = egraph_util:convert_to_integer(
              proplists:get_value(<<"arity">>, QsProplists, 0)),
    case read_resource(Key, Arity) of
        {ok, Vals} ->
            {{ok, Vals}, State};
        R ->
            {R, State}
    end.

%% @doc Update an existing resource.
%%
%% The modified resource is validated before this function is called.
-spec update(egraph_callback:id(), egraph_k(), state()) -> {boolean(), state()}.
update(Key, V, State) ->
    Info2 = V#{<<"source">> => Key},
    create_or_update_info(Info2, State).

%% @doc Update an existing resource with some expiry seconds.
-spec update(egraph_callback:id(), egraph_k(), integer(), state()) ->
    {boolean(), state()}.
update(Key, V, _QsProplist, State) ->
    update(Key, V, State).

%% @doc Delete an existing resource.
-spec delete(egraph_callback:id(), state()) -> {boolean(), state()}.
delete(Key, State) ->
    QsProplists = proplists:get_value(proplist, State, []),
    Arity = egraph_util:convert_to_integer(
              proplists:get_value(<<"arity">>, QsProplists, 0)),
    {delete_resource(Key, Arity), State}.

%%%===================================================================
%%% Internal
%%%===================================================================

create_or_update_info(Info, State) ->
    #{ <<"name">> := Key,
       <<"arity">> := Arity,
       <<"lang">> := Lang,
       <<"function">> := Details,
       <<"test_vectors">> := TestVectors,
       <<"test_validator_function">> := TestValidatorFunction
     } = Info,
    %% Onl Erlang supported at present
    <<"erlang">> = Lang,
    true = is_list(TestVectors),
    true = is_binary(Details),
    true = is_binary(TestValidatorFunction),

    %% ---------------------------------------------------------------
    %% 1. compile function (Details) and check that its arity is Arity.
    %% 2. compile test_validator_function and check that its arity is 2.
    %% 3. Run the function with test_vectors and validate with the
    %%    validator function.
    Function = try
    case egraph_compiler:evaluate_erlang_expression(Details, normal) of
        Fun when is_function(Fun) ->
            {arity, FunArity} = erlang:fun_info(Fun, arity),
            FunArity = Arity,  %% validation of received arity with provided one
            case egraph_compiler:evaluate_erlang_expression(TestValidatorFunction, normal) of
                ValidatorFun when is_function(ValidatorFun) ->
                    {arity, 2} = erlang:fun_info(ValidatorFun, arity),
                    %% run function and validate the output quickly
                    lists:foreach(fun(InputArgs) ->
                                          Arity = length(InputArgs),
                                          Output = erlang:apply(Fun, InputArgs),
                                          lager:debug("Output = ~p", [Output]),
                                          true = erlang:apply(ValidatorFun,
                                                              [InputArgs, Output])
                                  end, TestVectors)
            end
    end
    catch
        ExceptionClass:ExceptionError:StackTrace ->
            lager:error("[Exception]: ~p:~p:~p", [ExceptionClass,ExceptionError,StackTrace])
    end,

    %% ---------------------------------------------------------------
    TimeoutMsec = ?DEFAULT_MYSQL_TIMEOUT_MSEC,
    TableName = ?EGRAPH_TABLE_FUNCTION,

    DictInfo = get_compression_info(),
    lager:debug("DictInfo = ~p", [DictInfo]),

    CompressedDetails = compress_data(Details, DictInfo),
    lager:debug("CompressedDetails = ~p", [CompressedDetails]),
    CompressedDetailsHash = egraph_util:generate_xxhash_binary(
                              egraph_util:convert_to_binary(CompressedDetails)),
    lager:debug("CompressedDetailsHash = ~p", [CompressedDetailsHash]),

    CompressedTestVec = compress_data(TestVectors, DictInfo),
    lager:debug("CompressedTestVec = ~p", [CompressedTestVec]),
    CompressedTestValidatorFunction = compress_data(TestValidatorFunction, DictInfo),
    lager:debug("CompressedTestValidatorFunction = ~p", [CompressedTestValidatorFunction]),

    ReturnLoc = iolist_to_binary(
                  [Key,
                   <<"?arity=">>,
                   egraph_util:convert_to_binary(Arity)]),
    lager:debug("ReturnLoc = ~p", [ReturnLoc]),
    case read_resource(Key, Arity) of
        {error, not_found} ->
            case sql_insert_record(TableName,
                                   Key, Arity, Lang,
                                   CompressedDetails, CompressedDetailsHash,
                                   CompressedTestVec,
                                   CompressedTestValidatorFunction,
                                   TimeoutMsec) of
                true ->
                    %% {ok, {Fun, Hash}} = egraph_cache_util:get({func, Key, Arity}, ?CACHE_GENERIC)
                    egraph_cache_util:async_put({func, Key, Arity},
                                                {Function, CompressedDetailsHash},
                                                ?CACHE_GENERIC),
                    {{true, ReturnLoc}, State};
                false ->
                    {false, State}
            end;
        {ok, [DbInfo]} ->
            OldVersion = maps:get(<<"version">>, DbInfo),
            %% TODO: Check for failures while updating info
            sql_update_record(TableName,
                              OldVersion,
                              Key, Arity, Lang,
                              CompressedDetails, CompressedDetailsHash,
                              CompressedTestVec,
                              CompressedTestValidatorFunction,
                              TimeoutMsec),
            egraph_cache_util:async_put({func, Key, Arity},
                                        {Function, CompressedDetailsHash},
                                        ?CACHE_GENERIC),
            {{true, ReturnLoc}, State}
    end.

%% TODO: Find the cluster nodes which must have this data and delete from there.
delete_resource(Key) ->
    TableName = ?EGRAPH_TABLE_FUNCTION,
    Q = iolist_to_binary([<<"DELETE FROM ">>,
                          TableName,
                          <<" WHERE name=?">>]),
    %% TODO: should we check for collisions?
    Params = [Key],
    TimeoutMsec = ?DEFAULT_MYSQL_TIMEOUT_MSEC,
    case egraph_sql_util:mysql_write_query(
           ?EGRAPH_RW_MYSQL_POOL_NAME,
           Q, Params, TimeoutMsec) of
        ok ->
            true;
        _ ->
            false
    end.

delete_resource(Key, Arity) ->
    TableName = ?EGRAPH_TABLE_FUNCTION,
    Q = iolist_to_binary([<<"DELETE FROM ">>,
                          TableName,
                          <<" WHERE name=? and arity=?">>]),
    %% TODO: should we check for collisions?
    Params = [Key, Arity],
    TimeoutMsec = ?DEFAULT_MYSQL_TIMEOUT_MSEC,
    case egraph_sql_util:mysql_write_query(
           ?EGRAPH_RW_MYSQL_POOL_NAME,
           Q, Params, TimeoutMsec) of
        ok ->
            true;
        _ ->
            false
    end.

%% TODO: Find the cluster nodes which must have this data and pull from there.
-spec read_resource(binary()) -> {ok, [map()]} | {error, term()}.
read_resource(Key) ->
    TableName = ?EGRAPH_TABLE_FUNCTION,
    Q = iolist_to_binary([<<"SELECT * FROM ">>,
                          TableName,
                          <<" WHERE name=?">>]),
    Params = [Key],
    read_generic_resource(Q, Params).

%% TODO: Find the cluster nodes which must have this data and pull from there.
-spec read_resource(binary(), integer()) -> {ok, [map()]} | {error, term()}.
read_resource(Key, Arity) ->
    TableName = ?EGRAPH_TABLE_FUNCTION,
    Q = iolist_to_binary([<<"SELECT * FROM ">>,
                          TableName,
                          <<" WHERE name=? and arity=?">>]),
    Params = [Key, Arity],
    read_generic_resource(Q, Params).

-spec read_all_resource(ShardKey :: integer(),
                        Limit :: integer(),
                        Offset :: integer()) ->
    {ok, [map()], NewOffset :: integer()} | {error, term()}.
read_all_resource(_ShardKey, Limit, Offset) ->
    TableName = ?EGRAPH_TABLE_FUNCTION,
    Q = iolist_to_binary([<<"SELECT * FROM ">>,
                          TableName,
                          <<" ORDER BY name ASC, arity ASC LIMIT ? OFFSET ?">>]),
    Params = [Limit, Offset],
    case read_generic_resource(Q, Params) of
        {ok, R} ->
            {ok, R, Offset + length(R)};
        E ->
            E
    end.

read_generic_resource(Query, Params) ->
    ConvertToMap = true,
    TimeoutMsec = ?DEFAULT_MYSQL_TIMEOUT_MSEC,
    case egraph_sql_util:mysql_query(
           [?EGRAPH_RO_MYSQL_POOL_NAME],
           Query, Params, TimeoutMsec, ConvertToMap) of
        {ok, Maps} ->
            Maps2 = lists:foldl(fun transform_result/2, [], Maps),
            {ok, Maps2};
        Error ->
            Error
    end.

transform_result(E, AccIn) ->
    E2 = case maps:get(<<"details_hash">>, E, undefined) of
             undefined ->
                 E;
             DetailsHash ->
                 %% egraph_shard_util:convert_xxhash_bin_to_integer(DetailsHash)
                 E#{<<"details_hash">> =>
                    egraph_util:bin_to_hex_binary(DetailsHash)}
         end,
    E3 = case maps:get(<<"details">>, E2, undefined) of
             undefined ->
                 E2;
             Details ->
                 E2#{<<"details">> =>
                     decompress_data(Details)}
         end,
    E4 = case maps:get(<<"test_vectors">>, E3, undefined) of
             undefined ->
                 E3;
             TestVectors ->
                 E3#{<<"test_vectors">> =>
                     erlang:binary_to_term(decompress_data(TestVectors))}
         end,
    E5 = case maps:get(<<"updated_datetime">>, E4, undefined) of
             undefined ->
                 E4;
             UpdatedDateTime ->
                 E4#{<<"updated_datetime">> =>
                     qdate:to_string(<<"Y-m-d H:i:s">>,UpdatedDateTime)}
         end,
    E6 = case maps:get(<<"test_validator_function">>, E5, undefined) of
             undefined ->
                 E5;
             TestValidatorFunctionBin ->
                 E5#{<<"test_validator_function">> =>
                     decompress_data(TestValidatorFunctionBin)}
         end,
    [E6 | AccIn].

sql_insert_record(TableName,
                  Key, Arity, Lang,
                  CompressedDetails, CompressedDetailsHash,
                  CompressedTestVec,
                  CompressedTestValidatorFunction,
                  TimeoutMsec) ->
    lager:debug("[] insert record"),
    DefaultVersion = 0,
    UpdatedDateTime = qdate:to_date(erlang:system_time(second)),
    Q = iolist_to_binary([<<"INSERT INTO ">>,
                          TableName,
                          <<" VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)">>]),
    Params = [Key, Arity, Lang, DefaultVersion, CompressedDetails, CompressedDetailsHash,
              CompressedTestValidatorFunction,
              CompressedTestVec, UpdatedDateTime],
    %% TODO: find out the cluster nodes which must persist this data
    %%       and save it there.
    case egraph_sql_util:mysql_write_query(
           ?EGRAPH_RW_MYSQL_POOL_NAME,
           Q, Params, TimeoutMsec) of
        ok ->
            true;
        _ ->
            false
    end.

sql_update_record(TableName, OldVersion,
                  Key, Arity, Lang,
                  CompressedDetails, CompressedDetailsHash,
                  CompressedTestVec,
                  CompressedTestValidatorFunction,
                  TimeoutMsec) ->
    lager:debug("[] update record"),
    Version = OldVersion + 1,
    UpdatedDateTime = qdate:to_date(erlang:system_time(second)),
    Q = iolist_to_binary([<<"UPDATE ">>,
                          TableName,
                          <<" SET version=?, lang=?, details=?, details_hash=?, test_validator_function=?, test_vectors=?, updated_datetime=? WHERE name=? and arity=? and version=?">>]),
    Params = [Version, Lang, CompressedDetails, CompressedDetailsHash,
              CompressedTestValidatorFunction, CompressedTestVec,
              UpdatedDateTime, Key, Arity, OldVersion],
    %% TODO: need to check whether update indeed happened or not because
    %% the where clause may not match.
    case egraph_sql_util:mysql_write_query(
           ?EGRAPH_RW_MYSQL_POOL_NAME,
           Q, Params, TimeoutMsec) of
        ok -> true;
        _ -> false
    end.

%% TODO unify this same as that for egraph_detail_model
get_compression_info() ->
    %% TODO: Optimize and cache the max dictionary key instead
    %% of retrieving this info from database each time. Note that
    %% approprate TTL must be associated with the data though.
    case egraph_dictionary_model:read_max_resource() of
        {ok, M} ->
            #{ <<"id">> := Key,
               <<"dictionary">> := Dictionary } = M,
            {Key, Dictionary};
        _ ->
            %% no compression
            %% TODO: What if the database connection is down then we'll land here
            %% as well, but then there are other issues to tackle.
            {0, <<>>}
    end.

%% TODO unify this same as that for egraph_detail_model
compress_data(Data, {Key, Dictionary}) when is_binary(Data) ->
    case Key > 0 of
        true ->
            case egraph_zlib_util:dict_deflate(Key, Data) of
                {error, _} ->
                    egraph_zlib_util:load_dicts([{Key, Dictionary}]),
                    R = egraph_zlib_util:dict_deflate(Key, Data),
                    iolist_to_binary(R);
                R2 ->
                    iolist_to_binary(R2)
            end;
        false ->
            %% no compression
            %% TODO: What if the database connection is down then we'll land here
            %% as well, but then there are other issues to tackle.
            R3 = egraph_zlib_util:dict_deflate(0, Data),
            iolist_to_binary(R3)
    end;
compress_data(Data, {Key, Dictionary}) ->
    compress_data(erlang:term_to_binary(Data), {Key, Dictionary}).


%% TODO unify this same as that for egraph_detail_model
decompress_data(Data) ->
    case egraph_zlib_util:dict_inflate(Data) of
        {error, _} ->
            Key = egraph_zlib_util:extract_key(Data),
            case egraph_dictionary_model:read_resource(Key) of
                {ok, [M]} ->
                    #{ <<"id">> := Key,
                       <<"dictionary">> := Dictionary } = M,
                    egraph_zlib_util:load_dicts([{Key, Dictionary}]),
                    {ok, {_, UncompressedData}} = egraph_zlib_util:dict_inflate(Data),
                    iolist_to_binary(UncompressedData);
                E ->
                    E
            end;
        {ok, {_, UncompressedData2}} ->
            iolist_to_binary(UncompressedData2)
    end.

