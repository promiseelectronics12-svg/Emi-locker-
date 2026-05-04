$p = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object { $_.CommandLine -like '*autonomous_builder*' }; Write-Output $p.ProcessId
