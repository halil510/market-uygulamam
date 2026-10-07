// lib/servisler/supabase_sync_servisi.dart
// ignore_for_file: avoid_print

import 'bulut/supabase_oturum.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'kolon_haritalama.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../veri/database/veritabani.dart';
import 'bulut/supabase_ayarlari.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import 'senkron_sonrasi_mutabakat.dart';

part 'supabase_sync_sabitleri.dart';

class _Ayar {
  final String url, key;
  _Ayar({required this.url, required this.key});
  String get rest => '$url/rest/v1';
}

class BaglantiSonuc {
  final bool basarili;
  final String mesaj;
  BaglantiSonuc(this.basarili, this.mesaj);
}

class SyncSonuc {
  final Map<String, int> eklenen    = {};
  final Map<String, int> guncellenen = {};
  final Map<String, int> silinen    = {};
  final List<String> hatalar        = [];

  int get toplamEklenen    => eklenen.values.fold(0, (a, b) => a + b);
  int get toplamGuncellenen=> guncellenen.values.fold(0, (a, b) => a + b);
  int get toplamSilinen    => silinen.values.fold(0, (a, b) => a + b);
  bool get basarili        => hatalar.isEmpty;

  String get ozet {
    final p = <String>[];
    if (toplamEklenen > 0)     p.add('+$toplamEklenen eklendi');
    if (toplamGuncellenen > 0) p.add('~$toplamGuncellenen güncellendi');
    if (toplamSilinen > 0)     p.add('-$toplamSilinen silindi');
    if (hatalar.isNotEmpty)    p.add('${hatalar.length} hata');
    return p.isEmpty ? 'Değişiklik yok' : p.join(', ');
  }
}

class SupabaseSyncServisi {
  static const _prefCihaz = 'mp_cihaz_id';

  // YARDIMCI METODLAR
  // --------------------------------------------------------------
  static Future<_Ayar?> _ayarGetir() async {
    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.keyOku();
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return _Ayar(url: url.trim(), key: key.trim());
  }

  static Future<void> ayarlariKaydet(String url, String key) async {
    final temiz = url.trim()
        .replaceAll(RegExp(r'/rest/v1/?$'), '')
        .replaceAll(RegExp(r'/$'), '');
    await SupabaseAyarlari.kaydet(url: temiz, key: key.trim());
  }

