// lib/depolar/urun_rapor_deposu.dart
//
// Ürün Raporu (Satış / Alım) için SQL toplulaştırma katmanı.
// Filtreler: tarih aralığı, ana grup, marka, cari, arama metni.
// Gruplama: ürün | ana grup | marka | cari.
//
// Kurallar (uygulamadaki mevcut sözleşmeler):
//  • satis_kalem.toplam_tutar KDV DAHİL; maliyet alis_fiyat_kdv (KDV dahil)
//    ile hesaplanır — ciro ile aynı baz (bkz. Net Kâr KDV dahil maliyet fix).
//  • İptal / silinmiş / sync çakışma kopyası satışlar dahil edilmez.
//  • Alım = tedarikci_siparisler.durum = 'teslim_alindi' (iptal edilenler hariç).
//  • Tarih karşılaştırması substr(tarih,1,10) ile yapılır: 'yyyy-MM-dd HH:mm'
//    ve ISO 'T' biçimlerinin ikisinde de doğru çalışır.
import '../veri/database/veritabani.dart';

enum UrunRaporGruplama { urun, anaGrup, marka, cari }

extension UrunRaporGruplamaEtiket on UrunRaporGruplama {
  String get etiket => switch (this) {
        UrunRaporGruplama.urun => 'Ürün',
        UrunRaporGruplama.anaGrup => 'Ana Grup',
        UrunRaporGruplama.marka => 'Marka',
        UrunRaporGruplama.cari => 'Cari',
      };
}

class UrunRaporFiltre {
  final DateTime bas;
  final DateTime bit;
  final String? anaGrup;
  final String? marka;
  final int? cariId;
  final String arama;
  final UrunRaporGruplama gruplama;

  const UrunRaporFiltre({
    required this.bas,
    required this.bit,
    this.anaGrup,
    this.marka,
    this.cariId,
    this.arama = '',
    this.gruplama = UrunRaporGruplama.urun,
  });

  factory UrunRaporFiltre.buAy() {
    final n = DateTime.now();
    return UrunRaporFiltre(
        bas: DateTime(n.year, n.month, 1), bit: DateTime(n.year, n.month, n.day));
  }

  /// null'ı geri yazabilmek için ayrı bayraklar.
  UrunRaporFiltre kopya({
    DateTime? bas,
    DateTime? bit,
    String? anaGrup,
    bool anaGrupTemizle = false,
    String? marka,
    bool markaTemizle = false,
    int? cariId,
    bool cariTemizle = false,
    String? arama,
    UrunRaporGruplama? gruplama,
  }) =>
      UrunRaporFiltre(
        bas: bas ?? this.bas,
        bit: bit ?? this.bit,
        anaGrup: anaGrupTemizle ? null : (anaGrup ?? this.anaGrup),
        marka: markaTemizle ? null : (marka ?? this.marka),
        cariId: cariTemizle ? null : (cariId ?? this.cariId),
        arama: arama ?? this.arama,
        gruplama: gruplama ?? this.gruplama,
      );

  bool get filtreVar =>
      anaGrup != null || marka != null || cariId != null || arama.isNotEmpty;
}

class UrunRaporSatir {
  final String anahtar; // gruplama anahtarı (ürün id, grup adı…)
  final String ad;
  final String alt; // ürün: kod/barkod; diğer: ürün çeşit sayısı
  final String anaGrup;
  final String marka;
  final double miktar;
  final double tutar; // satış: KDV dahil ciro, alım: alım tutarı
  final double maliyet; // sadece satış
  final int fisSayisi;

  const UrunRaporSatir({
    required this.anahtar,
    required this.ad,
    required this.alt,
    required this.anaGrup,
    required this.marka,
    required this.miktar,
    required this.tutar,
    required this.maliyet,
    required this.fisSayisi,
  });

  double get kar => tutar - maliyet;
  double get karMarji => tutar > 0 ? (kar / tutar) * 100 : 0;
  double get ortBirimFiyat => miktar > 0 ? tutar / miktar : 0;
}

class UrunRaporSonuc {
  final List<UrunRaporSatir> satirlar;
  final double toplamMiktar;
  final double toplamTutar;
  final double toplamMaliyet;
  final int fisSayisi;
  const UrunRaporSonuc({
    required this.satirlar,
    required this.toplamMiktar,
    required this.toplamTutar,
    required this.toplamMaliyet,
    required this.fisSayisi,
  });
  double get toplamKar => toplamTutar - toplamMaliyet;
}

class UrunRaporDeposu {
  final Veritabani _db = Veritabani();

