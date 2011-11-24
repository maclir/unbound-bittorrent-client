-module(bencode).

-export([decode/1]).
-define(DICT, orddict).
-include("torrent_db_records.hrl").


decode(Data) ->
    case catch dec(Data,#torrent{}) of
	{'EXIT', _} ->
	    {error, unparsed};
	{Res, _} ->
	    {ok, Res}
    end.

dec(<<$l, Tail/binary>>,Record) ->
    dec_list(Tail, [],Record);
dec(<<$d, Tail/binary>>,Record) ->
    dec_dict(Tail,Record);
dec(<<$i, Tail/binary>>,_Record) ->
    dec_int(Tail, []);
dec(Data,_Record) ->
    dec_string(Data, []).

dec_int(<<$e, Tail/binary>>, Acc) ->
    {list_to_integer(lists:reverse(Acc)), Tail};
dec_int(<<X, Tail/binary>>, Acc) ->
    dec_int(Tail, [X|Acc]).

dec_string(<<$:, Tail/binary>>, Acc) ->
    Int = list_to_integer(lists:reverse(Acc)),
    <<Str:Int/binary, Rest/binary>> = Tail,
    {Str, Rest};
dec_string(<<X, Tail/binary>>, Acc) ->
    dec_string(Tail, [X|Acc]).

dec_list(<<$e, Tail/binary>>, Acc,_Record) ->
    {lists:reverse(Acc), Tail};
dec_list(Data, Acc, Record) ->
    {Res, Tail} = dec(Data, Record),
    dec_list(Tail, [Res|Acc],Record).

dec_dict(<<$e, Tail/binary>>, Record) ->
    {Record, Tail};
dec_dict(Data, Record) ->
    {Key, Tail1} = dec(Data,Record),
    case Key of
	<<"info">> ->
	    NewRecord = #info{};
	<<"files">> ->
	    NewRecord = #file{};
	_ ->
	    NewRecord = Record
    end,
    {Val, Tail2} = dec(Tail1,NewRecord),
    dec_dict(Tail2, record:store(Key,Val,Record)).
