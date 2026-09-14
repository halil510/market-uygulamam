// lib/servisler/ai/ai_anlayici.dart
// Gelişmiş NLP — tüm kombinasyonları destekler
import 'ai_modeller.dart';

class AiAnlayici {
  // Context hafızası
  static String? _sonUrun;
  static String? _sonMusteri;
  static String? _sonKategori;
  static AiIntent? _sonIntent;

  static AiSoru anla(String soru) {
    final s = soru.toLowerCase().trim();
    final p = <String, dynamic>{};

    _zamanCikar(s, p);
    _sayiCikar(s, p);
    _urunCikar(s, p);
    _musteriCikar(s, p);

    final intent = _intent(s, p);
    _sonIntent = intent;

    return AiSoru(metin: soru, intent: intent, params: p);
  }

  // ── Zaman çıkar ──────────────────────────────────────────────────────────
  static void _zamanCikar(String s, Map<String, dynamic> p) {
    final now = DateTime.now();
    final bugun = DateTime(now.year, now.month, now.day);

    // Önce yıl
    if (_ic(s, ['bu yıl','bu yil','yıllık','yillik','yılın','yilin'])) {
      p['bas'] = DateTime(now.year, 1, 1);
      p['bit'] = DateTime(now.year, 12, 31, 23, 59, 59);
      p['periyot'] = 'Bu Yıl (${now.year})'; return;
    }
    if (_ic(s, ['geçen yıl','gecen yil'])) {
      p['bas'] = DateTime(now.year-1, 1, 1);
      p['bit'] = DateTime(now.year-1, 12, 31, 23, 59, 59);
      p['periyot'] = 'Geçen Yıl (${now.year-1})'; return;
    }

    // Ay
    if (_ic(s, ['bu ay','bu ayın','aylık','aylik','ayın','bu ayki'])) {
      p['bas'] = DateTime(now.year, now.month, 1);
      p['bit'] = DateTime(now.year, now.month+1, 0, 23, 59, 59);
      p['periyot'] = 'Bu Ay'; return;
    }
    if (_ic(s, ['geçen ay','gecen ay','geçen ayın'])) {
      final ay = now.month == 1 ? 12 : now.month-1;
      final yil = now.month == 1 ? now.year-1 : now.year;
      p['bas'] = DateTime(yil, ay, 1);
      p['bit'] = DateTime(yil, ay+1, 0, 23, 59, 59);
      p['periyot'] = 'Geçen Ay'; return;
    }

    // Hafta
    if (_ic(s, ['bu hafta','bu haftaki','haftalık','haftalik'])) {
      final pzt = bugun.subtract(Duration(days: bugun.weekday-1));
      p['bas'] = pzt;
      p['bit'] = pzt.add(const Duration(days:6, hours:23, minutes:59, seconds:59));
      p['periyot'] = 'Bu Hafta'; return;
    }
    if (_ic(s, ['geçen hafta','gecen hafta'])) {
      final pzt = bugun.subtract(Duration(days: bugun.weekday+6));
      p['bas'] = pzt;
      p['bit'] = pzt.add(const Duration(days:6, hours:23, minutes:59, seconds:59));
      p['periyot'] = 'Geçen Hafta'; return;
    }

    // Gün
    if (_ic(s, ['bugün','bugun','bugünkü','bugunku'])) {
      p['bas'] = bugun;
      p['bit'] = bugun.add(const Duration(days:1)).subtract(const Duration(seconds:1));
      p['periyot'] = 'Bugün'; return;
    }
    if (_ic(s, ['dün','dun','dünkü','dunku'])) {
      final d = bugun.subtract(const Duration(days:1));
      p['bas'] = d;
      p['bit'] = d.add(const Duration(days:1)).subtract(const Duration(seconds:1));
      p['periyot'] = 'Dün'; return;
    }

    // Son N gün/hafta/ay
    final mGun = RegExp(r'son\s+(\d+)\s*(gün|gun)').firstMatch(s);
    if (mGun != null) {
      final n = int.parse(mGun.group(1)!);
      p['bas'] = bugun.subtract(Duration(days: n));
      p['bit'] = bugun.add(const Duration(days:1)).subtract(const Duration(seconds:1));
      p['periyot'] = 'Son $n Gün'; return;
    }
    final mHafta = RegExp(r'son\s+(\d+)\s*hafta').firstMatch(s);
    if (mHafta != null) {
      final n = int.parse(mHafta.group(1)!);
      p['bas'] = bugun.subtract(Duration(days: n*7));
      p['bit'] = bugun.add(const Duration(days:1)).subtract(const Duration(seconds:1));
      p['periyot'] = 'Son $n Hafta'; return;
    }

    // Varsayılan: bugün
    p['bas'] = bugun;
    p['bit'] = bugun.add(const Duration(days:1)).subtract(const Duration(seconds:1));
    p['periyot'] = 'Bugün';
  }