  static String _gun(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<String>> markalariGetir() async {
    final db = await _db.db;
    final r = await db.rawQuery(
        "SELECT DISTINCT marka FROM urunler WHERE marka IS NOT NULL AND TRIM(marka) <> '' AND is_deleted = 0 ORDER BY marka");
    return r.map((e) => e['marka'] as String).toList();
  }

  Future<List<String>> anaGruplariGetir() async {
    final db = await _db.db;
    final r = await db.rawQuery(
        "SELECT DISTINCT ana_grup FROM urunler WHERE ana_grup IS NOT NULL AND TRIM(ana_grup) <> '' AND is_deleted = 0 ORDER BY ana_grup");
    return r.map((e) => e['ana_grup'] as String).toList();
  }

  Future<List<({int id, String unvan})>> carileriGetir() async {
    final db = await _db.db;
    final r = await db.rawQuery(
        'SELECT id, unvan FROM cari WHERE is_deleted = 0 ORDER BY unvan');
    return r.map((e) => (id: e['id'] as int, unvan: e['unvan'] as String)).toList();
  }

  Future<UrunRaporSonuc> satisRaporu(UrunRaporFiltre f) => _calistir(f, satis: true);
  Future<UrunRaporSonuc> alimRaporu(UrunRaporFiltre f) => _calistir(f, satis: false);

  Future<UrunRaporSonuc> _calistir(UrunRaporFiltre f, {required bool satis}) async {
    final db = await _db.db;

    // Kaynak tablolar
    final String kalem = satis ? 'satis_kalem' : 'tedarikci_siparis_kalem';
    final String fis = satis ? 'satislar' : 'tedarikci_siparisler';
    final String fisFk = satis ? 'satis_id' : 'siparis_id';
    final String tarihKol = satis ? 'f.tarih' : 'f.siparis_tarihi';
    final String miktarKol = satis ? 'k.miktar' : 'k.teslim_mik';
    final String tutarKol = satis ? 'k.toplam_tutar' : 'k.toplam_tutar';
    final String maliyetIfade =
        satis ? 'k.miktar * k.alis_fiyat_kdv' : '0';

    final where = <String>[
      'substr($tarihKol,1,10) >= ?',
      'substr($tarihKol,1,10) <= ?',
      'f.is_deleted = 0',
      if (satis) ...[
        'f.iptal = 0',
        'f.sync_cakisma_kopyasi = 0',
      ] else
        "f.durum = 'teslim_alindi'",
      if (!satis) '${miktarKol} > 0',
    ];
    final args = <Object?>[_gun(f.bas), _gun(f.bit)];

    if (f.anaGrup != null) {
      where.add('u.ana_grup = ?');
      args.add(f.anaGrup);
    }
    if (f.marka != null) {
      where.add('u.marka = ?');
      args.add(f.marka);
    }
    if (f.cariId != null) {
      where.add('f.cari_id = ?');
      args.add(f.cariId);
    }
    final q = f.arama.trim();
    if (q.isNotEmpty) {
      where.add('(u.urun_adi LIKE ? OR u.barkod LIKE ? OR u.kod LIKE ?)');
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }

    // Gruplama ifadeleri: anahtar, görünen ad, alt başlık
    final (String key, String ad, String alt) = switch (f.gruplama) {
      UrunRaporGruplama.urun => (
          'CAST(k.urun_id AS TEXT)',
          'MAX(u.urun_adi)',
          "COALESCE(MAX(u.barkod), MAX(u.kod), '')"
        ),
      UrunRaporGruplama.anaGrup => (
          "COALESCE(NULLIF(TRIM(u.ana_grup),''),'(Grupsuz)')",
          "COALESCE(NULLIF(TRIM(u.ana_grup),''),'(Grupsuz)')",
          "COUNT(DISTINCT k.urun_id) || ' çeşit'"
        ),
      UrunRaporGruplama.marka => (
          "COALESCE(NULLIF(TRIM(u.marka),''),'(Markasız)')",
          "COALESCE(NULLIF(TRIM(u.marka),''),'(Markasız)')",
          "COUNT(DISTINCT k.urun_id) || ' çeşit'"
        ),
      UrunRaporGruplama.cari => (
          "COALESCE(CAST(f.cari_id AS TEXT),'-')",
          satis
              ? "COALESCE(MAX(c.unvan),'Perakende (Carisiz)')"
              : "COALESCE(MAX(c.unvan),'(Tedarikçisiz)')",
          "COUNT(DISTINCT k.urun_id) || ' çeşit'"
        ),
    };

    final sql = '''
      SELECT $key AS anahtar, $ad AS ad, $alt AS alt,
             COALESCE(MAX(u.ana_grup),'') AS ana_grup,
             COALESCE(MAX(u.marka),'') AS marka,
             SUM($miktarKol) AS miktar,
             SUM($tutarKol) AS tutar,
             SUM($maliyetIfade) AS maliyet,
             COUNT(DISTINCT f.id) AS fis_sayisi
      FROM $kalem k
      JOIN $fis f ON f.id = k.$fisFk
      JOIN urunler u ON u.id = k.urun_id
      LEFT JOIN cari c ON c.id = f.cari_id
      WHERE ${where.join(' AND ')}
      GROUP BY $key
      ORDER BY tutar DESC
    ''';
    final rows = await db.rawQuery(sql, args);

    double tm = 0, tt = 0, tmal = 0;
    final satirlar = rows.map((r) {
      final s = UrunRaporSatir(
        anahtar: '${r['anahtar']}',
        ad: (r['ad'] as String?) ?? '',
        alt: (r['alt'] as String?) ?? '',
        anaGrup: (r['ana_grup'] as String?) ?? '',
        marka: (r['marka'] as String?) ?? '',
        miktar: (r['miktar'] as num?)?.toDouble() ?? 0,
        tutar: (r['tutar'] as num?)?.toDouble() ?? 0,
        maliyet: (r['maliyet'] as num?)?.toDouble() ?? 0,
        fisSayisi: (r['fis_sayisi'] as num?)?.toInt() ?? 0,
      );
      tm += s.miktar;
      tt += s.tutar;
      tmal += s.maliyet;
      return s;
    }).toList();

    // Toplam fiş sayısı: satır toplamı bir fişi birden çok kez sayar,
    // bu yüzden ayrı (tekil) sorgu.
    final fisRow = await db.rawQuery('''
      SELECT COUNT(DISTINCT f.id) AS n
      FROM $kalem k
      JOIN $fis f ON f.id = k.$fisFk
      JOIN urunler u ON u.id = k.urun_id
      WHERE ${where.join(' AND ')}
    ''', args);
    final fisSayisi = (fisRow.first['n'] as num?)?.toInt() ?? 0;

    return UrunRaporSonuc(
      satirlar: satirlar,
      toplamMiktar: tm,
      toplamTutar: tt,
      toplamMaliyet: tmal,
      fisSayisi: fisSayisi,
    );
  }
}
