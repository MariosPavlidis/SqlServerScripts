$64K = 64 * 1024        # 65536
$1M  = 1024 * 1024      # 1048576

Get-WmiObject -Class Win32_DiskPartition |
Select-Object Name, StartingOffset, BlockSize,
    @{ Name = 'Mod_64K';  Expression = { $_.StartingOffset % $64K } },
    @{ Name = 'Mod_1M';   Expression = { $_.StartingOffset % $1M  } },
    @{ Name = 'Aligned_64K'; Expression = { if ($_.StartingOffset % $64K -eq 0) { 'YES' } else { 'NO' } } },
    @{ Name = 'Aligned_1M';  Expression = { if ($_.StartingOffset % $1M  -eq 0) { 'YES' } else { 'NO' } } } |
Sort-Object Name |
Format-Table -AutoSize