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
-module(egraph_index_model).
%% -behaviour(egraph_callback).
-export([init/0, init/2, terminate/1, % CRUD
         validate/2, create/3, read/2, update/3, delete/2]).
-export([create/4, update/4]).
-export([search/6, search/3]).
-export([read_all_resource/4]).
-export([create_or_update_info/2]).
-export([delete_resource/3]).
-export([read_resource/5]).
%% -export([sql_insert_record/4]).
-export_type([egraph_k/0]).

-include("egraph_constants.hrl").

-type egraph_k() :: binary().
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
create(InputKey, #{<<"key_type">> := KeyType} = V, State) ->
    Key = convert_input_key_to_key(KeyType, InputKey),
    Info2 = V#{<<"key_data">> => Key},
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
    {{function, fun read_all_resource/4}, State};
read(InputKey, State) ->
    QsProplists = proplists:get_value(proplist, State),
    KeyType = proplists:get_value(<<"keytype">>, QsProplists),
    InputIndexName = proplists:get_value(<<"indexname">>, QsProplists),
    IgnoreCase = proplists:get_value(<<"lower">>, QsProplists, <<"false">>),
    IndexName = case IgnoreCase of
                    <<"true">> ->
                        <<InputIndexName/binary, ?EGRAPH_INDEX_SPECIAL_SUFFIX_LOWERCASE/binary>>;
                    _ ->
                        InputIndexName
                end,
    WithinSphericalDistanceMeters = proplists:get_value(<<"distance_sphere">>, QsProplists, undefined),
    Limit = egraph_util:convert_to_integer(
              proplists:get_value(
                <<"limit">>,
                QsProplists,
                ?DEFAULT_EGRAPH_INDEX_SEARCH_LIMIT_RECORDS)),
    Offset = egraph_util:convert_to_integer(
               proplists:get_value(
                 <<"offset">>,
                 QsProplists,
                 0)),
    IsAsc = case proplists:get_value(<<"isasc">>, QsProplists, undefined) of
                undefined -> undefined;
                IsAscBin -> egraph_util:convert_to_boolean(IsAscBin)
            end,
    Key = convert_input_key_to_key(KeyType, InputKey),
    case read_resource(Key, KeyType, IndexName, Limit, Offset, IsAsc, WithinSphericalDistanceMeters, selected, id) of
        {ok, {_ColumnNames, MultipleRowValues}} ->
            HexIds = [begin [H] = X, egraph_util:bin_to_hex_binary(H) end || X <- MultipleRowValues],
            {{ok, HexIds}, State};
        R ->
            {R, State}
    end.

%% @doc Update an existing resource.
%%
%% The modified resource is validated before this function is called.
-spec update(egraph_callback:id(), egraph_k(), state()) -> {boolean(), state()}.
update(InputKey, #{<<"key_type">> := KeyType} = V, State) ->
    Key = convert_input_key_to_key(KeyType, InputKey),
    Info2 = V#{<<"key_data">> => Key},
    create_or_update_info(Info2, State).

%% @doc Update an existing resource with some expiry seconds.
-spec update(egraph_callback:id(), egraph_k(), integer(), state()) ->
    {boolean(), state()}.
update(Key, V, _QsProplist, State) ->
    update(Key, V, State).

%% @doc Delete an existing resource.
-spec delete(egraph_callback:id(), state()) -> {boolean(), state()}.
delete(InputKey, State) ->
    QsProplists = proplists:get_value(proplist, State),
    KeyType = proplists:get_value(<<"keytype">>, QsProplists),
    InputIndexName = proplists:get_value(<<"indexname">>, QsProplists),
    IgnoreCase = proplists:get_value(<<"lower">>, QsProplists, <<"false">>),
    IndexName = case IgnoreCase of
                    <<"true">> ->
                        <<InputIndexName/binary, ?EGRAPH_INDEX_SPECIAL_SUFFIX_LOWERCASE/binary>>;
                    _ ->
                        InputIndexName
                end,
    Key = convert_input_key_to_key(KeyType, InputKey),
    {delete_resource(Key, KeyType, IndexName), State}.

%% search exact match or range query.
%% Note that Key is a tuple {KeyStart, KeyEnd} (inclusive) in
%% case of range queries
search(Key, KeyType, IndexName, Limit, Offset, IsAsc) ->
    case read_resource(Key, KeyType, IndexName, Limit, Offset, IsAsc, undefined, selected, id) of
        {ok, {_ColumnNames, MultipleRowValues}} ->
            Ids = lists:flatten(MultipleRowValues),
            {ok, Ids};
        R ->
            R
    end.

search(Key, KeyType, IndexName) ->
    search(Key, KeyType, IndexName,
           ?DEFAULT_EGRAPH_INDEX_SEARCH_LIMIT_RECORDS,
           0,
           undefined).

%%%===================================================================
%%% Internal
%%%===================================================================

create_or_update_info(Info, State) ->
    #{ <<"key_data">> := Key,
       <<"id">> := HexId,
       <<"index_name">> := IndexName,
       <<"key_type">> := KeyType } = Info,
    lager:debug("[] HexId = ~p", [HexId]),
    %% TODO: strip unwanted characters and only retain alpha-numeric and underscore (VALIDATE) IMPORTANT
    8*2 = byte_size(HexId),
    TimeoutMsec = egraph_config_util:mysql_rw_timeout_msec(index),
    BaseTableName = egraph_shard_util:base_table_name(KeyType),
    lager:debug("[] BaseTableName = ~p", [BaseTableName]),
    TableName = egraph_shard_util:sharded_tablename(IndexName, BaseTableName),
    lager:debug("[] TableName = ~p", [TableName]),
    DbKey = egraph_shard_util:convert_key_to_datatype(KeyType, Key),
    lager:debug("[] DbKey = ~p", [DbKey]),
    DbId = egraph_util:hex_binary_to_bin(HexId),
    lager:debug("[] DbId = ~p", [DbId]),
    %% DbId = egraph_shard_util:convert_integer_to_xxhash_bin(IntId),
    ReturnLoc = iolist_to_binary(
                  [convert_key_to_http_location(Key),
                   <<"?keytype=">>, KeyType,
                   <<"&indexname=">>, IndexName]),
    lager:debug("[] ReturnLoc = ~p", [ReturnLoc]),
    %% why bother reading because if it exists then its good as well
    case sql_insert_record(TableName, {KeyType, DbKey}, DbId, TimeoutMsec) of
        true ->
            {{true, ReturnLoc}, State};
        false ->
            {false, State};
        {error, table_non_existent} ->
            CreateQuery = iolist_to_binary(
                            [<<"CREATE TABLE ">>,
                             TableName,
                             <<" LIKE ">>,
                             BaseTableName]),
            WritePoolName = egraph_config_util:mysql_rw_pool(index),
            ok = egraph_sql_util:mysql_write_query(WritePoolName,
                                                  CreateQuery,
                                                  [],
                                                  TimeoutMsec),
            case sql_insert_record(TableName, {KeyType, DbKey}, DbId, TimeoutMsec) of
                true ->
                    {{true, ReturnLoc}, State};
                false ->
                    {false, State}
            end
    end.

delete_resource(Key, KeyType, IndexName) ->
    DbKey = egraph_shard_util:convert_key_to_datatype(KeyType, Key),
    BaseTableName = egraph_shard_util:base_table_name(KeyType),
    {Query, Params} = case KeyType of
        <<"geo">> ->
            Q = iolist_to_binary([<<"DELETE FROM ">>,
                              egraph_shard_util:sharded_tablename(
                                IndexName, BaseTableName),
                              <<" WHERE key_data=ST_GeomFromGeoJSON(?)">>]),
            %% TODO: should we check for collisions?
            P = [DbKey],
            {Q, P};
        _ ->
            Q = iolist_to_binary([<<"DELETE FROM ">>,
                              egraph_shard_util:sharded_tablename(
                                IndexName, BaseTableName),
                              <<" WHERE key_data=?">>]),
            %% TODO: should we check for collisions?
            P = [DbKey],
            {Q, P}
    end,
    TimeoutMsec = egraph_config_util:mysql_rw_timeout_msec(index),
    PoolName = egraph_config_util:mysql_rw_pool(index),
    case egraph_sql_util:mysql_write_query(
           PoolName, Query, Params, TimeoutMsec) of
        ok ->
            true;
        _ ->
            false
    end.

-spec read_resource(binary(), binary(), binary(), binary(), create) -> {ok, [map()]} | {error, term()}.
read_resource(Key, KeyType, DbId, IndexName, create) ->
    lager:debug("[] read_resource"),
    DbKey = egraph_shard_util:convert_key_to_datatype(KeyType, Key),
    BaseTableName = egraph_shard_util:base_table_name(KeyType),
    TableName = egraph_shard_util:sharded_tablename(IndexName, BaseTableName),
    {Query, Params} = case KeyType of
                          <<"geo">> ->
                              Q = iolist_to_binary([<<"SELECT ST_AsGeoJSON(key_data) AS GeoJSON, id FROM ">>,
                                                TableName,
                                                <<" WHERE key_data=ST_GeomFromGeoJSON(?) and `id`=?">>]),
                              P = [DbKey, DbId],
                              {Q, P};
                          _ ->
                              Q = iolist_to_binary([<<"SELECT * FROM ">>,
                                                TableName,
                                                <<" WHERE key_data=? and `id`=?">>]),
                              P = [DbKey, DbId],
                              {Q, P}
                      end,
    lager:debug("[] Q = ~p, Params = ~p", [Query, Params]),
    read_generic_resource(Query, Params, create, BaseTableName, TableName).

%% @doc run exact match or range query
-spec read_resource(binary() | {binary(), binary()}, binary(), binary(),
                    pos_integer(), non_neg_integer(),
                    undefined | boolean(),
                    undefined | binary(), selected, id) -> {ok, [map()]} | {error, term()}.
read_resource(Key, KeyType, IndexName, Limit, Offset, IsAsc, WithinSphericalDistanceMeters, selected, id) ->
    BaseTableName = egraph_shard_util:base_table_name(KeyType),
    OrderByClause = case IsAsc of
                        undefined -> <<"">>;
                        true -> <<" ORDER BY id ASC ">>;
                        false -> <<" ORDER BY id DESC ">>
                    end,
    {WhereClause, Params} = case Key of
                                {KeyStart, KeyEnd} ->
                                    %% TODO: breaks for GEO
                                    DbKeyStart = egraph_shard_util:convert_key_to_datatype(KeyType, KeyStart),
                                    DbKeyEnd = egraph_shard_util:convert_key_to_datatype(KeyType, KeyEnd),
                                    {<<" WHERE key_data >= ? and key_data <= ? ">>,
                                     [DbKeyStart, DbKeyEnd, Limit, Offset]};
                                _ ->
                                    DbKey = egraph_shard_util:convert_key_to_datatype(KeyType, Key),
                                    WhereCriteria = case {KeyType, WithinSphericalDistanceMeters} of
                                                        {<<"geo">>, undefined} ->
                                                            <<" WHERE key_data=ST_GeomFromGeoJSON(?) ">>;
                                                        {<<"geo">>, _} ->
                                                            %% convert twice to avoid SQL injection attack
                                                            SpDistanceMeters = egraph_util:convert_to_float(
                                                                                 WithinSphericalDistanceMeters),
                                                            iolist_to_binary(
                                                              [<<" WHERE ST_Distance_Sphere(ST_GeomFromGeoJSON(?), key_data) <= ">>,
                                                               egraph_util:convert_to_binary(SpDistanceMeters)]);
                                                        _ ->
                                                            <<" WHERE key_data = ? ">>
                                                    end,
                                    {WhereCriteria,
                                     [DbKey, Limit, Offset]}
                            end,
    Q = iolist_to_binary([<<"SELECT id FROM ">>,
                          egraph_shard_util:sharded_tablename(
                            IndexName, BaseTableName),
                          WhereClause,
                          OrderByClause,
                          <<" LIMIT ? OFFSET ?">>]),
    read_generic_resource(Q, Params, false);
read_resource(Key, KeyType, IndexName, Limit, Offset, IsAsc, WithinSphericalDistanceMeters, _, _) ->
    BaseTableName = egraph_shard_util:base_table_name(KeyType),
    OrderByClause = case IsAsc of
                        undefined -> <<"">>;
                        true -> <<" ORDER BY id ASC ">>;
                        false -> <<" ORDER BY id DESC ">>
                    end,
    {WhereClause, Params} = case Key of
                                {KeyStart, KeyEnd} ->
                                    %% TODO: break for GEO
                                    DbKeyStart = egraph_shard_util:convert_key_to_datatype(KeyType, KeyStart),
                                    DbKeyEnd = egraph_shard_util:convert_key_to_datatype(KeyType, KeyEnd),
                                    {<<" WHERE key_data >= ? and key_data <= ? ">>,
                                     [DbKeyStart, DbKeyEnd, Limit, Offset]};
                                _ ->
                                    DbKey = egraph_shard_util:convert_key_to_datatype(KeyType, Key),
                                    WhereCriteria = case {KeyType, WithinSphericalDistanceMeters} of
                                                        {<<"geo">>, undefined} ->
                                                            <<" WHERE key_data=ST_GeomFromGeoJSON(?) ">>;
                                                        {<<"geo">>, _} ->
                                                            %% convert twice to avoid SQL injection attack
                                                            SpDistanceMeters = egraph_util:convert_to_float(
                                                                                 WithinSphericalDistanceMeters),
                                                            iolist_to_binary(
                                                              [<<" WHERE ST_Distance_Sphere(ST_GeomFromGeoJSON(?), key_data) <= ">>,
                                                               egraph_util:convert_to_binary(SpDistanceMeters)]);
                                                        _ ->
                                                            <<" WHERE key_data = ? ">>
                                                    end,
                                    {WhereCriteria,
                                     [DbKey, Limit, Offset]}
                            end,
    SelectCriteria = case KeyType of
                         <<"geo">> ->
                             <<"SELECT ST_AsGeoJSON(key_data) AS GeoJSON, id FROM ">>;
                         _ ->
                             <<"SELECT key_data, id FROM ">>
                     end,
    Q = iolist_to_binary([SelectCriteria,
                          egraph_shard_util:sharded_tablename(
                            IndexName, BaseTableName),
                          WhereClause,
                          OrderByClause,
                          <<" LIMIT ? OFFSET ?">>]),
    read_generic_resource(Q, Params).

-spec read_all_resource(KeyType :: binary(),
                        IndexName :: binary(),
                        Limit :: integer(),
                        Offset :: integer()) ->
    {ok, [map()], NewOffset :: integer()} | {error, term()}.
read_all_resource(KeyType, IndexName, Limit, Offset) ->
    BaseTableName = egraph_shard_util:base_table_name(KeyType),
    SelectCriteria = case KeyType of
                         <<"geo">> ->
                             <<"SELECT ST_AsGeoJSON(key_data) AS GeoJSON, id FROM ">>;
                         _ ->
                             <<"SELECT key_data, id FROM ">>
                     end,
    Q = iolist_to_binary([SelectCriteria,
                          egraph_shard_util:sharded_tablename(
                            IndexName, BaseTableName),
                          <<" LIMIT ? OFFSET ?">>]),
    Params = [Limit, Offset],
    case read_generic_resource(Q, Params) of
        {ok, R} ->
            {ok, R, Offset + length(R)};
        E ->
            E
    end.

read_generic_resource(Query, Params, read, BaseTableName, TableName) ->
    ConvertToMap = true,
    TimeoutMsec = egraph_config_util:mysql_ro_timeout_msec(index),
    IsRetry = false,
    IsReadOnly = true,
    ReadPools = egraph_config_util:mysql_ro_pools(index),
    PoolName = lists:nth(1, ReadPools),
    case egraph_sql_util:run_sql_read_query_for_shard(
           PoolName,
           BaseTableName,
           ReadPools,
           TableName,
           Query, Params, TimeoutMsec, IsRetry, IsReadOnly,
           ConvertToMap) of
        {ok, Maps} ->
            %% TODO: detect key_data type and convert from Geo Json to Json
            Maps2 = lists:foldl(fun transform_result/2, [], Maps),
            {ok, Maps2};
        Error ->
            Error
    end;
read_generic_resource(Query, Params, create, BaseTableName, TableName) ->
    ConvertToMap = true,
    TimeoutMsec = egraph_config_util:mysql_rw_timeout_msec(index),
    IsRetry = false,
    IsReadOnly = false,
    PoolName = egraph_config_util:mysql_rw_pool(index),
    case egraph_sql_util:run_sql_read_query_for_shard(
           PoolName,
           BaseTableName,
           [PoolName],
           TableName,
           Query, Params, TimeoutMsec, IsRetry, IsReadOnly,
           ConvertToMap) of
        {ok, Maps} ->
            %% TODO: detect key_data type and convert from Geo Json to Json
            Maps2 = lists:foldl(fun transform_result/2, [], Maps),
            {ok, Maps2};
        Error ->
            Error
    end.

read_generic_resource(Query, Params) ->
    read_generic_resource(Query, Params, true).

read_generic_resource(Query, Params, ConvertToMap) ->
    TimeoutMsec = egraph_config_util:mysql_ro_timeout_msec(index),
    ReadPools = egraph_config_util:mysql_ro_pools(index),
    case egraph_sql_util:mysql_query(
           ReadPools, Query, Params, TimeoutMsec, ConvertToMap) of
        {ok, Maps} when is_map(Maps) ->
            %% TODO: detect key_data type and convert from Geo Json to Json
            Maps2 = lists:foldl(fun transform_result/2, [], Maps),
            {ok, Maps2};
        {ok, R} when is_list(R) ->
            {ok, R};
        {ok, {_Cols, _MultiRows}} = R->
            R;
        Error ->
            Error
    end.

transform_result(E, AccIn) ->
    E2 = case maps:get(<<"key_data">>, E, undefined) of
             undefined ->
                 %% detect key_data type and convert from Geo Json to Json
                 case maps:get(<<"GeoJSON">>, E, undefined) of
                     undefined ->
                         E;
                     GeoJSONKey ->
                         E#{<<"key_data">> => jiffy:decode(GeoJSONKey, [return_maps])}
                 end;
             Key ->
                 E#{<<"key_data">> =>
                    egraph_shard_util:convert_dbkey_to_datatype_json(Key)}
         end,
    E3 = case maps:get(<<"id">>, E2, undefined) of
             undefined ->
                 E2;
             Id ->
                 E2#{<<"id">> =>
                     egraph_util:bin_to_hex_binary(Id)}
         end,
    [E3 | AccIn].

