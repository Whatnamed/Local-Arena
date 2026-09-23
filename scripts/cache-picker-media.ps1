# Refresh the small glove/music catalogs only. Never downloads the weapon catalog.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$data = Join-Path $repo 'Panel/src/data'
$destination = Join-Path $repo 'Panel/public/media/pickers'
New-Item -ItemType Directory -Force $destination | Out-Null
$rows = @()
foreach ($glove in (Get-Content (Join-Path $data 'gloveSkins.json') -Raw | ConvertFrom-Json)) {
    $url = $glove.image.Replace('community.akamai.steamstatic.com', 'community.fastly.steamstatic.com')
    if ($url -like '*/economy/image/*') { $url += '/256fx256f' }
    $rows += @{ key="glove-$($glove.defindex)-$($glove.paint)"; original=$glove.image; url=$url }
}
foreach ($music in (Get-Content (Join-Path $data 'musicKits.json') -Raw | ConvertFrom-Json)) {
    $url = $music.image.Replace('community.akamai.steamstatic.com', 'community.fastly.steamstatic.com')
    if ($url -like '*/economy/image/*') { $url += '/256fx256f' }
    $rows += @{ key="music-$($music.def_index)"; original=$music.image; url=$url }
}
$results = @($rows | ForEach-Object -ThrottleLimit 6 -Parallel {
    $ErrorActionPreference = 'Stop'
    $row = $_
    $path = Join-Path $using:destination "$($row.key).png"
    if (!(Test-Path -LiteralPath $path)) {
        & curl.exe --fail --silent --show-error --max-time 25 --retry 2 --retry-all-errors --output $path $row.url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $($row.key)" }
    }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ([Convert]::ToHexString($bytes[0..7]) -ne '89504E470D0A1A0A') { throw "Invalid PNG: $($row.key)" }
    if ($bytes.Length -gt 250000) {
        Add-Type -AssemblyName System.Drawing
        $inputStream = [IO.MemoryStream]::new($bytes)
        $sourceImage = [Drawing.Image]::FromStream($inputStream)
        $bitmap = [Drawing.Bitmap]::new(256,256)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $ratio = [Math]::Min(256 / $sourceImage.Width, 256 / $sourceImage.Height)
            $width = [int]($sourceImage.Width * $ratio); $height = [int]($sourceImage.Height * $ratio)
            $graphics.DrawImage($sourceImage, [int]((256-$width)/2), [int]((256-$height)/2), $width, $height)
            $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose(); $sourceImage.Dispose(); $inputStream.Dispose() }
        $bytes = [IO.File]::ReadAllBytes($path)
    }
    @{ original=$row.original; source=$row.url; path="/media/pickers/$($row.key).png"; bytes=$bytes.Length; sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant() }
})
if ($results.Count -ne $rows.Count) { throw 'Incomplete catalog download' }
$total = ($results | Measure-Object -Property bytes -Sum).Sum
if ($total -gt 20MB) { throw "Picker media exceeds 20 MiB: $total" }
$results | Sort-Object -Property path | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $data 'bundledPickerMedia.json')
Write-Host "Bundled $($results.Count) images, $total bytes"