  static void _sayiCikar(String s, Map<String, dynamic> p) {
    final m = RegExp(r'\b(\d+)\b').firstMatch(s);
    if (m != null) p['sayi'] = int.parse(m.group(1)!);
  }

  static void _urunCikar(String s, Map<String, dynamic> p) {
    // Soru içinde ürün adını çıkarmaya çalış
    // "süt stoku" "ekmek satışı" gibi
    final stop = {'stok','satış','satis','fiyat','rapor','kaç','adet','var','kaldı',
                  'bugün','bugun','bu','bir','için','olan','ne','nasıl','hangi'};
    final kelimeler = s.split(RegExp(r'[\s,]+'))
        .where((k) => k.length > 2 && !stop.contains(k))
        .toList();
    if (kelimeler.isNotEmpty) {
      p['aramaMetni'] = kelimeler.join(' ');
      _sonUrun = p['aramaMetni'];
    } else if (_sonUrun != null) {
      p['aramaMetni'] = _sonUrun;
    }
  }

  static void _musteriCikar(String s, Map<String, dynamic> p) {
    final stop = {'borç','borcu','bakiye','alacak','öde','müşteri','carisi','ne','kadar',
                  'kalan','olan','var','nasıl','hangi'};
    final kelimeler = s.split(RegExp(r'[\s,]+'))
        .where((k) => k.length > 2 && !stop.contains(k))
        .toList();
    if (kelimeler.length <= 3) {
      p['musteriAdi'] = kelimeler.join(' ');
      _sonMusteri = p['musteriAdi'];
    } else if (_sonMusteri != null) {
      p['musteriAdi'] = _sonMusteri;
    }
  }

  static bool _ic(String s, List<String> k) => k.any((x) => s.contains(x));

