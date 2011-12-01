%%% @author Peter Myllykoski <peter@UL30JT>, Nahid Vafaie
%%% @copyright (C) 2011, Peter Myllykoski
%%% @doc
%%%
%%% @end
%%% Created :  9 Nov 2011 by Peter Myllykoski <peter@UL30JT>

-module(torrent).
-export([start_link_loader/1,init_loader/1]).
-export([start_link/2,init/1]).
-include("torrent_db_records.hrl").
-include("torrent_status.hrl").

%% =============================================================================
%% Torrent loader function that is responsible for opening the persistent
%% storage and dynamically add all the torrents found into the supervisor.

start_link_loader(Id) ->
	Self = self(),
	spawn_link(?MODULE,init_loader,[{Self,Id}]),
	receive
		{ok,Pid} ->
			{ok,Pid}
		after 100 ->
			{error,time_out}
	end.

init_loader({Pid,Id})->
	io:fwrite("Torrent Loader Started!\n"),
	Pid ! {ok,self()},
	RecordList = [torrent_db:get_torrent_by_id(0)],
	start_torrent(Pid,RecordList,Id).

start_torrent(Pid,[Record|Tail],Id) ->
	InfoHash = info_hash:to_hex(Record#torrent.info_sha),
	StartFunc = {torrent,start_link,[Id,Record]},
	ChildSpec = {InfoHash,StartFunc,transient,brutal_kill,worker,[torrent]},
	supervisor:start_child(Pid,ChildSpec),
	start_torrent(Pid,Tail,Id);

start_torrent(_Pid,[],_) ->
	ok.



%% =============================================================================
%% Regular torrent functions

start_link(Id,Record) ->
	{ok,spawn_link(torrent,init,[{Id,Record}])}.

init({Id,Record}) ->
	process_flag(trap_exit,true),
	DownloadPid = spawn(download,init,[Record,self()]),
	AnnounceList = lists:flatten(Record#torrent.announce_list) -- [Record#torrent.announce],
	Announce = AnnounceList ++ [Record#torrent.announce],
	spawn_trackers(Announce,Record#torrent.info_sha,Id),
	loop(Record,#torrent_status{},[],[],DownloadPid,Id,[]).

loop(Record,StatusRecord,TrackerList,LowPeerList,DownloadPid,Id,ActiveNetList) ->
	receive
		{get_statistics,Pid} ->
			Pid ! {statistics,0,0,0},
			loop(Record,StatusRecord,TrackerList,LowPeerList,DownloadPid,Id,ActiveNetList);
		{im_free, NetPid} ->
			DownloadPid ! {new_free, NetPid},
			loop(Record,StatusRecord,TrackerList,LowPeerList,DownloadPid,Id,ActiveNetList);
		{peer_list,FromPid,ReceivedPeerList} ->
			io:fwrite("Got Peer List\n"),
			%% why do we need the tracker list?
			TempTrackerList = lists:delete(FromPid, TrackerList),
			NewTrackerList = [FromPid|TempTrackerList],
			io:fwrite("Low:~p\n", [LowPeerList]),
			NewSpawns = ReceivedPeerList ++ LowPeerList,
			TempActiveNetList = spawn_connections(NewSpawns,ActiveNetList,Record#torrent.info_sha,Id, [],10 - length(ActiveNetList)),
			NewActiveNetList = TempActiveNetList ++ ActiveNetList,
			loop(Record,StatusRecord,NewTrackerList,LowPeerList,DownloadPid,Id,NewActiveNetList);
		{bitfield,FromPid,ReceivedBitfield} ->
			NumPieces = byte_size(Record#torrent.info#info.pieces) div 20,
			case (bit_size(ReceivedBitfield) > NumPieces) of
				true ->
					<<Bitfield:NumPieces/bitstring,Rest/bitstring>> = ReceivedBitfield,
					RestSize = bit_size(Rest),
					if
						Rest == <<0:RestSize>> ->
							PeerIndexList = bitfield:to_indexlist(Bitfield,invert),
							DownloadPid ! {net_index_list, FromPid, PeerIndexList};
						true ->
							FromPid ! bad_bitfield
					end;
				false ->
					FromPid ! bad_bitfield
			end,
			loop(Record,StatusRecord,TrackerList,LowPeerList,DownloadPid,Id,ActiveNetList);
		{have,FromPid,Index} ->
			DownloadPid ! {net_index_list, FromPid, [{Index}]},
			loop(Record,StatusRecord,TrackerList,LowPeerList,DownloadPid,Id,ActiveNetList);
		{dowloaded,SenderPid,PieceIndex,Data} ->
			Done = bitfield:has_one_zero(Record#torrent.info#info.bitfield),
			case write_to_file:write(PieceIndex,Data,Record,Done) of
				{ok, TempRecord} ->
					SenderPid ! {ok, done},
					DownloadPid ! {piece_done, PieceIndex},					
					NewBitField = bitfield:flip_bit(PieceIndex, TempRecord#torrent.info#info.bitfield),
					NewLength = TempRecord#torrent.info#info.length_complete + byte_size(Data),
					%% 					Percentage = NewLength / TempRecord#torrent.info#info.length * 100,
					%% 					io:fwrite("....~n~.2f~n....~n", [Percentage]),
					NewRecord = TempRecord#torrent{info = (TempRecord#torrent.info)#info{bitfield = NewBitField, length_complete = NewLength}},
					torrent_db:delete_by_SHA1(NewRecord#torrent.info_sha),
					torrent_db:add(NewRecord),
					io:fwrite("done:~p~n", [PieceIndex]),
					loop(NewRecord,StatusRecord,TrackerList,LowPeerList,DownloadPid,Id,ActiveNetList);
				{error, _Reason} ->
					SenderPid ! {error, corrupt_data},
					loop(Record,StatusRecord,TrackerList,LowPeerList,DownloadPid,Id,ActiveNetList)
			end;
		{'EXIT',FromPid,_Reason} ->
			%% 			io:fwrite("~p Got EXIT: ~p\n", [FromPid, _Reason]),
			{NewActiveNetList ,NewLowPeerList} = ban_net_pid(FromPid, ActiveNetList, LowPeerList, DownloadPid),
			loop(Record,StatusRecord,TrackerList,NewLowPeerList,DownloadPid,Id,NewActiveNetList)
	end.

ban_net_pid(FromPid, ActiveNetList, LowPeerList, DownloadPid) ->
	BadNet = lists:keyfind(FromPid,1,ActiveNetList),
	NewActiveNetList = lists:delete(BadNet, ActiveNetList),
	NewLowPeerList = [element(2,BadNet)|LowPeerList],
	DownloadPid ! {net_exited, FromPid},
	{NewActiveNetList ,NewLowPeerList}.

spawn_trackers([],_,_) ->
	ok;
spawn_trackers([Announce|AnnounceList],InfoHash,Id) ->
	Self = self(),
	spawn(tracker,init,[Self,Announce,InfoHash,Id]),
	spawn_trackers(AnnounceList,InfoHash,Id).

spawn_connections(_,_,_InfoHash,_Id,NetList,Count) when Count < 1->
	NetList;
spawn_connections([],_,_InfoHash,_Id,NetList,_) ->
	NetList;
spawn_connections([{Ip,Port}|Rest],Active,InfoHash,Id,NetList,Count) ->
	case lists:keymember({Ip,Port}, 2, Active) of
		true ->
			spawn_connections(Rest,Active,InfoHash,Id,NetList,Count);
		false ->
			Pid = spawn_link(nettransfer,init,[self(),Ip,Port,InfoHash,Id]),
			spawn_connections(Rest,Active,InfoHash,Id, [{Pid, {Ip,Port}}|NetList],Count - 1)
	end.