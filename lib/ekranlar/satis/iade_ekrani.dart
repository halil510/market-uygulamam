import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
// lib/ekranlar/satis/iade_ekrani.dart
// Eski uygulamanın BarkodluIadeEkrani mantığı yeni altyapıya tam entegre edildi

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'iade/iade_arama_widget.dart';
import 'iade/iade_urun_formu.dart';
import 'iade/iade_gecmis_widget.dart';
import 'iade/iade_cari_dialog.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/fatura_model.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/satis_kalem_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/satis_deposu.dart';
import '../../depolar/stok_deposu.dart';
import '../../depolar/kasa_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';
import '../../servisler/excel_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';

// Geçmiş İadeler sekmesinin kodu, dosya boyutunu azaltmak için ayrı bir
// dosyaya taşındı (bkz. dosyanın sonundaki not). part/part of ile bu
// dosyayla AYNI kütüphane kapsamını paylaşıyor — davranış değişmedi.
part 'iade_ekrani_gecmis.dart';
part 'iade_ekrani_fis.dart';
part 'iade_ekrani_hizli.dart';

// ─── Renk paleti ─────────────────────────────────────────────────────────────
class _R {
  static const bg = Color(0xFFF4F6FB);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF1A2E5A);
  static const orange = Color(0xFFFF6635);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const blue = Color(0xFF3B82F6);
  static const textD = Color(0xFF0F172A);
  static const textL = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const shadow = Color(0x10000000);
}

// ─── Hızlı mod öğesi ─────────────────────────────────────────────────────────
class _HizliItem {
  final UrunModel urun;
  int adet;
  _HizliItem({required this.urun, this.adet = 1});
}

// ─────────────────────────────────────────────────────────────────────────────
class IadeEkrani extends ConsumerStatefulWidget {
  final List<UrunModel>? baslangicUrunleri;
  // Kullanıcı isteği: "iade alımı yaptığımızda o ekran kapanacak" —
  // toptan cari panelinden tek-ürünlük hızlı iade akışı için. Normal
  // (çok kalemli, sekmeli) perakende iade akışını BOZMAMAK için
  // varsayılan false — sadece açıkça istenirse otomatik kapanır.
  final bool otomatikKapat;
  const IadeEkrani(
      {super.key, this.baslangicUrunleri, this.otomatikKapat = false});

  @override
  ConsumerState<IadeEkrani> createState() => _IadeEkraniState();
}

