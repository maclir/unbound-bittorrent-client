%%%----------------------------------------------------------------------
%%% Author:		Stepan Stepasyuk
%%% Desc.:		API for external communication. (with seeders and tracker)
%%%----------------------------------------------------------------------
-module(tcp).
-import(bencode, [decode/1, encode/1]).
-export([open_a_socket/5 ,check_handshake/2, start_listening/3,connect_to_server/9, init_listening/2, scrape/2]).

%%----------------------------------------------------------------------
%% Function:	connect_to_server/9
%% Purpose:		builds a request string and sends it to the tracker
%% Args:		AnnounceBin,InfoHashBin,ClientIdBin (binaries)
%%				Eventt (string)
%%				UploadedVal,DownloadedVal,LeftVal,NumWantedVal (integers)
%% Returns:		List of peers and the interval is successful
%%----------------------------------------------------------------------	
connect_to_server(AnnounceBin,InfoHashBin,ClientIdBin,Eventt,UploadedVal,DownloadedVal,LeftVal,NumWantedVal,tcp)->   
	Announce = binary_to_list(AnnounceBin) ++ "?",
	InfoHash = "info_hash=" ++ binary_to_list(InfoHashBin) ++ "&",
	ClientId = "peer_id=" ++ binary_to_list(info_hash:url_encode(ClientIdBin)) ++ "&",
	Port = "port=" ++ "6991" ++ "&",
	Uploaded = "uploaded=" ++ integer_to_list(UploadedVal) ++ "&",
	Downloaded = "downloaded=" ++ integer_to_list(DownloadedVal) ++ "&",
	Left = "left=" ++ integer_to_list(LeftVal) ++ "&",
	NumWanted = "numwant=" ++ integer_to_list(NumWantedVal) ++ "&", 
	Compact = "compact=" ++ "1",
	if Eventt /= "none" ->
		   Event = "&event=" ++ Eventt,
		   RequestString = Announce ++ InfoHash ++ ClientId ++ Port ++ Uploaded ++ Downloaded ++ Left ++ NumWanted ++ Compact ++ Event;
	   true->
		   RequestString = Announce ++ InfoHash ++ ClientId ++ Port ++ Uploaded ++ Downloaded ++ Left ++ NumWanted ++ Compact
	end,
	
	case httpc:request(get, {RequestString,[{"User-Agent", "Unbound"},
											{"Accept", "*/*"}]
							},[], []) of
		{ok,{_,_,Response}} -> 
			case decode(list_to_binary(Response)) of 
				{ok,{dict,Pairs}} -> 
					Result = lists:map(fun(X)->process_pairs(X) end, Pairs),
					[lists:keyfind("Interval",1,Result),lists:keyfind("peers",1,Result)];
				{error, Reason} ->
					exit(self(), Reason)
			end;
		{error,Reason} ->
			exit(self(), Reason)
	end;

