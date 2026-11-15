# Cut the flat magenta background out of a Copilot image -> transparent PNG.
# Background = magenta-ish pixels connected to the border (flood fill), so pink/magenta INSIDE the art survives.
# Then 1 px erosion (removes the blended fringe) and a 1 px soft alpha edge.
# Usage: powershell -File key_magenta.ps1 <in.png> <out.png> [threshold=110]
param([string]$In, [string]$Out, [int]$Threshold = 110)
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Keyer {
  public static void Run(string inPath, string outPath, int thr) {
    var src = new Bitmap(inPath);
    int w = src.Width, h = src.Height;
    var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) g.DrawImage(src, 0, 0, w, h);
    src.Dispose();
    var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    var px = new byte[w * h * 4];
    Marshal.Copy(data.Scan0, px, 0, px.Length);
    Func<int, bool> isKey = i => { int b = px[i*4], gg = px[i*4+1], r = px[i*4+2];
      int dr = 255 - r, dg = gg, db = 255 - b; return dr*dr + dg*dg + db*db < thr*thr; };
    var bg = new bool[w * h];
    var q = new Queue<int>();
    for (int x = 0; x < w; x++) { q.Enqueue(x); q.Enqueue((h-1)*w + x); }
    for (int y = 0; y < h; y++) { q.Enqueue(y*w); q.Enqueue(y*w + w-1); }
    while (q.Count > 0) { int i = q.Dequeue(); if (bg[i] || !isKey(i)) continue; bg[i] = true;
      int x = i % w, y = i / w;
      if (x > 0) q.Enqueue(i-1); if (x < w-1) q.Enqueue(i+1); if (y > 0) q.Enqueue(i-w); if (y < h-1) q.Enqueue(i+w); }
    // erode the foreground by 1 px (fringe pixels blended with magenta)
    var bg2 = (bool[])bg.Clone();
    for (int y = 1; y < h-1; y++) for (int x = 1; x < w-1; x++) { int i = y*w + x;
      if (!bg[i] && (bg[i-1] || bg[i+1] || bg[i-w] || bg[i+w])) bg2[i] = true; }
    // alpha: 0 for background, soft (average of 3x3) at the edge
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { int i = y*w + x;
      int n = 0, fg = 0;
      for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) { int xx = x+dx, yy = y+dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue; n++; if (!bg2[yy*w+xx]) fg++; }
      int a = bg2[i] ? (fg * 255 / n) / 3 : fg * 255 / n;
      px[i*4+3] = (byte)a;
      if (a < 255 && a > 0) { // despill: pull a magenta cast toward neutral on edge pixels
        int b = px[i*4], gg = px[i*4+1], r = px[i*4+2]; int spill = Math.Min(r, b) - gg;
        if (spill > 60) { px[i*4] = (byte)Math.Max(gg, b - spill/2); px[i*4+2] = (byte)Math.Max(gg, r - spill/3); } }
    }
    Marshal.Copy(px, 0, data.Scan0, px.Length);
    bmp.UnlockBits(data);
    bmp.Save(outPath, ImageFormat.Png);
    bmp.Dispose();
  }
}
"@
[Keyer]::Run((Resolve-Path $In).Path, $Out, $Threshold)
"keyed: $Out"
