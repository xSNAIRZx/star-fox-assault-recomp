$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$project=Split-Path -Parent $PSScriptRoot
$output=Join-Path $project 'assets\assault-launcher.ico'
$sizes=@(16,24,32,48,64,128,256)
$frames=New-Object 'System.Collections.Generic.List[byte[]]'
foreach($size in $sizes){
  $bitmap=[Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics=[Drawing.Graphics]::FromImage($bitmap)
  $stream=[IO.MemoryStream]::new()
  try {
    $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.ScaleTransform(($size/80.0),($size/80.0))
    $panel=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255,5,20,27))
    $edge=[Drawing.Pen]::new([Drawing.Color]::FromArgb(255,126,159,171),2)
    $cyan=[Drawing.Pen]::new([Drawing.Color]::FromArgb(255,70,224,244),4)
    $violet=[Drawing.Pen]::new([Drawing.Color]::FromArgb(255,145,117,250),3)
    $cyan.LineJoin=[Drawing.Drawing2D.LineJoin]::Bevel
    $violet.LineJoin=[Drawing.Drawing2D.LineJoin]::Bevel
    try {
      $outline=[Drawing.PointF[]]@([Drawing.PointF]::new(12,2),[Drawing.PointF]::new(68,2),[Drawing.PointF]::new(78,12),[Drawing.PointF]::new(78,68),[Drawing.PointF]::new(68,78),[Drawing.PointF]::new(12,78),[Drawing.PointF]::new(2,68),[Drawing.PointF]::new(2,12))
      $graphics.FillPolygon($panel,$outline)
      $graphics.DrawPolygon($edge,$outline)
      $left=[Drawing.PointF[]]@([Drawing.PointF]::new(10,34),[Drawing.PointF]::new(27,22),[Drawing.PointF]::new(38,30),[Drawing.PointF]::new(24,41),[Drawing.PointF]::new(10,34))
      $right=[Drawing.PointF[]]@([Drawing.PointF]::new(70,34),[Drawing.PointF]::new(53,22),[Drawing.PointF]::new(42,30),[Drawing.PointF]::new(56,41),[Drawing.PointF]::new(70,34))
      $graphics.DrawLines($cyan,$left)
      $graphics.DrawLines($cyan,$right)
      $graphics.DrawLines($violet,[Drawing.PointF[]]@([Drawing.PointF]::new(25,44),[Drawing.PointF]::new(40,57),[Drawing.PointF]::new(55,44)))
      $graphics.DrawLine($violet,40,30,40,49)
    } finally { $panel.Dispose(); $edge.Dispose(); $cyan.Dispose(); $violet.Dispose() }
    $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
    $frames.Add($stream.ToArray())
  } finally { $stream.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
}
$file=[IO.File]::Create($output)
$writer=[IO.BinaryWriter]::new($file)
try {
  $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
  $offset=6+16*$sizes.Count
  for($i=0;$i -lt $sizes.Count;$i++){
    $dimension=if($sizes[$i] -eq 256){0}else{$sizes[$i]}
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$frames[$i].Length); $writer.Write([uint32]$offset)
    $offset+=$frames[$i].Length
  }
  foreach($frame in $frames){$writer.Write([byte[]]$frame)}
} finally { $writer.Dispose(); $file.Dispose() }
Write-Output "Built $output (7 icon sizes)"