connect_to_server(AnnounceBinFull,InfoHashBin,ClientIdBin,Event,UploadedVal,DownloadedVal,LeftVal,NumWantedVal,{udp, TempConnectionId})->
	{ok, Socket} = gen_udp:open(0, [{active, true}]),
	<<TransactionID:32>> =  app_sup:gen_random(4),
	[TempAnnounceBin,TrackerPortBinTemp] = binary:split(AnnounceBinFull,[<<":">>],[{scope,{byte_size(AnnounceBinFull),6-byte_size(AnnounceBinFull)}}]),
	[TrackerPortBin|AnnounceBinTail] = binary:split(TrackerPortBinTemp,[<<"/">>],[]),
	[_,AnnounceBinHead] = binary:split(TempAnnounceBin,[<<"udp://">>],[]),
	case AnnounceBinTail of
		[] ->
			AnnounceBin = AnnounceBinHead;
		[Tail] ->
			AnnounceBin = <<AnnounceBinHead/binary, "/", Tail/binary>>
	end,	
	TrackerPort = list_to_integer(binary_to_list(TrackerPortBin)),
	case TempConnectionId of
		connection_id ->
			%% http://www.rasterbar.com/products/libtorrent/udp_tracker_protocol.html
			Result = gen_udp:send(Socket,binary_to_list(AnnounceBin), TrackerPort, <<4497486125440:64,0:32,TransactionID:32>>),
			case Result of
				ok ->
					receive
						{udp,_Sockett,_FromHost,_FromPort,TempList} ->
							<<_Action:32,TransactionID:32,ConnectionId:64>> = list_to_binary(TempList),
							gen_udp:close(Socket),
							{connection_id,ConnectionId};
						Msg ->
							io:fwrite("msg: ~p~n", [Msg]),
							gen_udp:close(Socket),
							Msg
					end;
				{error,Reason} ->
					io:fwrite("err: ~p~n", [Reason]),
					{error,Reason}
			end;
		ConnectionId ->
			<<Key:32>> = app_sup:gen_random(4),
			DecodedEvent = decode_event(Event),
			%%TODO normal phase, return like normal tcp: [lists:keyfind("Interval",1,Result),lists:keyfind("peers",1,Result)]
			Result = gen_udp:send(Socket,binary_to_list(AnnounceBin), TrackerPort, <<ConnectionId:64,1:32,TransactionID:32,InfoHashBin/binary,ClientIdBin/binary,DownloadedVal:64,LeftVal:64,
																					 UploadedVal:64,DecodedEvent:32,0:32,Key:32,NumWantedVal:32,6991:16>>),
			case Result of
				ok ->
					receive
						{udp,_Sockett,_FromHost,_FromPort,TempList} ->
							<<_Action:32,TransactionID:32,Interval:32,_NumPeers:32,_NumSeeders:32,Peers/binary>> = list_to_binary(TempList),
							gen_udp:close(Socket),
							[{"Interval",Interval},
							 {"peers",separate(Peers)}];
						Msg ->
							io:fwrite("msg: ~p~n", [Msg]),
							gen_udp:close(Socket),
							Msg
					end;
				{error,Reason} ->
					io:fwrite("err: ~p~n", [Reason]),
					{error,Reason}
			end
	end.

decode_event(Event) ->
	case Event of
		"none" -> 0;
		"completed" -> 1;
		"started" -> 2;
		"stopped" -> 3
	end.
%%----------------------------------------------------------------------
%% Function:	scrape/2
%% Purpose:		builds a scrape request string,sends it and
%%				parses the response
%% Args:		ScrapeBin, InfoHashBin (binaries)
%% Returns:		amount of seeders,
%%				peers who started downloading,
%%				peers who started downloading and stopped
%%----------------------------------------------------------------------	
scrape(ScrapeBin,InfoHashBin)->	
	Scrape = binary_to_list(ScrapeBin) ++ "?",
	InfoHash = "info_hash" ++ binary_to_list(InfoHashBin),
	RequestString = Scrape ++ InfoHash,
	{ok,{_,_,Response}} = httpc:request(get, {RequestString,[]},[], []),
	case decode(list_to_binary(Response)) of	
		{ok,
		 {dict,
		  [{<<"files">>,
			{dict, [{InfoHash,
					 {dict,[{<<"complete">>,Complete},
							{<<"downloaded">>,Downloaded},
							{<<"incomplete">>,Incomplete}]}}]}}]}}-> 
			[{"Complete",Complete},{"Downloaded",Downloaded},{"Incomplete",Incomplete}];
		_ -> "Tracker does not support scraping or probably does not like you~n"
	end.

%%----------------------------------------------------------------------
%% Function:	process_pairs/1
%% Purpose:		parses the response from the tracker
%% Args:		a tuple with 2 elements
%% Returns:		a list with pairs with the response details
%%----------------------------------------------------------------------	
process_pairs({Key, Value})->
	case binary_to_list(Key) of
		"complete" -> {"complete", Value};
		"incomplete" -> {"incomplete",Value};
		"min interval" -> {"Min Interval",Value};
		"interval" -> {"Interval",Value};
		"peers" -> {"peers",separate(Value)};
		_ -> {"Unknown pair. Key: ~p Value: ~p~n",[Key,Value]}
	end.