  // ── Intent belirleme ─────────────────────────────────────────────────────
  static AiIntent _intent(String s, Map<String, dynamic> p) {
    // Selamlama
    if (_ic(s, ['merhaba','selam','günaydın','nasılsın','teşekkür','sağ ol','iyi akşam'])) return AiIntent.sohbet;

    // Z Raporları - öncelikli
    if (_ic(s, ['z raporu','z-raporu','gün sonu raporu','günlük z','günlük rapor'])) {
      if (_ic(s, ['ürün','urun'])) return AiIntent.urunZRaporu;
      return AiIntent.zRaporu;
    }
    if (_ic(s, ['aylık rapor','aylik rapor','ay raporu','ay sonu','aylık özet'])) return AiIntent.aylikRapor;
    if (_ic(s, ['kategori rapor','grup rapor','kategoriye göre','gruba göre','grup bazlı','kategori bazlı'])) return AiIntent.grupRaporu;
    if (_ic(s, ['marka rapor','markaya göre','marka bazlı'])) return AiIntent.markaRaporu;
    if (_ic(s, ['alan1 rapor','alan1','alan 1'])) return AiIntent.alan1Raporu;

    // FAZ 10 — kâr değişim açıklaması: "kâr" + "neden/niye/düş/azal" birlikte
    // geçiyorsa, salt netKar yerine dönem karşılaştırmalı açıklamaya git.
    if (_ic(s, ['kar','kâr','kazanç','kazancım','kârım']) &&
        _ic(s, ['neden','niye','niçin','düştü','düşüş','azaldı','azalma','geriledi'])) {
      return AiIntent.karDegisimAciklama;
    }

    // Kâr - önce kar kelimesi geçiyorsa
    if (_ic(s, ['kar','kâr','kazanç','kazancım','kârım','net kar','karlılık','brüt kar','kar marjı'])) {
      return AiIntent.netKar;
    }

    // FAZ 10 — anormal işlem tespiti
    if (_ic(s, ['anormal','şüpheli','supheli','olağandışı','olagandisi','garip işlem','garip satış','fazla iade','sıra dışı'])) {
      return AiIntent.anormalTespit;
    }

    // FAZ 10 — stok tükenme tahmini (mevcut "stok" intent'lerinden ÖNCE
    // kontrol edilmeli, aksi halde genel 'stok' eşleşmesi bunu yakalar)
    if (_ic(s, ['tükenme','tukenme','ne zaman biter','ne zaman tükenir','kaç günde biter','kac gunde biter','stok bitiş','stok tahmini'])) {
      return AiIntent.stokTukenmeTahmini;
    }

    // Satış kombinasyonları
    if (_ic(s, ['satış','satiş','ciro','hasılat','gelir','brüt'])) {
      if (_ic(s, ['bu yıl','yıllık'])) return AiIntent.yillikSatis;
      if (_ic(s, ['bu ay','aylık','geçen ay'])) return AiIntent.aylikSatis;
      if (_ic(s, ['bu hafta','haftalık','geçen hafta'])) return AiIntent.haftalikSatis;
      if (_ic(s, ['dün','dünkü'])) return AiIntent.gunlukSatis;
      return AiIntent.gunlukSatis;
    }

    // Stok kombinasyonları
    if (_ic(s, ['kritik','bitmek üzere','azalmış','alarm','uyarı'])) return AiIntent.kritikStok;
    if (_ic(s, ['stok değeri','stok tutarı','stok kaç tl','depo değeri'])) return AiIntent.stokDeger;
    if (_ic(s, ['stok hareket','stok giriş','stok çıkış'])) return AiIntent.stokHareket;
    if (_ic(s, ['stok','kaç adet','adet kaldı','ne kadar var'])) return AiIntent.stokSorgula;

    // Ürün
    if (_ic(s, ['en çok satan','çok satan','popüler','bestseller'])) return AiIntent.enCokSatan;
    if (_ic(s, ['en karlı','en kârlı','karlı ürün','yüksek karlı'])) return AiIntent.enKarli;
    if (_ic(s, ['ürün ara','barkod','ürün bul','nerede'])) return AiIntent.urunAra;
    if (_ic(s, ['ürün listele','tüm ürün','ürün liste','ürünleri göster'])) return AiIntent.urunListele;
    if (_ic(s, ['kategori','grup','kategoriler'])) return AiIntent.kategoriAnaliz;

    // Cari & Kasa
    if (_ic(s, ['kasa','nakit','kasada ne var','kasada kaç'])) return AiIntent.kasaDurumu;
    if (_ic(s, ['tahsilat','tahsil etilen','toplanan','ödeme aldım'])) return AiIntent.tahsilat;
    if (_ic(s, ['borç','borçlu','bakiye','alacak','hesap durumu'])) return AiIntent.cariBorc;
    if (_ic(s, ['cari hareket','hareket listesi','hareketler'])) return AiIntent.cariHareket;
    if (_ic(s, ['cari','müşteri listesi','müşteriler','tedarikçi','firma listesi'])) return AiIntent.cariListele;
    if (_ic(s, ['ödeme yöntemi','nasıl ödendi','ödeme dağılımı','nakit mi kart mi'])) return AiIntent.odemeYontemi;

    // Tahmin & Öneri
    if (_ic(s, ['gruplar neler','kategoriler neler','kaç grup','hangi gruplar','grup listesi'])) return AiIntent.grupDetay;
    if (_ic(s, ['alan1 neler','alan1 listesi','alan1 grupları'])) return AiIntent.alan1Detay;
    if (_ic(s, ['genel stok','stok durumu','stok özet','stok raporu','depo durumu'])) return AiIntent.stokGenelDurum;
    if (_ic(s, ['tahmin','öngörü','gelecek satış','kaç olur','ne kadar olacak'])) return AiIntent.tahmin;
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "cari ismi veriyorum,
    // bana sipariş önerileri diyor"): burada bağımsız/tek başına "öner"
    // kelimesi de tetikleyiciydi. "Öner" GERÇEK, yaygın bir Türk soyadı/
    // isim — bu satır "cari" kelimesi hiç geçmeyen, sadece müşteri adı
    // "Öner" (veya "Önerşan", "Törnöner" gibi içinde bu 4 harfi
    // barındıran HERHANGİ bir isim) olan HER soruyu, daha spesifik cari
    // kurallarına (yukarıda) hiç fırsat vermeden "Sipariş Önerileri"ne
    // kaçırıyordu. "sipariş öner"/"ne sipariş" gibi asıl beklenen
    // kalıplar zaten bu amacı karşılıyor — tek başına "öner" kaldırıldı.
    if (_ic(s, ['sipariş öner','ne sipariş','sipariş ver','al bunları'])) return AiIntent.oneri;

    // Context'ten devam: önceki intent ne ise devam et
    if (_sonIntent != null && !_ic(s, ['ne','nasıl','ne zaman','kim','hangi','kaç'])) {
      return _sonIntent!;
    }

    return AiIntent.bilinmiyor;
  }
}
