%% Author: Evelina Vorobyeva
%% Created: Nov 18, 2011

-module(file_split).
-export([start/4, path_create/2, merge_data/4]).
-include("torrent_db_records.hrl").


start(Data, StartPos, TempPath, Records) ->
	Files = calc_files(StartPos, Records#torrent.info#info.piece_length, Records#torrent.info#info.files, 0, []),
	write_to_file(Files, Data, TempPath).

write_to_file([], _, _) ->
	{error, no_file_match};
write_to_file([{Path, Name, StartPos, _}|[]], Data, TempPath) ->
	FilePath = TempPath ++ Path,
	filelib:ensure_dir(FilePath),
	{ok, Index} = file:open(FilePath ++ Name, [read, write]),	
	file:pwrite(Index, StartPos + 1, Data),
	file:close(Index),
	{ok, done};
write_to_file([{Path, Name, StartPos, Length}|T], AllData, TempPath) ->
	<<Data:Length/binary, Rest/binary>> = AllData,
	FilePath = TempPath ++ Path,
	filelib:ensure_dir(FilePath),
	{ok, Index} = file:open(FilePath ++ Name, [read, write]),	
	file:pwrite(Index, StartPos + 1, Data),
	file:close(Index),
	write_to_file(T, Rest, TempPath).

path_create([H|[]], String) ->
	Name = binary_to_list(H),
 	{Name, String};
path_create([H|T], String) ->
	Path = String ++ binary_to_list(H) ++ "/",
	path_create(T, Path).

%% ...#...files
merge_data(StartPos, Length, Files, TorrentPath) ->
	FileMap = calc_files(StartPos, Length, Files, 0, []),
	merge_data(TorrentPath, FileMap, <<>>).

merge_data(_, [], Data) ->
	Data;
merge_data(TorrentPath, [{Path, Name, StartPos, Length}|T], BinaryData) ->
	{ok, File} = file:open(TorrentPath ++ Path ++ Name, [read]),
	{ok, Data} = file:pread(File, StartPos, Length),
	file:close(File),
	NewData = <<Data, BinaryData>>,
	merge_data(TorrentPath, T, NewData).
	


%% co-author: Alireza Pazirandeh
%% the startPos < startFilePos, it is over
calc_files(StartPos, Length, _, StartFilePos, Files)
	when (StartPos + Length =< StartFilePos) ->
		lists:reverse(Files);
%% the startPos and endPos < endFilePos, all the block belongs here
calc_files(StartPos, Length, [H|_], StartFilePos, Files)
	when ((StartPos < StartFilePos + H#file.length) and (StartPos + Length =< StartFilePos + H#file.length)) ->
		{Name, FilePath} = path_create(H#file.path, ""),
		NewFile = {FilePath, Name, StartPos - StartFilePos, Length},
		[NewFile|Files];
%% the startPos < endFilePos but endPos > endFilePos, starts in this file but still continues
calc_files(StartPos, Length, [H|T], StartFilePos, Files)
	when ((StartPos < StartFilePos + H#file.length) and (StartPos + Length > StartFilePos + H#file.length)) ->
		{Name, FilePath} = path_create(H#file.path, ""),
		NewFile = {FilePath, Name, StartPos - StartFilePos, StartFilePos + H#file.length - StartPos},
		calc_files(StartPos, Length, T, StartFilePos + H#file.length, [NewFile|Files]);
%% the endPos > endFilePos, started before and it ends later
calc_files(StartPos, Length, [H|T], StartFilePos, Files)
	when (StartPos + Length > StartFilePos + H#file.length) ->
		{Name, FilePath} = path_create(H#file.path, ""),
		NewFile = {FilePath, Name, 0, H#file.length},
		calc_files(StartPos, Length, T, StartFilePos + H#file.length, [NewFile|Files]);
%% the endPos < endFilePos, started before and it ends here
calc_files(StartPos, Length, [H|_], StartFilePos, Files)
	when (StartPos + Length =< StartFilePos + H#file.length) ->
		{Name, FilePath} = path_create(H#file.path, ""),
		NewFile = {FilePath, Name, 0, StartPos + Length - StartFilePos},
		[NewFile|Files];
calc_files(StartPos, Length, [H|T], StartFilePos, Files) ->
	calc_files(StartPos, Length, T, StartFilePos + H#file.length, Files).