%%----------------------------------------------------------------------
%% Function:	separate/1
%% Purpose:		converts the peers IP from binary to list.
%% Args:		binary
%% Returns:		a list of peers' IPs
%%----------------------------------------------------------------------	
separate(<<>>)->
	[];
separate(<<Ip1:8, Ip2:8, Ip3:8, Ip4:8,Port:16,Rest/binary>>)->
	[{{Ip1,Ip2,Ip3,Ip4},Port}|separate(Rest)];
separate(_)->
	ok.

%%----------------------------------------------------------------------
%% Function:	open_a_socket/5
%% Purpose:		connects to a peer	
%% Args: 		DestinationIp(tuple of 4 elements), 
%%				DestinationPort(integer), InfoHash (string)
%%				ClientId (string), MasterPid (pid)	
%%----------------------------------------------------------------------
open_a_socket(DestinationIp, DestinationPort,InfoHash,ClientId,MasterPid)->
	case gen_tcp:connect(DestinationIp, DestinationPort, [binary, {packet,0},{active,false}], 5000) of
		{ok,Socket} -> 
			connect_to_client(MasterPid, Socket,InfoHash,ClientId);
		{error, Reason} ->
			exit(self(), Reason)
	end.

%%----------------------------------------------------------------------
%% Function:	connect_to_client/4
%% Purpose:		handshakes a peer and starts listening for the response,
%%				after response, changes options of a socket and enters
%%				the main loop
%% Args:		MasterPid (pid), Socket (socket), InfoHash (string)
%%				ClientId (string)
%%----------------------------------------------------------------------	
connect_to_client(MasterPid, Socket,InfoHash,ClientId)-> 
	gen_tcp:send(Socket,[
						 19,
						 "BitTorrent protocol",
						 <<0,0,0,0,0,0,0,0>>,
						 InfoHash,
						 ClientId
						]),
	handshake_loop(MasterPid,Socket),
	inet:setopts(Socket, [{packet, 4},{active, true}]),
	main_loop(Socket, MasterPid).

%%----------------------------------------------------------------------
%% Function:	handshake_loop/2
%% Purpose:		parses the peers' handshake
%% Returns:		if a handshake is successful, the function sends
%%				a message to the parent process, otherwise process dies
%% Args:		MasterPid (pid), Socket (socket)
%%----------------------------------------------------------------------	
handshake_loop(MasterPid, Socket)->
	case gen_tcp:recv(Socket,68) of
		{ok,<< 19, "BitTorrent protocol", 
			   _ReservedBytes:8/binary, 
			   _InfoHash:20/binary, 
			   _PeerID:20/binary
			   >>}->
			MasterPid ! "peer accepted handshake";
		{error, _Reason}->
			gen_tcp:close(Socket),
			exit(self(), handshake)
	end.

