%%%----------------------------------------------------------------------
%%% Author:		Alireza Pazirandeh
%%% Desc.:		generating teh xml representing the state of
%%				the application
%%%----------------------------------------------------------------------
-module(web_response).

-export([get_data_xml/1]).
-include("torrent_status.hrl").

get_data_xml(Filter) ->
	Header = 
		"<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>
		<rows>
		<page>1</page>
		<total>1</total>",

	Body = get_body(get_data(Filter), []),
	
	Footer = 
		"</rows>",
		
	Data = Header ++ Body ++ Footer,
	XmlData = lists:flatten(Data),
	iolist_to_binary(XmlData).

get_body([], Body) ->
	Body;
get_body([H|T], Body) ->
	NewRow = 
		"<row status=\"" ++ H#torrent_status.status ++ "\" id=\"" ++ H#torrent_status.info_hash ++ "\">
			<cell><![CDATA[" ++ H#torrent_status.priority ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.name ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.size ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.percent ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.status ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.seeds ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.peers ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.downspeed ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.upspeed ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.eta ++ "]]></cell>
			<cell><![CDATA[" ++ H#torrent_status.uploaded ++ "]]></cell>
		</row>",
	get_body(T, NewRow ++ Body).

get_data(<<"all">>) ->
	temp_get_data();
get_data(Filter) ->
	Data = temp_get_data(),
	[X || X <- Data, X#torrent_status.status == binary_to_list(Filter)].

temp_get_data() ->
	Row1 = #torrent_status{info_hash = "12fe3465ef7265238767", priority = "1", name = "S01E01", size = "14 GB", percent = "100", status = "Stopped", seeds = "2 (34)", peers = "4 (98)", downspeed = "34.4 kB/s", upspeed = "640 kB/s", eta = "10:12:12", uploaded = "15.2 GB", db_bitfield = "00011",temp_bitfield = "100110"},
	Row2 = #torrent_status{info_hash = "12ae213465ef726523ae", priority = "2", name = "S01E02", size = "12 GB", percent = "100", status = "Downloading", seeds = "0 (14)", peers = "14 (49)", downspeed = "34.4 kB/s", upspeed = "640 kB/s", eta = "10:12:12", uploaded = "15.2 GB", db_bitfield = "00011",temp_bitfield = "100110"},
	Row3 = #torrent_status{info_hash = "43fe34aeb4c7e654f834", priority = "3", name = "S01E03", size = "23 GB", percent = "100", status = "Seeding", seeds = "1 (349)", peers = "40 (99)", downspeed = "34.4 kB/s", upspeed = "640 kB/s", eta = "10:12:12", uploaded = "15.2 GB", db_bitfield = "00011",temp_bitfield = "100110"},
	[Row1, Row2, Row3].