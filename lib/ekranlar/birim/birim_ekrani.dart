// lib/ekranlar/birim/birim_ekrani.dart
// Birim yönetimi — ADET, KG, LİTRE vb.
//
// 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu ekran önceden
// SharedPreferences kullanıyordu — ama SQLite'ta ZATEN senkron
// sistemine kayıtlı ('birimler': 'ad' benzersiz anahtarıyla) gerçek
// bir 'birimler' tablosu var, hiçbir yerden kullanılmıyordu. Sonuç:
// bir cihazda eklenen özel birim (ör. "TON") DİĞER cihazlara HİÇ
// senkronize olmuyordu — çok şubeli/çok terminalli kullanımda ciddi
// bir tutarsızlık. Artık SQLite tablosu kullanılıyor; dış API
// (birimListesiGetir() → List<String>) AYNI kaldığı için Ürün Ekle
// gibi bu listeyi kullanan diğer ekranlar hiç etkilenmiyor.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../veri/database/veritabani.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/app_widgetlar.dart' show basariMesaji, hataMesaji;

class BirimEkrani extends ConsumerStatefulWidget {
  const BirimEkrani({super.key});

  static const List<String> _varsayilan = [
    'ADET', 'KG', 'GR', 'LİTRE', 'ML', 'PAKET', 'KOLİ', 'KUTU', 'ÇIFT', 'METRE', 'M²',
  ];

  /// Diğer ekranlar (ör. ürün ekle) buradan birim listesi alır.
  static Future<List<String>> birimListesiGetir() async {
    try {
      final db = await Veritabani().db;
      final rows = await db.query('birimler', where: 'aktif = 1', columns: ['ad']);
      final kayitli = rows.map((r) => r['ad'] as String).toList();
      return {..._varsayilan, ...kayitli}.toList()..sort();
    } catch (_) {
      return _varsayilan.toList()..sort();
    }
  }

  /// Kullanıcı isteği: "Ölçü Birimleri ekranından her birime ayrı
  /// çarpan tanımlanabilsin" (ör. Paket=24, Koli=12). Bayilerden
  /// Sipariş Alma ekranı bu listeyi kullanır — bir birim seçildiğinde
  /// miktar otomatik olarak bu çarpanla ana birime (Adet) çevrilir.
  static Future<List<(String ad, double carpan)>> birimListesiCarpanliGetir() async {
    try {
      final db = await Veritabani().db;
      final rows = await db.query('birimler', where: 'aktif = 1', columns: ['ad', 'carpan']);
      final kayitliMap = <String, double>{
        for (final r in rows) r['ad'] as String: (r['carpan'] as num?)?.toDouble() ?? 1,
      };
      final tumAdlar = {..._varsayilan, ...kayitliMap.keys}.toList()..sort();
      return tumAdlar.map((ad) => (ad, kayitliMap[ad] ?? 1.0)).toList();
    } catch (_) {
      return _varsayilan.map((ad) => (ad, 1.0)).toList();
    }
  }

  @override
  ConsumerState<BirimEkrani> createState() => _BirimEkraniState();
}

class _BirimEkraniState extends ConsumerState<BirimEkrani> {
  static const List<String> _varsayilan = BirimEkrani._varsayilan;

