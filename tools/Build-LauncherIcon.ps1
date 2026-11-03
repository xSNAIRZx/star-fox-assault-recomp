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
    $markFont=[Drawing.Font]::new('Bahnschrift SemiBold',27,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
    $markBrush=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255,235,245,246))
    $cyan.LineJoin=[Drawing.Drawing2D.LineJoin]::Bevel
    $violet.LineJoin=[Drawing.Drawing2D.LineJoin]::Bevel
    try {
      $outline=[Drawing.PointF[]]@([Drawing.PointF]::new(12,2),[Drawing.PointF]::new(68,2),[Drawing.PointF]::new(78,12),[Drawing.PointF]::new(78,68),[Drawing.PointF]::new(68,78),[Drawing.PointF]::new(12,78),[Drawing.PointF]::new(2,68),[Drawing.PointF]::new(2,12))
      $graphics.FillPolygon($panel,$outline)
      $graphics.DrawPolygon($edge,$outline)
      $format=[Drawing.StringFormat]::GenericTypographic
      $format.Alignment=[Drawing.StringAlignment]::Center
      $format.LineAlignment=[Drawing.StringAlignment]::Center
      $graphics.DrawString('PF',$markFont,$markBrush,[Drawing.RectangleF]::new(6,11,68,44),$format)
      $graphics.DrawLine($cyan,24,59,56,59)
      $graphics.DrawLine($violet,31,65,49,65)
      $format.Dispose()
    } finally { $panel.Dispose(); $edge.Dispose(); $cyan.Dispose(); $violet.Dispose(); $markFont.Dispose(); $markBrush.Dispose() }
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
