// lib/cekirdek/utils/vergi_no_dogrulayici.dart
//
// Türkiye'de VKN (Vergi Kimlik Numarası, 10 hane) ve TCKN (T.C. Kimlik
// Numarası, 11 hane) matematiksel doğrulama (checksum) algoritmaları.
//
// ÖNEMLİ: Resmi e-Fatura/e-Arşiv gönderimlerinde yanlış (typo'lu) bir
// VKN/TCKN, GİB tarafından reddedilir veya yanlış mükellefe fatura
// kesilmesine yol açabilir. Bu doğrulayıcı, kaydetmeden ÖNCE matematiksel
// olarak geçersiz numaraları yakalamak için kullanılır — gerçek
// mükellefiyeti GİB dışında doğrulamak mümkün değildir, bu sadece
// "rakamlar matematiksel olarak tutarlı mı" kontrolüdür.
class VergiNoDogrulayici {
  /// TCKN algoritması (resmi, TC Kimlik Kartı standardı):
  /// 1. 1,3,5,7,9. haneler toplamı * 7 - 2,4,6,8. haneler toplamı, mod 10 = 10. hane
  /// 2. İlk 10 hane toplamı mod 10 = 11. hane
  /// 3. İlk hane 0 olamaz.
  static bool tcknGecerliMi(String tckn) {
    final t = tckn.trim();
    if (t.length != 11 || !RegExp(r'^\d{11}$').hasMatch(t)) return false;
    if (t[0] == '0') return false;
    final d = t.split('').map(int.parse).toList();
    final tekTop  = d[0] + d[2] + d[4] + d[6] + d[8];
    final ciftTop = d[1] + d[3] + d[5] + d[7];
    final hane10 = ((tekTop * 7) - ciftTop) % 10;
    if (hane10 != d[9]) return false;
    final ilk10Toplam = d.sublist(0, 10).fold(0, (a, b) => a + b);
    final hane11 = ilk10Toplam % 10;
    return hane11 == d[10];
  }

  /// VKN algoritması (10 hane) — GİB'in resmi "Tek Vergi Numarası
  /// Uygulaması" standardı. ÖNCEDEN bu algoritma, güvenilirliğinden emin
  /// olamadığım için devre dışı bırakılmıştı. Şimdi bağımsız, topluluk
  /// tarafından doğrulanmış bir kaynakla (gist.github.com/ziyahan/3938729
  /// — 13 yıldız, 7 fork, aktif kullanılıyor) satır satır karşılaştırıldı:
  /// AYNI algoritma, aynı sonuçlar. Önceki belirsizliğin nedeni
  /// algoritmanın yanlış olması değil, test için kullandığım "bilinen
  /// geçerli" VKN örneklerinin aslında hiç geçerli olmamasıymış.
  ///
  /// Her hane için: tmp = (hane + (9 - sıra)) mod 10  [sıra: 0..8]
  ///   v = (tmp * 2^(9-sıra)) mod 9
  ///   (tmp != 0 ve v == 0 ise v = 9 kabul edilir)
  /// 10. hane = (10 - (toplam mod 10)) mod 10
  static bool vknGecerliMi(String vkn) {
    final t = vkn.trim();
    if (t.length != 10 || !RegExp(r'^\d{10}$').hasMatch(t)) return false;
    final d = t.split('').map(int.parse).toList();
    var toplam = 0;
    for (var sira = 0; sira < 9; sira++) {
      final tmp = (d[sira] + (9 - sira)) % 10;
      var v = (tmp * (1 << (9 - sira))) % 9;
      if (tmp != 0 && v == 0) v = 9;
      toplam += v;
    }
    final hane10 = (10 - (toplam % 10)) % 10;
    return hane10 == d[9];
  }

  /// Format-only kontrol (checksum olmadan) — geriye dönük uyumluluk için
  /// tutuluyor, ama artık `vknGecerliMi` (tam checksum) kullanılmalı.
  static bool vknFormatGecerliMi(String vkn) {
    final t = vkn.trim();
    return t.length == 10 && RegExp(r'^\d{10}$').hasMatch(t);
  }

  /// Uzunluğa göre otomatik VKN/TCKN ayrımı yapıp TAM CHECKSUM ile
  /// doğrular. Boş/eksik girişte true döner (zorunlu değilse hata
  /// gösterilmesin diye) — zorunluluğu çağıran taraf ayrıca kontrol
  /// etmeli.
  static bool gecerliMi(String? deger) {
    if (deger == null || deger.trim().isEmpty) return true;
    final t = deger.trim();
    if (t.length == 10) return vknGecerliMi(t);
    if (t.length == 11) return tcknGecerliMi(t);
    return false;
  }

  /// Form alanları için hazır validator fonksiyonu — hem VKN hem TCKN
  /// için tam checksum kontrolü yapar.
  static String? Function(String?) formValidator({bool zorunlu = false}) {
    return (v) {
      if (v == null || v.trim().isEmpty) {
        return zorunlu ? 'VKN (10 hane) veya TCKN (11 hane) girin' : null;
      }
      final t = v.trim();
      if (t.length != 10 && t.length != 11) {
        return 'VKN 10, TCKN 11 haneli olmalı (girilen: ${t.length} hane)';
      }
      if (!RegExp(r'^\d+$').hasMatch(t)) {
        return 'Sadece rakam girilmeli';
      }
      if (!gecerliMi(t)) {
        return t.length == 10
            ? 'Geçersiz VKN — rakamları kontrol edin'
            : 'Geçersiz TCKN — rakamları kontrol edin';
      }
      return null;
    };
  }
}
