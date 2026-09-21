// lib/servisler/ai/ai_sohbet_servisi.dart
// Tüm AI sohbet mantığı — doğru DB kolonları ile
import 'package:intl/intl.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/log_servisi.dart';
import 'ai_modeller.dart';
import 'ai_anlayici.dart';
import 'ai_rapor_servisi.dart';
import 'ai_genel_asistan.dart';
import 'ai_niyet_yonlendirici.dart';

/// AI Chat'in cevabı — normal metin cevabının yanı sıra, bir gezinme
/// komutu algılandıysa hedef rota + (varsa) arama terimini de taşır.
class AiSohbetSonuc {
  final String cevap;
  final String? rota;
  final String? aramaTerimi;
  const AiSohbetSonuc({required this.cevap, this.rota, this.aramaTerimi});
}

class AiSohbetServisi {
  static final AiSohbetServisi _i = AiSohbetServisi._();
  factory AiSohbetServisi() => _i;
  AiSohbetServisi._();

  static final _p = NumberFormat('#,##0.00', 'tr_TR');

  String? _sonUrun;
  String? _sonMusteri;

  // ÖNCEDEN: AI Chat SADECE soru-cevap yapıyordu, ekranlar arası hiçbir
  // gezinme (navigasyon) yeteneği yoktu — "ürün listesi ülker bisküviye
  // git" gibi bir komut sadece metin cevap alıp hiçbir yere gitmiyordu.
  // Artık "git/aç/göster" gibi kalıplar tanınıp gerçek rotaya + (varsa)
  // arama terimine dönüştürülüyor; ai_panel_ekrani.dart bu sonucu görüp
  // GERÇEKTEN o ekrana yönlendiriyor.
  // Dashboard'daki TÜM önemli ekranlardan derlendi — anahtar kelime en
  // UZUNDAN en KISAYA sıralanmalı (aşağıdaki döngü ilk eşleşeni seçer,
  // bu yüzden Map sırası önemli: "cari hareket" "cari"den önce olmalı
  // gibi düşünülerek en spesifik ifadeler üstte tutuldu).
  static const Map<String, String> _rotaKelimeleri = {
    // Satış
    'satış listesi': '/satis/liste', 'satis listesi': '/satis/liste',
    'iadeler': '/satis/iade', 'iade ekranı': '/satis/iade',
    'sıcak satış': '/satis/sicak', 'soğuk satış': '/satis/soguk',
    'hızlı satış': '/satis', 'satış ekranı': '/satis', 'kasiyer': '/satis',
    // Ürün
    'ürün ekle': '/urun/ekle', 'ürün eklemek': '/urun/ekle',
    'toplu işlem': '/urun/toplu-islem', 'toplu fiyat': '/urun/toplu-fiyat',
    'kategoriler': '/urun/kategori', 'markalar': '/urun/marka',
    'plu yönetimi': '/urun/plu', 'plu': '/urun/plu',
    'ürün listesi': '/urun', 'ürün liste': '/urun', 'ürünler': '/urun',
    // Stok
    'stok sayım': '/stok/sayim', 'stok hareket': '/stok/hareket',
    'depo transfer': '/stok/transfer',
    'lot': '/lot', 'seri takibi': '/lot', 'birimler': '/birim',
    'kritik stok': '/stok',
    'toplu döviz güncelle': '/urun/doviz-guncelle', 'döviz güncelle': '/urun/doviz-guncelle',
    'stok listesi': '/stok', 'stok': '/stok', 'depo': '/stok',
    // Masa/Restoran
    'mutfak': '/mutfak', 'bar ekranı': '/mutfak',
    'rezervasyon': '/rezervasyon', 'masa raporu': '/masa-rapor',
    'masalar': '/masa', 'masa listesi': '/masa',
    // Cari
    'cari ekle': '/cari/ekle',
    // Not: "Cari Hareket"/"Tahsilat" ekranları belirli bir cari ID'si
    // gerektirir (parametreli rota) — sesli komuttan doğrudan
    // açılamazlar, bu yüzden burada YOK; kullanıcı önce Cari Listesi'ne
    // gidip ilgili cariye tıklamalı.
    'cari listesi': '/cari', 'cari liste': '/cari', 'cariler': '/cari',
    'müşteri listesi': '/cari', 'müşteriler': '/cari', 'cari': '/cari',
    // Fatura / İrsaliye / Promosyon
    'fatura oluştur': '/fatura/yeni', 'fatura listesi': '/fatura',
    'faturalar': '/fatura', 'irsaliye': '/irsaliye',
    'gelen kutusu': '/fatura/gelen-kutusu', 'gelen fatura': '/fatura/gelen-kutusu',
    'promosyonlar': '/promosyon', 'promosyon ekle': '/promosyon',
    'kampanya': '/promosyon',
    // Banka / Kredi Kartı / Borç
    'banka hareketleri': '/banka-hareket', 'banka yönetimi': '/banka',
    'bankalar': '/banka', 'banka': '/banka',
    'kredi kartları': '/kredi-karti', 'kredi kartı': '/kredi-karti',
    'borç dashboard': '/borc-dashboard', 'borç ekle': '/borc-ekle',
    'borç takip': '/borc-takip', 'borçlar': '/borc-takip', 'borç': '/borc-takip',
    'mail bağlantısı': '/mail-baglanti',
    // Kasa / Gider
    'kasa raporu': '/kasa/rapor', 'kasa hareket': '/kasa/hareket',
    'virman': '/kasa/virman', 'kasa': '/kasa',
    'gider ekle': '/gider/ekle', 'giderler': '/gider', 'gider': '/gider',
    // Raporlar
    'günlük rapor': '/rapor/gunluk', 'satış raporu': '/rapor/satis',
    'kar zarar': '/rapor/kar', 'kâr zarar': '/rapor/kar',
    'stok raporu': '/rapor/stok', 'cari raporu': '/rapor/cari',
    // Diğer
    'ai analiz': '/ai', 'yapay zeka': '/ai', 'asistan': '/ai',
    'fiyat gör': '/fiyat-gor', 'fiyat sorgula': '/fiyat-gor',
    'tedarikçi sipariş': '/tedarik', 'mal alımı': '/tedarik/alim',
    'tedarik': '/tedarik', 'alım': '/tedarik',
    'etiket yazdır': '/barkod/etiket', 'etiket': '/barkod/etiket',
    'barkod üreteci': '/barkod/uret', 'barkod üret': '/barkod/uret',
    'yazıcı ayarları': '/ayarlar/yazici', 'yedekleme': '/ayarlar/yedek',
    'kullanıcılar': '/kullanici', 'kullanıcı listesi': '/kullanici',
    'personel': '/personel', 'çalışanlar': '/personel',
    'şubeler': '/sube', 'vardiya': '/vardiya',
    'bildirimler': '/bildirimler', 'sistem logları': '/ayarlar/log',
    'gib efatura': '/ayarlar/gib', 'gib e-fatura': '/ayarlar/gib',
    'fatura ayarları': '/ayarlar/fatura', 'fiş tasarımı': '/ayarlar/fis',
    'bulut senkronizasyon': '/ayarlar/bulut-sync',
    'ayarlar': '/ayarlar/icerik',
  };