%%----------------------------------------------------------------------
%% Function:	main_loop/2
%% Purpose:		endless loo, used for identyfing incoming messages,
%%				including internal ones.
%% Args:		MasterPid (pid), Socket (socket)
%%----------------------------------------------------------------------	
main_loop(Socket, MasterPid)->
	receive
		choke ->
			gen_tcp:send(Socket,<<0>>), 
			main_loop(Socket,MasterPid); 
		unchoke ->
			gen_tcp:send(Socket,<<1>>), 
			main_loop(Socket,MasterPid); 
		keep_alive ->
			gen_tcp:send(Socket,<<0>>), 
			main_loop(Socket,MasterPid);
		interested ->
			gen_tcp:send(Socket,<<2>>),
			main_loop(Socket,MasterPid);
		not_interested ->
			gen_tcp:send(Socket,<<3>>),
			main_loop(Socket,MasterPid);
		{send_have, PieceIndex}->
			gen_tcp:send(Socket,[<<4:8,PieceIndex:32>>]),
			main_loop(Socket,MasterPid);
		{send_bitfield, <<Bitfield/binary>>}->
			gen_tcp:send(Socket,[<<5:8, Bitfield/binary>>]),
			main_loop(Socket,MasterPid);
		{tcp,_,<<5:8,Bitfield/binary>>} ->
			MasterPid ! {client_bitfield, self(), Bitfield},
			main_loop(Socket,MasterPid);
		{request, Index, Offset, Length} ->
			gen_tcp:send(Socket, [<<6:8, Index:32, Offset:32, Length:32>>]),
			main_loop(Socket,MasterPid);
		{send_piece,Index, Offset, Block}->
			gen_tcp:send(Socket, [<<7:8,Index:32,Offset:32,Block/binary>>]),
			main_loop(Socket,MasterPid);
		{send_cancel,Index,Offset,Length}->
			gen_tcp:send(Socket,[<<8:8,Index:32,Offset:32,Length:32>>]),
			main_loop(Socket,MasterPid);
		{tcp,_,<<4:8, PieceIndex:32>>} ->
			MasterPid ! {have,self(),PieceIndex},
			main_loop(Socket,MasterPid);
		{tcp,_,<<0>>} ->
			MasterPid ! {got_choked, self()},
			main_loop(Socket, MasterPid);
		{tcp,_,<<2>>}->
			MasterPid ! {got_interested,self()},
			main_loop(Socket, MasterPid);
		{tcp,_,<<3>>}->
			MasterPid ! {got_not_interested, self()},
			main_loop(Socket, MasterPid);
		{tcp,_,<<>>}->
			main_loop(Socket, MasterPid);
		{tcp,_,<<1>>}-> 
			MasterPid ! {got_unchoked,self()},
			main_loop(Socket, MasterPid);
		{tcp,_,<<6:8, Index:32, Offset:32, Length:32>>}->
			MasterPid ! {got_request,self(), Index,Offset,Length},
			main_loop(Socket, MasterPid);
		{tcp,_,<<8:8, Index:32, Offset:32, Length:32>>}->
			MasterPid ! {got_cancel, self(), Index, Offset, Length},
			main_loop(Socket,MasterPid);
		{tcp,_,<<9:8,_Port:16>>}->
			% normally, we should not get this message, but just in case. 
			main_loop(Socket,MasterPid);
		{tcp_closed,_}->
			gen_tcp:close(Socket),
			exit(self(), port_closed);
		{tcp,_,<<7:8, 
				 _PieceIndex:32,
				 Offset:32,
				 Block/binary>>}->
			MasterPid ! {got_block, Offset,byte_size(Block),Block},
			main_loop(Socket, MasterPid);
		{stop,Reason} ->
			gen_tcp:close(Socket),
			exit(self(), Reason);
		{error, Reason}->
			gen_tcp:close(Socket),
			exit(self(), Reason);
		_Smth ->
			main_loop(Socket, MasterPid)
		after 10000 ->
			gen_tcp:close(Socket),
			exit(self(), main_loop_timeout)
	end.

%%----------------------------------------------------------------------
%% Function:	init_listening/2
%% Purpose:		spawns a listening process
%%				afterwards, enters a receive loop and waits for a
%%				listening socket to arrive
%% Returns:		Pid of the process, if a listening socket arrived,
%%				error, of a listening socket does not arrive.
%% Args:		PortNumber(integer), ClietId(string)
%%----------------------------------------------------------------------
init_listening(PortNumber,ClientId) ->
	ListeningPid = spawn_link(tcp,start_listening,[self(),PortNumber,ClientId]),
	receive 
		{ok, _Socket} ->
			{ok, ListeningPid};
		{error, _ } ->
			{error, error_opening_socket}
	end.

