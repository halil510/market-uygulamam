# assets\images\logo.png -> windows\runner\resources\app_icon.ico
# Logonun dış beyaz zeminini şeffaflaştırır, kare kırpar, 16-256 px boyutlarında
# PNG içerikli çok boyutlu .ico üretir. Çalıştırma:
#   powershell -ExecutionPolicy Bypass -File windows\installer\ikon_uret.ps1
$ErrorActionPreference = 'Stop'
$kok = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$kaynak = Join-Path $kok 'assets\images\logo.png'
$hedef = Join-Path $kok 'windows\runner\resources\app_icon.ico'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class IkonUretici {
  static bool Beyaz(byte r, byte g, byte b) { return r >= 238 && g >= 238 && b >= 238; }

  public static void Uret(string kaynakYol, string hedefYol) {
    Bitmap src = new Bitmap(kaynakYol);
    int w = src.Width, h = src.Height;
    Bitmap argb = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (Graphics g = Graphics.FromImage(argb)) g.DrawImage(src, 0, 0, w, h);
    src.Dispose();

    BitmapData d = argb.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int stride = d.Stride;
    byte[] px = new byte[stride * h];
    System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);

    // Dıştaki beyaz zemini kenarlardan başlayarak doldur (şeffaf yap).
    bool[] dis = new bool[w * h];
    Queue<int> q = new Queue<int>();
    Action<int, int> ekle = (x, y) => {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      int i = y * w + x;
      if (dis[i]) return;
      int o = y * stride + x * 4;
      if (!Beyaz(px[o + 2], px[o + 1], px[o])) return;
      dis[i] = true; q.Enqueue(i);
    };
    for (int x = 0; x < w; x++) { ekle(x, 0); ekle(x, h - 1); }
    for (int y = 0; y < h; y++) { ekle(0, y); ekle(w - 1, y); }
    while (q.Count > 0) {
      int i = q.Dequeue(); int x = i % w, y = i / w;
      ekle(x + 1, y); ekle(x - 1, y); ekle(x, y + 1); ekle(x, y - 1);
    }
    int minx = w, miny = h, maxx = 0, maxy = 0;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      int o = y * stride + x * 4;
      if (dis[y * w + x]) { px[o + 3] = 0; }
      else {
        // Dış kenara komşu açık tonlu (kenar yumuşatma) pikselleri de erit.
        bool komsu = false;
        if (x > 0 && dis[y * w + x - 1]) komsu = true;
        if (x < w - 1 && dis[y * w + x + 1]) komsu = true;
        if (y > 0 && dis[(y - 1) * w + x]) komsu = true;
        if (y < h - 1 && dis[(y + 1) * w + x]) komsu = true;
        byte mn = Math.Min(px[o], Math.Min(px[o + 1], px[o + 2]));
        if (komsu && mn > 190) { px[o + 3] = 0; }
        else {
          if (x < minx) minx = x; if (x > maxx) maxx = x;
          if (y < miny) miny = y; if (y > maxy) maxy = y;
        }
      }
    }
    System.Runtime.InteropServices.Marshal.Copy(px, 0, d.Scan0, px.Length);
    argb.UnlockBits(d);

    // Kare kırp (küçük boşlukla) ve ortala.
    int cw = maxx - minx + 1, ch = maxy - miny + 1;
    int kenar = Math.Max(cw, ch) / 24;
    int side = Math.Max(cw, ch) + kenar * 2;
    Bitmap kare = new Bitmap(side, side, PixelFormat.Format32bppArgb);
    using (Graphics g = Graphics.FromImage(kare)) {
      g.Clear(Color.Transparent);
      g.DrawImage(argb, new Rectangle((side - cw) / 2, (side - ch) / 2, cw, ch),
                  new Rectangle(minx, miny, cw, ch), GraphicsUnit.Pixel);
    }
    argb.Dispose();

    int[] boyutlar = new int[] { 16, 24, 32, 48, 64, 128, 256 };
    List<byte[]> pngler = new List<byte[]>();
    foreach (int s in boyutlar) {
      Bitmap k = new Bitmap(s, s, PixelFormat.Format32bppArgb);
      using (Graphics g = Graphics.FromImage(k)) {
        g.Clear(Color.Transparent);
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.SmoothingMode = SmoothingMode.HighQuality;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.DrawImage(kare, 0, 0, s, s);
      }
      using (MemoryStream ms = new MemoryStream()) { k.Save(ms, ImageFormat.Png); pngler.Add(ms.ToArray()); }
      k.Dispose();
    }
    kare.Dispose();

    using (FileStream fs = new FileStream(hedefYol, FileMode.Create))
    using (BinaryWriter bw = new BinaryWriter(fs)) {
      bw.Write((short)0); bw.Write((short)1); bw.Write((short)boyutlar.Length);
      int ofset = 6 + 16 * boyutlar.Length;
      for (int i = 0; i < boyutlar.Length; i++) {
        int s = boyutlar[i];
        bw.Write((byte)(s >= 256 ? 0 : s)); bw.Write((byte)(s >= 256 ? 0 : s));
        bw.Write((byte)0); bw.Write((byte)0);
        bw.Write((short)1); bw.Write((short)32);
        bw.Write(pngler[i].Length); bw.Write(ofset);
        ofset += pngler[i].Length;
      }
      foreach (byte[] p in pngler) bw.Write(p);
    }
  }
}
"@

[IkonUretici]::Uret($kaynak, $hedef)
Write-Host "Simge üretildi: $hedef"
