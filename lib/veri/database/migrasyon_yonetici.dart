// lib/veri/database/migrasyon_yonetici.dart
import 'package:sqflite/sqflite.dart';
import 'semalar/kolon_tamamlayici.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'semalar/masa_semasi.dart';
import 'semalar/doviz_semasi.dart';

part 'migrasyon_yonetici_v1_v12.dart';
part 'migrasyon_yonetici_v12_v36.dart';
part 'migrasyon_yonetici_v36_v63.dart';

class MigrasyonYonetici {
  static Future<void> guncelle(
      Database db, int eskiVersiyon, int yeniVersiyon) async {
    // v1'den v2'ye
    if (eskiVersiyon < 2) await _v1denV2ye(db);

    // v2'den v3'e
    if (eskiVersiyon < 3) await _v2denV3e(db);

    // v3'ten v4'e
    if (eskiVersiyon < 4) await _v3denV4e(db);

    // v4'ten v5'e
    if (eskiVersiyon < 5) await _v4denV5e(db);

    // v5'ten v6'ya
    if (eskiVersiyon < 6) await _v5denV6ya(db);

    // v6'dan v7'ye
    if (eskiVersiyon < 7) await _v6denV7ye(db);

    // v7'den v8'e (İade Faturası)
    if (eskiVersiyon < 8) await _v7denV8e(db);

    // v8'den v9'a (Masa/Restoran)
    if (eskiVersiyon < 9) await _v8denV9a(db);

    // v9'dan v10'a (PLU)
    if (eskiVersiyon < 10) await _v9denV10a(db);

    // v10'dan v11'e (Rezervasyon + Garson Çağrı)
    if (eskiVersiyon < 11) await _v10denV11e(db);

    // v11'den v12'ye (Masa rapor indexleri)
    if (eskiVersiyon < 12) await _v11denV12e(db);

    // v12'den v13'e (Masa Detay + Adisyon log)
    if (eskiVersiyon < 13) await _v12denV13e(db);

    //  YENİ: v13'ten v14'e (Tüm eksik sütunlar)
    if (eskiVersiyon < 14) await _v13denV14e(db);

    //  YENİ: v14'ten v15'e (Tüm eksik sütunlar)
    if (eskiVersiyon < 15) await _v14denV15e(db);

    //  YENİ: v15'ten v16'ya (Borc Takip)
    if (eskiVersiyon < 16) await _v15denV16ya(db);

    //  YENİ: v16'ten v17'ye (Banka, Kredi Kartı, Mail)
    if (eskiVersiyon < 17) await _v16denV17ye(db);

    // YENI: v17'den v18'e (duzeltme: cift bakiye guncellemesi + bozuk
    if (eskiVersiyon < 18) await _v17denV18e(db);

    if (eskiVersiyon < 19) await _v18denV19a(db);

    // GÜVENLİK: v19'dan v20'ye — kredi kartı numarası artık maskelenmiş
    // saklanıyor, CVC hiç saklanmıyor (bkz. _v19denV20ye yorumu)
    if (eskiVersiyon < 20) await _v19denV20ye(db);

    // v20'den v21'e — çoklu para birimi (döviz kurları) tablosu eklendi
    if (eskiVersiyon < 21) await _v20denV21e(db);

    // v21'den v22'ye — PLU panelinde sürükle-bırak sıralaması artık
    // kalıcı (önceden sadece görsel olarak değişiyordu, veritabanına
    // hiç kaydedilmiyordu, ekran yenilenince kayboluyordu).
    if (eskiVersiyon < 22) await _v21denV22ye(db);

    // v22'den v23'e — Personel telefon/e-posta alanları (form bu
    // bilgileri topluyordu ama veritabanında sütun hiç yoktu, sessizce
    // kayboluyordu).
    if (eskiVersiyon < 23) await _v22denV23e(db);

    // v23'ten v24'e — Cari kartlarda "e-Fatura Mükellefi mi?" durumu
    // (LOGO gibi profesyonel yazılımlardaki gibi, GİB Kayıtlı Kullanıcılar
    // Listesi sorgusu sonucu önbelleğe alınıyor).
    if (eskiVersiyon < 24) await _v23denV24e(db);

    // v24'ten v25'e — Fatura "Ödeme Şekli" alanı (Nakit/Kart/Havale vb.
    // — hem basılan faturada hem UBL-TR XML'inde eksikti).
    if (eskiVersiyon < 25) await _v24denV25e(db);

    // v25'ten v26'ya — Ürün "döviz bazlı fiyatlandırma" (kur değişince
    // toplu yeniden fiyatlandırma için).
    if (eskiVersiyon < 26) await _v25denV26ya(db);

    // v26'dan v27'ye — Şifre güvenliği: tuzsuz düz SHA-256 yerine
    // kullanıcı başına rastgele tuz (salt) + çok turlu hash. Bu
    // oturumda tespit edilen güvenlik açığının düzeltmesi.
    if (eskiVersiyon < 27) await _v26danV27ye(db);

    // v27'den v28'e — GİB şifresi ve mali mühür şifresi SQLite'tan
    // (düz metin) güvenli depolamaya (flutter_secure_storage) taşınıyor.
    if (eskiVersiyon < 28) await _v27denV28e(db);

    // v28'den v29'a — Borç ödemeleri artık hareket-bazlı (event
    // sourcing), önceki oku-hesapla-yaz riskini ortadan kaldırıyor.
    if (eskiVersiyon < 29) await _v28denV29a(db);

    // v29'dan v30'a — Kredi kartı limit kullanımı hareket-bazlı oldu.
    if (eskiVersiyon < 30) await _v29danV30a(db);

    // v30'dan v31'e — Ürün görselinin bulut adresi için sütun eklendi.
    if (eskiVersiyon < 31) await _v30danV31e(db);

    // v31'den v32'ye — QR menüde gösterilecek ürünler için sütun eklendi.
    if (eskiVersiyon < 32) await _v31denV32ye(db);
    if (eskiVersiyon < 33) await _v32denV33e(db);
    if (eskiVersiyon < 34) await _v33denV34e(db);
    if (eskiVersiyon < 35) await _v34denV35e(db);
    if (eskiVersiyon < 36) await _v35denV36e(db);
    if (eskiVersiyon < 37) await _v36denV37e(db);
    if (eskiVersiyon < 38) await _v37denV38e(db);
    if (eskiVersiyon < 39) await _v38denV39a(db);
    if (eskiVersiyon < 40) await _v39danV40a(db);
    if (eskiVersiyon < 41) await _v40danV41a(db);
    if (eskiVersiyon < 42) await _v41denV42e(db);
    if (eskiVersiyon < 43) await _v42denV43e(db);
    if (eskiVersiyon < 44) await _v43denV44e(db);
    if (eskiVersiyon < 45) await _v44denV45e(db);
    if (eskiVersiyon < 46) await _v45denV46e(db);
    if (eskiVersiyon < 47) await _v46denV47e(db);
    if (eskiVersiyon < 48) await _v47denV48e(db);
    if (eskiVersiyon < 49) await _v48denV49a(db);
    if (eskiVersiyon < 50) await _v49danV50ye(db);
    if (eskiVersiyon < 51) await _v50denV51e(db);

    // v51'den v52'ye
    if (eskiVersiyon < 52) await _v51denV52ye(db);

    // v52'den v53'e
    if (eskiVersiyon < 53) await _v52denV53e(db);

    // v53'ten v54'e — Sync Çakışmaları tablosu (protokol §12)
    if (eskiVersiyon < 54) await _v53denV54e(db);

    // v54'ten v55'e — bozuk 'last_updated' tetikleyicileri kaldırıldı
    if (eskiVersiyon < 55) await _v54denV55e(db);

    // v55'ten v56'ya — kasa_hareketleri.odeme_yontemi eklendi (Vardiya/Kasa mutabakatı)
    if (eskiVersiyon < 56) await _v55denV56ya(db);

    // v56'dan v57'ye — Onay Merkezi (FAZ 9, kullanıcı onayıyla)
    if (eskiVersiyon < 57) await _v56denV57ye(db);

    // v57'den v58'e — Bayi Portalı (kullanıcı onayıyla)
    if (eskiVersiyon < 58) await _v57denV58e(db);
    if (eskiVersiyon < 59) await _v58denV59a(db);
    if (eskiVersiyon < 60) await _v59denV60a(db);
    if (eskiVersiyon < 61) await _v60danV61e(db);
    if (eskiVersiyon < 62) await _v61denV62ye(db);
    if (eskiVersiyon < 63) await _v62denV63e(db);

    // v63'ten v64'e — fis_seri buluta senkronize oluyor (MAX-birleştirme)
    if (eskiVersiyon < 64) await _v63denV64e(db);

    // v64'ten v65'e — sync_queue kalıcı senkron kuyruğuna hata_mesaji
    // eklendi (Madde 5 sertleştirmesi — bkz. _v64denV65e yorumu).
    if (eskiVersiyon < 65) await _v64denV65e(db);
  }
}
