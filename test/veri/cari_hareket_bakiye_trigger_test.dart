// test/veri/cari_hareket_bakiye_trigger_test.dart
//
// KOMPLE UYGULAMA DERİN ANALİZİNDE bulunan, kanıtlanmış veri bozulması:
// 'trg_cari_hareket_bakiye' tetikleyicisi (semalar/diger_semasi.dart,
// yükseltilen kurulumlarda migrasyon zincirindeki eski adıyla
// 'trg_cari_bakiye_ins'), her yeni cari_hareket INSERT'inde cari
// bakiyesini yeniden hesaplarken is_deleted=0 FİLTRESİ İÇERMİYORDU.
//
// Uygulamanın "resmi" cari_hareket ekleme yollarının (CariDeposu.
// hareketEkle, cari_hareket_ekrani.dart'taki iptal akışı,
// iade_ekrani_gecmis.dart) HEPSİ, kendi INSERT'lerinden HEMEN SONRA
// AYNI transaction içinde doğru (is_deleted=0 filtreli) bir UPDATE ile
// bakiyeyi TEKRAR yazdığı için bu hata gizleniyordu — SON SÖZ her
// zaman doğru koddan geliyordu. AMA Veritabani.supaKayitlariEkle()
// (buluttan gelen kayıtları JENERİK biçimde toplu ekleyen yol —
// "Hızlı Al"/"Tam Al" sırasında kullanılır) hiçbir tabloya özel takip
// mantığı içermez; SADECE INSERT eder. Bu yüzden bir müşterinin
// GEÇMİŞTE iptal edilmiş (is_deleted=1) bir hareketi varsa, o
// müşteriye ait BAŞKA bir cihazdan senkronize olan TAMAMEN İLGİSİZ bir
// YENİ hareket, tetikleyiciyi ateşleyip bakiyeyi o eski, iptal edilmiş
// tutar kadar SESSİZCE yanlış şişiriyordu.
//
// Bu test, tetikleyicinin GERÇEK üretim şemasında (TestVeritabani —
// fresh-install şeması, semalar/diger_semasi.dart'takiyle BİREBİR
// aynı) doğru davrandığını doğrular: soft-delete edilmiş bir
// cari_hareket, YENİ bir cari_hareket eklendiğinde bakiye hesabına
// KESİNLİKLE dahil edilmemeli.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('trg_cari_hareket_bakiye tetikleyicisi', () {
    test('soft-delete edilmiş (is_deleted=1) eski bir hareket, YENİ bir '
        'hareket eklenince bakiye hesabına DAHİL EDİLMEZ — tıpkı buluttan '
        'gelen bir cari_hareket senkronunda olduğu gibi', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);

      // 1) Geçmişte iptal edilmiş bir hareket — is_deleted=1 olarak
      // DOĞRUDAN ekleniyor (cari_hareket_ekrani.dart'taki gerçek iptal
      // akışının SONUCUNU simüle ediyor — bu senaryoda önemli olan,
      // tetikleyicinin bunu görmezden GELMESİ gerektiği).
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'borc': 100, 'alacak': 0,
        'is_deleted': 1, 'fis_tipi': 'İade İptali',
        'tarih': DateTime.now().toIso8601String(),
      });

      // 2) Veritabani.supaKayitlariEkle()'nin yaptığı JENERİK, takip
      // mantığı OLMAYAN INSERT'i simüle eden, TAMAMEN İLGİSİZ yeni bir
      // hareket (ör. başka bir cihazdan senkronize olan bir tahsilat).
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'borc': 0, 'alacak': 30,
        'is_deleted': 0, 'fis_tipi': 'Tahsilat',
        'tarih': DateTime.now().toIso8601String(),
      });

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      final bakiye = (cari['bakiye'] as num).toDouble();

      expect(bakiye, equals(-30.0),
          reason: 'Sadece is_deleted=0 olan hareket (0 borç - 30 alacak = '
              '-30) sayılmalı; iptal edilmiş 100 TL\'lik borç ASLA dahil '
              'edilmemeli (dahil edilseydi bakiye 70.0 olurdu).');
    });

    test('normal (soft-delete edilmemiş) hareketler her zaman olduğu gibi '
        'toplanmaya devam eder — düzeltme mevcut davranışı bozmadı', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'borc': 200, 'alacak': 0, 'is_deleted': 0,
        'fis_tipi': 'Satış', 'tarih': DateTime.now().toIso8601String(),
      });
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'borc': 0, 'alacak': 50, 'is_deleted': 0,
        'fis_tipi': 'Tahsilat', 'tarih': DateTime.now().toIso8601String(),
      });

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(150.0));
    });
  });
}