  /// Metinde bir gezinme komutu var mı diye bakar. Varsa hedef rota +
  /// (varsa) "X'e git" kalıbındaki X'i arama terimi olarak döndürür.
  ({String rota, String? arama})? _navigasyonAlgila(String soru) {
    final s = soru.toLowerCase().trim();
    final gitKaliplari = ['git', 'aç', 'ac', 'göster', 'goster', 'gider misin'];
    final gecerliMi = gitKaliplari.any((k) => s.contains(k));
    if (!gecerliMi) return null;

    for (final entry in _rotaKelimeleri.entries) {
      final idx = s.indexOf(entry.key);
      if (idx == -1) continue;

      // "X'e git" kalıbındaki X'i (varsa) ayıkla: ekran adından SONRA
      // gelen ve "git/aç/göster" kelimesinden ÖNCE gelen kısım aranıyor.
      var kalan = s.substring(idx + entry.key.length).trim();
      for (final k in gitKaliplari) {
        final gi = kalan.indexOf(k);
        if (gi != -1) kalan = kalan.substring(0, gi).trim();
      }
      // "ülker bisküviye", "kasaya" gibi yönelme ekini kabaca temizle
      kalan = kalan.replaceAll(RegExp(r"(ye|ya|e|a)$"), '').trim();
      // Bağlaç kalıntılarını temizle
      kalan = kalan.replaceAll(RegExp(r'^(için|olan)\s+'), '').trim();

      return (rota: entry.value, arama: kalan.isEmpty ? null : kalan);
    }
    return null;
  }

  Future<AiSohbetSonuc> sor(String soru) async {
    final nav = _navigasyonAlgila(soru);
    if (nav != null) {
      return AiSohbetSonuc(
        cevap: nav.arama != null
            ? '${_rotaAdi(nav.rota)} açılıyor, "${nav.arama}" aranıyor... 🔎'
            : '${_rotaAdi(nav.rota)} açılıyor... 🔎',
        rota: nav.rota,
        aramaTerimi: nav.arama,
      );
    }
    final cevapMetni = await _soruyaCevapVer(soru);
    return AiSohbetSonuc(cevap: cevapMetni);
  }

  String _rotaAdi(String rota) => switch (rota) {
        '/urun' => 'Ürün Listesi',
        '/stok' => 'Stok',
        '/cari' => 'Cari Listesi',
        '/kasa' => 'Kasa',
        '/kredi-karti' => 'Kredi Kartları',
        '/gider' => 'Giderler',
        '/borc-takip' => 'Borç Takip',
        '/satis' => 'Hızlı Satış',
        '/vardiya' => 'Vardiya',
        '/personel' => 'Personel',
        '/rapor/satis' => 'Satış Raporu',
        '/rapor/kar' => 'Kâr-Zarar',
        _ => 'Ekran',
      };

