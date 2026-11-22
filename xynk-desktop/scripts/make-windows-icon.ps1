param(
  [string]$Source = (Join-Path $PSScriptRoot '..\resources\xynk-icon.png'),
  [string]$Destination = (Join-Path $PSScriptRoot '..\resources\icon.ico')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sourceImage = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$entries = @()
try {
  foreach ($size in $sizes) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.DrawImage($sourceImage, 0, 0, $size, $size)
      $stream = New-Object System.IO.MemoryStream
      try {
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $entries += [pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() }
      } finally { $stream.Dispose() }
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
  }
} finally { $sourceImage.Dispose() }

$output = [System.IO.File]::Create($Destination)
$writer = New-Object System.IO.BinaryWriter($output)
try {
  $writer.Write([uint16]0)
  $writer.Write([uint16]1)
  $writer.Write([uint16]$entries.Count)
  $offset = 6 + 16 * $entries.Count
  foreach ($entry in $entries) {
    $writer.Write([byte]($entry.Size % 256))
    $writer.Write([byte]($entry.Size % 256))
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$entry.Bytes.Length)
    $writer.Write([uint32]$offset)
    $offset += $entry.Bytes.Length
  }
  foreach ($entry in $entries) { $writer.Write([byte[]]$entry.Bytes) }
} finally { $writer.Dispose() }
Write-Host "Created $Destination"
