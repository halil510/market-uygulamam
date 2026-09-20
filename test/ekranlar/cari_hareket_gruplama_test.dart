// test/ekranlar/cari_hareket_gruplama_test.dart
//
// Kullanıcı bulgusu (2026-09-20): Karma ödemeli (hem Cari hem Cari-dışı
// payı olan) bir satış, Cari Hareketler listesinde AYNI satışın 2 ayrı
// "Satış" kartı gibi görünüyordu — SatisTamamlamaServisi.tamamla()'nın
// aynı fis_id için 2 cari_hareket satırı yazması yüzünden (gerçek Cari
// borcu + bakiyeyi etkilemeyen bilgi amaçlı satır). Bu, cari_detay_
// ekrani.dart'taki cariHareketleriniGrupla() SAF fonksiyonunun testi —
// DB/widget bağımlılığı yok, doğrudan import edilip çağrılabiliyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/cari/cari_detay_ekrani.dart';
import 'package:market_plus/modeller/cari_hareket_model.dart';

CariHareketModel _h({
  required int cariId,
  required DateTime tarih,
  required String fisTipi,
  int? fisId,
  String? fisNo,
  double borc = 0,
  double alacak = 0,
  String? aciklama,
}) =>
    CariHareketModel(
      cariId: cariId, tarih: tarih, fisTipi: fisTipi, fisId: fisId,
      fisNo: fisNo, borc: borc, alacak: alacak, aciklama: aciklama ?? '',
    );

void main() {
  final tarih = DateTime(2026, 9, 20, 14, 0);

  group('cariHareketleriniGrupla', () {
    test('Karma+Cari satışın 2 satırı (gerçek borç + self-cancelling) TEK karta birleşir', () {
      final ham = [
        // gerçek Cari borcu — 50 TL
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 100, fisNo: 'F1',
            borc: 50, alacak: 0, aciklama: 'Veresiye (Karma): F1'),
        // bakiyeyi etkilemeyen bilgi satırı (Nakit 50 TL) — self-cancelling
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 100, fisNo: 'F1',
            borc: 50, alacak: 50, aciklama: 'Nakit Satış (Karma): F1 — bakiyeyi etkilemez'),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1), reason: '2 satır yerine TEK kart görünmeli');
      expect(sonuc.first.borc, 50.0, reason: 'net bakiye etkisi SADECE gerçek Cari payı olmalı');
      expect(sonuc.first.alacak, 0.0);
      expect(sonuc.first.fisId, 100);
    });

    test('tek yöntemli (Karma olmayan) satış TEK satır olarak DEĞİŞMEDEN kalır', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 200, fisNo: 'F2',
            borc: 100, alacak: 0, aciklama: 'Veresiye: F2'),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1));
      expect(sonuc.first.borc, 100.0);
      expect(identical(sonuc.first, ham.first), isTrue,
          reason: 'tek satırlı grup birleştirilmemeli, olduğu gibi geçmeli');
    });

    test('sadece nakit satış + müşteri (self-cancelling TEK satır) — değişmeden kalır', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 300, fisNo: 'F3',
            borc: 100, alacak: 100, aciklama: 'Nakit Satış: F3 — bakiyeyi etkilemez'),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1));
      expect(sonuc.first.borc, 100.0);
      expect(sonuc.first.alacak, 100.0);
    });

    test('Satış olmayan hareketler (Tahsilat/Ödeme) HİÇ dokunulmadan geçer', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Tahsilat', alacak: 200),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Ödeme', borc: 30),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(2));
      expect(sonuc[0].fisTipi, 'Tahsilat');
      expect(sonuc[1].fisTipi, 'Ödeme');
    });

    test('birden fazla FARKLI Karma satış birbirinden bağımsız gruplanır, sıra korunur', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 100, fisNo: 'F1', borc: 50, alacak: 0),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Tahsilat', alacak: 999), // aralarda başka bir hareket
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 100, fisNo: 'F1', borc: 50, alacak: 50),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 200, fisNo: 'F2', borc: 20, alacak: 0),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 200, fisNo: 'F2', borc: 30, alacak: 30),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(3), reason: '2 Karma satış (her biri 1 karta düşer) + 1 Tahsilat');
      expect(sonuc[0].fisId, 100);
      expect(sonuc[0].borc, 50.0); // sadece F1'in gerçek Cari payı
      expect(sonuc[1].fisTipi, 'Tahsilat', reason: 'orijinal sıra korunmalı (F1 birleşmiş halde İLK GÖRÜLDÜĞÜ yerde kalır)');
      expect(sonuc[2].fisId, 200);
      expect(sonuc[2].borc, 20.0); // sadece F2'nin gerçek Cari payı
    });

    test('boş liste boş döner', () {
      expect(cariHareketleriniGrupla([]), isEmpty);
    });
  });
}
