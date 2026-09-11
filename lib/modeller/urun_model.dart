// lib/modeller/urun_model.dart
class UrunModel {
  final int? id;
  final String? globalId;
  final String? kod;
  final String? barkod;
  final String? barkodlar;
  final String urunAdi;
  final String? alternatifUrunAdi;
  final String birimAdi;
  final double alisFiyat;
  /// Döviz bazlı fiyatlandırma — dolu ise bu ürün belirli bir yabancı
  /// para tutarına "sabitlenmiş" demektir (ör. "her zaman 2 USD").
  /// Kur değiştiğinde "Toplu Döviz Güncelleme" ekranından bu ürünlerin
  /// TL fiyatı yeniden hesaplanabilir.
  final String? dovizKodu;
  final double? dovizTutari;
  final double alisFiyatKdvDahil;
  final double satisFiyati;
  final double stok;
  final double toplamMaliyet;
  final double toplamStok;
  final double alisKdvOran;
  final String kdvOran;
  final int?    kategoriId;
  final String? anaGrup;
  final String? altGrup;
  final bool aktif;
  final bool seriNoTakibi;
  final bool lotTakibi;
  final String? lotNo;
  final String? sonKullanmaTarihi;
  final String? alan1;
  final String? alan2;
  final String? alan3;
  final String? alan4;
  final String paraBirimi;
  final double indirimOrani;
  final bool otomatikIndirim;
  final double sonAlimIndirimOran;
  final double minimumStok;
  final double maksimumStok;
  final double maksimumSatirMiktari;
  final String? renk;
  final String? beden;
  final String? sube;
  final String? resimYolu;
  // Kullanıcı isteği: QR bulut menüde görsel gösterilebilmesi için —
  // resimYolu cihazın kendi dosya yolu, resimUrl ise Supabase
  // Storage'a yüklendiğinde oluşan, internetten erişilebilen adres.
  final String? resimUrl;
  // Kullanıcı isteği: 400 üründen sadece seçilenler QR menüde
  // görünsün (Kafe/Restoran ürünleri gibi) — market/yöresel ürünler
  // QR menüde görünmesin, ama kasada/garson tarafından satılabilsin.
  final bool qrMenude;
  // Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
  // profesyonel sistem." Genel toptan taban fiyatı (fiyat grubu/kademe
  // tanımlanmamışsa bayi/toptan müşterilere bu fiyat uygulanır).
  final double toptanFiyat;
  // 1 koli kaç adet/kg (0 = koli tanımlı değil, sadece adet/kg satılır).
  final double koliIciMiktar;
  final String koliBirimAdi; // 'Koli', 'Paket', 'Palet', 'Kasa' — esnek
  // Ürünün TEMEL satış birimi: 'adet' | 'kg' — kg ise koli kavramı
  // genelde uygulanmaz ama yine de tanımlanabilir bırakılır.
  final String satisBirimiTipi;
  // Kullanıcı isteği: "toptan satış tıkladık, o listede gözüksün,
  // diğerleri gözükmesin" — QR Menü'deki qrMenude ile birebir aynı
  // desen, ama toptan ürün listesi için ayrı bir işaret.
  final bool toptanSatista;
  // Kullanıcı isteği: profesyonel B2B/toptan sistemlerin standart
  // kuralı — "asgari sipariş miktarı" (MOQ). 0 = sınır yok.
  final double asgariSiparisMiktari;
  final String? uretici;
  final String? marka;
  final String? model;
  final String? grupSorumlusu;
  final String? mensei;
  final String? rafNumarasi;
  final int? rafOmru;
  final String? pluNumarasi;
  final int plu;          // 0=normal 1=PLU panelinde göster
  final int pluKartBoyut; // 1=küçük 2=orta 3=büyük
  final double puanOrani;
  final String? muhasebeKodu;
  final String? muafiyetKodu;
  final double resmiBakiye;
  final String? barkodOlcuBirimi;
  final double en;
  final double boy;
  final double yukseklik;
  final double agirlik;
  final String? eskiKodu;
  final String kartTipi;
  final String? seriNumarasi;
  final String? fiyatGuncellemeTarih;
  final String? fiyatGuncelleyenKullanici;
  final String? barkodYazdirmaTarih;
  final String? barkodYazdiranKullanici;
  final String? maliyetGuncellemeTarih;
  final String? maliyetGuncelleyenKullanici;
  final String? guncellemeTarihi;
  final String? kayitTarihi;
  final String? guncelleyenKullanici;
  final String? kaydedenKullanici;
  final String? lastUpdated;
  final String? syncStatus;
  final bool isDeleted;
  // DByii uyumlu ek alanlar
  final double indirimliFiyatKayitli;
  final double hacim;
  final bool evrakKontrolAktif;
  final String? lotAciklama;
  final double eskiFiyat;
  final DateTime? eskiFiyatTarih;
  final String? promosyonGrup;
  final bool promosyonAktif;
  final double receteKatsayi;
  final double netAlisFiyat;

