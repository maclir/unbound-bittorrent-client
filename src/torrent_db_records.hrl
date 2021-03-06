%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(torrent, { id='_', info='_', announce='_', announce_list=[], creation_date=0, 
		   comment='_', created_by='_', encoding='_',
		   info_sha='_', dir='_', status='downloading'}).

-record(info, {piece_length, pieces, bitfield, private=0, name, length, md5sum="", length_complete=0, files, length_uploaded=0}).

-record(file, {length, md5sum="", path, length_complete=0}).
