param([string]$Img, [int]$X0, [int]$Y0, [int]$X1, [int]$Y1, [string]$Out, [int]$Zoom = 4)
# 裁剪放大诊断工具：从截图中裁区域并放大保存，供人工确认模板框
Add-Type -AssemblyName System.Drawing
$src = New-Object System.Drawing.Bitmap $Img
$w = $X1 - $X0 + 1; $h = $Y1 - $Y0 + 1
$dst = New-Object System.Drawing.Bitmap ($w * $Zoom), ($h * $Zoom)
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, ($w * $Zoom), ($h * $Zoom)), (New-Object System.Drawing.Rectangle $X0, $Y0, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$dst.Save($Out)
"saved=$Out ($w x $h zoom $Zoom)"
$src.Dispose(); $dst.Dispose()
