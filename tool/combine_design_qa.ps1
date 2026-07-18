param(
  [Parameter(Mandatory = $true)][string]$Reference,
  [Parameter(Mandatory = $true)][string]$Implementation,
  [Parameter(Mandatory = $true)][string]$Output
)

Add-Type -AssemblyName System.Drawing

$targetWidth = 390
$gap = 16
$top = 34

$referenceImage = [System.Drawing.Image]::FromFile((Resolve-Path $Reference))
$implementationImage = [System.Drawing.Image]::FromFile((Resolve-Path $Implementation))

try {
  $referenceHeight = [int][Math]::Round($referenceImage.Height * $targetWidth / $referenceImage.Width)
  $implementationHeight = [int][Math]::Round($implementationImage.Height * $targetWidth / $implementationImage.Width)
  $canvasHeight = $top + [Math]::Max($referenceHeight, $implementationHeight)
  $bitmap = New-Object System.Drawing.Bitmap (($targetWidth * 2) + $gap), $canvasHeight
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

  try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(14, 24, 28))
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

    try {
      $graphics.DrawString('REFERENCE', $font, $brush, 8, 7)
      $graphics.DrawString('IMPLEMENTATION', $font, $brush, ($targetWidth + $gap + 8), 7)
      $graphics.DrawImage($referenceImage, 0, $top, $targetWidth, $referenceHeight)
      $graphics.DrawImage($implementationImage, ($targetWidth + $gap), $top, $targetWidth, $implementationHeight)

      $outputPath = Join-Path (Get-Location) $Output
      $outputDirectory = Split-Path $outputPath -Parent
      if (!(Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
      }
      $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
      $brush.Dispose()
      $font.Dispose()
    }
  }
  finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}
finally {
  $implementationImage.Dispose()
  $referenceImage.Dispose()
}