sql_insert_record(TableName, {<<"geo">>, DbKey}, DbId, TimeoutMsec) ->
    Q = iolist_to_binary([<<"INSERT INTO ">>,
                          TableName,
                          <<" VALUES(ST_GeomFromGeoJSON(?), ?)">>]),
    Params = [DbKey, DbId],
    PoolName = egraph_config_util:mysql_rw_pool(index),
    case egraph_sql_util:mysql_write_query(
           PoolName, Q, Params, TimeoutMsec) of
        ok ->
            true;
        {error, {1146,<<"42S02">>, _TableDoNotExist}} ->
            {error, table_non_existent};
        {error, {1062, <<"23000">>, _ErrorMsg}} ->
            %% duplicate entry, so can be safely ignored.
            true;
        _E ->
            false
    end;
sql_insert_record(TableName, {_, DbKey}, DbId, TimeoutMsec) ->
    Q = iolist_to_binary([<<"INSERT INTO ">>,
                          TableName,
                          <<" VALUES(?, ?)">>]),
    Params = [DbKey, DbId],
    PoolName = egraph_config_util:mysql_rw_pool(index),
    case egraph_sql_util:mysql_write_query(
           PoolName, Q, Params, TimeoutMsec) of
        ok ->
            true;
        {error, {1146,<<"42S02">>, _TableDoNotExist}} ->
            {error, table_non_existent};
        {error, {1062, <<"23000">>, _ErrorMsg}} ->
            %% duplicate entry, so can be safely ignored.
            true;
        _E ->
            false
    end.

convert_input_key_to_key(<<"geo">>, <<"point:", K/binary>>) ->
    Parts = binary:split(K, <<",">>, [trim_all]),
    [Lon, Lat] = [egraph_util:convert_to_float(X) || X <- Parts],
    #{<<"type">> => <<"Point">>,
      <<"coordinates">> => [Lon, Lat]};
convert_input_key_to_key(_, K) ->
    K.

convert_key_to_http_location(#{<<"type">> := <<"Point">>,
                               <<"coordinates">> := [Lon, Lat]}) ->
    LatBin = egraph_util:convert_to_binary(Lat),
    LonBin = egraph_util:convert_to_binary(Lon),
    <<"point:", LonBin/binary, ",", LatBin/binary>>;
convert_key_to_http_location(K) ->
    egraph_util:convert_to_binary(K).