  // Hesaplanan alanlar
  double get stokDegeri => stok * alisFiyat;
  double get toplamStokDegeri => toplamStok * alisFiyat;
  // DB'ye kayıtlı indirimli fiyat varsa onu kullan, yoksa hesapla
  double get indirimliFiyat {
    if (indirimliFiyatKayitli > 0) return indirimliFiyatKayitli;
    if (indirimOrani > 0) return satisFiyati * (1 - indirimOrani / 100);
    return satisFiyati;
  }
  double get indirimliFiyati => indirimliFiyat;
  
  double get satisFiyatiKdvDahil {
    final kdv = double.tryParse(kdvOran) ?? 0;
    return satisFiyati * (1 + kdv / 100);
  }
  
  double get karOraniKdvli {
    final kdvliFiyat = satisFiyatiKdvDahil;
    return alisFiyat > 0 ? (kdvliFiyat - alisFiyat) / alisFiyat * 100 : 0;
  }
  
  double get karOrani {
    // alisFiyatKdvDahil varsa onu kullan, yoksa alisFiyat'a bak
    final alis = alisFiyatKdvDahil > 0 ? alisFiyatKdvDahil : alisFiyat;
    return alis > 0 ? ((satisFiyati - alis) / alis) * 100 : 0;
  }

  bool get kritikStok => stok <= minimumStok && minimumStok > 0;

  const UrunModel({
    this.id,
    this.globalId,
    this.kod,
    this.barkod,
    this.barkodlar,
    required this.urunAdi,
    this.alternatifUrunAdi,
    this.birimAdi = 'Adet',
    this.alisFiyat = 0,
    this.dovizKodu, this.dovizTutari,
    this.alisFiyatKdvDahil = 0,
    this.satisFiyati = 0,
    this.stok = 0,
    this.toplamMaliyet = 0,
    this.toplamStok = 0,
    this.alisKdvOran = 18,
    this.kdvOran = '18',
    this.kategoriId,
    this.anaGrup,
    this.altGrup,
    this.aktif = true,
    this.seriNoTakibi = false,
    this.lotTakibi = false,
    this.lotNo,
    this.sonKullanmaTarihi,
    this.alan1,
    this.alan2,
    this.alan3,
    this.alan4,
    this.paraBirimi = 'TRY',
    this.indirimOrani = 0,
    this.otomatikIndirim = false,
    this.sonAlimIndirimOran = 0,
    this.minimumStok = 0,
    this.maksimumStok = 0,
    this.maksimumSatirMiktari = 0,
    this.renk,
    this.beden,
    this.sube,
    this.resimYolu,
    this.resimUrl,
    this.qrMenude = false,
    this.toptanFiyat = 0,
    this.koliIciMiktar = 0,
    this.koliBirimAdi = 'Koli',
    this.satisBirimiTipi = 'adet',
    this.toptanSatista = false,
    this.asgariSiparisMiktari = 0,
    this.uretici,
    this.marka,
    this.model,
    this.grupSorumlusu,
    this.mensei,
    this.rafNumarasi,
    this.rafOmru,
    this.pluNumarasi,
    this.plu = 0,
    this.pluKartBoyut = 2,
    this.puanOrani = 0,
    this.muhasebeKodu,
    this.muafiyetKodu,
    this.resmiBakiye = 0,
    this.indirimliFiyatKayitli = 0,
    this.hacim = 0,
    this.evrakKontrolAktif = false,
    this.lotAciklama,
    this.eskiFiyat = 0,
    this.eskiFiyatTarih,
    this.promosyonGrup,
    this.promosyonAktif = false,
    this.receteKatsayi = 1,
    this.netAlisFiyat = 0,
    this.barkodOlcuBirimi,
    this.en = 0,
    this.boy = 0,
    this.yukseklik = 0,
    this.agirlik = 0,
    this.eskiKodu,
    this.kartTipi = 'Standart',
    this.seriNumarasi,
    this.fiyatGuncellemeTarih,
    this.fiyatGuncelleyenKullanici,
    this.barkodYazdirmaTarih,
    this.barkodYazdiranKullanici,
    this.maliyetGuncellemeTarih,
    this.maliyetGuncelleyenKullanici,
    this.guncellemeTarihi,
    this.kayitTarihi,
    this.guncelleyenKullanici,
    this.kaydedenKullanici,
    this.lastUpdated,
    this.syncStatus = 'synced',
    this.isDeleted = false,
  });

