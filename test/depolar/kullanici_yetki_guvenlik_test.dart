// test/depolar/kullanici_yetki_guvenlik_test.dart
//
// Derin denetim (2026-11-09), yüksek:
//  #21 'kullanici' yetkili admin olmayan müdür admin hesabının şifresini
//      sıfırlayıp tam admin olabiliyor, kendine tüm yetkileri verebiliyordu.
//  #22 Kaldırılan yetki diğer cihazlara ulaşmıyor, "Tam Al"da geri geliyordu
//      (satırlar silinip yeni kimlikle yazılıyordu).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/sifre_hash.dart';
import 'package:market_plus/depolar/kullanici_deposu.dart';
import 'package:market_plus/modeller/kullanici_model.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import '../robot/robot_ortam.dart';

void main() {
  late Database db;
  final depo = KullaniciDeposu();

  Future<int> kullanici(String ad, String rol) {
    final tuz = SifreHash.tuzUret();
    return depo.ekle(KullaniciModel(
        kullaniciAdi: ad, sifreHash: SifreHash.hashleTuzlu('9999', tuz), tuz: tuz,
        adSoyad: ad, rol: rol));
  }

  Future<int> adminId() async =>
      (await db.query('kullanicilar', where: "kullanici_adi = 'admin'")).first['id'] as int;

  setUp(() async {
    await RobotOrtam.hazirla();
    db = await RobotOrtam.veritabaniAc();
    await RobotOrtam.tohumla(db);
    expect(await AuthServisi().girisYap('admin', '1234'), isTrue);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await AuthServisi().cikisYap();
    await db.close();
  });

  group('#21 admin hesabı koruması', () {
    late int mudur;
    setUp(() async {
      mudur = await kullanici('mudur1', 'mudur');
      await depo.yetkileriKaydet(mudur, {'kullanici', 'urun'});
      await AuthServisi().cikisYap();
      expect(await AuthServisi().girisYap('mudur1', '9999'), isTrue);
    });

    test('müdür admin hesabının şifresini değiştiremez', () async {
      await expectLater(depo.sifreDegistir(await adminId(), 'yeni'),
          throwsA(isA<Exception>().having((e) => e.toString(), 'mesaj', contains('admin'))));
      await AuthServisi().cikisYap();
      expect(await AuthServisi().girisYap('admin', '1234'), isTrue, reason: 'admin şifresi değişmemeli');
    });

    test('müdür admin hesabını silemez, rolünü düşüremez, kimseyi admin yapamaz', () async {
      final a = await adminId();
      await expectLater(depo.sil(a), throwsException);
      final adminModel = KullaniciModel.fromMap((await db.query('kullanicilar', where: 'id = ?', whereArgs: [a])).first);
      await expectLater(depo.guncelle(adminModel.copyWith(rol: 'mudur')), throwsException);
      final kasiyer = await kullanici('kasiyer1', 'kasiyer');
      final kasiyerModel = KullaniciModel.fromMap((await db.query('kullanicilar', where: 'id = ?', whereArgs: [kasiyer])).first);
      await expectLater(depo.guncelle(kasiyerModel.copyWith(rol: 'admin')), throwsException);
    });

    test('müdür başkasına kendinde olmayan yetkiyi veremez, sahip olduğunu verebilir', () async {
      final kasiyer = await kullanici('kasiyer2', 'kasiyer');
      await expectLater(depo.yetkileriKaydet(kasiyer, {'ayarlar'}), throwsException);
      await depo.yetkileriKaydet(kasiyer, {'urun'});
      expect(await depo.yetkileriniGetir(kasiyer), {'urun'});
    });
  });

  test('#22 kaldırılan yetki silinmez, kimliği korunarak pasifleşir ve geri açılabilir', () async {
    final kasiyer = await kullanici('kasiyer3', 'kasiyer');
    await depo.yetkileriKaydet(kasiyer, {'kasa', 'rapor'});
    final kasaGid = (await db.query('roller_yetki',
            where: "kullanici_id = ? AND yetki_kodu = 'kasa'", whereArgs: [kasiyer]))
        .single['global_id'];

    await depo.yetkileriKaydet(kasiyer, {'rapor'});
    expect(await depo.yetkileriniGetir(kasiyer), {'rapor'});
    final pasif = (await db.query('roller_yetki', where: 'global_id = ?', whereArgs: [kasaGid])).single;
    expect(pasif['yetki_kodu'], '-kasa', reason: 'satır silinmemeli — buluta pasif olarak gitmeli');
    final kuyruk = await db.query('sync_queue',
        where: "tablo_adi = 'roller_yetki' AND kayit_global_id = ?", whereArgs: [kasaGid]);
    expect(kuyruk, isNotEmpty, reason: 'kaldırma diğer cihazlara bildirilmeli');

    await depo.yetkileriKaydet(kasiyer, {'rapor', 'kasa'});
    final geri = (await db.query('roller_yetki', where: 'global_id = ?', whereArgs: [kasaGid])).single;
    expect(geri['yetki_kodu'], 'kasa');
    expect(await depo.yetkileriniGetir(kasiyer), {'rapor', 'kasa'});
  });
}