%%----------------------------------------------------------------------
%% Function:	start_listening/3
%% Purpose:		listens on a port, sends back
%%				listening socket.
%% Args:		InitPid (pid), PortNumber(integer), ClietId(string)
%%----------------------------------------------------------------------
start_listening(InitPid, PortNumber, ClientId)->
	case gen_tcp:listen(PortNumber, [binary, {packet,0}]) of 
		{ok, Socket} ->
			InitPid ! {ok, Socket},
			accepting(Socket, ClientId);
		{error, _} ->
			io:fwrite("Port ~p in use, retrying in 5 seconds\n",[PortNumber]),
			receive
				after 5000 ->
					ok
			end,
			start_listening(InitPid, PortNumber, ClientId)
	end.

%%----------------------------------------------------------------------
%% Function:	accepting/2
%% Purpose:		accepting connections, spawns a hanler process when
%%				a connection is made.
%% Returns:		amount of seeders,
%%				peers who started downloading,
%%				peers who started downloading and stopped
%% Args:		Socket (socket), ClietId(string)
%%----------------------------------------------------------------------	
accepting(Socket, ClientId)->
	{ok, ListenSocket} = gen_tcp:accept(Socket),
	HandlingPid = spawn(?MODULE, check_handshake,[ListenSocket,ClientId]),
	gen_tcp:controlling_process(ListenSocket, HandlingPid),
	accepting(Socket,ClientId).

%%----------------------------------------------------------------------
%% Function:	check_handshake/2
%% Purpose:		checks if the peer sent us a right handshake
%% Args:		Socket (socket), ClietId(string)
%%----------------------------------------------------------------------		
check_handshake(Socket,ClientId)->
	receive
		{tcp,_,<< 19, "BitTorrent protocol", 
				  _ReservedBytes:8/binary, 
				  InfoHash:20/binary, 
				  _PeerID:20/binary>>} ->
			MasterPid = check_infohash(Socket,InfoHash),
			send_handshake(Socket,InfoHash,ClientId),
			inet:setopts(Socket, [{packet, 4},{active, true}]),
			main_loop(Socket, MasterPid);
		{tcp_closed,_}->
			gen_tcp:close(Socket),
			exit(self(), "remote peer closed connection");
		{stop,Reason} ->
			gen_tcp:close(Socket),
			exit(self(), Reason);
		{tcp,_,Msg} ->
			gen_tcp:close(Socket),
			exit(self(), {"remote peer sent this",Msg})
	end.

%%----------------------------------------------------------------------
%% Function:	send_handshake/3
%% Purpose:	handshakes a peer.
%% Returns:	ok, if the packet was sent, otherwise - {error, Reason}
%% Args:	Socket (socket), InfoHash (string), ClietId(string)
%%----------------------------------------------------------------------		
send_handshake(Socket, InfoHash, ClientId)->
	gen_tcp:send(Socket,[
						 19,
						 "BitTorrent protocol",
						 <<0,0,0,0,0,0,0,0>>,
						 InfoHash,
						 ClientId
						]).

%%----------------------------------------------------------------------
%% Function:	check_infohash/2
%% Purpose:		check peers' infohash, receives a pid of master process
%% Returns:		sends back a message with ip and port of a peer,
%%				if successful,
%%				if not, kills itself.
%% Args:		Socket (socket), InfoHashFromPeer (string)
%%----------------------------------------------------------------------							
check_infohash(Socket,InfoHashFromPeer)->
	case torrent_mapper:req(InfoHashFromPeer) of
		{error,_} ->
			gen_tcp:close(Socket),
			exit(self(), "remote peer sent wrong infohash");
		{ok,TorrentPid} ->
			{ok, IpPort} = inet:peername(Socket),
			TorrentPid ! {new_upload,self(),IpPort}
	end,
	receive
		{new_master_pid, Pid} -> 
			Pid;
		{stop,Reason} ->
			gen_tcp:close(Socket),
			exit(self(), Reason)
		after 1000 ->
			gen_tcp:close(Socket),
			exit(self(), normal)
	end.
