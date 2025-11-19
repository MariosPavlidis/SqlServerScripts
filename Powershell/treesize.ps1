param(
    [string]$RootPath = (Get-Location).Path,
    [int]$Top = 0     # 0 = show full tree
)

function Format-Size {
    param([long]$Bytes)

    if     ($Bytes -ge 1TB) { "{0:N2} TB" -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { "{0:N2} KB" -f ($Bytes / 1KB) }
    else                    { "$Bytes B" }
}

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
    Write-Error "Path '$RootPath' is not a directory."
    exit 1
}

$root = (Get-Item -LiteralPath $RootPath).FullName

# ------------------------------
# Build size map for all folders
# ------------------------------
$sizeMap = @{}
$sizeMap[$root] = 0

$allDirs = Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue
foreach ($d in $allDirs) { $sizeMap[$d.FullName] = 0 }

# Add file sizes
Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        $dir = $_.DirectoryName
        if (-not $sizeMap.ContainsKey($dir)) { $sizeMap[$dir] = 0 }
        $sizeMap[$dir] += $_.Length
    }

# Propagate sizes upwards
$dirsByDepthDesc = $sizeMap.Keys |
    Sort-Object { $_.Split([IO.Path]::DirectorySeparatorChar).Count } -Descending

foreach ($dir in $dirsByDepthDesc) {
    $parent = Split-Path $dir -Parent
    if ($parent -and $sizeMap.ContainsKey($parent)) {
        $sizeMap[$parent] += $sizeMap[$dir]
    }
}

# ------------------------------
# Show Top X mode
# ------------------------------
if ($Top -gt 0) {

    $items = $sizeMap.GetEnumerator() |
        Where-Object { $_.Key -ne $root } |
        Sort-Object Value -Descending |
        Select-Object -First $Top

    foreach ($i in $items) {
        $s = Format-Size $i.Value
        Write-Host ("{0}  ({1})" -f $i.Key, $s)
    }

    exit 0
}

# ------------------------------
# Tree mode (full output)
# ------------------------------
function Print-Tree {
    param(
        [string]$Path,
        [string]$Prefix = ""
    )

    $children = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name

    for ($i = 0; $i -lt $children.Count; $i++) {

        $child  = $children[$i]
        $isLast = ($i -eq $children.Count - 1)

        if ($isLast) {
            $branch = "\--- "
            $nextPrefix = $Prefix + "    "
        } else {
            $branch = "+--- "
            $nextPrefix = $Prefix + "|   "
        }

        $sizeStr = Format-Size $sizeMap[$child.FullName]
        Write-Host ("{0}{1}{2} ({3})" -f $Prefix, $branch, $child.Name, $sizeStr)

        Print-Tree -Path $child.FullName -Prefix $nextPrefix
    }
}

$rootSize = Format-Size $sizeMap[$root]
Write-Host ("{0} ({1})" -f $root, $rootSize)
Print-Tree -Path $root
