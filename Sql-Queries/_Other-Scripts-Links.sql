-- 01) sp_WhoIsActive_v12_00(Modified)
https://raw.githubusercontent.com/imajaydwivedi/SqlServer-Baselining-Grafana/master/DDLs/SCH-sp_WhoIsActive_v12_00(Modified).sql

-- 02) SCH-sp_WhatIsRunning
	-- Executes in Database Context
https://raw.githubusercontent.com/imajaydwivedi/SqlServer-Baselining-Grafana/master/DDLs/SCH-sp_WhatIsRunning.sql

-- 03) SqlServerVersions.sql
https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/SqlServerVersions.sql

-- 04) FirstResponderKit-Install-All-Scripts
	https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/Install-Core-Blitz-With-Query-Store.sql
Install-DbaFirstResponderKit -SqlInstance SqlMonitor

-- 05) sp_PressureDetector & sp_HumanEvents
	https://raw.githubusercontent.com/erikdarlingdata/DarlingData/main/sp_PressureDetector/sp_PressureDetector.sql
	https://raw.githubusercontent.com/erikdarlingdata/DarlingData/main/sp_HumanEvents/sp_HumanEvents.sql
Install-DbaDarlingData -SqlInstance SqlMonitor




/*
$GitHubURL = 'https://raw.githubusercontent.com/erikdarlingdata/DarlingData/main/sp_PressureDetector/sp_PressureDetector.sql'

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch file from Internet.."
$SqlFileQuery = (Invoke-WebRequest $GitHubURL -UseBasicParsing).Content


Invoke-DbaQuery -SqlInstance SqlMonitor -Query $SqlFileQuery;
*/