  Future<String> _soruyaCevapVer(String soru) async {
    try {
      var q = AiAnlayici.anla(soru);

      // 🔴🔴 KÖK NEDEN DÜZELTMESİ (kullanıcı bulgusu — "Akıllı Analiz'de
      // konuşmama göre herşeyi getiremiyor"): AiAnlayici SAF anahtar-
      // kelime eşleştirmesiyle çalışır — kalıpların dışına çıkan HER
      // soru buraya (bilinmiyor) düşüp gerçek veriye erişimi OLMAYAN
      // genel sohbete (aşağıdaki default dalı) gidiyordu. Artık kural
      // tabanlı sistem tanıyamazsa, AYNI rapor/sorgu fonksiyonları
      // Gemini'ye "araç" olarak sunuluyor — model SADECE hangi aracın
      // uyduğuna karar veriyor, sayıları YİNE aşağıdaki AYNI, değişmemiş
      // SQL fonksiyonları üretiyor (bkz. ai_niyet_yonlendirici.dart).
      if (q.intent == AiIntent.bilinmiyor) {
        final yonlendirilen = await AiNiyetYonlendirici().yonlendir(soru);
        if (yonlendirilen != null) q = yonlendirilen;
      }

      final p = q.params;
      final bas = p['bas'] as DateTime? ?? DateTime.now();
      final bit = p['bit'] as DateTime? ?? DateTime.now();
      final periyot = p['periyot'] as String? ?? 'Bugün';

      // Bağlam
      if (p['urunAdi'] != null) _sonUrun = p['urunAdi'];
      if (p['musteriAdi'] != null) _sonMusteri = p['musteriAdi'];

      switch (q.intent) {
        case AiIntent.sohbet:         return _sohbet(soru);
        case AiIntent.zRaporu:        return AiRaporServisi.zRaporu(bas);
        case AiIntent.urunZRaporu:    return AiRaporServisi.urunZRaporu(bas);
        case AiIntent.aylikRapor:     return AiRaporServisi.aylikRapor(bas);
        case AiIntent.grupRaporu:     return AiRaporServisi.grupRaporu(bas, bit);
        case AiIntent.markaRaporu:    return AiRaporServisi.grupRaporu(bas, bit, kolon: 'marka', baslik: 'MARKA');
        case AiIntent.alan1Raporu:    return AiRaporServisi.grupRaporu(bas, bit, kolon: 'alan1', baslik: 'ALAN1');
        case AiIntent.kategoriAnaliz: return AiRaporServisi.grupRaporu(bas, bit);
        case AiIntent.gunlukSatis:
        case AiIntent.haftalikSatis:
        case AiIntent.aylikSatis:
        case AiIntent.yillikSatis:
        case AiIntent.ciroRaporu:     return _satisCevap(bas, bit, periyot);
        case AiIntent.netKar:         return _netKarCevap(bas, bit, periyot);
        case AiIntent.karDegisimAciklama: return AiRaporServisi.karDegisimAciklama();
        case AiIntent.anormalTespit:      return AiRaporServisi.anormalIslemleriTespitEt();
        case AiIntent.stokTukenmeTahmini: return AiRaporServisi.stokTukenmeTahmini();
        case AiIntent.kasaDurumu:     return _kasaCevap();
        case AiIntent.odemeYontemi:   return _odemeDagilimCevap(bas, bit, periyot);
        case AiIntent.kritikStok:     return _kritikStokCevap();
        case AiIntent.stokSorgula:    return _stokSorgulaCevap(_sonUrun ?? _araUrunIsmi(soru));
        case AiIntent.stokDeger:      return _stokDegerCevap();
        case AiIntent.stokHareket:    return _stokHareketCevap(bas, bit, periyot);
        case AiIntent.enCokSatan:     return _enCokSatanCevap(bas, bit, p['sayi'] as int? ?? 10);
        case AiIntent.enKarli:        return _enKarliCevap();
        case AiIntent.urunAra:        return _urunAraCevap(_sonUrun ?? _araUrunIsmi(soru));
        case AiIntent.urunListele:    return _urunListeleCevap(p['sayi'] as int? ?? 20);
        case AiIntent.cariListele:    return _cariListeleCevap();
        case AiIntent.cariBorc:       return _cariBorcCevap(_sonMusteri ?? _araMusteriIsmi(soru));
        case AiIntent.cariHareket:    return _cariHareketCevap(p['sayi'] as int? ?? 10);
        case AiIntent.tahsilat:       return _tahsilatCevap(bas, bit, periyot);
        case AiIntent.tahmin:         return _tahminCevap(p['sayi'] as int? ?? 7);
        case AiIntent.oneri:          return _oneriCevap();
        case AiIntent.grupDetay:        return _grupDetayCevap();
        case AiIntent.alan1Detay:       return _alan1DetayCevap();
        case AiIntent.stokGenelDurum:   return _stokGenelDurumCevap();
        default:
          // Kural tabanlı sistem bu soruyu tanımadı — önceden burada
          // sadece bir "örnek komutlar" listesi dönülüyordu, soruya
          // GERÇEKTEN cevap verilmiyordu. Artık Gemini API anahtarı
          // ayarlıysa genel amaçlı yapay zeka asistanı devreye giriyor
          // (bkz. ai_genel_asistan.dart) — uygulamanın tüm modüllerini
          // bilir, "nasıl yaparım" tarzı sorulara da cevap verebilir.
          final aiCevap = await AiGenelAsistan().yanitla(soru);
          return aiCevap;
      }
    } catch (e, st) {
      LogServisi().hata('AiSohbetServisi.sor', hata: e, yigin: st);
      return 'Üzgünüm, bir hata oluştu: $e\n\nLütfen tekrar deneyin.';
    }
  }

  String _araUrunIsmi(String soru) {
    final s = soru.toLowerCase();
    final kelimeler = s.split(' ');
    final stopWords = {'stok','kaç','adet','var','kaldı','ne','bu','bir','için','olan'};
    return kelimeler.where((k) => k.length > 2 && !stopWords.contains(k)).join(' ');
  }

  String _araMusteriIsmi(String soru) {
    final s = soru.toLowerCase();
    final kelimeler = s.split(' ');
    final stopWords = {'borç','bakiye','alacak','öde','müşteri','carisi','ne','kadar'};
    return kelimeler.where((k) => k.length > 2 && !stopWords.contains(k)).join(' ');
  }

