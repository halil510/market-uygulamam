// test/unit/route_yetki_cozumleme_test.dart
//
// DEEP_AUDIT_REPORT FAZ 7 (madde 2, 2026-09-21): uygulama_router.dart'ın
// redirect fonksiyonundaki rota→yetki çözümleme algoritmasını (artık
// "en uzun/en özel eşleşen anahtar kazanır") izole olarak doğrular.
// GoRouter'ın redirect'i gerçek WidgetRef/authProvider'a bağımlı olduğu
// için doğrudan test edilemiyor — bu yüzden AYNI saf algoritma burada
// kopyalanıp test ediliyor (bu oturumdaki diğer depo testleriyle AYNI
// desen: singleton'a bağımlı mantığı izole edip ayrı doğrulamak).
//
// Neden önemli: önceki davranış ("TÜM eşleşen prefix'ler gerekli")
// altında '/ayarlar/yedek' hem 'ayarlar' HEM 'ayarlar_yedek' isterdi —
// granüler kodların bağımsız çalışmasını İMKANSIZ kılardı (bir müdür
// varsayılan olarak 'ayarlar'dan yoksun olduğu için asla erişemezdi).
import 'package:flutter_test/flutter_test.dart';

/// uygulama_router.dart'taki redirect fonksiyonunun rota→yetki çözümleme
/// kısmıyla BİREBİR AYNI algoritma.
String? _gerekliYetkiyiBul(
    Map<String, String> routeYetkiler, String gidilenYol) {
  String? enOzelAnahtar;
  String? gerekliYetki;
  for (final e in routeYetkiler.entries) {
    if (gidilenYol.startsWith(e.key) &&
        (enOzelAnahtar == null || e.key.length > enOzelAnahtar.length)) {
      enOzelAnahtar = e.key;
      gerekliYetki = e.value;
    }
  }
  return gerekliYetki;
}

void main() {
  // uygulama_router.dart._routeYetkiler'in ilgili bir alt kümesi.
  const routeYetkiler = <String, String>{
    '/satis': 'satis',
    '/satis/liste': 'satis_liste',
    '/ayarlar': 'ayarlar',
    '/ayarlar/yedek': 'ayarlar_yedek',
    '/ayarlar/veri-sagligi': 'ayarlar_yedek',
    '/ayarlar/sync': 'ayarlar_sync',
    '/ayarlar/audit-log': 'ayarlar_audit_log',
    '/ayarlar/gib': 'ayarlar_gib',
    '/ayarlar/log': 'ayarlar_log',
  };

  group('Rota→yetki çözümleme — en özel (en uzun) eşleşme kazanır', () {
    test('/ayarlar/yedek SADECE ayarlar_yedek ister, genel ayarlar İSTEMEZ',
        () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/ayarlar/yedek'),
          'ayarlar_yedek');
    });

    test('/ayarlar/veri-sagligi de ayarlar_yedek koduna eşlenir', () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/ayarlar/veri-sagligi'),
          'ayarlar_yedek');
    });

    test('/ayarlar/audit-log SADECE ayarlar_audit_log ister', () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/ayarlar/audit-log'),
          'ayarlar_audit_log');
    });

    test(
        'özel girdisi OLMAYAN bir /ayarlar/* alt rotası genel "ayarlar" '
        'koduna DÜŞER (fallback)', () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/ayarlar/icerik'), 'ayarlar');
      expect(_gerekliYetkiyiBul(routeYetkiler, '/ayarlar/doviz'), 'ayarlar');
    });

    test('tam /ayarlar rotası genel "ayarlar" koduna eşlenir', () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/ayarlar'), 'ayarlar');
    });

    test(
        '/satis/liste hâlâ SADECE satis_liste ister (kümülatif DEĞİL — '
        'davranış korunuyor, sadece artık tek kod yeterli)', () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/satis/liste'), 'satis_liste');
    });

    test('/satis (temel) hâlâ satis ister', () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/satis'), 'satis');
    });

    test('haritada hiç olmayan bir yol null döner (kontrolsüz geçer)', () {
      expect(_gerekliYetkiyiBul(routeYetkiler, '/bilinmeyen-rota'), isNull);
    });
  });
}
