IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 15,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Check-InstanceAvailability%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 15,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Check-SQLAgentJobs%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 90,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-DiskSpace%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-FileIOStats%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-MemoryClerks%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-AgHealthState%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-OSProcesses%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-PerfmonData%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-WaitStats%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go


update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-XEvents%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerCollectedData%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerInfo%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Invoke-AvailableMemoryAlert%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Invoke-BlockingAlert%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Invoke-MemoryGrantsPendingAlert%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go


update sajt
set		[Expected-Max-Duration(Min)] = 60,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 4320,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Partitions-Maintenance%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 60,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 4320,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Purge-Tables%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 5,
		Successfull_Execution_ClockTime_Threshold_Minutes = 60,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Remove-XEventFiles%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 60,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 21600,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and (	sajt.JobName like '(dba) Run-Blitz%'
	and	sajt.JobName not like '(dba) Run-BlitzIndex%'
	)
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 60,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 4320,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and (	sajt.JobName like '(dba) Run-BlitzIndex'
	or	(	sajt.JobName like '(dba) Run-BlitzIndex - %'
		and	sajt.JobName not like '(dba) Run-BlitzIndex - Weekly%'
		)
	)
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 120,
		Continous_Failure_Threshold = 1,
		Successfull_Execution_ClockTime_Threshold_Minutes = 21600,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Run-BlitzIndex - Weekly%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Run-LogSaver%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Run-TempDbSaver%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 15,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Run-WhoIsActive%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 15,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect-PrivilegedInfo%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 1,
		Successfull_Execution_ClockTime_Threshold_Minutes = 10080,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Update-SqlServerVersions%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 150,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Stop-StuckSQLMonitorJobs'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 525600,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Capture-AlertMessages'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 129600,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Collect Login Expiration Info'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go


update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 129600,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerDashboardMail'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 4320,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Populate Inventory Tables'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 30,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 4320,
		StopJob_If_LongRunning =  1,
		StopJob_If_NotSuccessful_In_ThresholdTime = 1,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 1,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Send Login Expiry EMails'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go


update sajt
set		[Expected-Max-Duration(Min)] = 30,
		Continous_Failure_Threshold = 2,
		Successfull_Execution_ClockTime_Threshold_Minutes = 4320,
		StopJob_If_LongRunning =  1,
		StopJob_If_NotSuccessful_In_ThresholdTime = 1,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 1,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Application Job Cleanup'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 5,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerAgHealthState%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 45,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerBackups%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 45,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerCollectionLatencyInfo%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 30,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerDiskSpace%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 15,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerLogSpaceConsumers%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 40,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerServices%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 40,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerSqlAgentJobs%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go


update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 40,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerStableInfo%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 15,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerTempdbSpaceUsage%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

update sajt
set		[Expected-Max-Duration(Min)] = 10,
		Continous_Failure_Threshold = 3,
		Successfull_Execution_ClockTime_Threshold_Minutes = 15,
		StopJob_If_LongRunning =  0,
		StopJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_NotSuccessful_In_ThresholdTime = 0,
		RestartJob_If_Failed = 0,
		Kill_Job_Blocker = 0,
		Alert_When_Blocked = 0,
		EnableJob_If_Found_Disabled = 0,
		IgnoreJob = 0,
		Include_In_MailNotification = 0
from dbo.sql_agent_job_thresholds sajt
where 1=1
and sajt.JobCategory = '(dba) SQLMonitor'
and sajt.JobName like '(dba) Get-AllServerVolatileInfo%'
and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1
go

--select *
--from dbo.sql_agent_job_thresholds sajt
--where sajt.CollectionTimeUTC >= dateadd(day,-1,GETUTCDATE())
--and sajt.Successfull_Execution_ClockTime_Threshold_Minutes = -1

