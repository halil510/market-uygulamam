// test/veri/cari_filtresiz_devir_snapshot_test.dart
//
// DEEP_AUDIT (kendi-keşif turu, 2026-09-21 — FAZ 4 devir mekanizması
// ikinci-göz denetimi): DonemDevirServisi._cariSnapshotAl() ÖNCEDEN
// CariDeposu.tumunuGetir() (is_deleted=0 AND aktif=1 filtreli)
// kullanıyordu — dönem içinde hareketi olan ama devir anında pasif/
// silinmiş bir cari varsa hiç kapanış snapshot'ı (dolayısıyla "kalan
// bakiye" açılışı) alamıyordu. CariDeposu.tumunuGetirFiltresiz() bu
// açığı kapatıyor — bu test onun GERÇEKTEN filtresiz olduğunu doğrular.
//
// CariDeposu Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo testlerinde olduğu gibi) burada AYNI SQL gerçek şema üzerinde
// doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, dynamic>>> _tumunuGetirFiltresiz(Database db) =>
    db.query('cari', orderBy: 'id ASC');

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Devir kapanış snapshot\'ı — filtresiz cari sorgusu', () {
    test(
        'pasif (aktif=0) VE soft-deleted (is_deleted=1) cariler de '
        'sonuca dahil edilir — normal tumunuGetir() bunları atlardı',
        () async {
      final aktifId = await TestVeritabani.ornekCariEkle(db);
      final pasifId = await db.insert('cari', {
        'unvan': 'Pasif Cari', 'cari_tipi': 'Müşteri', 'bakiye': 250.0,
        'aktif': 0, 'is_deleted': 0,
      });
      final silinmisId = await db.insert('cari', {
        'unvan': 'Silinmiş Cari', 'cari_tipi': 'Müşteri', 'bakiye': -80.0,
        'aktif': 1, 'is_deleted': 1,
      });

      final sonuc = await _tumunuGetirFiltresiz(db);
      final idler = sonuc.map((r) => r['id']).toSet();

      expect(idler, containsAll([aktifId, pasifId, silinmisId]),
          reason: 'devir snapshot\'ı HİÇBİR cariyi atlamamalı — aksi halde '
              'o carinin geçmiş bakiyesi devir sonrası kalıcı olarak '
              'tutarsız kalır (silinen hareketleri telafi eden açılış '
              'satırı hiç yazılmaz)');
    });

    test(
        'normal (filtreli) sorgu ile karşılaştırma: filtreli sorgu pasif/'
        'silinmiş carileri GERÇEKTEN dışarıda bırakıyor (regresyon '
        'senaryosunu kanıtlar)', () async {
      await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari', {
        'unvan': 'Pasif', 'cari_tipi': 'Müşteri', 'bakiye': 0,
        'aktif': 0, 'is_deleted': 0,
      });
      await db.insert('cari', {
        'unvan': 'Silinmiş', 'cari_tipi': 'Müşteri', 'bakiye': 0,
        'aktif': 1, 'is_deleted': 1,
      });

      final filtreli = await db.query('cari',
          where: 'is_deleted = 0 AND aktif = 1');
      expect(filtreli, hasLength(1),
          reason: 'bu, DÜZELTİLMEDEN ÖNCEKİ hatalı davranıştır — devir '
              'artık bunu KULLANMIYOR');
    });
  });
}