  static UrunModel? fromMapSafe(Map<String, dynamic> m) {
    try { return UrunModel.fromMap(m); } catch (_) { return null; }
  }

  factory UrunModel.fromMap(Map<String, dynamic> m) {
    double toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    bool toBool(dynamic v, {bool varsayilan = false}) =>
        v == null ? varsayilan : (v == 1 || v == true);

    return UrunModel(
      id: m['id'] as int?,
      globalId: m['global_id'] as String?,
      kod: m['kod'] as String?,
      barkod: m['barkod'] as String?,
      barkodlar: m['barkodlar'] as String?,
      urunAdi: m['urun_adi'] as String? ?? '',
      alternatifUrunAdi: m['alternatif_urun_adi'] as String?,
      birimAdi: m['birim_adi'] as String? ?? 'Adet',
      alisFiyat: toDouble(m['alis_fiyat']),
      dovizKodu: m['doviz_kodu'] as String?,
      dovizTutari: (m['doviz_tutari'] as num?)?.toDouble(),
      alisFiyatKdvDahil: toDouble(m['alis_fiyat_kdv_dahil']),
      satisFiyati: toDouble(m['satis_fiyati']),
      stok: toDouble(m['stok']),
      toplamMaliyet: toDouble(m['toplam_maliyet']),
      toplamStok: toDouble(m['toplam_stok']),
      alisKdvOran: toDouble(m['alis_kdv_oran']),
      kdvOran: m['kdv_oran'] as String? ?? '18',
      kategoriId: m['kategori_id'] as int?,
      anaGrup: m['ana_grup'] as String?,
      altGrup: m['alt_grup'] as String?,
      aktif: toBool(m['aktif'], varsayilan: true),
      seriNoTakibi: toBool(m['seri_no_takibi']),
      lotTakibi: toBool(m['lot_takibi']),
      lotNo: m['lot_no'] as String?,
      sonKullanmaTarihi: m['son_kullanma_tarihi'] as String?,
      alan1: m['alan1'] as String?,
      alan2: m['alan2'] as String?,
      alan3: m['alan3'] as String?,
      alan4: m['alan4'] as String?,
      paraBirimi: m['para_birimi'] as String? ?? 'TRY',
      indirimOrani: toDouble(m['indirim_orani']),
      otomatikIndirim: toBool(m['otomatik_indirim']),
      sonAlimIndirimOran: toDouble(m['son_alim_indirim_oran']),
      minimumStok: toDouble(m['minimum_stok']),
      maksimumStok: toDouble(m['maksimum_stok']),
      maksimumSatirMiktari: toDouble(m['maksimum_satir_miktari']),
      renk: m['renk'] as String?,
      beden: m['beden'] as String?,
      sube: m['sube'] as String?,
      resimYolu: m['resim_yolu'] as String?,
      resimUrl: m['resim_url'] as String?,
      qrMenude: ((m['qr_menude'] as int?) ?? 0) == 1,
      toptanFiyat: (m['toptan_fiyat'] as num?)?.toDouble() ?? 0,
      koliIciMiktar: (m['koli_ici_miktar'] as num?)?.toDouble() ?? 0,
      koliBirimAdi: m['koli_birim_adi'] as String? ?? 'Koli',
      satisBirimiTipi: m['satis_birimi_tipi'] as String? ?? 'adet',
      toptanSatista: ((m['toptan_satista'] as int?) ?? 0) == 1,
      asgariSiparisMiktari: (m['asgari_siparis_miktari'] as num?)?.toDouble() ?? 0,
      uretici: m['uretici'] as String?,
      marka: m['marka'] as String?,
      model: m['model'] as String?,
      grupSorumlusu: m['grup_sorumlusu'] as String?,
      mensei: m['mensei'] as String?,
      rafNumarasi: m['raf_numarasi'] as String?,
      rafOmru: m['raf_omru'] as int?,
      pluNumarasi:   m['plu_numarasi']    as String?,
      plu:           (m['plu']            as int? ?? 0),
      pluKartBoyut:  (m['plu_kart_boyut'] as int? ?? 2),
      puanOrani: toDouble(m['puan_orani']),
      muhasebeKodu: m['muhasebe_kodu'] as String?,
      muafiyetKodu: m['muafiyet_kodu'] as String?,
      resmiBakiye: toDouble(m['resmi_bakiye']),
      indirimliFiyatKayitli: toDouble(m['indirimli_fiyat']),
      hacim: toDouble(m['hacim']),
      evrakKontrolAktif: toBool(m['evrak_kontrol_aktif']),
      lotAciklama: m['lot_aciklama'] as String?,
      eskiFiyat: toDouble(m['eski_fiyat']),
      eskiFiyatTarih: m['eski_fiyat_tarih'] != null
          ? DateTime.tryParse(m['eski_fiyat_tarih'].toString()) : null,
      promosyonGrup: m['promosyon_grup'] as String?,
      promosyonAktif: toBool(m['promosyon_aktif']),
      receteKatsayi: m['recete_katsayi'] != null ? toDouble(m['recete_katsayi']) : 1.0,
      netAlisFiyat: toDouble(m['net_alis_fiyat']),
      barkodOlcuBirimi: m['barkod_olcu_birimi'] as String?,
      en: toDouble(m['en']),
      boy: toDouble(m['boy']),
      yukseklik: toDouble(m['yukseklik']),
      agirlik: toDouble(m['agirlik']),
      eskiKodu: m['eski_kodu'] as String?,
      kartTipi: m['kart_tipi'] as String? ?? 'Standart',
      seriNumarasi: m['seri_numarasi'] as String?,
      fiyatGuncellemeTarih: m['fiyat_guncelleme_tarih'] as String?,
      fiyatGuncelleyenKullanici: m['fiyat_guncelleyen_kullanici'] as String?,
      barkodYazdirmaTarih: m['barkod_yazdirma_tarih'] as String?,
      barkodYazdiranKullanici: m['barkod_yazdiran_kullanici'] as String?,
      maliyetGuncellemeTarih: m['maliyet_guncelleme_tarih'] as String?,
      maliyetGuncelleyenKullanici: m['maliyet_guncelleyen_kullanici'] as String?,
      guncellemeTarihi: m['guncelleme_tarihi'] as String?,
      kayitTarihi: m['kayit_tarihi'] as String?,
      guncelleyenKullanici: m['guncelleyen_kullanici'] as String?,
      kaydedenKullanici: m['kaydeden_kullanici'] as String?,
      lastUpdated: m['last_updated'] as String?,
      syncStatus: m['sync_status'] as String? ?? 'synced',
      isDeleted: toBool(m['is_deleted']),
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    if (kod != null) 'kod': kod,
    if (barkod != null) 'barkod': barkod,
    if (barkodlar != null) 'barkodlar': barkodlar,
    'urun_adi': urunAdi,
    if (alternatifUrunAdi != null) 'alternatif_urun_adi': alternatifUrunAdi,
    'birim_adi': birimAdi,
    'alis_fiyat': alisFiyat,
    if (dovizKodu != null) 'doviz_kodu': dovizKodu,
    if (dovizTutari != null) 'doviz_tutari': dovizTutari,
    'alis_fiyat_kdv_dahil': alisFiyatKdvDahil,
    'satis_fiyati': satisFiyati,
    'stok': stok,
    'toplam_maliyet': toplamMaliyet,
    'toplam_stok': toplamStok,
    'alis_kdv_oran': alisKdvOran,
    'kdv_oran': kdvOran,
    if (kategoriId != null) 'kategori_id': kategoriId,
    if (anaGrup != null) 'ana_grup': anaGrup,
    if (altGrup != null) 'alt_grup': altGrup,
    'aktif': aktif ? 1 : 0,
    'seri_no_takibi': seriNoTakibi ? 1 : 0,
    'lot_takibi': lotTakibi ? 1 : 0,
    if (lotNo != null) 'lot_no': lotNo,
    if (sonKullanmaTarihi != null) 'son_kullanma_tarihi': sonKullanmaTarihi,
    if (alan1 != null) 'alan1': alan1,
    if (alan2 != null) 'alan2': alan2,
    if (alan3 != null) 'alan3': alan3,
    if (alan4 != null) 'alan4': alan4,
    'para_birimi': paraBirimi,
    'indirim_orani': indirimOrani,
    'otomatik_indirim': otomatikIndirim ? 1 : 0,
    'son_alim_indirim_oran': sonAlimIndirimOran,
    'minimum_stok': minimumStok,
    'maksimum_stok': maksimumStok,
    'maksimum_satir_miktari': maksimumSatirMiktari,
    if (renk != null) 'renk': renk,
    if (beden != null) 'beden': beden,
    if (sube != null) 'sube': sube,
    if (resimYolu != null) 'resim_yolu': resimYolu,
    if (resimUrl != null) 'resim_url': resimUrl,
    'qr_menude': qrMenude ? 1 : 0,
    'toptan_fiyat': toptanFiyat,
    'koli_ici_miktar': koliIciMiktar,
    'koli_birim_adi': koliBirimAdi,
    'satis_birimi_tipi': satisBirimiTipi,
    'toptan_satista': toptanSatista ? 1 : 0,
    'asgari_siparis_miktari': asgariSiparisMiktari,
    if (uretici != null) 'uretici': uretici,
    if (marka != null) 'marka': marka,
    if (model != null) 'model': model,
    if (grupSorumlusu != null) 'grup_sorumlusu': grupSorumlusu,
    if (mensei != null) 'mensei': mensei,
    if (rafNumarasi != null) 'raf_numarasi': rafNumarasi,
    if (rafOmru != null) 'raf_omru': rafOmru,
    if (pluNumarasi != null) 'plu_numarasi': pluNumarasi,
    'plu':            plu,
    'plu_kart_boyut': pluKartBoyut,
    'puan_orani': puanOrani,
    if (muhasebeKodu != null) 'muhasebe_kodu': muhasebeKodu,
    if (muafiyetKodu != null) 'muafiyet_kodu': muafiyetKodu,
    'resmi_bakiye': resmiBakiye,
    'indirimli_fiyat': indirimliFiyatKayitli,
    'hacim': hacim,
    'evrak_kontrol_aktif': evrakKontrolAktif ? 1 : 0,
    if (lotAciklama != null) 'lot_aciklama': lotAciklama,
    'eski_fiyat': eskiFiyat,
    if (eskiFiyatTarih != null) 'eski_fiyat_tarih': eskiFiyatTarih!.toIso8601String(),
    if (promosyonGrup != null) 'promosyon_grup': promosyonGrup,
    'promosyon_aktif': promosyonAktif ? 1 : 0,
    'recete_katsayi': receteKatsayi,
    'net_alis_fiyat': netAlisFiyat,
    if (barkodOlcuBirimi != null) 'barkod_olcu_birimi': barkodOlcuBirimi,
    'en': en, 'boy': boy, 'yukseklik': yukseklik, 'agirlik': agirlik,
    if (eskiKodu != null) 'eski_kodu': eskiKodu,
    'kart_tipi': kartTipi,
    if (seriNumarasi != null) 'seri_numarasi': seriNumarasi,
    if (fiyatGuncellemeTarih != null) 'fiyat_guncelleme_tarih': fiyatGuncellemeTarih,
    if (fiyatGuncelleyenKullanici != null) 'fiyat_guncelleyen_kullanici': fiyatGuncelleyenKullanici,
    if (barkodYazdirmaTarih != null) 'barkod_yazdirma_tarih': barkodYazdirmaTarih,
    if (barkodYazdiranKullanici != null) 'barkod_yazdiran_kullanici': barkodYazdiranKullanici,
    if (maliyetGuncellemeTarih != null) 'maliyet_guncelleme_tarih': maliyetGuncellemeTarih,
    if (maliyetGuncelleyenKullanici != null) 'maliyet_guncelleyen_kullanici': maliyetGuncelleyenKullanici,
    if (guncellemeTarihi != null) 'guncelleme_tarihi': guncellemeTarihi,
    if (kayitTarihi != null) 'kayit_tarihi': kayitTarihi,
    if (guncelleyenKullanici != null) 'guncelleyen_kullanici': guncelleyenKullanici,
    if (kaydedenKullanici != null) 'kaydeden_kullanici': kaydedenKullanici,
    'last_updated': lastUpdated ?? DateTime.now().toIso8601String(),
    'sync_status': syncStatus ?? 'synced',
    'is_deleted': isDeleted ? 1 : 0,
  };

  UrunModel copyWith({
    int? id,
    String? globalId,
    String? kod,
    String? barkod,
    String? barkodlar,
    String? urunAdi,
    String? alternatifUrunAdi,
    String? birimAdi,
    double? alisFiyat,
    String? dovizKodu, double? dovizTutari,
    double? alisFiyatKdvDahil,
    double? satisFiyati,
    double? stok,
    double? toplamMaliyet,
    double? toplamStok,
    double? alisKdvOran,
    String? kdvOran,
    int?    kategoriId,
    String? anaGrup,
    String? altGrup,
    bool? aktif,
    bool? seriNoTakibi,
    bool? lotTakibi,
    String? lotNo,
    String? sonKullanmaTarihi,
    String? alan1,
    String? alan2,
    String? alan3,
    String? alan4,
    String? paraBirimi,
    double? indirimOrani,
    bool? otomatikIndirim,
    double? sonAlimIndirimOran,
    double? minimumStok,
    double? maksimumStok,
    double? maksimumSatirMiktari,
    String? renk,
    String? beden,
    String? sube,
    String? resimYolu,
    String? resimUrl,
    bool? qrMenude,
    double? toptanFiyat,
    double? koliIciMiktar,
    String? koliBirimAdi,
    String? satisBirimiTipi,
    bool? toptanSatista,
    double? asgariSiparisMiktari,
    String? uretici,
    String? marka,
    String? model,
    String? grupSorumlusu,
    String? mensei,
    String? rafNumarasi,
    int? rafOmru,
    String? pluNumarasi,
    double? puanOrani,
    String? muhasebeKodu,
    String? muafiyetKodu,
    double? resmiBakiye,
    double? indirimliFiyatKayitli,
    double? eskiFiyat,
    DateTime? eskiFiyatTarih,
    String? promosyonGrup,
    bool? promosyonAktif,
    double? receteKatsayi,
    String? lotAciklama,
    double? hacim,
    bool? evrakKontrolAktif,
    double? netAlisFiyat,
    String? barkodOlcuBirimi,
    double? en,
    double? boy,
    double? yukseklik,
    double? agirlik,
    String? eskiKodu,
    String? kartTipi,
    String? seriNumarasi,
    String? fiyatGuncellemeTarih,
    String? fiyatGuncelleyenKullanici,
    String? barkodYazdirmaTarih,
    String? barkodYazdiranKullanici,
    String? maliyetGuncellemeTarih,
    String? maliyetGuncelleyenKullanici,
    String? guncellemeTarihi,
    String? kayitTarihi,
    String? guncelleyenKullanici,
    String? kaydedenKullanici,
    String? lastUpdated,
    String? syncStatus,
    bool? isDeleted,
  }) => UrunModel(
    id: id ?? this.id,
    globalId: globalId ?? this.globalId,
    kod: kod ?? this.kod,
    barkod: barkod ?? this.barkod,
    barkodlar: barkodlar ?? this.barkodlar,
    urunAdi: urunAdi ?? this.urunAdi,
    alternatifUrunAdi: alternatifUrunAdi ?? this.alternatifUrunAdi,
    birimAdi: birimAdi ?? this.birimAdi,
    alisFiyat: alisFiyat ?? this.alisFiyat,
    dovizKodu: dovizKodu ?? this.dovizKodu,
    dovizTutari: dovizTutari ?? this.dovizTutari,
    alisFiyatKdvDahil: alisFiyatKdvDahil ?? this.alisFiyatKdvDahil,
    satisFiyati: satisFiyati ?? this.satisFiyati,
    stok: stok ?? this.stok,
    toplamMaliyet: toplamMaliyet ?? this.toplamMaliyet,
    toplamStok: toplamStok ?? this.toplamStok,
    alisKdvOran: alisKdvOran ?? this.alisKdvOran,
    kdvOran: kdvOran ?? this.kdvOran,
    anaGrup: anaGrup ?? this.anaGrup,
    altGrup: altGrup ?? this.altGrup,
    aktif: aktif ?? this.aktif,
    seriNoTakibi: seriNoTakibi ?? this.seriNoTakibi,
    lotTakibi: lotTakibi ?? this.lotTakibi,
    lotNo: lotNo ?? this.lotNo,
    sonKullanmaTarihi: sonKullanmaTarihi ?? this.sonKullanmaTarihi,
    alan1: alan1 ?? this.alan1,
    alan2: alan2 ?? this.alan2,
    alan3: alan3 ?? this.alan3,
    alan4: alan4 ?? this.alan4,
    paraBirimi: paraBirimi ?? this.paraBirimi,
    indirimOrani: indirimOrani ?? this.indirimOrani,
    otomatikIndirim: otomatikIndirim ?? this.otomatikIndirim,
    sonAlimIndirimOran: sonAlimIndirimOran ?? this.sonAlimIndirimOran,
    minimumStok: minimumStok ?? this.minimumStok,
    maksimumStok: maksimumStok ?? this.maksimumStok,
    maksimumSatirMiktari: maksimumSatirMiktari ?? this.maksimumSatirMiktari,
    renk: renk ?? this.renk,
    beden: beden ?? this.beden,
    sube: sube ?? this.sube,
    resimYolu: resimYolu ?? this.resimYolu,
    resimUrl: resimUrl ?? this.resimUrl,
    qrMenude: qrMenude ?? this.qrMenude,
    toptanFiyat: toptanFiyat ?? this.toptanFiyat,
    koliIciMiktar: koliIciMiktar ?? this.koliIciMiktar,
    koliBirimAdi: koliBirimAdi ?? this.koliBirimAdi,
    satisBirimiTipi: satisBirimiTipi ?? this.satisBirimiTipi,
    toptanSatista: toptanSatista ?? this.toptanSatista,
    asgariSiparisMiktari: asgariSiparisMiktari ?? this.asgariSiparisMiktari,
    uretici: uretici ?? this.uretici,
    marka: marka ?? this.marka,
    model: model ?? this.model,
    grupSorumlusu: grupSorumlusu ?? this.grupSorumlusu,
    mensei: mensei ?? this.mensei,
    rafNumarasi: rafNumarasi ?? this.rafNumarasi,
    rafOmru: rafOmru ?? this.rafOmru,
    pluNumarasi: pluNumarasi ?? this.pluNumarasi,
    puanOrani: puanOrani ?? this.puanOrani,
    muhasebeKodu: muhasebeKodu ?? this.muhasebeKodu,
    muafiyetKodu: muafiyetKodu ?? this.muafiyetKodu,
    resmiBakiye: resmiBakiye ?? this.resmiBakiye,
    barkodOlcuBirimi: barkodOlcuBirimi ?? this.barkodOlcuBirimi,
    en: en ?? this.en,
    boy: boy ?? this.boy,
    yukseklik: yukseklik ?? this.yukseklik,
    agirlik: agirlik ?? this.agirlik,
    eskiKodu: eskiKodu ?? this.eskiKodu,
    kartTipi: kartTipi ?? this.kartTipi,
    seriNumarasi: seriNumarasi ?? this.seriNumarasi,
    fiyatGuncellemeTarih: fiyatGuncellemeTarih ?? this.fiyatGuncellemeTarih,
    fiyatGuncelleyenKullanici: fiyatGuncelleyenKullanici ?? this.fiyatGuncelleyenKullanici,
    barkodYazdirmaTarih: barkodYazdirmaTarih ?? this.barkodYazdirmaTarih,
    barkodYazdiranKullanici: barkodYazdiranKullanici ?? this.barkodYazdiranKullanici,
    maliyetGuncellemeTarih: maliyetGuncellemeTarih ?? this.maliyetGuncellemeTarih,
    maliyetGuncelleyenKullanici: maliyetGuncelleyenKullanici ?? this.maliyetGuncelleyenKullanici,
    guncellemeTarihi: guncellemeTarihi ?? this.guncellemeTarihi,
    kayitTarihi: kayitTarihi ?? this.kayitTarihi,
    guncelleyenKullanici: guncelleyenKullanici ?? this.guncelleyenKullanici,
    kaydedenKullanici: kaydedenKullanici ?? this.kaydedenKullanici,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    syncStatus: syncStatus ?? this.syncStatus,
    isDeleted: isDeleted ?? this.isDeleted,
  );

  // Excel dışa aktarma için satır oluştur
  List<dynamic> toExcelRow() => [
    id,
    kod,
    barkod,
    barkodlar,
    urunAdi,
    alternatifUrunAdi,
    birimAdi,
    alisFiyat,
    alisFiyatKdvDahil,
    satisFiyati,
    stok,
    stokDegeri,
    toplamMaliyet,
    toplamStok,
    toplamStokDegeri,
    alisKdvOran,
    kdvOran,
    anaGrup,
    altGrup,
    aktif ? 1 : 0,
    seriNoTakibi ? 1 : 0,
    alan1,
    alan2,
    paraBirimi,
    minimumStok,
    maksimumStok,
    alan3,
    alan4,
    renk,
    beden,
    sube,
    uretici,
    marka,
    model,
    rafNumarasi,
    rafOmru,
    pluNumarasi,
    puanOrani,
    indirimOrani,
    indirimliFiyat,
    lotTakibi ? 1 : 0,
    lotNo,
    sonAlimIndirimOran,
    muhasebeKodu,
    en,
    boy,
    yukseklik,
    hacim,
    agirlik,
    eskiKodu,
    kartTipi,
    seriNumarasi,
    otomatikIndirim ? 1 : 0,
    guncellemeTarihi,
    kayitTarihi,
    resimYolu,
    resimUrl,
    grupSorumlusu,
    mensei,
    barkodOlcuBirimi,
    karOrani,
    muafiyetKodu,
    resmiBakiye,
    fiyatGuncellemeTarih,
    fiyatGuncelleyenKullanici,
    barkodYazdirmaTarih,
    barkodYazdiranKullanici,
    maliyetGuncellemeTarih,
    maliyetGuncelleyenKullanici,
    maksimumSatirMiktari,
    guncelleyenKullanici,
    kaydedenKullanici,
    sonKullanmaTarihi,
  ];

  // Excel başlıkları - DIŞA AKTAR için
  static const List<String> excelBasliklari = [
    "Id", "Kod", "Barkod", "Barkodlar", "Ürün Adı", "Alternatif ürün adı",
    "Birim Adı", "Alış fiyat", "Alış fiyat kdv dahil", "Satış fiyatı",
    "Stok", "Stok değeri", "Toplam Maliyet", "Toplam Stok", "Toplam stok değeri",
    "Alış KDV Oran", "KDV Oran", "Ana Grup", "Alt Grup", "Aktif",
    "Seri no takibi", "Alan1", "Alan2", "Para Birimi", "Minimum Stok",
    "Maximum Stok", "Alan3", "Alan4", "Renk", "Beden", "Şube",
    "Üretici", "Marka", "Model", "Raf numarası", "Raf ömrü",
    "Plu numarası", "Puan Oranı", "Indirim Oranı", "İndirimli Fiyatı",
    "Lot Takibi", "Lot No", "Son alım indirim oran", "Muhasebe Kodu",
    "En", "Boy", "Yükseklik", "Hacim", "Ağırlık", "Eski kodu",
    "Kart Tipi", "Seri numarası", "Otomatik Indirim", "Güncelleme tarihi",
    "Kayıt tarihi", "Resim yolu", "Grup Sorumlusu", "Menşei",
    "Barkod Ölçü Birimi", "Kar oranı", "Muafiyet Kodu", "Resmi Bakiye",
    "Fiyat Güncelleme Tarih", "Fiyat Güncelleyen Kullanıcı",
    "Barkod Yazdırma Tarih", "Barkod Yazdıran Kullanıcı",
    "Maliyet Güncelleme Tarih", "Maliyet Güncelleyen Kullanıcı",
    "Maksimum Satır Miktarı", "Güncelleyen Kullanıcı", "Kaydeden Kullanıcı",
    "Son Kullanma Tarihi",
  ];

  // Uyumluluk getter'ları
  String get ad => urunAdi;
  double get satisFiyat => satisFiyati;
  double get stokMiktari => stok;
  String? get kategoriAdi => anaGrup;
  String? get markaAdi => marka;
  String get birim => birimAdi;
}