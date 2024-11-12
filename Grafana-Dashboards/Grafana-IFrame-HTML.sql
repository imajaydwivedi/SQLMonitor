declare @_title nvarchar(2000);
declare @_allServerDashLink nvarchar(4000);
declare @_styleCSS nvarchar(max);
declare @_coreHealthMetricsHTML nvarchar(MAX);
declare @_htmlContent nvarchar(max);

set quoted_identifier off;
set @_title = 'Monitoring - Live - All Servers';
set @_allServerDashLink = 'https://sqlmonitor.ajaydwivedi.com:3000/d/distributed_live_dashboard_all_servers';

set @_styleCSS = "<style>
    iframe {
        overflow: scroll;
        width: 100%;
        border: 1px solid black;
    }
  </style>";

set @_coreHealthMetricsHTML = '<div id="core-health-metrics" class="dashboard-panel"><iframe src="https://sqlmonitor.ajaydwivedi.com:3000/d-solo/distributed_live_dashboard_all_servers/monitoring---live---all-servers?orgId=1&refresh=1m&from=1703996344492&to=1703998144492&panelId=842" width="100%"></iframe></div>';

set @_htmlContent = "<head><title>"+@_title+"</title><head>";
set @_htmlContent += @_styleCSS;
set @_htmlContent += "<body>";
set @_htmlContent += '<h1>< a href="'+@_allServerDashLink+'" target="_blank">Monitoring - Live - All Servers</a></h1>';
set @_htmlContent += '<p>'+@_coreHealthMetricsHTML+'</p>';
set @_htmlContent += "</body>";

set quoted_identifier on;


EXEC msdb.dbo.sp_send_dbmail @recipients = 'ajay.dwivedi2007@gmail.com',
    @subject = @_title,
    @body = @_htmlContent,
    @body_format = 'HTML';
go