  // ── Satış cevabı ─────────────────────────────────────────────────────────
  Future<String> _satisCevap(DateTime bas, DateTime bit, String periyot) async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) as islem,
             COALESCE(SUM(genel_toplam),0) as ciro,
             COALESCE(SUM(iskonto_tutar),0) as iskonto,
             COALESCE(SUM(kdv_tutar),0) as kdv
      FROM satislar
      WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
    ''', [bas.toIso8601String(), bit.toIso8601String()]);

    final r    = rows.first;
    final ciro = (r['ciro'] as num?)?.toDouble() ?? 0;
    final isk  = (r['iskonto'] as num?)?.toDouble() ?? 0;

    return '''📊 $periyot SATIŞ RAPORU
  İşlem sayısı : ${r['islem']}
  Brüt ciro    : ${_p.format(ciro)} TL
  İskonto      : ${_p.format(isk)} TL
  Net ciro     : ${_p.format(ciro - isk)} TL
  KDV          : ${_p.format((r['kdv'] as num?)?.toDouble() ?? 0)} TL''';
  }

  // ── Net kâr ──────────────────────────────────────────────────────────────
  Future<String> _netKarCevap(DateTime bas, DateTime bit, String periyot) async {
    final db     = await Veritabani().db;
    final s      = await db.rawQuery('''
      SELECT COALESCE(SUM(genel_toplam),0) as ciro
      FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
    final m = await db.rawQuery('''
      SELECT COALESCE(SUM(sk.miktar * COALESCE(sk.alis_fiyat,0)),0) as mal
      FROM satis_kalem sk JOIN satislar st ON sk.satis_id=st.id
      WHERE st.tarih BETWEEN ? AND ? AND st.iptal=0 AND st.is_deleted=0
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
    // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu fonksiyon
    // "NET KÂR" etiketliyordu ama giderler (kira, elektrik, personel
    // vb.) HİÇ düşülmüyordu — aslında brüt kâr (ciro-maliyet)
    // gösteriliyordu. Bir kullanıcı AI'ya "net kârım ne kadar"
    // sorduğunda, gerçekte olduğundan HER ZAMAN daha yüksek bir rakam
    // alıyordu — bu, kâr-zarar ekranında (kar_zarar_provider.dart)
    // zaten doğru hesaplanan formülle tutarsızdı.
    final g = await db.rawQuery('''
      SELECT COALESCE(SUM(tutar),0) as gider
      FROM giderler WHERE tarih BETWEEN ? AND ? AND deleted_at IS NULL
    ''', [bas.toIso8601String(), bit.toIso8601String()]);

    final ciro   = (s.first['ciro'] as num?)?.toDouble() ?? 0;
    final mal    = (m.first['mal'] as num?)?.toDouble() ?? 0;
    final gider  = (g.first['gider'] as num?)?.toDouble() ?? 0;
    final brutKar = ciro - mal;
    final kar    = brutKar - gider;

    return '''💰 $periyot NET KÂR
  Toplam ciro   : ${_p.format(ciro)} TL
  Toplam maliyet: ${_p.format(mal)} TL
  Brüt kâr      : ${_p.format(brutKar)} TL
  Giderler      : ${_p.format(gider)} TL
  ──────────────────────────
  Net kâr      : ${_p.format(kar)} TL
  Kâr marjı   : %${ciro > 0 ? ((kar / ciro) * 100).toStringAsFixed(1) : '0.0'}''';
  }

  // ── Kasa ─────────────────────────────────────────────────────────────────
  Future<String> _kasaCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery(
      'SELECT bakiye_sonrasi FROM kasa_hareketleri ORDER BY tarih DESC, id DESC LIMIT 1');
    final bak = rows.isEmpty ? 0.0 : (rows.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0;
    return '💵 Güncel kasa bakiyesi: ${_p.format(bak)} TL';
  }

  // ── Ödeme dağılımı ───────────────────────────────────────────────────────
  Future<String> _odemeDagilimCevap(DateTime bas, DateTime bit, String periyot) async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT odeme_yontemi,
             COUNT(*) as adet,
             COALESCE(SUM(genel_toplam),0) as tutar
      FROM satislar
      WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
      GROUP BY odeme_yontemi ORDER BY tutar DESC
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
    if (rows.isEmpty) return '$periyot döneminde satış bulunamadı.';
    final sb = StringBuffer('💳 $periyot ÖDEME DAĞILIMI\n');
    for (final r in rows) {
      sb.writeln('  ${(r['odeme_yontemi']?.toString() ?? 'Diğer').padRight(14)}: ${_p.format((r['tutar'] as num?)?.toDouble() ?? 0)} TL  (${r['adet']} işlem)');
    }
    return sb.toString();
  }

  // ── Kritik stok ──────────────────────────────────────────────────────────
  Future<String> _kritikStokCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT urun_adi, stok, COALESCE(minimum_stok, 5) as min_stok
      FROM urunler
      WHERE stok <= COALESCE(minimum_stok, 5)
        AND aktif=1 AND is_deleted=0
      ORDER BY stok ASC LIMIT 20
    ''');
    if (rows.isEmpty) return '✅ Kritik stok seviyesinde ürün yok.';
    final sb = StringBuffer('⚠️ KRİTİK STOK (${rows.length} ürün)\n');
    for (final r in rows) {
      sb.writeln('  • ${r['urun_adi']}');
      sb.writeln('    Mevcut: ${r['stok']}  |  Minimum: ${r['min_stok']}');
    }
    return sb.toString();
  }

  // ── Stok sorgula ─────────────────────────────────────────────────────────
  Future<String> _stokSorgulaCevap(String? aramaMetni) async {
    if (aramaMetni == null || aramaMetni.trim().isEmpty) {
      return 'Hangi ürünün stoğunu öğrenmek istersiniz? (Örn: "süt stok")';
    }
    final db   = await Veritabani().db;
    // bkz. UrunDeposu.ara() üzerindeki kullanıcı bulgusu notu —
    // alternatif barkodlar (`barkodlar`) da aranıyor.
    final rows = await db.rawQuery('''
      SELECT urun_adi, barkod, stok, satis_fiyati, ana_grup
      FROM urunler
      WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ?) AND is_deleted=0
      LIMIT 5
    ''', ['%$aramaMetni%', '%$aramaMetni%', '%$aramaMetni%']);
    if (rows.isEmpty) return '"$aramaMetni" ile eşleşen ürün bulunamadı.';
    final sb = StringBuffer('📦 Stok Bilgisi:\n');
    for (final r in rows) {
      sb.writeln('  ▸ ${r['urun_adi']}');
      sb.writeln('    Stok: ${r['stok']}  |  Fiyat: ${_p.format((r['satis_fiyati'] as num?)?.toDouble() ?? 0)} TL');
    }
    return sb.toString();
  }

  // ── Stok değeri ──────────────────────────────────────────────────────────
  Future<String> _stokDegerCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(stok * COALESCE(alis_fiyat,0)),0) as alis,
             COALESCE(SUM(stok * satis_fiyati),0) as satis
      FROM urunler WHERE aktif=1 AND is_deleted=0
    ''');
    final alis  = (rows.first['alis'] as num?)?.toDouble() ?? 0;
    final satis = (rows.first['satis'] as num?)?.toDouble() ?? 0;
    return '''💰 STOK DEĞER ANALİZİ
  Alış değeri     : ${_p.format(alis)} TL
  Satış değeri    : ${_p.format(satis)} TL
  Potansiyel kâr  : ${_p.format(satis - alis)} TL''';
  }

  // ── Stok hareket ─────────────────────────────────────────────────────────
  Future<String> _stokHareketCevap(DateTime bas, DateTime bit, String periyot) async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT hareket_turu, SUM(miktar) as toplam
      FROM stok_hareket WHERE tarih BETWEEN ? AND ?
      GROUP BY hareket_turu
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
    if (rows.isEmpty) return '$periyot döneminde stok hareketi yok.';
    final sb = StringBuffer('📦 $periyot STOK HAREKETLERİ\n');
    for (final r in rows) {
      sb.writeln('  ${r['hareket_turu']}: ${(r['toplam'] as num?)?.toStringAsFixed(2)} adet');
    }
    return sb.toString();
  }

  // ── En çok satan ─────────────────────────────────────────────────────────
  Future<String> _enCokSatanCevap(DateTime bas, DateTime bit, int limit) async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT sk.urun_adi, SUM(sk.miktar) as miktar, SUM(sk.toplam_tutar) as tutar
      FROM satis_kalem sk JOIN satislar s ON sk.satis_id=s.id
      WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0
      GROUP BY sk.urun_adi ORDER BY tutar DESC LIMIT ?
    ''', [bas.toIso8601String(), bit.toIso8601String(), limit]);
    if (rows.isEmpty) return 'Bu dönemde satış verisi yok.';
    final sb = StringBuffer('🏆 EN ÇOK SATAN $limit ÜRÜN\n');
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      sb.writeln('  ${(i+1).toString().padLeft(2)}. ${r['urun_adi']}');
      sb.writeln('      ${_p.format((r['tutar'] as num?)?.toDouble() ?? 0)} TL  |  ${(r['miktar'] as num?)?.toStringAsFixed(0)} adet');
    }
    return sb.toString();
  }

  // ── En karlı ─────────────────────────────────────────────────────────────
  Future<String> _enKarliCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT urun_adi, satis_fiyati, alis_fiyat,
             CASE WHEN alis_fiyat > 0
               THEN ((satis_fiyati - alis_fiyat) / alis_fiyat * 100)
               ELSE 0 END as marj
      FROM urunler
      WHERE aktif=1 AND is_deleted=0 AND alis_fiyat > 0
      ORDER BY marj DESC LIMIT 10
    ''');
    if (rows.isEmpty) return 'Kâr marjı verisi yok.';
    final sb = StringBuffer('📈 EN KARLI 10 ÜRÜN\n');
    for (int i = 0; i < rows.length; i++) {
      final r   = rows[i];
      final marj = (r['marj'] as num?)?.toDouble() ?? 0;
      sb.writeln('  ${(i+1).toString().padLeft(2)}. ${r['urun_adi']}');
      sb.writeln('      Marj: %${marj.toStringAsFixed(1)}  |  Satış: ${_p.format((r['satis_fiyati'] as num?)?.toDouble() ?? 0)} TL');
    }
    return sb.toString();
  }

  // ── Ürün ara ─────────────────────────────────────────────────────────────
  Future<String> _urunAraCevap(String? arama) async {
    if (arama == null || arama.trim().isEmpty) return 'Aramak istediğiniz ürünü belirtin.';
    final db   = await Veritabani().db;
    // bkz. UrunDeposu.ara() üzerindeki kullanıcı bulgusu notu —
    // alternatif barkodlar (`barkodlar`) da aranıyor.
    final rows = await db.rawQuery('''
      SELECT urun_adi, barkod, stok, satis_fiyati, alis_fiyat, ana_grup
      FROM urunler
      WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?) AND is_deleted=0
      LIMIT 10
    ''', ['%$arama%', '%$arama%', '%$arama%', '%$arama%']);
    if (rows.isEmpty) return '"$arama" aramasında ürün bulunamadı.';
    final sb = StringBuffer('🔍 "$arama" Arama Sonuçları\n');
    for (final r in rows) {
      sb.writeln('  ▸ ${r['urun_adi']}');
      sb.writeln('    Barkod: ${r['barkod'] ?? '-'}  |  Stok: ${r['stok']}  |  Fiyat: ${_p.format((r['satis_fiyati'] as num?)?.toDouble() ?? 0)} TL');
    }
    return sb.toString();
  }

  // ── Ürün listele ─────────────────────────────────────────────────────────
  Future<String> _urunListeleCevap(int limit) async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT urun_adi, stok, satis_fiyati, ana_grup
      FROM urunler WHERE aktif=1 AND is_deleted=0
      ORDER BY urun_adi LIMIT ?
    ''', [limit]);
    if (rows.isEmpty) return 'Ürün bulunamadı.';
    final sb = StringBuffer('📋 ÜRÜN LİSTESİ (İlk $limit)\n');
    for (final r in rows) {
      sb.writeln('  ▸ ${r['urun_adi']}  —  ${r['stok']} adet  —  ${_p.format((r['satis_fiyati'] as num?)?.toDouble() ?? 0)} TL');
    }
    return sb.toString();
  }

  // ── Cari listele ─────────────────────────────────────────────────────────
  Future<String> _cariListeleCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT unvan, bakiye, cari_tipi
      FROM cari WHERE is_deleted=0 AND aktif=1
      ORDER BY ABS(bakiye) DESC LIMIT 20
    ''');
    if (rows.isEmpty) return 'Cari kaydı bulunamadı.';
    final sb = StringBuffer('👥 CARİ LİSTESİ\n');
    for (final r in rows) {
      final bak   = (r['bakiye'] as num?)?.toDouble() ?? 0;
      final durum = bak > 0 ? '(borçlu)' : bak < 0 ? '(alacaklı)' : '';
      sb.writeln('  ▸ ${r['unvan']}  —  ${_p.format(bak.abs())} TL $durum');
    }
    return sb.toString();
  }

  // ── Cari borç ────────────────────────────────────────────────────────────
  Future<String> _cariBorcCevap(String? arama) async {
    if (arama == null || arama.trim().isEmpty) {
      return 'Hangi müşterinin bakiyesini öğrenmek istersiniz?';
    }
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT unvan, bakiye, cari_tipi, telefon
      FROM cari WHERE unvan LIKE ? AND is_deleted=0 LIMIT 3
    ''', ['%$arama%']);
    if (rows.isEmpty) return '"$arama" adında cari bulunamadı.';
    final sb = StringBuffer();
    for (final r in rows) {
      final bak   = (r['bakiye'] as num?)?.toDouble() ?? 0;
      final durum = bak > 0 ? 'Borçlu' : bak < 0 ? 'Alacaklı' : 'Sıfır';
      sb.writeln('  ▸ ${r['unvan']}');
      sb.writeln('    Bakiye: ${_p.format(bak.abs())} TL ($durum)');
      if (r['telefon'] != null) sb.writeln('    Tel: ${r['telefon']}');
    }
    return sb.toString();
  }

  // ── Cari hareket ─────────────────────────────────────────────────────────
  Future<String> _cariHareketCevap(int limit) async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT ch.tarih, ch.fis_tipi, ch.borc, ch.alacak, c.unvan
      FROM cari_hareket ch
      JOIN cari c ON ch.cari_id = c.id
      ORDER BY ch.tarih DESC, ch.id DESC LIMIT ?
    ''', [limit]);
    if (rows.isEmpty) return 'Cari hareket bulunamadı.';
    final sb = StringBuffer('📋 SON $limit CARİ HAREKETİ\n');
    for (final r in rows) {
      final borc   = (r['borc'] as num?)?.toDouble() ?? 0;
      final alacak = (r['alacak'] as num?)?.toDouble() ?? 0;
      final tutar  = borc > 0 ? '${_p.format(borc)} TL borç' : '${_p.format(alacak)} TL alacak';
      final tarih  = r['tarih']?.toString().substring(0, 10) ?? '';
      sb.writeln('  ▸ $tarih  ${r['unvan']}  ${r['fis_tipi']}  $tutar');
    }
    return sb.toString();
  }

  // ── Tahsilat ─────────────────────────────────────────────────────────────
  Future<String> _tahsilatCevap(DateTime bas, DateTime bit, String periyot) async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(alacak),0) as tahsilat,
             COALESCE(SUM(borc),0) as odeme
      FROM cari_hareket
      WHERE tarih BETWEEN ? AND ?
        AND fis_tipi IN ('Tahsilat', 'Ödeme', 'Odeme')
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
    final tah = (rows.first['tahsilat'] as num?)?.toDouble() ?? 0;
    final ode = (rows.first['odeme'] as num?)?.toDouble() ?? 0;
    return '''💳 $periyot TAHSİLAT/ÖDEME
  Tahsilat : ${_p.format(tah)} TL
  Ödeme    : ${_p.format(ode)} TL
  Net      : ${_p.format(tah - ode)} TL''';
  }

  // ── Tahmin ───────────────────────────────────────────────────────────────
  // ── Grup/Kategori detay listesi ─────────────────────────────────────────
  Future<String> _grupDetayCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT ana_grup,
             COUNT(*) as urun_sayisi,
             SUM(stok) as toplam_stok,
             COUNT(CASE WHEN stok = 0 THEN 1 END) as stoksuz,
             COUNT(CASE WHEN stok <= 5 AND stok > 0 THEN 1 END) as kritik
      FROM urunler
      WHERE is_deleted=0 AND aktif=1 AND ana_grup IS NOT NULL
      GROUP BY ana_grup
      ORDER BY urun_sayisi DESC
    ''');
    if (rows.isEmpty) return 'Kategori verisi bulunamadı.';
    final sb = StringBuffer();
    sb.writeln('KATEGORI / GRUP DETAYI (${rows.length} grup)');
    sb.writeln('');
    for (final r in rows) {
      final stoksuz = (r['stoksuz'] as num?)?.toInt() ?? 0;
      final kritik  = (r['kritik'] as num?)?.toInt() ?? 0;
      sb.writeln('▸ ${r['ana_grup']}');
      sb.writeln('  ${r['urun_sayisi']} ürün  |  Toplam stok: ${r['toplam_stok']}');
      if (stoksuz > 0) sb.writeln('  ⚠️ Stoksuz: $stoksuz  Kritik: $kritik');
      sb.writeln('');
    }
    return sb.toString();
  }

  // ── Alan1 detay listesi ──────────────────────────────────────────────────
  Future<String> _alan1DetayCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(alan1, 'Tanımsız') as alan1_val,
             COUNT(*) as urun_sayisi,
             SUM(stok) as toplam_stok,
             AVG(satis_fiyati) as ort_fiyat
      FROM urunler
      WHERE is_deleted=0 AND aktif=1
      GROUP BY alan1
      ORDER BY urun_sayisi DESC
      LIMIT 20
    ''');
    if (rows.isEmpty) return 'Alan1 verisi bulunamadı.';
    final alan1Var = rows.where((r) => r['alan1_val'] != 'Tanımsız').length;
    if (alan1Var == 0) {
      return 'Alan1 alani henuz tanimlanmamis. Urun duzenleme ekranindan alan1 bilgisi girebilirsiniz.';
    }
    final sb = StringBuffer();
    sb.writeln('ALAN1 DETAYI');
    sb.writeln('');
    for (final r in rows) {
      final ort = (r['ort_fiyat'] as num?)?.toDouble() ?? 0;
      sb.writeln('▸ ${r['alan1_val']}');
      sb.writeln('  ${r['urun_sayisi']} ürün  |  Stok: ${r['toplam_stok']}  |  Ort. Fiyat: ${_p.format(ort)} TL');
      sb.writeln('');
    }
    return sb.toString();
  }

  // ── Stok genel durum ─────────────────────────────────────────────────────
  Future<String> _stokGenelDurumCevap() async {
    final db   = await Veritabani().db;
    final ozet = (await db.rawQuery('''
      SELECT COUNT(*) as toplam,
             COUNT(CASE WHEN stok = 0 THEN 1 END) as stoksuz,
             COUNT(CASE WHEN stok > 0 AND stok <= 5 THEN 1 END) as kritik,
             COUNT(CASE WHEN stok > 5 AND stok <= 20 THEN 1 END) as dusuk,
             COUNT(CASE WHEN stok > 20 THEN 1 END) as normal,
             COALESCE(SUM(stok * COALESCE(alis_fiyat,0)),0) as depo_degeri
      FROM urunler WHERE aktif=1 AND is_deleted=0
    ''')).first;

    final gruplar = await db.rawQuery('''
      SELECT ana_grup, COUNT(*) as adet,
             COUNT(CASE WHEN stok = 0 THEN 1 END) as stoksuz
      FROM urunler WHERE aktif=1 AND is_deleted=0 AND ana_grup IS NOT NULL
      GROUP BY ana_grup HAVING stoksuz > 0
      ORDER BY stoksuz DESC LIMIT 5
    ''');

    final sb = StringBuffer();
    sb.writeln('📦 GENEL STOK DURUMU');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    sb.writeln('Toplam ürün  : ${ozet['toplam']}');
    sb.writeln('Stoksuz      : ${ozet['stoksuz']} ürün ⚠️');
    sb.writeln('Kritik (≤5)  : ${ozet['kritik']} ürün');
    sb.writeln('Düşük (≤20)  : ${ozet['dusuk']} ürün');
    sb.writeln('Normal (>20) : ${ozet['normal']} ürün');
    sb.writeln('Depo değeri  : ${_p.format((ozet['depo_degeri'] as num?)?.toDouble() ?? 0)} TL');
    if (gruplar.isNotEmpty) {
      sb.writeln('');
      sb.writeln('❌ STOKSUZ OLAN GRUPLAR');
      for (final g in gruplar) {
        sb.writeln('  ${g['ana_grup']}: ${g['stoksuz']} stoksuz ürün');
      }
    }
    return sb.toString();
  }

  Future<String> _tahminCevap(int gun) async {
    final db  = await Veritabani().db;
    final now = DateTime.now();
    final bas = now.subtract(const Duration(days: 30)).toIso8601String();
    final bit = now.toIso8601String();
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(genel_toplam),0) as toplam, COUNT(DISTINCT DATE(tarih)) as gun_sayisi
      FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
    ''', [bas, bit]);
    final toplam  = (rows.first['toplam'] as num?)?.toDouble() ?? 0;
    final gunSay  = (rows.first['gun_sayisi'] as num?)?.toInt() ?? 1;
    final ortGun  = toplam / (gunSay > 0 ? gunSay : 1);
    final tahmin  = ortGun * gun;
    return '''🔮 $gun GÜNLÜK TAHMİN
  Son 30 gün ort. : ${_p.format(ortGun)} TL/gün
  $gun günlük tahmin: ${_p.format(tahmin)} TL''';
  }

  // ── Öneri ────────────────────────────────────────────────────────────────
  Future<String> _oneriCevap() async {
    final db   = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT urun_adi, stok, COALESCE(minimum_stok, 5) as min_stok
      FROM urunler
      WHERE stok <= COALESCE(minimum_stok, 5) AND aktif=1 AND is_deleted=0
      ORDER BY stok ASC LIMIT 15
    ''');
    if (rows.isEmpty) return '✅ Sipariş verilmesi gereken ürün yok.';
    final sb = StringBuffer('📋 SİPARİŞ ÖNERİLERİ (${rows.length} ürün)\n');
    for (final r in rows) {
      final stok   = (r['stok'] as num?)?.toDouble() ?? 0;
      final min    = (r['min_stok'] as num?)?.toDouble() ?? 5;
      final siparis = (min * 2 - stok).ceil().clamp(1, 9999);
      sb.writeln('  ▸ ${r['urun_adi']}');
      sb.writeln('    Mevcut: $stok  |  Min: $min  |  Sipariş önerisi: $siparis adet');
    }
    return sb.toString();
  }

  // ── Sohbet ───────────────────────────────────────────────────────────────
  // Genişletildi: daha fazla günlük konuşma kalıbı tanınıyor, aynı soruya
  // hep aynı kalıp cevap yerine birkaç varyasyondan rastgele seçiliyor —
  // daha doğal hissettirmesi için.
  String _sohbet(String soru) {
    final s = soru.toLowerCase().trim();
    final r = DateTime.now().millisecond % 3; // basit çeşitlilik seçici

    if (s.contains('merhaba') || s.contains('selam') || s.contains('günaydın') ||
        s.contains('naber') || s.contains('iyi günler') || s.contains('kolay gelsin')) {
      return const [
        'Merhaba! 👋 Size nasıl yardımcı olabilirim?\n\nRapor, satış, stok, cari veya kar analizi için soru sorabilirsiniz.',
        'Selam! 😊 Bugün hangi konuda yardımcı olayım — satış, stok, kar durumu?',
        'Merhaba, kolay gelsin! Ne öğrenmek istersiniz — raporlar, cari borçlar, en çok satanlar?',
      ][r];
    }
    if (s.contains('teşekkür') || s.contains('sağ ol') || s.contains('eyvallah')) {
      return const [
        'Rica ederim! 😊 Başka bir konuda yardımcı olabilir miyim?',
        'Ne demek, her zaman! Başka sorunuz varsa buradayım.',
      ][r % 2];
    }
    if (s.contains('nasılsın') || s.contains('iyi misin')) {
      return 'İyiyim, teşekkürler! Her zaman hizmetinizdeyim. Size nasıl yardımcı olabilirim?';
    }
    if (s.contains('görüşürüz') || s.contains('hoşça kal') || s.contains('bay bay')) {
      return 'Görüşmek üzere! 👋 İhtiyacınız olduğunda buradayım.';
    }
    if (s.contains('anlamadın') || s.contains('yanlış anladın') || s.contains('öyle demedim')) {
      return 'Özür dilerim, tam anlayamamış olabilirim 🙏 Sorunuzu biraz daha açık '
          'ifade eder misiniz? Örneğin ürün adı, tarih aralığı veya rapor türünü '
          'belirtirseniz daha isabetli cevap verebilirim.';
    }
    if (s.contains('kimsin') || s.contains('sen kimsin') || s.contains('adın ne')) {
      return 'Ben BarkoPro Akıllı Asistanı — mağazanızın satış, stok, cari ve kâr '
          'verilerini gerçek zamanlı analiz edip size özetliyorum. Ne öğrenmek istersiniz?';
    }
    return _yardim();
  }

  String _yardim() => '💡 AI Asistan — Örnek sorular:\n\n'
      '📋 RAPORLAR\n'
      '  "Z raporu"  —  "Dünkü Z raporu"\n'
      '  "Ürün Z raporu"  —  "Bu ayki ürün Z"\n'
      '  "Aylık rapor"  —  "Geçen ay raporu"\n'
      '  "Bu hafta kategori raporu"\n'
      '  "Bu ay marka raporu"\n\n'
      '💰 SATIŞ & KAR\n'
      '  "Bugünkü satışlar"  —  "Bu hafta ciro"\n'
      '  "Bu ayın net karı"  —  "Yıllık kazancım"\n'
      '  "Dünkü kar ne kadar?"\n'
      '  "Ödeme yöntemi dağılımı"\n\n'
      '📦 STOK\n'
      '  "Kritik stoklar"  —  "Stok uyarıları"\n'
      '  "Süt stok kaç?"  —  "Ekmek kaç adet"\n'
      '  "Stok değeri"  —  "Depo tutarı"\n'
      '  "Stok hareketleri"\n\n'
      '🏆 ÜRÜN ANALİZİ\n'
      '  "En çok satan 10 ürün"\n'
      '  "Bu hafta en çok satanlar"\n'
      '  "En karlı ürünler"\n'
      '  "Kategori bazlı satışlar"\n\n'
      '👥 CARİ & KASA\n'
      '  "Borçlu müşteriler"  —  "Ahmet bakiye"\n'
      '  "Son tahsilatlar"  —  "Kasa durumu"\n'
      '  "Cari hareket listesi"\n\n'
      '🔮 TAHMİN & ÖNERİ\n'
      '  "7 günlük satış tahmini"\n'
      '  "Sipariş önerileri"\n'
      '  "30 günlük tahmin"';
}
