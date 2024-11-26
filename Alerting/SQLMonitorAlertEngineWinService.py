"""_summary_
This script will be used to run SQLMonitorAlertEngine as a service.
Modify/Update the parameter values in SvcDoRun method if required.
"""
import win32serviceutil
import win32service
import win32event
import subprocess
import servicemanager
import socket

class SQLMonitorAlertEngineService(win32serviceutil.ServiceFramework):
    _svc_name_ = "SQLMonitorAlertEngine"
    _svc_display_name_ = "SQL Monitor Alert Engine"
    _svc_description_ = "Runs the SQLMonitorAlertEngineApp.py as a service."

    def __init__(self, args):
        win32serviceutil.ServiceFramework.__init__(self, args)
        self.stop_event = win32event.CreateEvent(None, 0, 0, None)
        self.proc = None

    def SvcDoRun(self):
        """Main service logic."""
        try:
            # Run the Flask app
            self.proc = subprocess.Popen(
                ["python", r"C:\SQLMonitor\Alerting\SQLMonitorAlertEngineApp.py", "--inventory_server", "localhost"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            # Wait until the stop event is triggered
            win32event.WaitForSingleObject(self.stop_event, win32event.INFINITE)
        except Exception as e:
            pass  # Add logging here if needed

    def SvcStop(self):
        """Stop the service."""
        if self.proc:
            self.proc.terminate()  # Terminate the Flask process
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        win32event.SetEvent(self.stop_event)
        self.ReportServiceStatus(win32service.SERVICE_STOPPED)

if __name__ == '__main__':
    win32serviceutil.HandleCommandLine(SQLMonitorAlertEngineService)