  static Future<String> cihazId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_prefCihaz);
    if (id == null) {
      id = 'cihaz_${DateTime.now().millisecondsSinceEpoch}';
      await p.setString(_prefCihaz, id);
    }
    return id;
  }

  static Map<String, String> _getH(String key) => {
    'apikey': key,
    'Authorization': 'Bearer ${SupabaseOturum.bearer(key)}',
    'Accept': 'application/json',
  };

  static Map<String, String> _upsertH(String key) => {
    'apikey': key,
    'Authorization': 'Bearer ${SupabaseOturum.bearer(key)}',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Prefer': 'resolution=merge-duplicates,return=minimal',
  };

  static Map<String, String> _insertH(String key) => {
    'apikey': key,
    'Authorization': 'Bearer ${SupabaseOturum.bearer(key)}',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Prefer': 'return=minimal',
  };

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 KRİTİK ÇOKLU CİHAZ DÜZELTMESİ — PAYLAŞILAN FİLİGRAN
  //
  // ÖNCEDEN: gönderme ve çekme AYNI anahtarı ('mp_sync_<tablo>')
  // kullanıyordu. Oysa bu ikisi FARKLI ZAMAN EKSENİNDE:
  //
  //   • GÖNDERME filigranı, BU CİHAZIN yazdığı yerel kayıtların
  //     last_updated'iyle karşılaştırılır → cihaz saati ekseni.
  //   • ÇEKME filigranı, BAŞKA CİHAZLARIN yazdığı bulut kayıtlarının
  //     last_updated'iyle karşılaştırılır → sunucu/diğer cihaz ekseni.
  //
  // KAYIP SENARYOSU (tek anahtar paylaşılınca):
  //   • Cihaz çevrimdışıyken 10:15'te bir satış kaydediyor (gönderilmedi)
  //   • Sonra "Hızlı Al" yapılıyor; bulutta 10:30 damgalı kayıtlar var
  //     → filigran 10:30'a ilerliyor
  //   • "Hızlı Gönder" filtresi: last_updated > 10:30
  //     → 10:15'lik KENDİ SATIŞI ELENİYOR, buluta HİÇ gitmiyor.
  //   → Kalıcı kayıp. "Tam Gönder" yapılmadıkça fark edilmez.
  //
  // DÜZELTME: iki ayrı anahtar. Eski tek anahtar, ilk okumada her iki
  // yöne de TOHUM olarak verilir — güncelleme sonrası gereksiz tam
  // senkron olmaz.
  // ══════════════════════════════════════════════════════════════════════
  static String _filigranAnahtari(String tablo, String yon) =>
      'mp_sync_${yon}_$tablo';

  static Future<DateTime?> _sonSenkron(String tablo, String yon) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_filigranAnahtari(tablo, yon))
        // Eski sürümden gelen tek anahtar — ilk okumada tohum.
        ?? p.getString('mp_sync_$tablo');
    final t = s != null ? DateTime.tryParse(s) : null;
    // 🔴 DÜZELTME (2026-09-27): çekme filigranı buluttaki en büyük
    // last_updated'ten gelir. Eski sürümler damgayı dilimsiz yerel saatle
    // yazdığı için bulutta 3 saat İLERİDE duran satırlar var; filigran
    // "gelecekte" kalırsa başka cihazların gerçek-UTC damgalı yeni
    // kayıtları "> filigran" filtresine hiç takılmaz, sessizce atlanırdı.
    // Gelecekteki filigran, dilim farkı + 1 saat geriye çekilir (fazladan
    // çekilen kayıtlar global_id ile eşleştiği için zararsızdır).
    if (t != null && yon == 'al') {
      final simdi = DateTime.now().toUtc();
      if (t.isAfter(simdi.add(const Duration(minutes: 1)))) {
        final geri = DateTime.now().timeZoneOffset.abs() + const Duration(hours: 1);
        return simdi.subtract(geri);
      }
    }
    return t;
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 KRİTİK ÇOKLU CİHAZ DÜZELTMESİ — SAAT KAYMASI VERİ KAYBI
  //
  // ÖNCEDEN: filigran her zaman `DateTime.now()` — yani BU CİHAZIN
  // saati — olarak kaydediliyordu. Ama çekme filtresi
  // `?last_updated=gt.<filigran>` bulut satırlarına uygulanıyor ve o
  // satırların `last_updated` değerleri BAŞKA CİHAZLARIN saatiyle
  // yazılmış.
  //
  // KAYIP SENARYOSU (iki kasa, saatleri 5 dk kaymış):
  //   • Kasa-B saat 10:00'da (B'nin saati) çekiyor → filigran = 10:00
  //   • Kasa-A'nın saati 5 dk GERİDE. A, gerçek saat 10:03'te bir satış
  //     kaydediyor; damga A'nın saatiyle 09:58 oluyor.
  //   • A gönderiyor, bulutta satır last_updated = 09:58.
  //   • B bir daha çektiğinde filtre "> 10:00" → 09:58 ELENİYOR.
  //   → O satış Kasa-B'ye ASLA gelmiyor. Sessiz, kalıcı veri kaybı.
  //     "Tam Al" yapılmadıkça fark edilmez.
  //
  // DÜZELTME: filigran artık cihaz saatinden değil, ÇEKİLEN VERİDEKİ
  // en büyük `last_updated` değerinden alınıyor. Böylece filigran her
  // zaman sunucudaki/diğer cihazlardaki zaman ekseninde kalır; yerel
  // saatin doğru olması gerekmez.
  //
  // Veri gelmediyse filigran İLERLETİLMEZ (eskisi korunur) — yoksa boş
  // bir çekim, henüz gönderilmemiş kayıtları geçmişte bırakırdı.
  // ══════════════════════════════════════════════════════════════════════
  static Future<void> _senkronKaydet(String tablo, String yon,
      [String? veridekiEnSonZaman]) async {
    final p = await SharedPreferences.getInstance();
    final anahtar = _filigranAnahtari(tablo, yon);

    // ÇEKME: filigran verideki en büyük last_updated'ten ilerler
    // (cihaz saatinden DEĞİL — saat kayması veri kaybı koruması).
    if (veridekiEnSonZaman != null && veridekiEnSonZaman.isNotEmpty) {
      final yeniZ = DateTime.tryParse(veridekiEnSonZaman);
      if (yeniZ != null) {
        final mevcutStr = p.getString(anahtar);
        final mevcut = mevcutStr != null ? DateTime.tryParse(mevcutStr) : null;
        if (mevcut == null || yeniZ.isAfter(mevcut)) {
          await p.setString(anahtar, yeniZ.toUtc().toIso8601String());
        }
        return;
      }
    }

    // GÖNDERME: yerel kayıtlarla karşılaştırıldığı için cihaz saati DOĞRU
    // eksendir. Çekmede ise (veri yoksa) mevcut filigran KORUNUR.
    if (yon == 'gonder') {
      await p.setString(anahtar, DateTime.now().toUtc().toIso8601String());
    } else if (p.getString(anahtar) == null) {
      await p.setString(anahtar, DateTime.now().toUtc().toIso8601String());
    }
  }

  /// sunucu_zamani filigranı (Bulgu 1). İlk geçişte eski last_updated
  /// filigranının 48 saat gerisinden başlar (aradaki satırlar LWW korumalı
  /// tekrar iner, zararsız). Filigran YALNIZ buluttan gelen değerle yazılır,
  /// cihaz saatiyle asla — cihaz saati ileride olsa kayıt kaçmasın.
  static Future<DateTime?> _sunucuZamaniFiligrani(String tablo) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_filigranAnahtari(tablo, 'al_sz'));
    final t = s != null ? DateTime.tryParse(s) : null;
    if (t != null) return t;
    final eski = await _sonSenkron(tablo, 'al');
    return eski?.subtract(const Duration(hours: 48));
  }

  /// Başarılı çekimden sonra iki filigranı da ilerletir: last_updated
  /// (sunucu_zamani olmayan bulutlar için) ve sunucu_zamani.
  static Future<void> _cekimFiligraniKaydet(
      String tablo, List<Map<String, dynamic>> kayitlar) async {
    await _senkronKaydet(tablo, 'al', _enSonZaman(kayitlar));
    final sz = _enSonZaman(kayitlar, alan: 'sunucu_zamani');
    if (sz == null) return;
    final yeni = DateTime.tryParse(sz);
    if (yeni == null) return;
    final p = await SharedPreferences.getInstance();
    final anahtar = _filigranAnahtari(tablo, 'al_sz');
    final mevcut = DateTime.tryParse(p.getString(anahtar) ?? '');
    if (mevcut == null || yeni.isAfter(mevcut)) {
      await p.setString(anahtar, yeni.toUtc().toIso8601String());
    }
  }

  /// Çekilen partideki en büyük [alan] değeri (varsayılan `last_updated`).
  static String? _enSonZaman(List<Map<String, dynamic>> kayitlar,
      {String alan = 'last_updated'}) {
    String? enSon;
    for (final r in kayitlar) {
      final s = r[alan]?.toString();
      if (s == null || s.isEmpty) continue;
      if (enSon == null || s.compareTo(enSon) > 0) enSon = s;
    }
    return enSon;
  }

  // --------------------------------------------------------------
  // VERİ HAZIRLAMA - TÜM NOT NULL SÜTUNLAR DOLDURULDU
  // --------------------------------------------------------------
  static Map<String, dynamic> _hazirla(
    Map<String, dynamic> row,
    String tablo,
    String cId,
    String now,
  ) {
    final m = Map<String, dynamic>.from(row);

    // Gönderilmeyecek kolonları temizle
    for (final k in _damaGonderilmez) {
      m.remove(k);
    }
    m.remove('id');

    // 🔥 EVRENSEL DÜZELTME: kullanıcının paylaştığı gerçek hata
    // kaydında ("cari_hareket INSERT 400: invalid input syntax for
    // type bigint: 'false'") görüldüğü gibi, bazı kayıtlarda BEKLENMEDİK
    // şekilde bir Dart boolean (true/false) değeri, Supabase'de
    // sayısal (bigint) olan bir sütuna gönderiliyordu. Kaynağını
    // (hangi kod yolunun bunu ürettiğini) kesin olarak izlemek yerine,
    // HANGİ TABLO/SÜTUN olursa olsun, göndermeden hemen önce TÜM
    // boolean değerleri güvenli şekilde 0/1'e çeviren evrensel bir
    // koruma ekleniyor — bu hata sınıfı bir daha hiçbir tabloda
    // çıkmayacak.
    for (final k in m.keys.toList()) {
      final v = m[k];
      if (v is bool) m[k] = v ? 1 : 0;
    }

    // 🔴🔴🔴 KAPSAMLI DERİN ANALİZ (kullanıcı isteği — "başka
    // tablolarda var mı bak"): 'faturalar' ve 'personel' tablolarının
    // migrasyon geçmişi tarandı — ESKİ bir migrasyon adımı bir sütun
    // ekledikten SONRA, DAHA SONRAKİ bir migrasyon adımı FARKLI bir
    // isimle onun YERİNE GEÇEN bir sütun daha eklemiş, ama eski sütun
    // hiç SİLİNMEMİŞ. Var olan (yükseltilmiş) her cihazda HER İKİ
    // sütun da hâlâ fiziksel olarak duruyor. Bulut şemasında sadece
    // YENİ isim var — eski isim buluta HİÇ gitmemiş. `_hazirla()`
    // gönderilecek sütun listesini payload'daki anahtarlardan kurduğu
    // için, eski sütun adı da listeye giriyor ve PostgREST TÜM
    // partiyi "column does not exist" hatasıyla reddediyordu — yani
    // 'faturalar' ve 'personel' senkronu, güncellenmiş (taze kurulum
    // olmayan) HER cihazda muhtemelen TAMAMEN çalışmıyordu. BUNU
    // GENEL (_damaGonderilmez) listesine EKLEMEDİM çünkü 'satislar'
    // tablosunda 'efatura_uuid'/'efatura_durum' aynı isimlerle
    // GERÇEKTEN kullanılıyor ve bulutta karşılığı var — genel bir
    // filtre onları da (yanlışlıkla) silerdi. Bu yüzden sadece BU İKİ
    // tabloda, nokta atışı olarak temizleniyor:
    //   faturalar: efatura_uuid  → yerini e_fatura_uuid aldı
    //   faturalar: efatura_durum → yerini e_fatura_durum aldı
    //   faturalar: efatura_tipi  → bulutta hiç karşılığı yok (kullanılmıyor)
    //   personel:  ise_baslama_tarihi → yerini ise_baslama aldı
    // Tek liste (otomatik yolla ortak): KolonHaritalama.yereleOzguSutunlar.
    // 🔴 satislar.sync_cakisma_kopyasi burada ÖNCEDEN ayıklanmıyordu —
    // "Buluta Gönder" tüm satışları PGRST204 ile reddettiriyordu.
    KolonHaritalama.yereleOzguSutunlariAyikla(tablo, m);

    // 🔥 SATISLAR için NOT NULL sütunları doldur
    if (tablo == 'satislar') {
      m['toplam_tutar'] ??= 0.0;
      m['iskonto_tutar'] ??= 0.0;
      m['iskonto_oran'] ??= 0.0;
      m['kdv_tutar'] ??= 0.0;
      m['genel_toplam'] ??= 0.0;
      m['odenen_tutar'] ??= 0.0;
      m['kargo_ucreti'] ??= 0.0;
      m['iptal'] ??= 0;
      m['is_deleted'] ??= 0;
      if (m['tarih'] == null) m['tarih'] = now;
      if (m['odeme_yontemi'] == null) m['odeme_yontemi'] = 'Nakit';
      if (m['fis_tipi'] == null) m['fis_tipi'] = 'Satış';
    }

    // 🔥 SATIS_KALEM için NOT NULL sütunları doldur
    if (tablo == 'satis_kalem') {
      m['miktar'] ??= 1.0;
      m['birim_fiyat'] ??= 0.0;
      m['iskonto_oran'] ??= 0.0;
      m['iskonto_tutar'] ??= 0.0;
      m['kdv_oran'] ??= 18.0;
      m['kdv_tutar'] ??= 0.0;
      m['net_fiyat'] ??= 0.0;
      m['toplam_tutar'] ??= 0.0;
      m['alis_fiyat'] ??= 0.0;
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
    }

    // 🔥 IADE_KALEM / IRSALIYE_KALEM / MASA_SIPARIS_KALEM /
    // TEDARIKCI_SIPARIS_KALEM için NOT NULL sütunları doldur
    // 🔴🔴 KAPSAMLI DERİN ANALİZ (kullanıcı isteği — "başka tablolarda
    // var mı bak"): satis_kalem'e ÖNCEDEN eklenmiş olan urun_adi
    // koruması, tam olarak AYNI riski taşıyan 3 kardeş "kalem" (kalem
    // satırı) tablosuna hiç uygulanmamıştı — hepsi urun_id yanında
    // DENORMALİZE bir urun_adi anlık görüntüsü tutuyor ve bulutta bu
    // sütun(lar) NOT NULL. kart_no_maskeli hatasında görüldüğü gibi,
    // aynı partideki başka bir kayıtta bu alan eksikse _normalizeBatch()
    // bunu null'a çevirebiliyor — burada da aynı savunma ekleniyor.
    if (tablo == 'iade_kalem') {
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
      m['miktar'] ??= 1.0;
      m['birim_fiyat'] ??= 0.0;
      m['toplam'] ??= 0.0;
    }
    if (tablo == 'irsaliye_kalem') {
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
      m['miktar'] ??= 1.0;
    }
    if (tablo == 'masa_siparis_kalem') {
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
    }
    if (tablo == 'tedarikci_iade_kalem') {
      m['miktar'] ??= 1.0;
      m['birim_fiyat'] ??= 0.0;
      m['toplam_tutar'] ??= 0.0;
    }
    if (tablo == 'tedarikci_siparis_kalem') {
      m['siparis_mik'] ??= 1.0;
      m['birim_fiyat'] ??= 0.0;
      m['toplam_tutar'] ??= 0.0;
    }

    // 🔥 KREDI_KARTLARI için NOT NULL sütunları doldur
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — gerçek Supabase hatası:
    // "kredi_kartlari UPSERT 400: ... kart_no_maskeli ... null ...").
    // Bu alan için koruma ÖNCEDEN sadece supaTumKayitlariGetirTemiz()
    // içinde (veritabani.dart) vardı — yani veri bu fonksiyona
    // ULAŞMADAN ÖNCEKİ bir adımda. Ama _normalizeBatch() (aşağıda),
    // aynı toplu istekteki kayıtları TÜM anahtarların BİRLEŞİMİNE göre
    // normalize ederken, bir kayıtta bu alan (herhangi bir sebeple)
    // eksikse ona AÇIKÇA `null` atıyor — yani bir kart için doğru
    // değer üretilse bile, aynı partideki BAŞKA bir kartta bu alan
    // eksikse, normalizasyon bunu yeniden null'a çevirebiliyordu. Artık
    // bu son kontrol noktasında (buluta gitmeden hemen önce, TEK
    // merkezi yerde) da garanti altına alınıyor — yukarı akıştaki
    // hiçbir adım bunu artık atlayamaz.
    if (tablo == 'kredi_kartlari') {
      final knm = m['kart_no_maskeli'];
      if (knm == null || (knm is String && knm.isEmpty)) {
        m['kart_no_maskeli'] = '**** **** **** ????';
      }
    }

    // 🔥 URUNLER için NOT NULL sütunları doldur
    if (tablo == 'urunler') {
      m['alis_fiyat'] ??= 0.0;
      m['alis_fiyat_kdv_dahil'] ??= 0.0;
      m['satis_fiyati'] ??= 0.0;
      m['stok'] ??= 0.0;
      m['toplam_maliyet'] ??= 0.0;
      m['toplam_stok'] ??= 0.0;
      m['alis_kdv_oran'] ??= 18.0;
      m['kdv_oran'] ??= '18';
      m['aktif'] ??= 1;
      m['seri_no_takibi'] ??= 0;
      m['lot_takibi'] ??= 0;
      m['indirim_orani'] ??= 0.0;
      m['otomatik_indirim'] ??= 0;
      m['son_alim_indirim_oran'] ??= 0.0;
      m['minimum_stok'] ??= 0.0;
      m['maksimum_stok'] ??= 0.0;
      m['maksimum_satir_miktari'] ??= 0.0;
      m['raf_omru'] ??= 0;
      m['plu'] ??= 0;
      m['plu_kart_boyut'] ??= 2;
      m['puan_orani'] ??= 0.0;
      m['en'] ??= 0.0;
      m['boy'] ??= 0.0;
      m['yukseklik'] ??= 0.0;
      m['agirlik'] ??= 0.0;
      m['is_deleted'] ??= 0;
      m['indirimli_fiyat'] ??= 0.0;
      m['hacim'] ??= 0.0;
      m['evrak_kontrol_aktif'] ??= 0;
      m['promosyon_aktif'] ??= 0;
      m['recete_katsayi'] ??= 1.0;
      m['net_alis_fiyat'] ??= 0.0;
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
      if (m['birim_adi'] == null || m['birim_adi'].toString().isEmpty) {
        m['birim_adi'] = 'Adet';
      }
    }

    // Boolean dönüşümü
    final skipBool = _skipBoolDonusum.contains(tablo);
    for (final k in m.keys.toList()) {
      final v = m[k];
      if (!skipBool && v is int && _boolAlanlar.contains(k)) {
        m[k] = v == 1;
      }
    }

    // global_id kontrolü
    if (_globalIdVar.contains(tablo)) {
      if (m['global_id'] == null || m['global_id'].toString().isEmpty) {
        m['global_id'] = const Uuid().v4();
      }
    } else {
      m.remove('global_id');
    }

    // last_updated kontrolü
    if (_lastUpdatedVar.contains(tablo)) {
      // Açık UTC (bkz. KolonHaritalama.utcDamga — dilimsiz yerel saat
      // bulutta 3 saat ileride saklanıyordu).
      m['last_updated'] = KolonHaritalama.utcDamga(m['last_updated']) ?? now;
    } else {
      m.remove('last_updated');
    }

    // cihaz_id kontrolü
    if (m.containsKey('cihaz_id')) {
      m['cihaz_id'] ??= cId;
    }

    // NULL değerleri JSON'dan çıkar
    m.removeWhere((_, v) => v == null);

    return m;
  }

  /// Batch içindeki tüm kayıtların aynı anahtarlara sahip olmasını sağlar.
  static List<Map<String, dynamic>> _normalizeBatch(List<Map<String, dynamic>> veriler) {
    if (veriler.isEmpty) return veriler;
    final allKeys = <String>{};
    for (final v in veriler) {
      allKeys.addAll(v.keys);
    }
    final normalized = <Map<String, dynamic>>[];
    for (final v in veriler) {
      final newMap = <String, dynamic>{};
      for (final key in allKeys) {
        newMap[key] = v[key];
      }
      normalized.add(newMap);
    }
    return normalized;
  }

  // --------------------------------------------------------------
  // BAĞLANTI TESTİ
  // --------------------------------------------------------------
  static Future<BaglantiSonuc> baglantiTest({String? url, String? key}) async {
    try {
      _Ayar ayar;
      if (url != null && key != null) {
        final temiz = url.trim()
            .replaceAll(RegExp(r'/rest/v1/?$'), '')
            .replaceAll(RegExp(r'/$'), '');
        ayar = _Ayar(url: temiz, key: key.trim());
      } else {
        final a = await _ayarGetir();
        if (a == null) return BaglantiSonuc(false, 'Bağlantı bilgileri girilmemiş');
        ayar = a;
      }
      final res = await http.get(
        Uri.parse('${ayar.rest}/urunler?limit=1&select=id'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return BaglantiSonuc(true, 'Bağlantı başarılı ✓');
      if (res.statusCode == 401) return BaglantiSonuc(false, 'API Key hatalı (401)');
      if (res.statusCode == 403) return BaglantiSonuc(false, 'Erişim reddedildi (403) — RLS kapatın');
      return BaglantiSonuc(false,
          'HTTP ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 100))}');
    } catch (e) {
      return BaglantiSonuc(false, 'Bağlanamadı: $e');
    }
  }

  // --------------------------------------------------------------
  // BULUTA GÖNDER
  // --------------------------------------------------------------
  /// Kullanıcı sorusu: "2 cihaz aynı kaydı değiştirirse ne olur?" —
  /// ÖNCEDEN bu kontrol hiç yoktu, "kim bulut'a son ulaşırsa o kazanır"
  /// mantığıydı (ağ gecikmesine bağlı, YANLIŞ olabilirdi). Artık
  /// göndermeden önce bulut'taki güncel last_updated değerleri
  /// çekiliyor; bulut'ta ZATEN daha yeni bir sürüm varsa o kayıt
  /// listeden çıkarılıyor (üzerine yazılmıyor) — gerçekten en son
  /// düzenlenen sürüm kazanıyor, ağ zamanlaması değil.
  static Future<List<Map<String, dynamic>>> _cakismaFiltrele(
    _Ayar ayar,
    String tablo,
    List<Map<String, dynamic>> batch,
    String uniqueAlan,
  ) async {
    final gidler = batch
        .map((r) => r[uniqueAlan]?.toString())
        .where((g) => g != null && g.isNotEmpty)
        .toSet();
    if (gidler.isEmpty) return batch;

    try {
      final gidListesi = gidler.map((g) => '"$g"').join(',');
      final res = await http.get(
        Uri.parse('${ayar.rest}/$tablo?select=$uniqueAlan,last_updated'
            '&$uniqueAlan=in.($gidListesi)'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return batch; // sorgu başarısızsa güvenli tarafta kal, eskisi gibi gönder

      final buluttakiler = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      final bulutZamanlari = <String, DateTime>{};
      for (final b in buluttakiler) {
        final gid = b[uniqueAlan]?.toString();
        final lu = b['last_updated']?.toString();
        if (gid != null && lu != null) {
          final t = KolonHaritalama.utcZaman(lu);
          if (t != null) bulutZamanlari[gid] = t;
        }
      }

      return batch.where((r) {
        final gid = r[uniqueAlan]?.toString();
        final yerelLu = r['last_updated']?.toString();
        if (gid == null || yerelLu == null) return true; // bilgi eksikse eskisi gibi gönder
        final bulutZamani = bulutZamanlari[gid];
        if (bulutZamani == null) return true; // bulut'ta hiç yoksa gönder
        final yerelZamani = KolonHaritalama.utcZaman(yerelLu);
        if (yerelZamani == null) return true;
        // Bulut ZATEN daha yeni ya da eşitse GÖNDERME (üzerine yazma).
        return yerelZamani.isAfter(bulutZamani);
      }).toList();
    } catch (_) {
      return batch; // kontrol başarısız olursa eski (güvenli) davranışa dön
    }
  }

  /// Bu cihazın yerel veritabanını buluta gönderir — ekranlar/sağlayıcılar
  /// Veritabani()'na dokunmadan bunu çağırır.
  static Future<SyncSonuc> yerelBulutaGonder({
    void Function(String)? log,
    bool sadeceDegisenler = true,
  }) {
    final db = Veritabani();
    return bulutaGonder(
      veriGetir: (t, f) => db.supaTumKayitlariGetirTemiz(t, f),
      log: log,
      sadeceDegisenler: sadeceDegisenler,
    );
  }

  /// Buluttaki veriyi bu cihazın yerel veritabanına alır.
  static Future<SyncSonuc> yerelBuluttanAl({
    void Function(String)? log,
    bool sadeceDegisenler = true,
    Set<String>? sadeceTablolar,
  }) {
    final db = Veritabani();
    return buluttanAl(
      kayitEkle: (t, k) => db.supaKayitlariEkle(t, k),
      kayitGuncelle: (t, k) => db.supaKayitlariGuncelle(t, k),
      sadeceDegisenler: sadeceDegisenler,
      sadeceTablolar: sadeceTablolar,
      log: log,
    );
  }

  static Future<SyncSonuc> bulutaGonder({
    required Future<List<Map<String, dynamic>>> Function(String, bool) veriGetir,
    void Function(String)? log,
    // Delta sync: true ise sadece son senkronizasyondan bu yana
    // değişen kayıtlar gönderilir — çok daha hızlı çalışır.
    // false ise TÜM kayıtlar gönderilir (ilk kurulum için).
    bool sadeceDegisenler = true,
  }) async {
    final ayar = await _ayarGetir();
    if (ayar == null) {
      return SyncSonuc()..hatalar.add('Bağlantı bilgileri yok');
    }

    final cId  = await cihazId();
    final now  = DateTime.now().toUtc().toIso8601String();
    final sonuc = SyncSonuc();

    // 🔴 KRİTİK DÜZELTME (FK remap — GÖNDERME yönü): Önceden çocuk
    // tabloların FK kolonları (satis_kalem.satis_id, masa_siparis_kalem
    // .siparis_id vb.) buluta LOKAL id olarak gidiyordu. Buluttaki
    // BIGSERIAL id'ler lokal id'lerle alakasız olduğundan, indiren
    // cihaz (indirme yönündeki remap bu değeri "bulut id" sanır) kalemi
    // YANLIŞ parent'a bağlayabiliyordu — tek cihaz + boş buluttan
    // başlanmışsa sayılar şans eseri hizalı gittiği için fark
    // edilmiyordu, silme/ikinci cihaz girince sessizce bozuluyordu.
    // Artık gönderim öncesi: lokal_id → (lokal global_id) →
    // (buluttaki id) dönüşümü yapılıyor. Parent tablolar _tabloSirasi
    // gereği çocuklardan ÖNCE gönderildiği için, parent gönderimi
    // sonrası cache tazelenerek yeni eklenen parent'ların bulut id'leri
    // de görülebiliyor.
    final gidCloudCache = <String, Map<String, int>>{};   // parent → {gid: cloudId}
    final lokalGidCache = <String, Map<int, String>>{};   // parent → {lokalId: gid}
    final fkParentlar = _tabloSirasi.expand(KolonHaritalama.ebeveynler).toSet();

    for (final tablo in _tabloSirasi) {
      try {
        log?.call('📤 $tablo...');
        // Delta sync: sadeceDegisenler=true ise sadece son
        // senkronizasyondan bu yana değişen kayıtları gönder.
        DateTime? sonSenkronZamani;
        if (sadeceDegisenler && _lastUpdatedVar.contains(tablo)) {
          sonSenkronZamani = await _sonSenkron(tablo, 'gonder');
        }
        List<Map<String, dynamic>> rows = await veriGetir(tablo, _softDelete.contains(tablo));
        if (sonSenkronZamani != null) {
          rows = rows.where((r) {
            final lu = r['last_updated'];
            if (lu == null) return true;
            final luDate = KolonHaritalama.utcZaman(lu);
            return luDate != null && luDate.isAfter(sonSenkronZamani!);
          }).toList();
        }
        if (rows.isEmpty) { log?.call('   boş/değişim yok'); continue; }

        // sqflite sorgu sonuçları SALT-OKUNUR map'lerdir — hem backfill
        // hem sonraki adımlar için değiştirilebilir kopyaya çevriliyor.
        rows = rows.map((r) => Map<String, dynamic>.from(r)).toList();

        // Görünürlük: kullanıcı "stok_hareket'te 10 dakikadır bekliyor"
        // bildirdi ama loglar tablo İÇİ aşamaları göstermiyordu (tek
        // batch'lik küçük tablolarda ⏳ ilerleme logu da devreye
        // girmiyor). Artık her aşama loglanıyor — takılma olursa TAM
        // yeri anında görülür.
        log?.call('▶ $tablo: ${rows.length} kayıt hazırlanıyor...');

        // 🔴🔴 KÖK NEDEN DÜZELTMESİ (bulut şişmesi / id=12504 kanıtı):
        // Bazı tabloların (özellikle stok_hareket) lokal insert'lerinde
        // global_id HİÇ atanmıyordu. _hazirla, boş global_id'ye her
        // sync'te YENİ bir Uuid üretiyordu ama bunu LOKALE GERİ
        // YAZMIYORDU → aynı kayıt her gönderimde FARKLI kimlikle
        // gidiyor, on_conflict hiç eşleşmiyor, bulut her sync'te
        // ÇOĞALIYORDU (kullanıcının bulutunda 50 lokal kayda karşılık
        // id 12504'e ulaşmış satırlar!). Ayrıca last_updated de boş
        // olduğundan delta filtresi bu tabloda hiç çalışmıyor, her
        // sync TÜM kayıtları gönderiyordu. Artık: gönderimden önce
        // boş global_id'lere KALICI kimlik üretilip lokale yazılıyor
        // (bundan sonra hep aynı kimlikle gider), boş last_updated'e
        // tek seferlik damga vuruluyor (delta çalışır hale gelir).
        final uniqueAlanOnKontrol = _uniqueAlan[tablo];
        if (uniqueAlanOnKontrol == 'global_id') {
          final localDb = await Veritabani().db;
          // Önce kimlik/damga eksik kayıtları tespit et (bellekte, hızlı)
          final eksikler = <Map<String, dynamic>>[];
          for (final r in rows) {
            final gidBos = r['global_id'] == null ||
                r['global_id'].toString().isEmpty;
            final luBos = r['last_updated'] == null;
            if ((gidBos || luBos) && r['id'] != null) {
              if (gidBos) r['global_id'] = const Uuid().v4();
              if (luBos) r['last_updated'] = now;
              eksikler.add(r);
            }
          }
          if (eksikler.isNotEmpty) {
            log?.call('   ↳ ${eksikler.length} kayda kalıcı kimlik atanıyor (tek seferlik)...');
            final b = localDb.batch();
            for (final r in eksikler) {
              b.update(tablo,
                  {'global_id': r['global_id'], 'last_updated': r['last_updated']},
                  where: 'id = ?', whereArgs: [r['id']]);
            }
            var kalici = false;
            try {
              await b.commit(noResult: true);
              // 🔴 ÇELİK KORUMA — kalıcılık DOĞRULAMASI: Kullanıcının
              // bulutunda "kimliksiz=0, mükerrer=0 ama toplam sürekli
              // artıyor" görüldü — yani kayıtlar her turda YENİ
              // kimliklerle gidiyordu (kimlikler lokale kalıcı
              // OLMUYORDU). Artık yazımdan sonra örnek bir kayıt geri
              // OKUNARAK doğrulanıyor; kalıcı değilse bu tablo BU
              // TURDA GÖNDERİLMEZ (kalıcı olmayan kimlikle göndermek =
              // bulutta bir daha eşleşmeyecek satır = şişme).
              final kontrol = await localDb.query(tablo,
                  columns: ['global_id'],
                  where: 'id = ?', whereArgs: [eksikler.first['id']], limit: 1);
              kalici = kontrol.isNotEmpty &&
                  kontrol.first['global_id'] == eksikler.first['global_id'];
            } catch (_) {
              kalici = false;
            }
            if (kalici) {
              log?.call('   ↳ kimlik ataması tamam ✓ (kalıcılık doğrulandı)');
            } else {
              final hata = '❌ $tablo: kimlik ataması LOKALE YAZILAMADI — '
                  'bulut şişmesin diye bu tablo BU TURDA ATLANDI';
              sonuc.hatalar.add(hata);
              log?.call(hata);
              continue; // tabloyu gönderme!
            }
          }
        }


        final veriler = rows
            .map((r) => _hazirla(r, tablo, cId, now))
            .toList();

        // FK remap (lokal id → bulut id) — açıklama için döngü
        // öncesindeki 🔴 nota bakın.
        var fkBekletilen = 0;
        if (KolonHaritalama.ebeveynler(tablo).isNotEmpty) {
          log?.call('   ↳ ilişki (FK) dönüşümü...');
          final fkBaslangic = DateTime.now();
          final bekle = await _fkLocalToCloudDonustur(
              ayar, tablo, veriler, gidCloudCache, lokalGidCache, log);
          if (bekle.isNotEmpty) {
            // Yanlış kayda bağlanmasın diye bu tur gönderilmez; filigran
            // da ilerletilmez ki bir sonraki "Hızlı Gönder" onları alsın.
            fkBekletilen = bekle.length;
            veriler.removeWhere(bekle.contains);
          }
          final fkSure = DateTime.now().difference(fkBaslangic).inSeconds;
          if (fkSure > 3) log?.call('   ↳ FK dönüşümü $fkSure sn sürdü');
        }

        final uniqueAlan = _uniqueAlan[tablo];
        int atlandi = 0;

        if (uniqueAlan != null) {
          int basarili = 0;
          int batchHatasi = 0;
          const batchSize = 100;
          final toplamBatch = (veriler.length / batchSize).ceil();
          for (int i = 0; i < veriler.length; i += batchSize) {
            var batch = veriler.sublist(i, (i + batchSize).clamp(0, veriler.length));
            final oncekiBoyut = batch.length;
            final batchNo = (i ~/ batchSize) + 1;

            // 🔴 KULLANICI GERİ BİLDİRİMİ ("stok hareketlere geliyor,
            // orada bekliyor"): Büyük tablolarda (stok_hareket en
            // kalabalık tablodur — her satış kalemi bir hareket üretir)
            // yüzlerce batch dakikalarca sürüyor ama tablo BİTENE KADAR
            // hiç log yazılmıyordu — kullanıcı donduğunu sanıyordu.
            // Artık her 5 batch'te canlı ilerleme gösteriliyor.
            if (toplamBatch > 5 && (batchNo == 1 || batchNo % 5 == 0)) {
              log?.call('⏳ $tablo: ${(i + batch.length).clamp(0, veriler.length)}'
                  '/${veriler.length} işleniyor...');
            }

            try {
              // ÖNCEDEN BURADA CİDDİ BİR ÇAKIŞMA (CONFLICT) HATASI VARDI:
              // iki cihaz AYNI kaydı neredeyse aynı anda değiştirirse,
              // hangi cihazın isteği bulut'a DAHA SONRA ULAŞIRSA o
              // kazanıyordu. Artık göndermeden ÖNCE bulut'taki mevcut
              // last_updated değerleri kontrol ediliyor; bulut'ta ZATEN
              // daha yeni bir kayıt varsa gönderilmiyor.
              batch = await _cakismaFiltrele(ayar, tablo, batch, uniqueAlan);
              atlandi += oncekiBoyut - batch.length;
              if (batch.isEmpty) continue;

              final normalizedBatch = _normalizeBatch(batch);
              // 🔴🔴🔴 KESİN KÖK NEDEN (GitHub supabase-js #1653'te
              // resmi olarak doğrulandı — "DEFAULT is not allowed in
              // this context", 42601): `columns` URL parametresi
              // belirtilmezse PostgREST, payload'da olmayan sütunları
              // da işleme dahil etmeye çalışıp "DEFAULT" anahtar
              // kelimesini kullanmaya çalışıyor — bu bazı bağlamlarda
              // sözdizimi hatası veriyor. normalizedBatch zaten TÜM
              // kayıtları AYNI anahtar kümesine sahip hâle getirdiği
              // için, ilk kaydın anahtarları columns listesi olarak
              // kullanılabilir.
              final sutunlar = normalizedBatch.isNotEmpty
                  ? normalizedBatch.first.keys.map(Uri.encodeComponent).join(',')
                  : '';
              // on_conflict=$uniqueAlan ile gerçek UPSERT (bkz. önceki
              // düzeltme notları).
              //
              // 🔴 YENİ — YENİDEN DENEME + HATA İZOLASYONU: Önceden bir
              // batch'te ağ kopması (ClientException/Timeout) olursa
              // exception TÜM TABLONUN kalan batch'lerini iptal ediyordu
              // → bir sonraki sync aynı dev yükü BAŞTAN deniyordu →
              // zayıf bağlantıda tablo asla bitmiyordu (kullanıcının
              // loglarındaki "Software caused connection abort" döngüsü).
              // Artık: her batch 2 kez denenir (arada 2 sn bekleyerek);
              // yine de başarısızsa YALNIZCA o batch hata sayılır,
              // SONRAKİ batch'ler devam eder. Kısmi ilerleme KALICIDIR:
              // bir sonraki sync'te _cakismaFiltrele, zaten gönderilmiş
              // kayıtları (bulut last_updated artık >= yerel olduğu
              // için) otomatik eler ve kaldığı yerden hızla devam eder.
              http.Response? res;
              for (int deneme = 1; deneme <= 2; deneme++) {
                try {
                  res = await http.post(
                    Uri.parse('${ayar.rest}/$tablo?on_conflict=$uniqueAlan&columns=$sutunlar'),
                    headers: _upsertH(ayar.key),
                    body: jsonEncode(normalizedBatch),
                  ).timeout(const Duration(seconds: 30));
                  break;
                } catch (e) {
                  if (deneme == 2) rethrow;
                  log?.call('🔄 $tablo: bağlantı koptu, yeniden deneniyor...');
                  await Future.delayed(const Duration(seconds: 2));
                }
              }

              if (res!.statusCode >= 200 && res.statusCode < 300) {
                basarili += batch.length;
              } else {
                batchHatasi++;
                final hata = '❌ $tablo UPSERT ${res.statusCode}: '
                    '${res.body.substring(0, res.body.length.clamp(0, 200))}';
                sonuc.hatalar.add(hata);
                log?.call(hata);
              }
            } catch (e) {
              batchHatasi++;
              final hata = '❌ $tablo batch $batchNo/$toplamBatch: $e';
              sonuc.hatalar.add(hata);
              log?.call(hata);
              // devam — sonraki batch'ler denensin
            }
          }
          sonuc.eklenen[tablo] = basarili;
          // Delta güvenliği: tabloda EN AZ BİR batch hata aldıysa
          // senkron zamanı GÜNCELLENMEZ — gönderilemeyen kayıtlar bir
          // sonraki delta'da yeniden yakalanır (gönderilmiş olanlar
          // _cakismaFiltrele sayesinde tekrar gönderilmez).
          if (batchHatasi == 0 && fkBekletilen == 0) {
            await _senkronKaydet(tablo, 'gonder');
          } else {
            log?.call('⚠️ $tablo: $batchHatasi batch gönderilemedi — '
                'bir sonraki senkronda kaldığı yerden devam edilecek');
          }
        } else {
          int basarili = 0;
          int kayitHatasi = 0;
          for (final kayit in veriler) {
            // Kayıt bazlı hata izolasyonu — tek kaydın ağ hatası tüm
            // tabloyu (ve delta ilerlemesini) düşürmesin.
            try {
              final res = await http.post(
                Uri.parse('${ayar.rest}/$tablo'),
                headers: _insertH(ayar.key),
                body: jsonEncode(kayit),
              ).timeout(const Duration(seconds: 15));

              if (res.statusCode >= 200 && res.statusCode < 300) {
                basarili++;
              } else if (res.statusCode == 409) {
                basarili++; // insert-only log tablosunda 409 = zaten var
              } else {
                kayitHatasi++;
                sonuc.hatalar.add('❌ $tablo INSERT ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 150))}');
              }
            } catch (e) {
              kayitHatasi++;
              sonuc.hatalar.add('❌ $tablo INSERT: $e');
            }
            await Future.delayed(const Duration(milliseconds: 5));
          }
          sonuc.eklenen[tablo] = basarili;
          // Delta güvenliği (üstteki upsert dalıyla aynı mantık)
          if (kayitHatasi == 0 && fkBekletilen == 0) {
            await _senkronKaydet(tablo, 'gonder');
          } else {
            log?.call('⚠️ $tablo: $kayitHatasi kayıt gönderilemedi — '
                'bir sonraki senkronda yeniden denenecek');
          }
        }

        // NOT: _senkronKaydet artık YUKARIDA, her dalın kendi içinde ve
        // YALNIZCA tablo hatasız bittiyse çağrılıyor — önceden burada
        // koşulsuz çağrılıyordu, bu da hatalı tabloda bile senkron
        // zamanını güncelleyip GÖNDERİLEMEYEN kayıtların bir sonraki
        // delta'nın dışında kalmasına (sessiz veri kaybına) yol açardı.
        // Bu tablo başka tabloların FK parent'ıysa, bulut id cache'ini
        // temizle — az önce eklenen YENİ kayıtların bulut id'leri,
        // sonraki (çocuk) tablo işlenirken taze çekilebilsin.
        if (fkParentlar.contains(tablo)) {
          gidCloudCache.remove(tablo);
          lokalGidCache.remove(tablo);
        }
        log?.call('✅ $tablo: ${sonuc.eklenen[tablo]} gönderildi'
            '${atlandi > 0 ? " ($atlandi bulut'ta daha güncel olduğu için atlandı)" : ""}');
      } catch (e) {
        final hata = '❌ $tablo: $e';
        sonuc.hatalar.add(hata);
        log?.call(hata);
      }
    }

    log?.call('────────────────────────');
    log?.call('📊 ${sonuc.ozet}');
    return sonuc;
  }

  // --------------------------------------------------------------
  // FK DÖNÜŞÜMÜ — GÖNDERME YÖNÜ (lokal id → bulut id)
  // --------------------------------------------------------------
  /// Tek bir bulut tablosunun (global_id → bulut id) eşlemesini çeker.
  /// Bulut: eşleşme anahtarı → bulut id (anahtar: global_id ya da tablonun
  /// doğal anahtarı — bkz. KolonHaritalama.ebeveynAnahtari).
  static Future<Map<String, int>> _tekTabloGidCloud(
      _Ayar ayar, String tablo) async {
    final anahtar = KolonHaritalama.ebeveynAnahtari(tablo);
    final gidToCloud = <String, int>{};
    int offset = 0;
    // Güvenlik sınırı: sayfalama hiçbir koşulda 200 turdan
    // (200.000 kayıt) fazla dönemez — uç durumlarda (sunucunun
    // beklenmedik yanıtı) sonsuz döngüyü fiziksel olarak engeller.
    int guvenlikSayaci1 = 0;
    while (guvenlikSayaci1++ < 200) {
      final res = await http.get(
        Uri.parse('${ayar.rest}/$tablo?select=id,$anahtar&limit=1000&offset=$offset'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) break;
      final batch = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      if (batch.isEmpty) break;
      for (final r in batch) {
        final gid = r[anahtar]?.toString();
        final cid = r['id'];
        if (gid != null && gid.isNotEmpty && cid != null) {
          gidToCloud[gid] = cid is int ? cid : int.parse(cid.toString());
        }
      }
      if (batch.length < 1000) break;
      offset += 1000;
    }
    return gidToCloud;
  }

  /// Gönderilecek kayıtlardaki FK kolonlarını (lokal id) → (bulut id)
  /// olarak dönüştürür. Zincir: lokal id → lokal global_id → bulut id.
  /// Eşleşme bulunamazsa kolon OLDUĞU GİBİ bırakılır (eski davranış)
  /// ve log'a uyarı yazılır — parent bir sonraki senkronda buluta
  /// gidince, çocuk kaydın bir sonraki güncellemesi doğru id'yi yazar.
  /// Dönüş: ebeveyni henüz bulutta olmadığı için GÖNDERİLMEMESİ gereken
  /// kayıtlar (çağıran bunları bu turdan çıkarır, filigranı ilerletmez).
  static Future<Set<Map<String, dynamic>>> _fkLocalToCloudDonustur(
    _Ayar ayar,
    String tablo,
    List<Map<String, dynamic>> veriler,
    Map<String, Map<String, int>> gidCloudCache,
    Map<String, Map<int, String>> lokalGidCache,
    void Function(String)? log,
  ) async {
    final bekletilecek = Set<Map<String, dynamic>>.identity();
    final localDb = await Veritabani().db;

    Future<void> cacheHazirla(String parent) async {
      // 1) Lokal: id → global_id (cache'li)
      if (lokalGidCache[parent] == null) {
        final anahtar = KolonHaritalama.ebeveynAnahtari(parent);
        final rows = await localDb.query(parent, columns: ['id', anahtar]);
        final h = <int, String>{};
        for (final r in rows) {
          final id = r['id'] as int?;
          final gid = r[anahtar]?.toString();
          if (id != null && gid != null && gid.isNotEmpty) h[id] = gid;
        }
        lokalGidCache[parent] = h;
      }
      // 2) Bulut: global_id → bulut id (cache'li)
      if (gidCloudCache[parent] == null) {
        log?.call('   ↳ $parent bulut haritası çekiliyor...');
        gidCloudCache[parent] = await _tekTabloGidCloud(ayar, parent);
        log?.call('   ↳ $parent haritası hazır (${gidCloudCache[parent]!.length} kayıt)');
      }
    }

    int bulunamadi = 0, yerelYok = 0;
    for (final m in veriler) {
      // Satır bazlı: polimorfik referanslar (referans_id / fis_id) tür
      // sütununa göre farklı tabloya işaret eder (bkz. KolonHaritalama.
      // polimorfikFkHaritasi).
      final fkMap = KolonHaritalama.satirFkHaritasi(tablo, m);
      if (fkMap == null) continue;
      for (final entry in fkMap.entries) {
        final kolon = entry.key, parent = entry.value;
        final v = m[kolon];
        if (v == null) continue;
        final lid = v is int ? v : int.tryParse(v.toString());
        if (lid == null) continue;
        try {
          await cacheHazirla(parent);
          final gid = lokalGidCache[parent]![lid];
          if (gid == null) {
            // Ebeveyn yerelde yok — yerel id'yi göndermek buluttaki BAŞKA
            // bir kayda bağlardı (bkz. SupabaseSaglayici._fkDonustur).
            m[kolon] = null;
            yerelYok++;
            continue;
          }
          final cid = gidCloudCache[parent]![gid];
          if (cid != null) {
            m[kolon] = cid;
          } else {
            bekletilecek.add(m);
            bulunamadi++;
          }
        } catch (e) {
          log?.call('⚠️ $tablo.$kolon FK dönüşümü yapılamadı, kayıt bekletildi: $e');
          bekletilecek.add(m);
        }
      }
    }
    if (bulunamadi > 0) {
      log?.call('⚠️ $tablo: $bulunamadi ilişkide ebeveyn kayıt henüz bulutta '
          'yok — bu kayıtlar bekletildi (sonraki gönderimde gider)');
    }
    if (yerelYok > 0) {
      log?.call('⚠️ $tablo: $yerelYok ilişkide ebeveyn yerelde de yok — boş gönderildi');
    }
    return bekletilecek;
  }

  // --------------------------------------------------------------
  // ID HARİTASI (FK DÖNÜŞÜM İÇİN)
  // --------------------------------------------------------------
  /// 🔴🔴🔴 KULLANICI TARAFINDAN BULUNAN, GERÇEK BİR HATA: ÖNCEDEN ID
  /// haritası (cloud_id -> local_id) senkronizasyonun EN BAŞINDA, TEK
  /// SEFER kuruluyordu. Ama bir satış Cihaz A için YENİYSE (Cihaz A'da
  /// hiç yoksa), harita kurulduğu anda o satış henüz yerelde
  /// olmadığı için haritada YER ALAMIYORDU. Sonra satış eklenirdi
  /// (yeni bir yerel id alırdı), AMA satis_kalem işlenirken hâlâ ESKİ
  /// (o satışı içermeyen) harita kullanıldığı için, `localId` hiç
  /// bulunamıyor, kod da 'satis_id' alanını TAMAMEN SİLİYORDU —
  /// kalem hiçbir satışa bağlı olmadan "havada" kalıyor, kullanıcı
  /// "sadece tutar geliyor, ürünler gelmiyor" diye bunu fark etti. Bu
  /// fonksiyon, TEK BİR tablonun yerel eşlemesini, o tablonun kayıtları
  /// eklendikten HEMEN SONRA tazeler.
  static Future<void> _idHaritasiTabloGuncelle(
    String tablo,
    Map<String, Map<String, int>> bulutGidHaritasi,
    Map<String, Map<int, int>> idHaritasi,
  ) async {
    final gidToCloud = bulutGidHaritasi[tablo];
    if (gidToCloud == null || gidToCloud.isEmpty) return;
    try {
      final localDb = await Veritabani().db;
      final anahtar = KolonHaritalama.ebeveynAnahtari(tablo);
      final localRows = await localDb.query(tablo, columns: ['id', anahtar]);
      final harita = <int, int>{};
      for (final lr in localRows) {
        final gid = lr[anahtar]?.toString();
        if (gid == null) continue;
        final cloudId = gidToCloud[gid];
        final localId = lr['id'] as int?;
        if (cloudId != null && localId != null) harita[cloudId] = localId;
      }
      idHaritasi[tablo] = harita;
    } catch (_) {
      // Sessizce geç — bir sonraki genel senkronizasyonda düzelir
    }
  }

  // --------------------------------------------------------------
  // BULUTTAN AL
  // --------------------------------------------------------------

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 KRİTİK DÜZELTME — BULUT/YEREL SÜTUN KAYMASI KORUMASI
  //
  // SORUN: buluttanAl(), bulut satırını OLDUĞU GİBİ yerel tabloya
  // yazıyordu. Bulutta olup yerelde OLMAYAN bir sütun varsa SQLite
  // "no such column" fırlatıyor ve o tablonun TÜM partisi düşüyordu.
  //
  // Gerçek örnek (derin analizde bulundu): `_lastUpdatedVar` listesi
  // 8 tabloda 'last_updated' olduğunu varsayıyor ama yerel şemada bu
  // sütun HİÇ YOK (ne CREATE'te ne migrasyonda):
  //   fiyat_gecmis, irsaliye_kalem, promosyon_aksiyon, promosyon_kosul,
  //   rol_yetkileri, zaman_fiyat
  //   (+ garson_cagri_log, masa_hareket_log → taze kurulumda yok)
  // Gönderirken kod bu sütunu ekliyor, bulut saklıyor, ÇEKERKEN yerel
  // tablo kabul etmiyor → "Hızlı Al"/"Tam Al" bu 8 tabloda hiç
  // çalışmıyordu (hata log'a düşüyor ama sonuç kartı yeşil görünüyor).
  //
  // ÇÖZÜM: yerel tablonun GERÇEK sütunları PRAGMA ile okunup, bulut
  // satırındaki fazlalıklar atılıyor. Bu, gelecekteki her bulut/yerel
  // kayması için de kalıcı koruma sağlar.
  // ══════════════════════════════════════════════════════════════════════
  static final Map<String, Set<String>> _yerelKolonOnbellek = {};

  static Future<Set<String>> _yerelKolonlar(dynamic localDb, String tablo) async {
    final onbellek = _yerelKolonOnbellek[tablo];
    if (onbellek != null) return onbellek;
    try {
      final rows = await localDb.rawQuery('PRAGMA table_info($tablo)');
      final k = rows
          .map<String>((r) => (r['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      _yerelKolonOnbellek[tablo] = k;
      return k;
    } catch (_) {
      // PRAGMA okunamadıysa filtreleme yapma (eski davranış)
      return <String>{};
    }
  }

  static final Map<String, Set<String>> _yerelZorunluKolonOnbellek = {};

  /// Hangi yerel sütunların NOT NULL olduğunu döner (PRAGMA table_info'nun
  /// 'notnull' alanı). FK çözümlenemediğinde: sütun ZORUNLU değilse sadece
  /// o sütunu at (eski davranış); ZORUNLU ise satırın TAMAMINI atla —
  /// aksi halde NOT NULL ihlali tüm toplu ekleme işlemini (batch) kırar.
  static Future<Set<String>> _yerelZorunluKolonlar(dynamic localDb, String tablo) async {
    final onbellek = _yerelZorunluKolonOnbellek[tablo];
    if (onbellek != null) return onbellek;
    try {
      final rows = await localDb.rawQuery('PRAGMA table_info($tablo)');
      final k = rows
          .where((r) => (r['notnull'] as int? ?? 0) == 1 && (r['dflt_value']) == null)
          .map<String>((r) => (r['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      _yerelZorunluKolonOnbellek[tablo] = k;
      return k;
    } catch (_) {
      return <String>{};
    }
  }

  // 🔴 Derin analizde bulundu: buluttanAl() üç ayrı yerden tetiklenebiliyor
  // (masa siparişi 5sn'lik oto-senkron, dashboard açılışı, manuel "Tam Al"
  // butonu). İki çağrı ÇAKIŞIRSA: her ikisi de aynı satırı "yerelde yok"
  // (yeni) olarak sınıflandırabilir, ardından supaKayitlariEkle'nin
  // ConflictAlgorithm.replace'i last_updated karşılaştırması YAPMADAN
  // birinin yazdığı satırın üzerine sessizce yazabilir — supaKayitlariEkle
  // yolunda supaKayitlariGuncelle'deki LWW/çakışma-kaydı koruması yok.
  // En sağlam çözüm: aynı anda tek bir buluttanAl() çalışmasına izin
  // vermek — ikinci çağrı yeni bir tarama başlatmak yerine devam eden
  // taramanın sonucunu bekleyip paylaşır.
  static Future<SyncSonuc>? _aktifBuluttanAl;
  static bool _aktifKismi = false;

  @visibleForTesting
  static Future<DateTime?> sunucuZamaniFiligraniTest(String tablo) =>
      _sunucuZamaniFiligrani(tablo);

  @visibleForTesting
  static Future<void> cekimFiligraniKaydetTest(
          String tablo, List<Map<String, dynamic>> kayitlar) =>
      _cekimFiligraniKaydet(tablo, kayitlar);

  /// Tam senkron tablo sırası (test: ebeveynler çocuklardan önce mi).
  @visibleForTesting
  static List<String> get tabloSirasiTest => List.unmodifiable(_tabloSirasi);

  static Future<SyncSonuc> buluttanAl({
    required Future<void> Function(String, List<Map<String, dynamic>>) kayitEkle,
    required Future<void> Function(String, List<Map<String, dynamic>>) kayitGuncelle,
    bool sadeceDegisenler = true,
    Set<String>? sadeceTablolar,
    void Function(String)? log,
  }) {
    final kismi = sadeceTablolar != null;
    final devamEden = _aktifBuluttanAl;
    if (devamEden != null) {
      // Yalnız tam+tam çakışması paylaşılır. Kısmi istek (anlık bildirim /
      // masa) devam eden çekimin sonucuna BAĞLANMAZ: o çekim ilgili tabloyu
      // çoktan geçmiş olabilir ve yeni gelen kayıt bir sonraki turu beklerdi.
      if (!kismi && !_aktifKismi) return devamEden;
      Future<SyncSonuc> sonra() => buluttanAl(
            kayitEkle: kayitEkle,
            kayitGuncelle: kayitGuncelle,
            sadeceDegisenler: sadeceDegisenler,
            sadeceTablolar: sadeceTablolar,
            log: log,
          );
      return devamEden.then<SyncSonuc>((_) => sonra(), onError: (_) => sonra());
    }
    final gelecek = _buluttanAlCalistir(
      kayitEkle: kayitEkle,
      kayitGuncelle: kayitGuncelle,
      sadeceDegisenler: sadeceDegisenler,
      sadeceTablolar: sadeceTablolar,
      log: log,
    );
    _aktifBuluttanAl = gelecek;
    _aktifKismi = kismi;
    gelecek.whenComplete(() {
      if (identical(_aktifBuluttanAl, gelecek)) _aktifBuluttanAl = null;
    });
    return gelecek;
  }

  static Future<SyncSonuc> _buluttanAlCalistir({
    required Future<void> Function(String, List<Map<String, dynamic>>) kayitEkle,
    required Future<void> Function(String, List<Map<String, dynamic>>) kayitGuncelle,
    bool sadeceDegisenler = true,
    Set<String>? sadeceTablolar,
    void Function(String)? log,
  }) async {
    final ayar = await _ayarGetir();
    if (ayar == null) {
      return SyncSonuc()..hatalar.add('Bağlantı bilgileri yok');
    }

    final sonuc = SyncSonuc();
    // 🔴 PERFORMANS (2026-09-27): eşlemeler ÖNCEDEN her çekimin başında
    // 25 ebeveyn tablonun TAMAMI için buluttan İKİ KEZ indiriliyordu
    // (_bulutGidHaritasiCek + _idHaritasiOlustur aynı sorguyu yapıyordu) —
    // masa ekranı 15 sn'de bir çektiği için veri büyüdükçe ciddi yük.
    // Artık bir ebeveyn tablonun eşlemesi yalnızca o tabloya referans
    // veren bir satır geldiğinde, tek sefer indirilir. Değişiklik yoksa
    // hiç indirilmez.
    final bulutGidHaritasi = <String, Map<String, int>>{};
    final idHaritasi = <String, Map<int, int>>{};
    Future<Map<int, int>> idHaritasiGetir(String parent) async {
      final hazir = idHaritasi[parent];
      if (hazir != null) return hazir;
      try {
        bulutGidHaritasi[parent] ??= await _tekTabloGidCloud(ayar, parent);
        await _idHaritasiTabloGuncelle(parent, bulutGidHaritasi, idHaritasi);
      } catch (e) {
        log?.call('⚠️ $parent id haritası kurulamadı: $e');
      }
      return idHaritasi[parent] ??= <int, int>{};
    }
    // Bu turda buluttan GÜNCELLENEREK gelen satışlar — kalemleri başka
    // cihazda değişmiş olabilir (fiş güncelleme), sonda mutabakat yapılır.
    final guncellenenSatisGidleri = <String>{};

    for (final tablo in _tabloSirasi) {
      // İade başlığı çekilirken kalemleri de kontrol edilir: kalemler başlıktan
      // ÖNCE/ARAYA çekilip yarım kalabilir (bkz. eksikIadeKalemleriniTamamla).
      if (sadeceTablolar != null &&
          !sadeceTablolar.contains(tablo) &&
          !(tablo == 'iade_kalem' && sadeceTablolar.contains('iade'))) {
        continue;
      }
      try {
        log?.call('📥 $tablo...');

        // 🔴 Bulut Veri Güvenliği Raporu 2026-10-07, Bulgu 1: filigran
        // ÖNCEDEN istemci damgası last_updated'e dayanıyordu — çevrimdışı
        // kasanın kayıtları (eski damgalı) diğer kasaların ileri gitmiş
        // filigranının gerisinde kalıp HİÇ inmiyordu. Bulutta sunucu_zamani
        // (sunucunun yazma anı, tetikleyici) varsa çekim ona göre yapılır;
        // yoksa (SQL henüz çalıştırılmadı) eski davranış sürer.
        final szKullan = !_sunucuZamaniYok.contains(tablo);
        final filigranAlani = szKullan ? 'sunucu_zamani' : 'last_updated';
        DateTime? sonSenkron;
        if (sadeceDegisenler && _lastUpdatedVar.contains(tablo) && szKullan) {
          sonSenkron = await _sunucuZamaniFiligrani(tablo);
        } else if (sadeceDegisenler && _lastUpdatedVar.contains(tablo)) {
          sonSenkron = await _sonSenkron(tablo, 'al');
          // Çevrimdışı kalıp geç senkronlanan kayıtlar, kendi (eski)
          // last_updated damgalarıyla buluta düşer ve imleçten önce kaldığı
          // için "gt" filtresinde hiç inmezdi. Uygulama oturumundaki İLK
          // çekimde her tablo için pencere 48 saat geri açılır (LWW
          // korumalı upsert tekrar inen satırlar için zararsızdır).
          if (sonSenkron != null && _genisPencereYapilanlar.add(tablo)) {
            sonSenkron = sonSenkron.subtract(const Duration(hours: 48));
          }
        }

        final tumKayitlar = <Map<String, dynamic>>[];
        int offset = 0;

        // Güvenlik sınırı: sayfalama hiçbir koşulda 200 turdan
        // (200.000 kayıt) fazla dönemez — uç durumlarda (sunucunun
        // beklenmedik yanıtı) sonsuz döngüyü fiziksel olarak engeller.
        int guvenlikSayaci4 = 0;
        while (guvenlikSayaci4++ < 200) {
          var endpoint = '${ayar.rest}/$tablo?limit=500&offset=$offset';
          if (sonSenkron != null) {
            endpoint += '&$filigranAlani=gt.'
                '${Uri.encodeComponent(sonSenkron.toUtc().toIso8601String())}';
            // id tie-breaker: eşit damgalı (toplu now) satırlar offset sayfa
            // sınırında atlanmasın/tekrarlanmasın.
            endpoint += '&order=$filigranAlani.asc,id.asc';
          } else {
            endpoint += '&order=id.asc';
          }

          final res = await http
              .get(Uri.parse(endpoint), headers: _getH(ayar.key))
              .timeout(const Duration(seconds: 30));

          if (res.statusCode == 404) break;
          if (szKullan && sonSenkron != null && res.statusCode == 400 &&
              res.body.contains('sunucu_zamani')) {
            // Bulutta sütun yok (supabase_tam_sema.sql Bölüm H çalıştırılmadı) —
            // bu tablo için eski (last_updated) yönteme düşülür; sonraki
            // çekimde o yolla alınır.
            _sunucuZamaniYok.add(tablo);
            sonuc.hatalar.add('⚠️ $tablo: bulutta sunucu_zamani yok — '
                'supabase_tam_sema.sql (Bölüm H) çalıştırılmalı (bir sonraki çekimde eski yöntem)');
            break;
          }
          if (res.statusCode != 200) {
            if (res.statusCode != 406) {
              sonuc.hatalar.add('❌ $tablo GET ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 100))}');
            }
            break;
          }

          final batch = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
          if (batch.isEmpty) break;
          tumKayitlar.addAll(batch);
          if (batch.length < 500) break;
          offset += 500;
        }

        // Yarım inmiş iade kalemlerini imleçten BAĞIMSIZ tamamla.
        if (tablo == 'iade_kalem') {
          try {
            final var_ = tumKayitlar.map((k) => k['global_id']?.toString()).toSet();
            for (final k in await _eksikIadeKalemleriniGetir(ayar, bulutGidHaritasi)) {
              if (var_.add(k['global_id']?.toString())) tumKayitlar.add(k);
            }
          } catch (e) {
            log?.call('⚠️ eksik iade kalemi kontrolü atlandı: $e');
          }
        }

        if (tumKayitlar.isEmpty) {
          log?.call('   değişiklik yok');
          await _senkronKaydet(tablo, 'al');
          continue;
        }

        final db      = Veritabani();
        final localDb = await db.db;
        final yeni    = <Map<String, dynamic>>[];
        final guncel  = <Map<String, dynamic>>[];

        // FK haritası artık satır bazlı (polimorfik referanslar — bkz.
        // KolonHaritalama.polimorfikFkHaritasi), aşağıda her satırda çözülür.

        // Yerel tablonun gerçek sütunları — bulut fazlalıklarını atmak için
        final yerelKolonSeti = await _yerelKolonlar(localDb, tablo);
        // 🔴 Derin analizde bulundu ("satış hareketleri buluttan tam
        // almada hatalı"): FK çözümlenemeyince sütun sessizce
        // atılıyordu. Sütun NOT NULL ise (ör. satis_kalem.urun_id,
        // satis_kalem.satis_id) bu, tüm satırı değil TEK bir alanı
        // eksik bırakıyor, INSERT NOT NULL ihlaliyle patlıyordu — ve
        // sqflite'ın toplu ekleme (batch) işlemi varsayılan olarak İLK
        // hatada durduğu için, tek bir çözülemeyen ürün/satış referansı
        // O TABLONUN TÜM "tam al" turunu (yüzlerce kayıt) iptal
        // ediyordu. Artık hangi sütunların zorunlu olduğu önceden
        // biliniyor.
        final zorunluKolonSeti = await _yerelZorunluKolonlar(localDb, tablo);

        var atlananFk = 0;
        var yetimAtlanan = 0;
        for (final r in tumKayitlar) {
          final m = Map<String, dynamic>.from(r);
          m.remove('id');

          // 🔴 Bulutta olup yerelde OLMAYAN sütunları at.
          // (Boş set = PRAGMA okunamadı → filtreleme yapma.)
          if (yerelKolonSeti.isNotEmpty) {
            m.removeWhere((k, _) => !yerelKolonSeti.contains(k));
          }

          for (final k in m.keys.toList()) {
            if (m[k] is bool) m[k] = (m[k] as bool) ? 1 : 0;
            if (m[k] == null) m.remove(k);
          }

          var atlaSatir = false;
          final fkHaritasi = KolonHaritalama.satirFkHaritasi(tablo, m);
          if (fkHaritasi != null) {
            for (final entry in fkHaritasi.entries) {
              final kolon = entry.key, parentTablo = entry.value;
              final cloudVal = m[kolon];
              if (cloudVal == null) {
                // Bulutta zorunlu FK'sı BOŞ olan satır yetimdir (gönderen
                // cihazda ebeveyn silinmiş/yoktu); hiçbir turda düzelmez,
                // yazılırsa NOT NULL ihlaliyle tüm tabloyu hataya düşürür.
                if (zorunluKolonSeti.contains(kolon)) {
                  atlaSatir = true;
                  yetimAtlanan++;
                  break;
                }
                continue;
              }
              final cloudId = cloudVal is int ? cloudVal : int.tryParse(cloudVal.toString());
              if (cloudId == null) continue;
              final localId = (await idHaritasiGetir(parentTablo))[cloudId];
              if (localId != null) {
                m[kolon] = localId;
              } else if (zorunluKolonSeti.contains(kolon)) {
                // Zorunlu bir FK çözülemedi — bu satırı ekleme, ama
                // TÜM tabloyu iptal ETME. (ör. ürünü silinmiş bir
                // satışın kalemi: o kalem atlanır, sipariş/satışın
                // geri kalanı ve tablonun diğer kayıtları kaybolmaz.)
                atlaSatir = true;
                atlananFk++;
                break;
              } else {
                m.remove(kolon);
              }
            }
          }
          if (atlaSatir) continue;

          final gid = m['global_id']?.toString();
          if (gid != null && gid.isNotEmpty) {
            try {
              final existing = await localDb.query(
                tablo,
                where: 'global_id = ?',
                whereArgs: [gid],
                limit: 1,
              );
              if (existing.isNotEmpty) {
                if (_silinmisMi(tablo, m)) {
                  // 🔴 DÜZELTME: Önceden HER ZAMAN {'is_deleted': 1}
                  // yazılıyordu — 'deleted_at'/'aktif' kullanan
                  // tablolarda (faturalar, giderler, irsaliyeler,
                  // promosyonlar, markalar) bu ya YANLIŞ bir sütun
                  // yazmaya çalışırdı (SQL hatası) ya da hiçbir şey
                  // yapmazdı. Artık doğru sütun/değer kullanılıyor.
                  final kolon = _softDeleteKolonu[tablo]!;
                  final deger = kolon == 'aktif'
                      ? 0
                      : (kolon == 'deleted_at' ? (m['deleted_at'] ?? DateTime.now().toIso8601String()) : 1);
                  await localDb.update(tablo, {kolon: deger},
                      where: 'global_id = ?', whereArgs: [gid]);
                  sonuc.silinen[tablo] = (sonuc.silinen[tablo] ?? 0) + 1;
                } else {
                  guncel.add(m);
                }
              } else {
                if (!_silinmisMi(tablo, m)) {
                  yeni.add(m);
                }
              }
            } catch (_) {
              yeni.add(m);
            }
          } else {
            yeni.add(m);
          }
        }

        if (yeni.isNotEmpty) {
          await kayitEkle(tablo, yeni);
          sonuc.eklenen[tablo] = yeni.length;
        }
        if (guncel.isNotEmpty) {
          await kayitGuncelle(tablo, guncel);
          sonuc.guncellenen[tablo] = guncel.length;
          if (tablo == 'satislar') {
            for (final g in guncel) {
              final gid = g['global_id']?.toString();
              if (gid != null && gid.isNotEmpty) guncellenenSatisGidleri.add(gid);
            }
          }
        }

        // 🔴 KRİTİK: Bu tablo bir "ebeveyn" tablosuysa (cari, urunler,
        // satislar, iade, masalar), kayıtlar eklendikten HEMEN SONRA
        // ID haritası tazeleniyor — böylece bu tabloya bağımlı olan
        // SONRAKİ tablolar (ör. satis_kalem, satislar'a bağımlı),
        // BİRAZ ÖNCE eklenen YENİ kayıtların doğru yerel ID'sini
        // bulabiliyor. Önceden harita sadece başta kuruluyordu, bu
        // yüzden yeni satışların kalemleri "satis_id" alanını hiç
        // bulamayıp kayboluyordu.
        await _idHaritasiTabloGuncelle(tablo, bulutGidHaritasi, idHaritasi);

        log?.call('✅ $tablo: +${yeni.length} ~${guncel.length} -${sonuc.silinen[tablo] ?? 0}');
        if (yetimAtlanan > 0) {
          log?.call('ℹ️ $tablo: $yetimAtlanan yetim satır (bulutta ebeveyn bağı boş) atlandı');
        }
        // Filigran CİHAZ SAATİNDEN değil, çekilen verideki en büyük
        // last_updated'ten ilerletilir (saat kayması veri kaybı koruması)
        // Ebeveyni yerelde bulunamayan (atlanan) çocuk satır varsa filigran
        // ilerletilmez: ebeveyn sonraki turda gelirse bu satırlar yeniden
        // çekilip yazılır (önceden kalıcı kalem kaybıydı). Ebeveyn hiç
        // gelmeyecekse (bulutta silinmiş) sonsuz döngüyü önlemek için 5
        // ardışık denemeden sonra filigran yine ilerler.
        final fkSayacAnahtar = 'mp_sync_fk_atla_$tablo';
        final prefs = await SharedPreferences.getInstance();
        if (atlananFk > 0) {
          final deneme = (prefs.getInt(fkSayacAnahtar) ?? 0) + 1;
          if (deneme < 5) {
            await prefs.setInt(fkSayacAnahtar, deneme);
            sonuc.hatalar.add(
                '⚠️ $tablo: $atlananFk satırın ebeveyni henüz yok — sonraki turda yeniden denenecek ($deneme/5)');
          } else {
            await prefs.remove(fkSayacAnahtar);
            sonuc.hatalar.add(
                '❌ $tablo: $atlananFk satır ebeveyn kaydı olmadığı için ATLANDI (5 deneme)');
            await _cekimFiligraniKaydet(tablo, tumKayitlar);
          }
        } else {
          await prefs.remove(fkSayacAnahtar);
          await _cekimFiligraniKaydet(tablo, tumKayitlar);
        }
      } catch (e) {
        final hata = '❌ $tablo: $e';
        sonuc.hatalar.add(hata);
        log?.call(hata);
      }
    }

    try {
      await _satisKalemMutabakati(
          ayar,
          guncellenenSatisGidleri,
          guncellenenSatisGidleri.isEmpty
              ? const <String, int>{}
              : (bulutGidHaritasi['satislar'] ??= await _tekTabloGidCloud(ayar, 'satislar')),
          log);
    } catch (e) {
      log?.call('⚠️ satış kalem mutabakatı atlandı: $e');
    }

    // Türetilmiş değerler (cari bakiye, stok, puan …) hareketlerden yeniden
    // hesaplanır — yalnızca bir şey indiyse (masa ekranı 15 sn'de bir çeker).
    // Çekim eksik/hatalıysa (ör. stok_hareket yarım indi) bu turda türetilmiş
    // değerler yeniden hesaplanıp buluta itilmez: eksik veriden hesaplanan
    // yanlış stok/bakiye doğru bulut değerini ezerdi.
    if (sadeceTablolar != null) {
      // Kısmi (masa) çekimde türetilmiş değer mutabakatı çalıştırılmaz;
      // tam çekim zaten periyodik yapılıyor.
    } else if (sonuc.hatalar.isNotEmpty) {
      log?.call('⚠️ çekimde hata var — türetilmiş değer mutabakatı atlandı');
    } else if (sonuc.toplamEklenen +
            sonuc.toplamGuncellenen +
            sonuc.toplamSilinen >
        0) {
      await SenkronSonrasiMutabakat.calistir(log: log);
    }

    log?.call('────────────────────────');
    log?.call('📊 ${sonuc.ozet}');
    return sonuc;
  }

  /// Yerelde kalem toplamı başlık tutarıyla UYUŞMAYAN (son 30 gün, iptal
  /// olmayan) iadelerin kalemlerini buluttan imleç gözetmeden getirir.
  ///
  /// Neden: kalemler tek tek yüklenirken başka cihaz çekerse yalnız ilk
  /// kalemleri alır; imleç ilerlediği için kalanlar bazen hiç inmez ve iade
  /// diğer cihazda eksik tutarla (ör. 2086,59 yerine 970,03) görünür. Bulut
  /// satırları LWW korumalı upsert'ten geçtiği için tekrar inmesi zararsızdır.
  static Future<List<Map<String, dynamic>>> _eksikIadeKalemleriniGetir(
    _Ayar ayar,
    Map<String, Map<String, int>> bulutGidHaritasi,
  ) async {
    final localDb = await Veritabani().db;
    final eksik = await localDb.rawQuery('''
      SELECT i.global_id AS gid
      FROM iade i LEFT JOIN iade_kalem k ON k.iade_id = i.id
      WHERE i.global_id IS NOT NULL AND i.durum != 'iptal'
        AND i.deleted_at IS NULL
        AND i.tarih >= date('now', '-30 day')
      GROUP BY i.id
      HAVING ABS(i.toplam_tutar - COALESCE(SUM(k.toplam), 0)) > 0.05
    ''');
    if (eksik.isEmpty) return const [];
    final harita = bulutGidHaritasi['iade'] ??= await _tekTabloGidCloud(ayar, 'iade');
    final bulutIdler = eksik
        .map((r) => harita[r['gid']?.toString()])
        .whereType<int>()
        .toList();
    final sonuc = <Map<String, dynamic>>[];
    for (var i = 0; i < bulutIdler.length; i += 50) {
      final dilim = bulutIdler.sublist(i, (i + 50).clamp(0, bulutIdler.length));
      final res = await http.get(
        Uri.parse('${ayar.rest}/iade_kalem?limit=1000&order=id.asc'
            '&iade_id=in.(${dilim.join(',')})'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) break;
      sonuc.addAll((jsonDecode(res.body) as List).cast<Map<String, dynamic>>());
    }
    return sonuc;
  }

  /// Başka cihazda güncellenen (fiş güncelleme: eski kalemler silinip
  /// yenileri yazılır) satışların, bulutta ARTIK OLMAYAN kalemlerini
  /// yerelden kaldırır. satis_kalem'de is_deleted olmadığı için silme
  /// normal çekimle gelemez; bu yapılmazsa bu cihaz eski+yeni kalemleri
  /// birlikte gösterir (detay/maliyet/ürün raporu şişer).
  ///
  /// Güvenlik: bu cihazda henüz gönderilmemiş kalem değişikliği olan
  /// satışlara dokunulmaz; bulutta hiç kalemi görünmeyen satış (okuma
  /// eksik/yetki sorunu olabilir) atlanır; okuma hatasında hiçbir şey
  /// silinmez.
  static Future<void> _satisKalemMutabakati(
    _Ayar ayar,
    Set<String> satisGidleri,
    Map<String, int> satisGidCloud,
    void Function(String)? log,
  ) async {
    if (satisGidleri.isEmpty) return;
    final localDb = await Veritabani().db;

    final kuyruktaki = (await localDb.query(DbSabitler.syncQueue,
            columns: ['kayit_global_id'], where: 'tablo_adi = ?', whereArgs: ['satis_kalem']))
        .map((r) => r['kayit_global_id']?.toString())
        .whereType<String>()
        .toSet();

    // yerel satış id → (bulut satış id, yerel kalemler)
    final hedefler = <int, ({int bulutId, List<Map<String, Object?>> kalemler})>{};
    for (final gid in satisGidleri) {
      final bulutId = satisGidCloud[gid];
      if (bulutId == null) continue;
      final s = await localDb.query('satislar',
          columns: ['id'], where: 'global_id = ?', whereArgs: [gid], limit: 1);
      if (s.isEmpty) continue;
      final yerelId = s.first['id'] as int;
      final kalemler = await localDb.query('satis_kalem',
          columns: ['id', 'global_id'], where: 'satis_id = ?', whereArgs: [yerelId]);
      if (kalemler.any((k) => kuyruktaki.contains(k['global_id']?.toString()))) continue;
      hedefler[yerelId] = (bulutId: bulutId, kalemler: kalemler);
    }
    if (hedefler.isEmpty) return;

    final bulutKalemleri = <int, Set<String>>{};
    final bulutIdler = hedefler.values.map((h) => h.bulutId).toList();
    for (var i = 0; i < bulutIdler.length; i += 100) {
      final dilim = bulutIdler.sublist(i, (i + 100).clamp(0, bulutIdler.length));
      final res = await http.get(
        Uri.parse('${ayar.rest}/satis_kalem?select=global_id,satis_id'
            '&satis_id=in.(${dilim.join(',')})'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return; // emin değilsek hiçbir şey silme
      for (final r in (jsonDecode(res.body) as List).cast<Map<String, dynamic>>()) {
        final sid = r['satis_id'];
        final g = r['global_id']?.toString();
        if (sid == null || g == null) continue;
        final id = sid is int ? sid : int.tryParse(sid.toString());
        if (id != null) bulutKalemleri.putIfAbsent(id, () => <String>{}).add(g);
      }
    }

    var silinen = 0;
    for (final h in hedefler.values) {
      final buluttaki = bulutKalemleri[h.bulutId];
      if (buluttaki == null || buluttaki.isEmpty) continue;
      for (final k in h.kalemler) {
        final g = k['global_id']?.toString();
        if (g == null || g.isEmpty || buluttaki.contains(g)) continue;
        await localDb.delete('satis_kalem', where: 'id = ?', whereArgs: [k['id']]);
        silinen++;
      }
    }
    if (silinen > 0) {
      log?.call('🧹 satis_kalem: başka cihazda fişten çıkarılmış $silinen kalem yerelden kaldırıldı');
    }
  }
}