// test/unit/sessiz_catch_koruma_test.dart
//
// CLAUDE.md §5.7 koruması (2026-11-08): hata sessizce yutulmasın.
// lib/ altında (yorum içindeki metin hariç) şunlar YASAK:
//   • boş `catch (_) {}` — gerekçesi yorumla yazılmamış yutma
//   • yalnız `if (kDebugMode) debugPrint` yapan catch — sürüm derlemesinde
//     hata hiçbir yere yazılmaz; LogServisi kullanılmalı
//
// Yorumla gerekçelendirilmiş `catch (_) { // … }` blokları serbesttir
// ("kozmetik olanları belgele"). Aşağıdaki [_bilinenIstisnalar] BİLİNÇLİ
// bırakılan debugPrint catch'leridir; yeni bir tane eklenirse test kırılır.
// Listeden bir satır düzeltildiğinde listeden de silinmelidir (test bunu
// da denetler — eskimiş istisna kalmasın).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// dosya → bilinçli istisna sayısı (gerekçe yanında).
const _bilinenIstisnalar = <String, int>{
  // §10 "dokunma" dosyaları — yalnız test eşliğinde, tek tek değiştirilir.
  'lib/servisler/gib_servisi.dart': 3,
  'lib/servisler/gib/gib_ubl_olusturucu.dart': 1,
  'lib/servisler/iade_islem_servisi.dart': 2,
  'lib/servisler/iade_islem_servisi_duzenleme.dart': 2,
  'lib/servisler/iade_islem_servisi_gecmis.dart': 3,
  'lib/servisler/iade_islem_servisi_tedarikci_bayi.dart': 1,
  // Periyodik / her taramada çalışan yollar — loglanırsa her birkaç saniyede
  // bir kayıt birikir (Faz A-5'te bilinçli dışarıda bırakıldı).
  'lib/servisler/barkod_servisi.dart': 5, // bip/hata sesi
  'lib/servisler/bildirim_zamanlayici.dart': 2,
  'lib/servisler/masa/qr_siparis_cekici_servisi.dart': 1, // 2026-11-09: işleme hatası artık loglanıyor
  'lib/servisler/sync_servisi.dart': 3, // uzak durum/veri yoklama
};

/// Eşleşme bir `//` yorumunun içinde mi (ör. geçmiş hatayı anlatan not)?
bool _yorumda(String s, int konum) {
  final satirBasi = s.lastIndexOf('\n', konum) + 1;
  return s.substring(satirBasi, konum).contains('//');
}

int _say(RegExp re, String s) =>
    re.allMatches(s).where((m) => !_yorumda(s, m.start)).length;

void main() {
  final dosyalar = {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
  };

  test('boş catch (_) {} yok', () {
    final re = RegExp(r'catch\s*\(_\)\s*\{\s*\}');
    expect([for (final e in dosyalar.entries) if (_say(re, e.value) > 0) e.key], isEmpty);
  });

  test('yalnız debugPrint yapan catch yalnız bilinen istisnalarda', () {
    final re = RegExp(
        r'catch\s*\(\w+(,\s*\w+)?\)\s*\{\s*if\s*\(kDebugMode\)\s*debugPrint\([^;]*\);\s*(return[^;]*;\s*)?\}');
    final bulunan = <String, int>{
      for (final e in dosyalar.entries)
        if (_say(re, e.value) > 0) e.key: _say(re, e.value),
    };
    expect(bulunan, _bilinenIstisnalar,
        reason: 'Yeni sessiz catch → LogServisi().hata/uyari kullan. '
            'Bir istisnayı düzelttiysen listeden de düş.');
  });
}
