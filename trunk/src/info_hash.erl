%%% @author Peter Myllykoski <peter@UL30JT>
%%% @copyright (C) 2011, Peter Myllykoski
%%% @doc
%%%
%%% @end
%%% Created : 10 Nov 2011 by Peter Myllykoski <peter@UL30JT>

-module(info_hash).
-export([to_hex/1,from_hex/1,url_encode/1,url_decode/1]).

to_hex(<<C1:4,C2:4,Rest/binary>>) ->
    if 
	C1<10 ->
	    Char1 = C1+$0;
	C1>=10 ->
	    Char1 = C1+$0+7
    end,
    if 
	C2<10 ->
	    Char2 = C2+$0;
	C2>=10 ->
	    Char2 = C2+$0+7
    end,
    [Char1,Char2|to_hex(Rest)];

to_hex(<<>>) ->
    [].

from_hex([C1,C2|[]]) ->
    if
	C1>=$A,C1=<$F ->
	    Char1 = C1-55;
	C1=<$9,C1>=$0 ->
	    Char1 = C1-48;
	C1>=$a,C1=<$z ->
	    Char1 = C1-87
    end,
    if
	C2>=$A ->
	    Char2 = C2-55;
	C2=<$9 ->
	    Char2 = C2-48;
	C2>=$a,C2=<$z ->
	    Char2 = C2-87
    end,
    Return = <<Char1:4,Char2:4>>,
    Return;

from_hex([C1,C2|Tail]) ->
    BinTail = from_hex(Tail),
    Bin = from_hex([C1,C2]),
    list_to_binary(lists:flatten([Bin|[BinTail]])).

    
url_encode(<<Byte:8,Rest/binary>>) ->
    if
	Byte>=$0,Byte=<$9 ->
	    Enc = <<Byte>>;
	Byte>=$A,Byte=<$Z ->
	    Enc = <<Byte>>;
	Byte>=$a,Byte=<$z ->
	    Enc = <<Byte>>;
	Byte==$-;Byte==$_;Byte==$.;Byte==$~ ->
	    Enc = <<Byte>>;
	true ->
	    Percent = <<"%">>,
	    Hex = list_to_binary(to_hex(<<Byte>>)),
	    Enc = <<Percent/binary,Hex/binary>>
    end,
    if
	Rest == <<>> ->
	    Enc;
	Rest == <<Rest/binary>> ->
	    EncRest = url_encode(Rest),
	    <<Enc/binary,EncRest/binary>>
    end.

url_decode(<<String/binary>>) ->
    list_to_binary(url_decode(String,false)).

url_decode(<<V1,V2,Tail/binary>>,Hex) ->
    if
	Hex == true ->
	    [from_hex(binary_to_list(<<V1,V2>>))|url_decode(Tail,false)];
	Hex == false ->
	    case V1 of
		$% ->
		    url_decode(<<V2,Tail/binary>>,true);
		_ ->
		    [V1|url_decode(<<V2,Tail/binary>>,false)]
	    end
    end;

url_decode(<<V1/binary>>,false) ->
    V1.


    
	    