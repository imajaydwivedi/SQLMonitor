exec master..sp_BlitzCache @OnlyQueryHashes = '0x6C6C838BC8A9F0A7'
exec master..sp_BlitzCache @OnlySqlHandles = ''
exec master..sp_BlitzCache @DatabaseName = 'StackOverflow', @StoredProcName = 'usp_GetUserLikes'
