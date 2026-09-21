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

    // Kullanıcı isteği (2026-09-21): bir satış silinince (SatisDeposu.sil())
    // orijinal "Satış" kaydı silinmez (audit için), sadece net etkisini
    // sıfırlayan bir "Satış İptali" ters kaydı eklenir. Öncesinde bu ikisi
    // ayrı ayrı, "... İptali" yazan kafa karıştırıcı satırlar olarak
    // müşteri ekstresinde kalıyordu. Artık net etkisi sıfır olan böyle bir
    // grup ekrandan TAMAMEN kaldırılıyor — sanki satış hiç olmamış gibi.
    test('tamamen iptal edilmiş satış (Satış + Satış İptali, net 0) listede HİÇ görünmez', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 400, fisNo: 'F4',
            borc: 100, alacak: 0),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış İptali', fisId: 400, fisNo: 'F4',
            borc: 0, alacak: 100),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Tahsilat', alacak: 999),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1), reason: 'sadece ilgisiz Tahsilat kalmalı');
      expect(sonuc.first.fisTipi, 'Tahsilat');
    });

    test('net SIFIR olmayan (ör. kısmi/tutarsız) bir iptal grubu GÜVENLİ TARAFTA kalır — gizlenmez', () {
      // Bu senaryoda "Satış İptali" tutarı orijinal borcu tam karşılamıyor
      // (net = 100 - 70 = 30) — emin olunamayan bir durum, bu yüzden
      // fonksiyon dokunmadan göstermeye devam etmeli.
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 500, fisNo: 'F5',
            borc: 100, alacak: 0),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış İptali', fisId: 500, fisNo: 'F5',
            borc: 0, alacak: 70),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 600, fisNo: 'F6',
            borc: 20, alacak: 0),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      // F5 grubu net sıfır olmadığı için HİÇBİRİ gizlenmez (orijinal
      // "Satış" + "Satış İptali" iki ayrı satır olarak kalır, tıpkı
      // gruplama öncesi gibi), F6 zaten etkilenmemiştir.
      expect(sonuc, hasLength(3));
      expect(sonuc.map((h) => h.fisId), containsAll([500, 600]));
    });

    test('iptal edilmiş satışın izi sadece o fişe ait — diğer satışları etkilemez', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 700, fisNo: 'F7',
            borc: 50, alacak: 0),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış İptali', fisId: 700, fisNo: 'F7',
            borc: 0, alacak: 50),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 800, fisNo: 'F8',
            borc: 75, alacak: 0),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1));
      expect(sonuc.first.fisId, 800);
      expect(sonuc.first.borc, 75.0);
    });

    test('tek başına "Satış İptali" (Satış satırı olmadan) gizlenmez — güvenli taraf göstermektir', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış İptali', fisId: 900, fisNo: 'F9',
            borc: 0, alacak: 50),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1));
    });

    // Kullanıcı bulgusu (2026-09-22): satış silmede olduğu gibi, bir
    // Tahsilat/Ödeme de İPTAL edildiğinde (CariDeposu.hareketIptalEt())
    // hiç gözükmemeli. Orijinal kayıt zaten is_deleted=1 olduğu için
    // hareketleriniGetir() onu hiç getirmiyor — geriye sadece salt-audit,
    // borc=0/alacak=0 bir "Tahsilat İptali" damga satırı kalıyor. Bu
    // satırın kendisi de artık gizlenmeli.
    test('iptal edilen Tahsilat — orijinali zaten görünmez, sıfır tutarlı damga satırı da HİÇ görünmez', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Tahsilat İptali', fisId: 42,
            fisNo: null, borc: 0, alacak: 0, aciklama: 'İptal: Nakit tahsilat (₺90,00)'),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 1, fisNo: 'F1', borc: 30, alacak: 0),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1), reason: 'sadece ilgisiz Satış kalmalı');
      expect(sonuc.first.fisTipi, 'Satış');
    });

    test('iptal edilen Ödeme — sıfır tutarlı damga satırı HİÇ görünmez', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Ödeme İptali', fisId: 7,
            borc: 0, alacak: 0, aciklama: 'İptal: Ödeme (₺50,00)'),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, isEmpty);
    });

    test('gerçek (sıfır olmayan) Tahsilat/Ödeme kayıtları DEĞİŞMEDEN görünür', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Tahsilat', borc: 0, alacak: 100),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Ödeme', borc: 50, alacak: 0),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(2));
    });

    // Kullanıcı bulgusu (2026-09-22): AlimIslemServisi.sil() eklendi —
    // bir Alım silinince Satış'la AYNI desende (audit izi DB'de kalır,
    // ekranda net-sıfır grup gizlenir) davranmalı.
    test('tamamen iptal edilmiş Alım (Alım + Alım İptali, net 0) listede HİÇ görünmez', () {
      final ham = [
        _h(cariId: 1, tarih: tarih, fisTipi: 'Alım', fisId: 300, fisNo: 'AL1',
            borc: 0, alacak: 150),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Alım İptali', fisId: 300, fisNo: 'AL1',
            borc: 150, alacak: 0),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Tahsilat', alacak: 999),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1), reason: 'sadece ilgisiz Tahsilat kalmalı');
      expect(sonuc.first.fisTipi, 'Tahsilat');
    });

    // KRİTİK: Satış'ın fis_id'si satislar.id, Alım'ın fis_id'si
    // tedarikci_siparisler.id'dir — bu iki id uzayı ÇAKIŞABİLİR (ikisi de
    // 1'den başlar). Aynı fis_id'ye sahip bir Satış ile bir Alım YANLIŞLIKLA
    // aynı grupta birleşip net hesabını bozmamalı.
    test('AYNI fis_id\'ye sahip bir Satış ile bir Alım birbirine KARIŞMAZ (farklı id uzayları)', () {
      final ham = [
        // fis_id=5: tamamen iptal edilmiş bir SATIŞ (net 0 — gizlenmeli)
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış', fisId: 5, fisNo: 'S5', borc: 80, alacak: 0),
        _h(cariId: 1, tarih: tarih, fisTipi: 'Satış İptali', fisId: 5, fisNo: 'S5', borc: 0, alacak: 80),
        // fis_id=5: HÂLÂ AKTİF (iptal edilmemiş) bir ALIM — görünmeye devam etmeli
        _h(cariId: 1, tarih: tarih, fisTipi: 'Alım', fisId: 5, fisNo: 'AL5', borc: 0, alacak: 200),
      ];

      final sonuc = cariHareketleriniGrupla(ham);

      expect(sonuc, hasLength(1), reason: 'sadece aktif Alım kalmalı, Satış grubu gizlenmeli');
      expect(sonuc.first.fisTipi, 'Alım');
      expect(sonuc.first.alacak, 200.0);
    });
  });
}
