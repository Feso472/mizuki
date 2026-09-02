Add-Type -AssemblyName System.Drawing

$sourcePath = 'E:\Games\Steam\steamapps\common\The Binding of Isaac Rebirth\extracted_resources\resources\gfx\items\pick ups\pickup_007_pill.png'
$outputPath = 'E:\Games\Steam\steamapps\common\The Binding of Isaac Rebirth\mods\mizuki\resources\gfx\items\mizuki\experimental_capsule.png'
$uiSourcePath = 'E:\Games\Steam\steamapps\common\The Binding of Isaac Rebirth\extracted_resources\resources\gfx\ui\ui_cardspills.png'
$uiOutputPath = 'E:\Games\Steam\steamapps\common\The Binding of Isaac Rebirth\mods\mizuki\resources\gfx\items\mizuki\experimental_capsule_ui.png'

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
$output = New-Object System.Drawing.Bitmap 32, 32

$cellX = 64
$cellY = 32
$cellSize = 32

for ($localY = 0; $localY -lt $cellSize; $localY++) {
    for ($localX = 0; $localX -lt $cellSize; $localX++) {
        # Mirror inside the pill's native opaque bounds (x=9..25), not around
        # the whole cell. This changes / to \ without shifting its HUD anchor.
        if ($localX -ge 9 -and $localX -le 25) {
            $color = $source.GetPixel($cellX + (34 - $localX), $cellY + $localY)
        } else {
            $color = [System.Drawing.Color]::Transparent
        }

        # Retain the native outline/highlight ramps. Only replace the red end
        # with a softer coral-pink ramp matching Mizuki's capsule-hourglass.
        if ($color.A -gt 0) {
            if ($color.R -eq 83 -and $color.G -eq 0 -and $color.B -eq 0) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 174, 76, 91)
            } elseif ($color.R -eq 131 -and $color.G -eq 0 -and $color.B -eq 0) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 222, 105, 121)
            } elseif ($color.R -eq 179 -and $color.G -eq 0 -and $color.B -eq 0) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 242, 140, 151)
            } elseif ($color.R -eq 217 -and $color.G -eq 128 -and $color.B -eq 128) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 236, 174, 183)
            } elseif ($color.R -eq 255 -and $color.G -eq 151 -and $color.B -eq 151) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 250, 190, 199)
            } elseif ($color.R -eq 255 -and $color.G -eq 191 -and $color.B -eq 191) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 252, 216, 222)
            } elseif ($color.R -eq 255 -and $color.G -eq 231 -and $color.B -eq 231) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 254, 238, 241)
            } elseif ($color.R -eq 255 -and $color.G -eq 243 -and $color.B -eq 243) {
                $color = [System.Drawing.Color]::FromArgb($color.A, 255, 246, 248)
            }
        }

        $output.SetPixel($localX, $localY, $color)
    }
}

$output.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$output.Dispose()
$source.Dispose()

function Convert-CapsuleColor([System.Drawing.Color] $color) {
    if ($color.A -eq 0) { return $color }
    if ($color.R -eq 83 -and $color.G -eq 0 -and $color.B -eq 0) { return [System.Drawing.Color]::FromArgb($color.A, 174, 76, 91) }
    if ($color.R -eq 131 -and $color.G -eq 0 -and $color.B -eq 0) { return [System.Drawing.Color]::FromArgb($color.A, 222, 105, 121) }
    if ($color.R -eq 179 -and $color.G -eq 0 -and $color.B -eq 0) { return [System.Drawing.Color]::FromArgb($color.A, 242, 140, 151) }
    if ($color.R -eq 217 -and $color.G -eq 128 -and $color.B -eq 128) { return [System.Drawing.Color]::FromArgb($color.A, 236, 174, 183) }
    if ($color.R -eq 255 -and $color.G -eq 151 -and $color.B -eq 151) { return [System.Drawing.Color]::FromArgb($color.A, 250, 190, 199) }
    if ($color.R -eq 255 -and $color.G -eq 191 -and $color.B -eq 191) { return [System.Drawing.Color]::FromArgb($color.A, 252, 216, 222) }
    if ($color.R -eq 255 -and $color.G -eq 231 -and $color.B -eq 231) { return [System.Drawing.Color]::FromArgb($color.A, 254, 238, 241) }
    if ($color.R -eq 255 -and $color.G -eq 243 -and $color.B -eq 243) { return [System.Drawing.Color]::FromArgb($color.A, 255, 246, 248) }
    return $color
}

# Object-type pocket items require both HUD and HUDSmall to address 32x32
# frames. Center the native 16x16 pill artwork inside the second 32x32 frame.
$uiSource = [System.Drawing.Bitmap]::FromFile($uiSourcePath)
$uiOutput = New-Object System.Drawing.Bitmap 32, 64

foreach ($frame in @(
    @{ SourceX = 64; SourceY = 32; Width = 32; Height = 32; OutputX = 0; OutputY = 0; MirrorMin = 7; MirrorMax = 25 },
    @{ SourceX = 112; SourceY = 112; Width = 16; Height = 16; OutputX = 8; OutputY = 40; MirrorMin = 3; MirrorMax = 13 }
)) {
    for ($y = 0; $y -lt $frame.Height; $y++) {
        for ($x = 0; $x -lt $frame.Width; $x++) {
            if ($x -ge $frame.MirrorMin -and $x -le $frame.MirrorMax) {
                # ui_cardspills already uses the desired \ orientation, unlike
                # pickup_007_pill. Preserve its native pixel positions.
                $color = $uiSource.GetPixel($frame.SourceX + $x, $frame.SourceY + $y)
            } else {
                $color = [System.Drawing.Color]::Transparent
            }
            $uiOutput.SetPixel($frame.OutputX + $x, $frame.OutputY + $y, (Convert-CapsuleColor $color))
        }
    }
}

$uiOutputDirectory = Split-Path -Parent $uiOutputPath
[System.IO.Directory]::CreateDirectory($uiOutputDirectory) | Out-Null
$uiOutput.Save($uiOutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$uiOutput.Dispose()
$uiSource.Dispose()