  List<String> _birimler = [];
  Map<String, double> _carpanlar = {};
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    try {
      final tumCarpanli = await BirimEkrani.birimListesiCarpanliGetir();
      if (!mounted) return;
      setState(() {
        _birimler = tumCarpanli.map((e) => e.$1).toList();
        _carpanlar = {for (final e in tumCarpanli) e.$1: e.$2};
        _yukleniyor = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _yeniBirimEkle() async {
    final ctrl = TextEditingController();
    final carpanCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Text('Yeni Birim'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TsInput(
            etiket: 'Birim adı',
            ipucu: 'ör: TON, RULO, PAKET',
            controller: ctrl,
          ),
          const SizedBox(height: TsBosluk.md),
          TsInput(
            etiket: 'Çarpan (kaç Adet\'e eşit)',
            ipucu: 'ör: Paket için 24 — boş bırakılırsa 1',
            controller: carpanCtrl,
            klavyeTuru: TextInputType.number,
          ),
        ]),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon(metin: 'Ekle', onPressed: () {
            if (ctrl.text.trim().isEmpty) return;
            Navigator.pop(ctx, true);
          }),
        ],
      ),
    );
    if (ok != true) return;
    final yeni = ctrl.text.trim().toUpperCase();
    final carpan = double.tryParse(carpanCtrl.text.replaceAll(',', '.')) ?? 1;
    if (_birimler.contains(yeni)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bu birim zaten mevcut')));
      }
      return;
    }
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      // Daha önce silinmiş (aktif=0) aynı adlı birim varsa geri aktifleştir,
      // yoksa yeni satır ekle — 'ad' UNIQUE olduğu için çakışmayı önler.
      final mevcut = await db.query('birimler', where: 'ad = ?', whereArgs: [yeni], limit: 1);
      if (mevcut.isNotEmpty) {
        await db.update('birimler', {'aktif': 1, 'carpan': carpan, 'last_updated': now},
            where: 'ad = ?', whereArgs: [yeni]);
      } else {
        await db.insert('birimler', {'ad': yeni, 'aktif': 1, 'carpan': carpan, 'last_updated': now});
      }
      final satir = await db.query('birimler', where: 'ad = ?', whereArgs: [yeni], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('birimler', Map<String, dynamic>.from(satir.first));
      setState(() {
        _birimler = {..._birimler, yeni}.toList()..sort();
        _carpanlar[yeni] = carpan;
      });
      if (mounted) basariMesaji(context, '$yeni eklendi');
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) hataMesaji(context, 'Eklenemedi: $e');
    }
  }

  /// Kullanıcı isteği: "Ölçü Birimleri ekranından her birime ayrı
  /// çarpan tanımlanabilsin" — mevcut bir birimin çarpanını sonradan
  /// düzenleyebilmek için (kart üzerine dokununca açılır).
  Future<void> _carpanDuzenle(String birim) async {
    final ctrl = TextEditingController(text: (_carpanlar[birim] ?? 1).toStringAsFixed(
        (_carpanlar[birim] ?? 1) == (_carpanlar[birim] ?? 1).roundToDouble() ? 0 : 2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: Text('$birim — Çarpan'),
        content: TsInput(
          etiket: 'Kaç Adet\'e eşit',
          ipucu: 'ör: Paket için 24',
          controller: ctrl,
          klavyeTuru: TextInputType.number,
        ),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon(metin: 'Kaydet', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    final carpan = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 1;
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      final mevcut = await db.query('birimler', where: 'ad = ?', whereArgs: [birim], limit: 1);
      if (mevcut.isNotEmpty) {
        await db.update('birimler', {'carpan': carpan, 'last_updated': now}, where: 'ad = ?', whereArgs: [birim]);
      } else {
        // Varsayılan listeden (henüz db satırı olmayan) bir birimin
        // çarpanı ilk kez ayarlanıyor — satırı burada oluştur.
        await db.insert('birimler', {'ad': birim, 'aktif': 1, 'carpan': carpan, 'last_updated': now});
      }
      final satir = await db.query('birimler', where: 'ad = ?', whereArgs: [birim], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('birimler', Map<String, dynamic>.from(satir.first));
      setState(() => _carpanlar[birim] = carpan);
      if (mounted) basariMesaji(context, '$birim çarpanı $carpan olarak güncellendi');
    } catch (e) {
      if (mounted) hataMesaji(context, 'Güncellenemedi: $e');
    }
  }

  Future<void> _sil(String birim) async {
    if (_varsayilan.contains(birim)) {
      hataMesaji(context, 'Varsayılan birimler silinemez');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Text('Birimi Sil'),
        content: Text('$birim birimini silmek istiyor musunuz?'),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon.tehlike(metin: 'Sil', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    // 🔴 Derin analizde bulundu: DB yazması başarısız olursa (kilitli
    // veritabanı, disk hatası vb.) burada hiçbir geri alma/kullanıcı
    // bildirimi yoktu — birim listeden kalıcı olarak (ekran yeniden
    // yüklenene kadar) kaybolurdu ama SQLite'ta hâlâ aktif=1 olarak
    // kalırdı, kullanıcı silmenin başarılı olduğunu sanırdı.
    final oncekiIndex = _birimler.indexOf(birim);
    setState(() => _birimler.remove(birim));
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      await db.update('birimler', {'aktif': 0, 'last_updated': now},
          where: 'ad = ?', whereArgs: [birim]);
      final satir = await db.query('birimler', where: 'ad = ?', whereArgs: [birim], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('birimler', Map<String, dynamic>.from(satir.first));
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) {
        setState(() {
          final eklemeIndex = oncekiIndex >= 0 && oncekiIndex <= _birimler.length
              ? oncekiIndex : _birimler.length;
          _birimler.insert(eklemeIndex, birim);
        });
        hataMesaji(context, 'Birim silinemedi: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Birim Yönetimi',
        gradyanli: true,
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.add, color: Colors.white), tooltip: 'Yeni Birim', onPressed: _yeniBirimEkle),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(TsBosluk.md),
            child: TsKart(
              padding: const EdgeInsets.all(TsBosluk.md),
              child: Row(children: [
                Icon(Icons.info_outline, size: 18, color: TsRenk.bilgi),
                const SizedBox(width: TsBosluk.sm),
                const Expanded(
                  child: Text(
                    'Ürünlerde kullanılacak ölçü birimlerini buradan yönetebilirsiniz. '
                    'Silmek için kartı sola sürükleyin.',
                    style: TsMetin.kucuk,
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: TsListe<String>(
              yukleniyor: _yukleniyor,
              ogeler: _birimler,
              aramaMetniAl: (b) => b,
              bosBaslik: 'Henüz birim yok',
              bosIkon: Icons.straighten,
              kartOlustur: (context, b, i) {
                final varsayilan = _varsayilan.contains(b);
                return Dismissible(
                  key: ValueKey(b),
                  direction: varsayilan ? DismissDirection.none : DismissDirection.endToStart,
                  background: Container(
                    decoration: BoxDecoration(color: TsRenk.hata, borderRadius: BorderRadius.circular(TsRadius.lg)),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: TsBosluk.lg),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _sil(b),
                  child: TsKart.liste(
                    baslik: b,
                    ikon: const Icon(Icons.straighten),
                    altBaslik: (_carpanlar[b] ?? 1) != 1
                        ? '1 $b = ${(_carpanlar[b] ?? 1).toStringAsFixed((_carpanlar[b] ?? 1) == (_carpanlar[b] ?? 1).roundToDouble() ? 0 : 2)} Adet'
                        : null,
                    onTap: () => _carpanDuzenle(b),
                    etiketler: [
                      varsayilan ? const TsBadge(metin: 'VARSAYILAN', tur: TsBadgeTuru.bilgi) : const TsBadge(metin: 'ÖZEL', tur: TsBadgeTuru.basarili),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _yeniBirimEkle,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Birim'),
      ),
    );
  }
}
