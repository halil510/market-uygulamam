// lib/ekranlar/urun/kategori_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/kategori_deposu.dart';

class KategoriEkrani extends ConsumerStatefulWidget {
  const KategoriEkrani({super.key});
  @override
  ConsumerState<KategoriEkrani> createState() => _KategoriEkraniState();
}

class _KategoriEkraniState extends ConsumerState<KategoriEkrani> {
  final _depo = KategoriDeposu();
  List<Map<String, dynamic>> _kategoriler = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    try {
      if (mounted) setState(() => _yukleniyor = true);
      final liste = await _depo.hepsiGetir();
      if (!mounted) return;
      setState(() {
        _kategoriler = liste;
        _yukleniyor = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ekle() async {
    final ctrl = TextEditingController();
    final onay = await showDialog<String>(
      context: context,
      builder: (bCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Text('Yeni Kategori'),
        content: TsInput(etiket: 'Kategori Adı', controller: ctrl),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(bCtx)),
          TsButon(metin: 'Ekle', onPressed: () => Navigator.pop(context, ctrl.text.trim())),
        ],
      ),
    );
    if (onay != null && onay.isNotEmpty) {
      await _depo.ekle(onay);
      _yukle();
      if (mounted) BildirimServisi.basari(context, 'Kategori eklendi');
    }
  }

  Future<void> _sil(int id) async {
    // 🔴 DÜZELTME: Önceden hiç onay istenmeden DOĞRUDAN silinen
    // (gerçek hard-delete) bir kategoriydi. Kategori ürünler tarafından
    // referans verilebileceği için hem onay isteniyor hem de artık
    // soft-delete (is_deleted=1) yapılıyor — hard delete, silmenin
    // buluta hiç bildirilememesine ve bulut→yerel çekişte "dirilmesine"
    // yol açardı.
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategoriyi Sil'),
        content: const Text('Bu kategori silinecek. Bu kategoriye bağlı ürünler etkilenmez '
            'ama kategori listesinde artık görünmeyecek. Devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    try {
      await _depo.sil(id);
      _yukle();
      if (mounted) BildirimServisi.basari(context, 'Silindi');
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Kategoriler'),
      body: TsListe<Map<String, dynamic>>(
        yukleniyor: _yukleniyor,
        ogeler: _kategoriler,
        aramaMetniAl: (k) => k['ad'] as String? ?? '',
        bosBaslik: 'Kategori yok',
        bosAltyazi: 'Sağ alttaki + ile yeni kategori ekleyin',
        bosIkon: Icons.category_outlined,
        kartOlustur: (context, k, i) => TsKart.liste(
          baslik: k['ad'] as String? ?? '',
          ikon: const Icon(Icons.category_outlined),
          sagAksiyon: IconButton(
            icon: const Icon(Icons.delete_outline, color: TsRenk.hata),
            onPressed: () => _sil(k['id'] as int),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _ekle, child: const Icon(Icons.add)),
    );
  }
}
