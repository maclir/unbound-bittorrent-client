%%%author: Nahid Vafaie ,Peter Myllykoski
%%% created: 18 Nov 2011

-module(nettransfer).

-export([init/5]).


init(TorrentPid,DestinationIp,DestinationPort,InfoHash,ClientId)->
    TcpPid=tcp:open_a_socket(DestinationIp, DestinationPort,InfoHash,ClientId),
    Choked = true,
    Interested = false,
    DownloadStatus= {Choked,Interested},
    UploadStatus = {Choked,Interested},
    loop(DownloadStatus,TcpPid,TorrentPid,0,[],UploadStatus).


loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus) ->
    receive
	check_free ->
	    case Que of
		[] when (not element(1,DownloadStatus) and element(2,DownloadStatus)) ->
                TorrentPid! {im_free,self()},
                loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus);
		_ ->
                loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus)
	    end;
	is_interested ->
	    {OldChoked, OldInterested} = DownloadStatus,
	    if not OldInterested ->
			TcpPid ! interested;
		   true ->
			ok
		end,
	    NewDownloadStatus = {OldChoked,true},
	    loop(NewDownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus);
	not_interested ->
	    case DownloadStatus of
		{true,_} ->
		    TcpPid ! not_interested,
		    NewDownloadStatus = {true,false},
		    case UploadStatus of
			{_,false} ->
			    TcpPid ! stop;
			{_,true} ->
                 loop(NewDownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus)

		    end;
		{false,_} ->
		    TcpPid ! not_interested,
		    NewDownloadStatus = {false,false},
		    case UploadStatus of
			{_,false} ->
			    TcpPid ! stop;
			{_,true} ->
                    loop(NewDownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus)
		    end
	    end;


        choke ->
            TcpPid ! choke,
             {_Choked,Interested}= UploadStatus ,
            NewUploadStatus = {true,Interested},
              loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,NewUploadStatus);

	    {got_unchoked, _FromPid} ->
            case DownloadStatus of
			    {_,true}->
                    NewDownloadStatus= {false,true},
                     loop(NewDownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus);
			    {_,false} ->
                    NewDownloadStatus = {false,false},
                    loop(NewDownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus)
			end;


	    {got_choked, _FromPid} ->
		case DownloadStatus of
			    {_,true} ->
				NewDownloadStatus ={true,true},
                loop(NewDownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus);
			    {_,false} ->
                TcpPid !stop
			end;


	    {have,SenderPid,Piece_Index} ->
            case SenderPid of
			    TcpPid ->
                    TorrentPid ! {have,self(),Piece_Index};
			    TorrentPid ->
                    TcpPid ! { have,self(), Piece_Index}
			end,
            loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus);

	    {client_bitfield,SenderPid, Bitfield} ->
            case SenderPid of
			    TcpPid ->
				       TorrentPid ! {send_bitfield,Bitfield};
			    TorrentPid ->
				         TcpPid ! {bitfield,Bitfield}
			end,
            loop(DownloadStatus,TcpPid,TorrentPid,Bitfield,Que,UploadStatus);

	    {got_block,Offset,Length,Data} ->
            [H,NewQue] = Que,
            element(1,H) ! {block,self(),Offset,Length,Data},
            case NewQue of
			    [] ->
                    TorrentPid ! {im_free,self()},
                    loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,NewQue,UploadStatus);
			    [{_FromPid,Index,Offset,Length}|_T] ->
                    TcpPid ! {request, Index,Offset,Length},
                    loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,NewQue,UploadStatus)
			end;

	    {download_block,FromPid,Index,Offset,Length} ->
            loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que ++ [{FromPid,Index,Offset,Length}],UploadStatus);

        bad_bitfield ->
            TcpPid ! stop;

        {got_interested ,TcpPid} ->
            case UploadStatus of
                {true,_} ->
                    TcpPid ! unchoke,
                    NewUploadStatus = {false,true};
                {false,_} ->
                    NewUploadStatus={false,true}
            end,
            loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,NewUploadStatus);


        {got_not_interested , TcpPid} ->
            case UploadStatus of
                {true,_} ->
                    NewUploadStatus = {true,false},
                    case DownloadStatus of
                        {_,false} ->
                            TcpPid ! stop;
                        {_,true} ->
                           loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,NewUploadStatus)
                    end;
                {false,_} ->
                    NewUploadStatus = {false,false},
                    case DownloadStatus of
                        {_,false} ->
                            TcpPid ! stop;
                        {_,true} ->
                            loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,NewUploadStatus)
                    end
            end;

        {got_request,TcpPid,Index,Offset,Length} ->
            Self = self(),
            TorrentPid ! {upload, Self,Index,Offset,Length},
            loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus);

        {piece,Index,Offset,Length,Binary} ->
            TcpPid ! {send_piece,Index,Offset,Length,Binary},
            loop(DownloadStatus,TcpPid,TorrentPid,StoredBitfield,Que,UploadStatus)

	after 120000 ->
		%% shouldnt there be a loop after this line??
		TcpPid ! keep_alive
	end.
