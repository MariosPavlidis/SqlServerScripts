# Check current allocation unit size per volume
Get-WmiObject -Class Win32_Volume |
Select DriveLetter, Label, BlockSize |
Sort DriveLetter