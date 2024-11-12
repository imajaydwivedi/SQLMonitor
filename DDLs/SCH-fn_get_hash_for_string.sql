use [DBA]
go
if object_id('dbo.fn_get_hash_for_string') is null
	exec ('create function dbo.fn_get_hash_for_string () returns table as return select 1 as [varbinary_value];')
go
alter function dbo.fn_get_hash_for_string ( @string nvarchar(max) )
returns table
--RETURNS varbinary(200)
as
return
	with cte_params as (
		select [string] = @string, [str_length] = len(@string), [max_length] = 3999
	)
	,hashbytes_val as (
         Select substring([string],1, [max_length]) val, [max_length]+1 as st, [max_length] lv,
                        hashbytes('SHA2_256', substring([string],1, [max_length])) hashval
		 from cte_params p
		 --
         Union All
		 --
        Select substring([string],st,lv), st+lv , [max_length]  lv,
            hashbytes('SHA2_256', substring([string],st,lv) + convert( varchar(20), hashval ))
        From hashbytes_val h, cte_params
        where Len(substring([string],st,lv))>0
    )
    Select Top 1 [varbinary_value] = hashval From hashbytes_val	Order by st desc	
	--option (maxrecursion 0)
go

--select * from dbo.fn_get_hash_for_string('EXEC dbo.usp_run_WhoIsActive @recipients = ''sqlagentservice@gmail.com'';')