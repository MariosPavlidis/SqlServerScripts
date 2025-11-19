param(
    [string]$Path = (Get-Location).Path,
    [int]$Top = 0,            # 0 = full list
    [int]$Depth = 0           # 0 = infinite depth
)

function Format-Size {
    param([long]$Bytes)

    if     ($Bytes -ge 1TB) { "{0:N2} TB" -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { "{0:N2} KB" -f ($Bytes / 1KB) }
    else                    { "$Bytes B" }
}

# Validate root path
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Invalid path: $Path"
    exit 1
}

$root = (Get-Item -LiteralPath $Path).FullName
$rootDepth = $root.Split([IO.Path]::DirectorySeparatorChar).Count

# -------------------------------------------------------
# Enumerate directories limited by depth
# -------------------------------------------------------

function Get-Dirs-With-DepthLimit {
    param([string]$Base)

    if ($Depth -eq 0) {
        # unlimited
        return Get-ChildItem -Path $Base -Directory -Recurse -ErrorAction SilentlyContinue
    }

    return Get-ChildItem -Path $Base -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.FullName.Split([IO.Path]::DirectorySeparatorChar).Count - $rootDepth) -le $Depth
        }
}

# Build directory list with depth limit
$allDirs = Get-Dirs-With-DepthLimit -Base $root

# Init size map
$sizeMap = @{}
$sizeMap[$root] = 0
foreach ($d in $allDirs) { $sizeMap[$d.FullName] = 0 }

# -------------------------------------------------------
# Add file sizes into each folder (also depth-limited)
# -------------------------------------------------------

function Get-Files-With-DepthLimit {
    param([string]$Base)

    if ($Depth -eq 0) {
        return Get-ChildItem -Path $Base -Recurse -File -ErrorAction SilentlyContinue
    }

    return Get-ChildItem -Path $Base -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.DirectoryName.Split([IO.Path]::DirectorySeparatorChar).Count - $rootDepth) -le $Depth
        }
}

Get-Files-With-DepthLimit -Base $root |
    ForEach-Object {
        $dir = $_.DirectoryName
        if (-not $sizeMap.ContainsKey($dir)) { $sizeMap[$dir] = 0 }
        $sizeMap[$dir] += $_.Length
    }

# -------------------------------------------------------
# Bottom-up size propagation
# -------------------------------------------------------

$dirsByDepthDesc = $sizeMap.Keys |
    Sort-Object { $_.Split([IO.Path]::DirectorySeparatorChar).Count } -Descending

foreach ($dir in $dirsByDepthDesc) {
    $parent = Split-Path $dir -Parent
    if ($parent -and $sizeMap.ContainsKey($parent)) {
        $sizeMap[$parent] += $sizeMap[$dir]
    }
}

# -------------------------------------------------------
# TOP MODE
# -------------------------------------------------------
if ($Top -gt 0) {

    $items = $sizeMap.GetEnumerator() |
        Where-Object { $_.Key -ne $root } |
        Sort-Object Value -Descending |
        Select-Object -First $Top

    foreach ($i in $items) {
        $sizeStr = Format-Size $i.Value
        Write-Host ("{0}  ({1})" -f $i.Key, $sizeStr)
    }

    exit 0
}

# -------------------------------------------------------
# TREE MODE (depth-limited)
# -------------------------------------------------------

function Print-Tree {
    param(
        [string]$Path,
        [string]$Prefix = "",
        [int]$Level = 0
    )

    # Stop if depth exceeded
    if ($Depth -gt 0 -and $Level -ge $Depth) { return }

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

        Print-Tree -Path $child.FullName -Prefix $nextPrefix -Level ($Level + 1)
    }
}

# Print root + tree
$rootSize = Format-Size $sizeMap[$root]
Write-Host ("{0} ({1})" -f $root, $rootSize)
Print-Tree -Path $root -Level 0
