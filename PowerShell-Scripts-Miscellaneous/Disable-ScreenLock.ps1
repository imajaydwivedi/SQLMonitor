﻿# Prevent Lock Screen Timeout in Windows
$WShell = New-Object -Com "Wscript.Shell"
while (1) {$WShell.SendKeys("{SCROLLLOCK}"); sleep 60}