class _IadeEkraniState extends ConsumerState<IadeEkrani>
    with TickerProviderStateMixin {
  final _aciklamaCtrl = TextEditingController();
  final _urunDepo = UrunDeposu();
  final _cariDepo = CariDeposu();
  final _satisDepo = SatisDeposu();
  final _stokDepo = StokDeposu();
  final _kasaDepo = KasaDeposu();
  final _barkodSrv = BarkodServisi();
  final _excelSrv = ExcelServisi();

  // Veriler
  List<UrunModel> _tumUrunler = [];
  List<CariModel> _cariler = [];
  CariModel? _secilenCari;

  // İade geçmişi
  List<Map<String, dynamic>> _gecmisIadeler = [];
  bool _gecmisYukleniyor = false;
  DateTime? _gecmisTarihBaslangic;
  DateTime? _gecmisTarihBitis;
  CariModel? _gecmisCariFiltre;
  final _gecmisFisCtrl = TextEditingController();

  // Form state
  UrunModel? _secilenUrun;
  double _miktar = 1;
  double _orijinalFiyat = 0;
  bool _yukleniyor = false;
  // 🔴🔴 FAZ 1 madde 1 (kullanıcı onayıyla): bu manuel iade akışının
  // belirli bir orijinal satışa bağlantısı yok, bu yüzden "orijinal
  // ödeme yöntemi" bilinmiyor — kullanıcı burada seçiyor (varsayılan:
  // Nakit). Kart/Banka seçilirse kasa_hareketleri'ne hiç yazılmaz.
  String _iadeOdemeYontemi = 'Nakit';

  // Hızlı mod
  bool _hizli = false;
  final Map<int, _HizliItem> _hizliMap = {};

  // İade listesi (bu oturumda yapılanlar)
  final List<Map<String, dynamic>> _iadeListesi = [];

  // Oturum iade - tüm kalemler tek fiş altında
  int? _oturumIadeId;
  String _oturumFisNo = '';

  // Düzenleme modu — geçmişten açılan iade
  int?
      _duzenlemeModu_iadeId; // null = yeni iade, int = mevcut iade üzerinde çalışıyoruz
  String? _duzenlemeModu_fisNo;
  CariModel? _duzenlemeModu_cari;

  // Arama
  List<UrunModel> _aramaListesi = [];
  Timer? _debounce;

  // Fiş arama
  String _fisNo = '';
  SatisModel? _bulunanSatis;
  // urun_id -> bu satıştan bugüne kadar bu üründen kaç adet iade edilmiş.
  // Fiş sekmesinde aynı kalemin birden fazla kez iade edilmesini
  // (dolayısıyla kasadan mükerrer para çıkışını ve stok şişmesini)
  // önlemek için kullanılır.
  Map<int, double> _fisIadeEdilenMiktar = {};

  // Controllers
  final _aramaCtrl = TextEditingController();
  final _miktarCtrl = TextEditingController(text: '1');
  final _fiyatCtrl = TextEditingController();
  final _iskontoCtrl = TextEditingController(text: '0');
  final _fisNoCtrl = TextEditingController();
  final _aramaFocus = FocusNode();

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _yeniFisNoOlustur(); // Oturum başında fiş no oluştur
    _tab.addListener(() {
      if (_tab.index == 3) _gecmisYukle();
    });
    _aramaCtrl.addListener(_aramaDebounce);
    _miktarCtrl.addListener(() {
      final v = ParaUtils.sayiCoz(_miktarCtrl.text) ?? 1;
      if (v != _miktar) setState(() => _miktar = v);
    });
    _verileriYukle();

    if (widget.baslangicUrunleri?.isNotEmpty == true) {
      _hizli = true;
      for (final u in widget.baslangicUrunleri!) {
        if (u.id == null) continue;
        _hizliMap.containsKey(u.id)
            ? _hizliMap[u.id]!.adet++
            : _hizliMap[u.id!] = _HizliItem(urun: u);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _aramaCtrl.dispose();
    _miktarCtrl.dispose();
    _fiyatCtrl.dispose();
    _iskontoCtrl.dispose();
    _fisNoCtrl.dispose();
    _aramaFocus.dispose();
    _tab.dispose();
    _gecmisFisCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  Future<void> _verileriYukle() async {
    try {
      _gecmisYukle(); // Paralel yükle
      final results =
          await Future.wait([_urunDepo.tumunuGetir(), _cariDepo.tumunuGetir()]);
      if (!mounted) return;
      _tumUrunler = results[0] as List<UrunModel>;
      _cariler = results[1] as List<CariModel>;
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
      // ÖNCEDEN kullanıcıya hiçbir şey gösterilmiyordu — ürün/cari
      // listesi yüklenemezse ekran sessizce BOŞ kalır, kullanıcı
      // nedenini asla bilemezdi.
      if (mounted)
        BildirimServisi.hata(
            context, 'Veriler yüklenemedi, lütfen tekrar deneyin');
    }
  }

  // ── Arama ─────────────────────────────────────────────────────────────────
  void _aramaDebounce() {
    _debounce?.cancel();
    final q = _aramaCtrl.text.trim();
    if (q.isEmpty) {
      _aramaListesi = [];
      if (mounted) setState(() {});
      return;
    }
    if (q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 280), () => _ara(q));
  }

  void _ara(String q) {
    final ql = q.toLowerCase();
    final res = _tumUrunler
        .where((u) =>
            u.ad.toLowerCase().contains(ql) ||
            (u.barkod?.toLowerCase().contains(ql) ?? false))
        .toList();
    if (!mounted) return;
    _aramaListesi = res;
    if (mounted) setState(() {});
    if (res.length == 1) _secilenUrunAyarla(res.first);
  }

  void _secilenUrunAyarla(UrunModel u) {
    // Aynı ürün bu oturumda iade edilmişse öne çek
    final mevcutIdx = _iadeListesi.indexWhere((i) => i['urun_id'] == u.id);
    if (mevcutIdx > 0) {
      final mevcut = _iadeListesi.removeAt(mevcutIdx);
      _iadeListesi.insert(0, mevcut);
      _msg('${u.urunAdi} daha önce iade edildi — öne çekildi', err: false);
    }
    setState(() {
      _secilenUrun = u;
      _aramaListesi = [];
      // ÖNCEDEN BURADA HER ZAMAN alış fiyatı gösteriliyordu, cari
      // tipine (Müşteri/Tedarikçi) hiç bakılmıyordu. Kullanıcı isteği:
      // cari bir MÜŞTERİ ise satış fiyatı, bir TEDARİKÇİ ise alış
      // fiyatı üzerinden iade edilsin — bu artık cari tipine göre
      // koşullu olarak doğru fiyatı gösteriyor.
      final cariTipi = _secilenCari?.cariTipi ?? '';
      final isTedarikci =
          cariTipi.contains('edarik') || cariTipi.contains('upplier');
      _orijinalFiyat = isTedarikci ? u.alisFiyat : u.satisFiyat;
      _fiyatCtrl.text = _orijinalFiyat.toStringAsFixed(2);
      _miktar = 1;
      _miktarCtrl.text = '1';
    });
    _aramaCtrl.clear();
    _tab.animateTo(0);
  }

  // Oturum için yeni fiş no oluştur
  Future<void> _yeniFisNoOlustur() async {
    try {
      final no = await Veritabani()
          .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
      if (mounted)
        setState(() {
          _fisNo = '';
          _oturumFisNo = no;
        });
    } catch (_) {
      _oturumFisNo =
          'IAD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }
  }

  void _formSifirla() {
    _secilenUrun = null;
    _miktar = 1;
    _orijinalFiyat = 0;
    _aramaListesi = [];
    _aramaCtrl.clear();
    _miktarCtrl.text = '1';
    _fiyatCtrl.clear();
    _iskontoCtrl.text = '0';
    _aciklamaCtrl.clear();
    if (mounted) setState(() {});
  }

  /// Yeni iade başlat — düzenleme modunu kapat, listeyi temizle
  void _yeniIadeBaslat() {
    setState(() {
      _duzenlemeModu_iadeId = null;
      _duzenlemeModu_fisNo = null;
      _duzenlemeModu_cari = null;
      _oturumIadeId = null;
      _oturumFisNo = '';
      _iadeListesi.clear();
      _secilenCari = null;
      _fisNo = '';
    });
    _yeniFisNoOlustur(); // Yeni oturum için yeni fiş no
    _formSifirla();
    _msg('Yeni iade başlatıldı', err: false);
  }

  // ── Barkod ─────────────────────────────────────────────────────────────────
  Future<void> _barkodOku() async {
    try {
      final barkod = await _barkodSrv.barkodTara(context);
      if (barkod == null || barkod.isEmpty) return;
      final urun = await _urunDepo.barkodlaGetir(barkod);
      if (!mounted) return;
      if (urun != null) {
        _secilenUrunAyarla(urun);
      } else {
        _msg('Ürün bulunamadı: $barkod', err: true);
      }
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  // ── Hızlı mod ─────────────────────────────────────────────────────────────

  Future<void> _iadeIptal(Map<String, dynamic> iade) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('İade İptal'),
        content: Text(
            '${iade['fis_no']} numaralı iade iptal edilsin mi?\n\nStok geri alınacak.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hayır')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: Colors.red),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    try {
      final db = await Veritabani().db;
      final iadeId = iade['id'];
      // Kalemleri al
      final kalemler = await db
          .query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId]);
      final now = DateTime.now().toIso8601String();
      // ÖNCEDEN BURADA SADECE STOK geri alınıyordu — kasadan çıkan
      // (iade tutarı kadar) para ve cariye yazılan alacak/borç HİÇ
      // geri alınmıyordu. İadeyi iptal etmek, iadenin TÜM etkilerini
      // (stok + kasa + cari) tersine çevirmelidir.
      String? cariHareketGid, kasaHareketGid;
      int? cariId;
      await db.transaction((txn) async {
        for (final k in kalemler) {
          final urunId = k['urun_id'] as int?;
          final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
          if (urunId == null || miktar <= 0) continue;
          final urunRows = await txn.query('urunler',
              columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
          if (urunRows.isEmpty) continue;
          final onceki = (urunRows.first['stok'] as num).toDouble();
          final sonraki = onceki - miktar;
          await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
              where: 'id = ?', whereArgs: [urunId]);
          await txn.insert('stok_hareket', {
            'global_id': const Uuid().v4(),
            'urun_id': urunId,
            'hareket_turu': 'İade İptali',
            'miktar': miktar,
            'onceki_stok': onceki,
            'sonraki_stok': sonraki,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade_iptal',
            'aciklama': 'İade iptal edildi, stok geri alındı',
          });
        }

        // Kasa etkisini geri al (orijinal iade tutarı kasadan çıkmıştı —
        // şimdi tekrar kasaya girmeli, çünkü müşteriye ödenen para artık
        // geçersiz).
        final kasaRows = await txn.query('kasa_hareketleri',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade'],
            limit: 1);
        if (kasaRows.isNotEmpty) {
          final tutar = (kasaRows.first['tutar'] as num?)?.toDouble() ?? 0;
          kasaHareketGid = const Uuid().v4();
          await txn.insert('kasa_hareketleri', {
            'global_id': kasaHareketGid,
            'hareket_tipi': 'İade İptali',
            'tutar': tutar,
            'referans_id': iadeId,
            'referans_turu': 'iade_iptal',
            'tarih': now,
            'aciklama': 'İade iptal edildi: ${iade['fis_no']}',
          });
        }

        // Cari etkisini geri al (varsa)
        final cariHareketRows = await txn.rawQuery(
            "SELECT cari_id, borc, alacak FROM cari_hareket WHERE fis_id = ? AND fis_tipi IN ('İade','Alım İadesi') LIMIT 1",
            [iadeId]);
        if (cariHareketRows.isNotEmpty) {
          cariId = cariHareketRows.first['cari_id'] as int?;
          final eskiBorc =
              (cariHareketRows.first['borc'] as num?)?.toDouble() ?? 0;
          final eskiAlacak =
              (cariHareketRows.first['alacak'] as num?)?.toDouble() ?? 0;
          if (cariId != null) {
            cariHareketGid = const Uuid().v4();
            // Ters kayıt: borç/alacak yer değiştirir (iade "alacak"
            // yazmışsa iptali "borç" yazar, tam tersi).
            await txn.insert('cari_hareket', {
              'global_id': cariHareketGid,
              'cari_id': cariId,
              'tarih': now,
              'fis_tipi': 'İade İptali',
              'fis_id': iadeId,
              'fis_no': iade['fis_no'],
              'aciklama': 'İade iptal edildi: ${iade['fis_no']}',
              'borc': eskiAlacak,
              'alacak': eskiBorc,
              'odeme_turu': 'Nakit',
            });
            await txn.rawUpdate(
                'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=?) WHERE id=?',
                [cariId, cariId]);
          }
        }

        // İadeyi iptal işaretle (aynı transaction içinde, tutarlılık için)
        await txn.update('iade', {'durum': 'iptal', 'last_updated': now},
            where: 'id = ?', whereArgs: [iadeId]);
      });

      // Transaction başarılı — buluta bildir (bkz. _kaydet()'teki aynı desen).
      try {
        final iadeSatir = await db.query('iade',
            where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (iadeSatir.isNotEmpty)
          BulutManager()
              .upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
        final stokHareketler = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade_iptal']);
        for (final s in stokHareketler) {
          BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(s));
        }
        for (final k in kalemler) {
          final urunId = k['urun_id'] as int?;
          if (urunId == null) continue;
          final urunSatir = await db.query('urunler',
              where: 'id = ?', whereArgs: [urunId], limit: 1);
          if (urunSatir.isNotEmpty)
            BulutManager()
                .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        if (kasaHareketGid != null) {
          final kasaSatir = await db.query('kasa_hareketleri',
              where: 'global_id = ?', whereArgs: [kasaHareketGid], limit: 1);
          if (kasaSatir.isNotEmpty)
            BulutManager().upsert(
                'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
        if (cariHareketGid != null) {
          final cariHareketSatir = await db.query('cari_hareket',
              where: 'global_id = ?', whereArgs: [cariHareketGid], limit: 1);
          if (cariHareketSatir.isNotEmpty)
            BulutManager().upsert('cari_hareket',
                Map<String, dynamic>.from(cariHareketSatir.first));
        }
        if (cariId != null) {
          final cariSatir = await db.query('cari',
              where: 'id = ?', whereArgs: [cariId], limit: 1);
          if (cariSatir.isNotEmpty)
            BulutManager()
                .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
          ref.invalidate(cariDetayProvider(cariId!));
          ref.read(carilerProvider.notifier).yukle();
        }
        ref.invalidate(kasaRaporProvider);
      } catch (e) {
        if (kDebugMode) debugPrint('İade iptal bulut bildirimi hatası: $e');
      }

      _gecmisYukle();
      if (mounted) _msg('İade iptal edildi', err: false);
    } catch (e) {
      if (mounted) _msg('Hata: $e', err: true);
    }
  }

  // 🔥 "Hızlı" sekmesinin _hizliBarkod() kodu
  // 'iade_ekrani_hizli.dart' dosyasına taşındı (extension olarak).

  // ── Cari seçim - kayıtsız müşteri dahil ─────────────────────────────────
  Future<CariModel?> _cariSecimDialog() async {
    return showDialog<CariModel>(
      context: context,
      builder: (ctx) => CariSecDialog(cariler: _cariler),
    );
  }

  // ── İade kaydet (TEMİZ) ────────────────────────────────────────────────────
  Future<void> _kaydet() async {
    if (_secilenUrun == null) {
      _msg('Ürün seçin', err: true);
      return;
    }
    if (_miktar <= 0) {
      _msg('Geçerli miktar girin', err: true);
      return;
    }

    // Müşteri seçimi - kayıtsız müşteri veya kayıtlı cari seçimi
    if (_secilenCari == null) {
      final sec = await _cariSecimDialog();
      if (sec == null) return; // Kullanıcı iptal etti
      if (!mounted) return;
      setState(() => _secilenCari = sec);
    }

    // Düzenleme modunda mevcut fişe kalem ekle
    if (_duzenlemeModu_iadeId != null) {
      final fiyat = ParaUtils.sayiCoz(_fiyatCtrl.text) ?? _orijinalFiyat;
      final isk = ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0;
      final toplam = _miktar * fiyat * (1 - isk / 100);
      await _duzenlemeModu_kalemEkle(fiyat, isk, _miktar * fiyat * (isk / 100),
          fiyat * (1 - isk / 100), toplam);
      return;
    }

    if (!mounted) return;
    setState(() => _yukleniyor = true);

    try {
      final fiyat = ParaUtils.sayiCoz(_fiyatCtrl.text) ?? _orijinalFiyat;
      final isk = ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0;
      final toplam = _miktar * fiyat * (1 - isk / 100);
      final neden = _aciklamaCtrl.text.trim().isEmpty
          ? 'Iade'
          : _aciklamaCtrl.text.trim();
      final db = await Veritabani().db;

      // Fiş no transaction dışında (sequence güncelleme ayrı transaction gerektirir)
      if (_oturumFisNo.isEmpty)
        _oturumFisNo = await Veritabani()
            .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);

      final cariTipi = _secilenCari?.cariTipi ?? 'Müşteri';
      final isTedarikci =
          cariTipi.contains('edarik') || cariTipi.contains('upplier');
      final now = DateTime.now().toIso8601String();
      final kullaniciId = AuthServisi().aktifId;
      int iadeId = _oturumIadeId ?? 0;
      bool yeniIade = false;

      // ── TEK TRANSACTION: iade + kalem + stok + kasa + cari ──────────────
      await db.transaction((txn) async {
        // 1. İade kaydı
        if (_oturumIadeId != null) {
          await txn.rawUpdate(
              'UPDATE iade SET toplam_tutar = toplam_tutar + ?, iade_nedeni = ? WHERE id = ?',
              [toplam, neden, iadeId]);
        } else {
          iadeId = await txn.insert('iade', {
            'global_id': const Uuid().v4(),
            'cari_id': _secilenCari?.id,
            'fis_no': _oturumFisNo,
            'tarih': now,
            'toplam_tutar': toplam,
            'iade_nedeni': neden,
            'durum': 'tamamlandi',
            'kasiyer_id': kullaniciId,
          });
          yeniIade = true;
        }

        // 2. İade kalem
        final mevcutKalem = await txn.rawQuery(
            'SELECT id, miktar, toplam FROM iade_kalem WHERE iade_id=? AND urun_id=?',
            [iadeId, _secilenUrun!.id]);
        if (mevcutKalem.isNotEmpty) {
          final k = mevcutKalem.first;
          await txn.rawUpdate(
              'UPDATE iade_kalem SET miktar=?, toplam=? WHERE id=?', [
            ((k['miktar'] as num?)?.toDouble() ?? 0) + _miktar,
            ((k['toplam'] as num?)?.toDouble() ?? 0) + toplam,
            k['id']
          ]);
        } else {
          await txn.insert('iade_kalem', {
            'global_id': const Uuid().v4(),
            'iade_id': iadeId,
            'urun_id': _secilenUrun!.id,
            'urun_adi': _secilenUrun!.urunAdi,
            'miktar': _miktar,
            'birim_fiyat': fiyat,
            'toplam': toplam,
          });
        }

        // 3. Stok geri ekle
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [_secilenUrun!.id]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          await txn.update('urunler', {'stok': onceki + _miktar},
              where: 'id = ?', whereArgs: [_secilenUrun!.id]);
          await txn.insert('stok_hareket', {
            'global_id': const Uuid().v4(),
            'urun_id': _secilenUrun!.id,
            'hareket_turu': 'Iade Giris',
            'miktar': _miktar,
            'onceki_stok': onceki,
            'sonraki_stok': onceki + _miktar,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade',
            'kullanici_id': kullaniciId,
            'aciklama': 'Iade: $_oturumFisNo',
          });
        }

        // 4. Kasa — SADECE Nakit iade seçildiyse (bkz. _iadeOdemeYontemi).
        // Kart/Banka iadesinde fiziksel kasadan hiç para çıkmıyor, bu
        // yüzden kasa_hareketleri'ne hiç yazılmaz (aksi halde kasa
        // gerçekte olmayan bir nakit çıkışı gösterirdi). KasaDeposu ile
        // AYNI güvenli bakiye sorgusu kullanılıyor: deleted_at IS NULL +
        // tarih DESC sıralaması. 'ORDER BY id DESC' TEK BAŞINA yanlış
        // olabilirdi: başka bir cihazdan senkronla gelen, daha ESKİ
        // tarihli ama bu cihazda YENİ id alan bir kayıt varsa (çoklu
        // cihaz senkronunda olağan bir durum), yanlış bakiyeyi "son
        // bakiye" sanıp üzerine yazardı.
        if (_iadeOdemeYontemi == 'Nakit') {
          final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplam;
          await txn.insert('kasa_hareketleri', {
            'global_id': const Uuid().v4(),
            'hareket_tipi': 'Iade',
            'tutar': toplam,
            'bakiye_sonrasi': kasaBakiye,
            'referans_id': iadeId,
            'referans_turu': 'iade',
            'tarih': now,
            'sube_id': AktifSubeServisi().subeId,
            'aciklama': 'Iade: $_oturumFisNo - ${_secilenUrun!.urunAdi}',
            'kullanici_id': kullaniciId,
          });
        }

        // 5. Cari
        if (_secilenCari != null && _secilenCari!.id != null) {
          // ÖNCEDEN BURADA SADECE fis_id VE cari_id KONTROL EDİLİYORDU.
          // "iade" tablosu ve "satislar" tablosu BİRBİRİNDEN BAĞIMSIZ
          // otomatik artan ID sayaçlarına sahip — yani bir satışın ID'si
          // (örn. 5) ile bir iadenin ID'si (örn. 5) TESADÜFEN aynı
          // olabilir! fis_tipi kontrolü olmadan, bu sorgu YANLIŞLIKLA
          // satışın cari_hareket kaydını bulup GÜNCELLEYEBİLİR/
          // SİLEBİLİRDİ — kullanıcının bildirdiği "iade yapınca cari'nin
          // listesindeki satış kayboluyor" hatası tam olarak buydu.
          // Artık fis_tipi de kontrol ediliyor, asla yanlış tabloya
          // ait bir kayıtla eşleşmiyor.
          final mevcut = await txn.rawQuery(
              "SELECT id, alacak, borc FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
              [iadeId, _secilenCari!.id]);
          if (mevcut.isNotEmpty) {
            final eskiAlacak =
                (mevcut.first['alacak'] as num?)?.toDouble() ?? 0;
            final eskiBorc = (mevcut.first['borc'] as num?)?.toDouble() ?? 0;
            await txn.rawUpdate(
                "UPDATE cari_hareket SET alacak=?, borc=? WHERE fis_id=? AND cari_id=? AND fis_tipi IN ('İade','Alım İadesi')",
                [
                  isTedarikci ? eskiAlacak : eskiAlacak + toplam,
                  isTedarikci ? eskiBorc + toplam : eskiBorc,
                  iadeId,
                  _secilenCari!.id
                ]);
          } else {
            await txn.insert('cari_hareket', {
              'global_id': const Uuid().v4(),
              'cari_id': _secilenCari!.id,
              'tarih': now,
              'fis_tipi': isTedarikci ? 'Alım İadesi' : 'İade',
              'fis_id': iadeId,
              'fis_no': _oturumFisNo,
              'aciklama': _oturumFisNo,
              'borc': isTedarikci ? toplam : 0,
              'alacak': isTedarikci ? 0 : toplam,
              'odeme_turu': 'Nakit',
              'kullanici': AuthServisi().aktifAd,
            });
          }
          // Bakiye güncelle
          await txn.rawUpdate(
              'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=?) WHERE id=?',
              [_secilenCari!.id, _secilenCari!.id]);
        }
      }); // transaction sonu

      // 🔴🔴 Derin analizde bulundu: bu transaction 7 farklı tabloyu
      // (iade, iade_kalem, urunler, stok_hareket, kasa_hareketleri,
      // cari_hareket, cari) değiştiriyordu ama HİÇBİRİ için BulutManager
      // çağrılmıyordu — tüm iadeler sadece manuel senkronla buluta
      // gidiyordu. Transaction kapandıktan (veri kalıcı olduktan) SONRA,
      // her tablonun EN SON değişen satırı sorgulanıp bildiriliyor.
      try {
        final iadeSatir = await db.query('iade',
            where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (iadeSatir.isNotEmpty)
          BulutManager()
              .upsert('iade', Map<String, dynamic>.from(iadeSatir.first));

        final kalemSatir = await db.query('iade_kalem',
            where: 'iade_id = ? AND urun_id = ?',
            whereArgs: [iadeId, _secilenUrun!.id],
            limit: 1);
        if (kalemSatir.isNotEmpty)
          BulutManager().upsert(
              'iade_kalem', Map<String, dynamic>.from(kalemSatir.first));

        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [_secilenUrun!.id], limit: 1);
        if (urunSatir.isNotEmpty)
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));

        final stokSatir = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade'],
            orderBy: 'id DESC',
            limit: 1);
        if (stokSatir.isNotEmpty)
          BulutManager().upsert(
              'stok_hareket', Map<String, dynamic>.from(stokSatir.first));

        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade'],
            orderBy: 'id DESC',
            limit: 1);
        if (kasaSatir.isNotEmpty)
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));

        if (_secilenCari != null && _secilenCari!.id != null) {
          final cariHareketSatir = await db.query('cari_hareket',
              where:
                  "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
              whereArgs: [iadeId, _secilenCari!.id],
              limit: 1);
          if (cariHareketSatir.isNotEmpty) {
            BulutManager().upsert('cari_hareket',
                Map<String, dynamic>.from(cariHareketSatir.first));
          }
          final cariSatir = await db.query('cari',
              where: 'id = ?', whereArgs: [_secilenCari!.id], limit: 1);
          if (cariSatir.isNotEmpty)
            BulutManager()
                .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('İade bulut bildirimi hatası: $e');
      }

      // Transaction başarılı - state güncelle
      if (_oturumIadeId == null) _oturumIadeId = iadeId;

      // ── Lokal liste güncelle ─────────────────────────────────────────────
      final mevcutIdx =
          _iadeListesi.indexWhere((x) => x['urun_id'] == _secilenUrun!.id);
      if (mevcutIdx != -1) {
        final m = _iadeListesi[mevcutIdx];
        final yM = (m['miktar'] as double) + _miktar;
        final yT = (m['toplam_tutar'] as double) + toplam;
        final updated = {...m, 'miktar': yM, 'toplam_tutar': yT};
        _iadeListesi.removeAt(mevcutIdx);
        _iadeListesi.insert(0, updated); // Öne taşı
      } else {
        _iadeListesi.insert(0, {
          'iade_id': iadeId,
          'urun_id': _secilenUrun!.id,
          'tarih': DateTime.now(),
          'urun_adi': _secilenUrun!.urunAdi,
          'barkod': _secilenUrun!.barkod ?? '',
          'miktar': _miktar,
          'birim_fiyat': fiyat,
          'iskonto_oran': isk,
          'iskonto_tutar': _miktar * fiyat * (isk / 100),
          'toplam_tutar': toplam,
          'musteri_adi': _secilenCari?.unvan ?? 'Kayıtsız Müşteri',
          'cari_id': _secilenCari?.id,
          'fis_no': _oturumFisNo,
        });
      }

      // Lokal stok
      final si = _tumUrunler.indexWhere((u) => u.id == _secilenUrun!.id);
      if (si != -1)
        _tumUrunler[si] =
            _tumUrunler[si].copyWith(stok: _tumUrunler[si].stok + _miktar);

      _msg('${_secilenUrun!.urunAdi} iade edildi ✓', err: false);
      // Kullanıcı isteği: "iade alımı yaptığımızda o ekran kapanacak"
      // — bu, sadece toptan cari panelinden tek-ürünlük hızlı iade
      // akışında istenir; normal çok-kalemli akışta ekran açık kalıp
      // form sıfırlanmaya devam eder (mevcut davranış korunuyor).
      if (widget.otomatikKapat) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      _formSifirla();
      _gecmisYukle(); // Geçmişi güncelle
    } catch (e) {
      _msg('Hata: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // ── Toplu iade (hızlı mod) ───────────────────────────────────────────────
  // 🔥 "Hızlı" sekmesinin _hizliKaydet() kodu taşındı.

  // ── Fiş arama ─────────────────────────────────────────────────────────────
  // 🔥 "Fiş" sekmesinin _fisBul()/_fisKalemIade() kodu
  // 'iade_ekrani_fis.dart' dosyasına taşındı (extension olarak).

  // ── Excel ─────────────────────────────────────────────────────────────────
  Future<void> _excel() async {
    if (_iadeListesi.isEmpty) {
      _msg('İade kaydı yok', err: true);
      return;
    }
    try {
      final path = await _excelSrv.iadelerExcelEAktar(_iadeListesi);
      await _excelSrv.paylasExcel(path);
    } catch (e) {
      _msg('Excel hatası: $e', err: true);
    }
  }

  void _msg(String s, {bool err = false}) {
    if (!mounted) return;
    // 🔴 UX TUTARLILIK DÜZELTMESİ: bkz. aynı düzeltme diğer ekranlarda —
    // artık paylaşılan BildirimServisi kullanılıyor.
    if (err) {
      BildirimServisi.hata(context, s);
    } else {
      BildirimServisi.basari(context, s);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: _duzenlemeModu_iadeId != null
            ? Text('İade: ${_duzenlemeModu_fisNo ?? ''}',
                style: const TextStyle(fontSize: 15))
            : const Text('İade İşlemleri'),
        aksiyonlar: [
          if (_duzenlemeModu_iadeId != null)
            TextButton.icon(
              icon: const Icon(Icons.add_circle_outline,
                  color: Colors.white, size: 16),
              label: const Text('Yeni',
                  style: TextStyle(color: Colors.white, fontSize: 11)),
              onPressed: _yeniIadeBaslat,
            ),
          IconButton(
              icon: Image.asset("assets/images/excel_icon.png",
                  width: 22,
                  height: 22,
                  errorBuilder: (_, __, ___) => const Icon(Icons.table_chart)),
              tooltip: 'Excel',
              onPressed: _excel),
          if (_secilenCari != null)
            Chip(
                label: Text(_secilenCari!.unvan,
                    style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  _secilenCari = null;
                  if (mounted) setState(() {});
                }),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'musteri') {
                final secilen = await showDialog<CariModel?>(
                    context: context,
                    builder: (ctx) => CariSecDialog(cariler: _cariler));
                if (secilen != null) {
                  _secilenCari = secilen;
                  if (mounted) setState(() {});
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'musteri',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.person, color: AppRenkler.primary),
                      title: Text('Müşteri Seç'))),
            ],
          ),
        ],
        alt: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: _R.orange,
          tabs: const [
            Tab(icon: Icon(Icons.assignment_return, size: 18), text: 'İade'),
            Tab(icon: Icon(Icons.list_alt, size: 18), text: 'Hızlı'),
            Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Fiş'),
            Tab(icon: Icon(Icons.history, size: 18), text: 'Geçmiş'),
          ],
        ),
        lider: BackButton(onPressed: () => context.go('/')),
        modul: TsModul.uyari,
      ),
      body: TabBarView(controller: _tab, children: [
        _iadeTab(),
        _hizliTab(),
        _fisTab(),
        _gecmisTab(),
      ]),
    );
  }

  // ── İade Sekmesi ──────────────────────────────────────────────────────────
  Widget _iadeTab() => Column(children: [
        _aramaKutusu(),
        if (_aramaListesi.isNotEmpty) _aramaPanel(),
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  if (_secilenUrun != null) ...[
                    _urunFormu(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _yukleniyor ? null : _kaydet,
                        style: FilledButton.styleFrom(
                            backgroundColor: _R.orange,
                            foregroundColor: Colors.white),
                        icon: _yukleniyor
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.assignment_return),
                        label: const Text('İade Et',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else
                    _bosEkran(),
                  if (_iadeListesi.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _iadeGecmisi(),
                  ],
                ]))),
      ]);

  Widget _aramaKutusu() => IadeAramaKutusu(
        controller: _aramaCtrl,
        focusNode: _aramaFocus,
        onTemizle: () {
          _aramaCtrl.clear();
          _aramaListesi = [];
          if (mounted) setState(() {});
        },
        onBarkod: _barkodOku,
      );

  Widget _aramaPanel() => IadeAramaPanel(
        aramaListesi: _aramaListesi,
        onSec: (u) => _secilenUrunAyarla(u as dynamic),
      );
  Widget _urunFormu() => IadeUrunFormu(
        urun: _secilenUrun!,
        miktarCtrl: _miktarCtrl,
        fiyatCtrl: _fiyatCtrl,
        iskontoCtrl: _iskontoCtrl,
        miktar: _miktar,
        orijinalFiyat: _orijinalFiyat,
        onSifirla: _formSifirla,
        onDegisti: () {
          if (mounted) setState(() {});
        },
        odemeYontemi: _iadeOdemeYontemi,
        onOdemeYontemiChanged: (v) {
          if (mounted) setState(() => _iadeOdemeYontemi = v);
        },
      );

  // Eski _urunFormu gövdesi kaldırıldı
  // Bkz: IadeUrunFormu widget
  Widget _eskiUrunFormuGovdesi() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _R.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: _R.shadow, blurRadius: 8, offset: Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: Color.fromARGB(
                        26, _R.orange.red, _R.orange.green, _R.orange.blue),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.inventory_2_outlined,
                    color: _R.orange, size: 22)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_secilenUrun!.urunAdi,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _R.textD)),
                  Text(_secilenUrun!.barkod ?? '',
                      style: const TextStyle(fontSize: 12, color: _R.textL)),
                ])),
            IconButton(
                icon: const Icon(Icons.close, color: _R.textL),
                onPressed: _formSifirla),
          ]),
          const Divider(height: 24),
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Normal Satış Fiyatı',
                      style: TextStyle(fontSize: 11, color: _R.textL)),
                  Text(ParaUtils.formatla(_secilenUrun!.satisFiyat),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _R.textD)),
                ])),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Mevcut Stok',
                      style: TextStyle(fontSize: 11, color: _R.textL)),
                  Text(_secilenUrun!.stokMiktari.toStringAsFixed(0),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _secilenUrun!.stokMiktari <= 0
                              ? _R.red
                              : _R.green)),
                ])),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TextField(
              controller: _miktarCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'İade Miktarı',
                  prefixIcon: Icon(Icons.production_quantity_limits, size: 18),
                  border: OutlineInputBorder(),
                  isDense: true),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
              controller: _fiyatCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'Birim Fiyat (₺)',
                  prefixIcon: Icon(Icons.attach_money, size: 18),
                  border: OutlineInputBorder(),
                  isDense: true),
            )),
          ]),
          const SizedBox(height: 8),
          // İskonto alanı
          TextField(
            controller: _iskontoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: InputDecoration(
              labelText: 'İskonto % (0-100)',
              prefixIcon: const Icon(Icons.percent, size: 18),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixText: '%',
              helperText: 'İskonto uygulamak için doldurun',
              helperStyle: const TextStyle(fontSize: 10),
              filled: true,
              fillColor: Colors.orange.shade50,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Color.fromARGB(
                    15, _R.orange.red, _R.orange.green, _R.orange.blue),
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ara Toplam:',
                          style: TextStyle(fontSize: 12, color: _R.textL)),
                      Text(
                          ParaUtils.formatla(_miktar *
                              (ParaUtils.sayiCoz(_fiyatCtrl.text) ??
                                  _orijinalFiyat)),
                          style:
                              const TextStyle(fontSize: 13, color: _R.textL)),
                    ]),
                if ((ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('İskonto (${_iskontoCtrl.text}%):',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.orange)),
                        Text(
                            '- ${ParaUtils.formatla(_miktar * (ParaUtils.sayiCoz(_fiyatCtrl.text) ?? _orijinalFiyat) * (ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0) / 100)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.orange)),
                      ]),
                ],
                const Divider(height: 8),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('İade Toplam:',
                          style: TextStyle(fontSize: 13, color: _R.textL)),
                      Text(
                          ParaUtils.formatla(_miktar *
                              (ParaUtils.sayiCoz(_fiyatCtrl.text) ??
                                  _orijinalFiyat) *
                              (1 -
                                  (ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0) /
                                      100)),
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _R.orange)),
                    ]),
              ],
            ),
          ),
        ]),
      );

  Widget _bosEkran() => Center(
          child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          Opacity(
            opacity: 0.3,
            child: Image.asset('assets/images/empty_box.png',
                height: 80,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.assignment_return,
                    size: 52,
                    color: _R.orange)),
          ),
        ]),
      ));

  Widget _iadeGecmisi() => IadeGecmisWidget(
        iadeListesi: _iadeListesi,
        duzenlemeModu_iadeId: _duzenlemeModu_iadeId,
        duzenlemeModu_fisNo: _duzenlemeModu_fisNo,
        onSilOnay: _oturumIadeSilOnay,
        onSil: _oturumIadeSil,
        onDuzenle: _oturumIadeDuzenle,
        onExcel: _excel,
      );

  // ── Hızlı İade Sekmesi ────────────────────────────────────────────────────
  // 🔥 "Hızlı" sekmesinin _hizliTab() kodu 'iade_ekrani_hizli.dart' dosyasına taşındı.

  // ── Fiş Arama Sekmesi ─────────────────────────────────────────────────────
  // 🔥 "Fiş" sekmesinin _fisTab() kodu 'iade_ekrani_fis.dart' dosyasına taşındı.

// ── Geçmiş İadeler Tab ───────────────────────────────────────────────────────
  // 🔥 "Geçmiş İadeler" sekmesinin TÜM kodu (_gecmisTab, _oturumIadeSilOnay,
  // _oturumIadeSil, _oturumIadeDuzenle, _gecmisIadeyiDevamEt, _gecmisIadeSil,
  // _gecmisYukle, _iadeyiFaturalandir, _gecmisIadeDetay, _gecmisIadeDuzelt vb.)
  // dosya boyutunu azaltmak için 'iade_ekrani_gecmis.dart' dosyasına taşındı
  // (part/part of ile — mantık/davranış AYNEN korunuyor, sadece organizasyon
  // değişti). Bu metodlar hâlâ bu sınıfın (_IadeEkraniState) birer üyesi gibi
  // çağrılabiliyor, çünkü extension olarak tanımlandılar.

// ── Cari Seç Dialog ─────────────────────────────────────────────────────────
}
