// lib/ekranlar/bildirim/bildirim_merkezi_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../depolar/bildirim_deposu.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class _BildirimItem {
  final int id;
  final String baslik, mesaj, tur;
  final DateTime zaman;
  final bool okundu;
  const _BildirimItem({required this.id, required this.baslik,
    required this.mesaj, required this.tur, required this.zaman, required this.okundu});

  // DB sütunları: baslik, mesaj, tip, tarih, okundu
  factory _BildirimItem.fromMap(Map<String, dynamic> m) => _BildirimItem(
    id:     m['id'] as int,
    baslik: m['baslik'] as String? ?? 'Bildirim',
    mesaj:  m['mesaj']  as String? ?? '',
    tur:    m['tip']    as String? ?? 'bilgi',   // DB'de 'tip' -> 'tur'
    zaman:  m['tarih'] != null                   // DB'de 'tarih' -> 'zaman'
        ? DateTime.tryParse(m['tarih'].toString()) ?? DateTime.now()
        : DateTime.now(),
    okundu: (m['okundu'] as int? ?? 0) == 1,
  );
}

final bildirimlerProvider = FutureProvider.autoDispose<List<_BildirimItem>>((ref) async {
  final rows = await BildirimDeposu().sonBildirimler();
  return rows.map(_BildirimItem.fromMap).toList();
});

final okunmamisSayiProvider = Provider.autoDispose<int>((ref) =>
    ref.watch(bildirimlerProvider).valueOrNull?.where((b) => !b.okundu).length ?? 0);

class BildirimMerkeziEkrani extends ConsumerStatefulWidget {
  const BildirimMerkeziEkrani({super.key});
  @override
  ConsumerState<BildirimMerkeziEkrani> createState() => _BildirimMerkeziEkraniState();
}

class _BildirimMerkeziEkraniState extends ConsumerState<BildirimMerkeziEkrani> {
  String _filtre = 'Tümü';
  static const _filtreler = ['Tümü', 'Okunmamış', 'Kritik', 'Sistem'];

  List<_BildirimItem> _filtrele(List<_BildirimItem> liste) {
    return switch (_filtre) {
      'Okunmamış' => liste.where((b) => !b.okundu).toList(),
      'Kritik'    => liste.where((b) => b.tur.contains('kritik') || b.tur.contains('uyari')).toList(),
      'Sistem'    => liste.where((b) => b.tur == 'bilgi' || b.tur == 'sistem').toList(),
      _           => liste,
    };
  }

  final _depo = BildirimDeposu();

  Future<void> _okunduIsaretle(int id) async {
    try {
      await _depo.okunduIsaretle(id);
      ref.invalidate(bildirimlerProvider);
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _tumunuOku() async {
    try {
      await _depo.tumunuOkunduIsaretle();
      ref.invalidate(bildirimlerProvider);
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bildirimlerProvider);
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Bildirimler',
        aksiyonlar: [
          async.whenOrNull(data: (liste) => liste.any((b) => !b.okundu)
              ? TextButton(onPressed: _tumunuOku,
                  child: const Text('Tümünü Oku', style: TextStyle(color: Colors.white70)))
              : null) ?? const SizedBox.shrink(),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => ref.invalidate(bildirimlerProvider)),
        ],
      ),
      body: Column(children: [
        // Filtre chips
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            itemCount: _filtreler.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _filtreler[i];
              final secili = f == _filtre;
              return FilterChip(
                label: Text(f),
                selected: secili,
                onSelected: (_) => setState(() => _filtre = f),
                selectedColor: TsRenk.primary,
                labelStyle: TextStyle(
                  color: secili ? Colors.white : TsRenk.metinIkincil(context),
                  fontSize: 12, fontWeight: FontWeight.w500),
                backgroundColor: TsRenk.kart(context),
                checkmarkColor: Colors.white,
              );
            },
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const TsYukleniyor(iskelet: true),
            error:   (e, _) => const TsBosDurum(
              ikon: Icons.notifications_none_outlined,
              baslik: 'Bildirim tablosu boş',
              altyazi: 'Sistem bildirimleri burada görünür',
            ),
            data: (liste) {
              final filtreli = _filtrele(liste);
              if (filtreli.isEmpty) {
                return const TsBosDurum(
                  ikon: Icons.notifications_none_outlined,
                  baslik: 'Bildirim yok',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(TsBosluk.lg),
                itemCount: filtreli.length,
                separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
                itemBuilder: (_, i) => _BildirimKarti(
                  bildirim: filtreli[i],
                  onOku: () => _okunduIsaretle(filtreli[i].id),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _BildirimKarti extends StatelessWidget {
  final _BildirimItem bildirim;
  final VoidCallback  onOku;
  const _BildirimKarti({required this.bildirim, required this.onOku});

  // 🔴 DÜZELTME: Bildirimleri GERÇEKTEN üreten servis
  // (bildirim_merkezi_servisi.dart) sadece 'kritik' ve 'uyari' tipini
  // kullanıyor — ama burada 'kritik' hiç tanımlı değildi. Sonuç: en
  // önemli bildirimler (vadesi geçmiş borç, tükenen stok, süresi
  // dolmuş ürün) varsayılan gri renk/ikonla gösteriliyordu, kırmızı/
  // acil görünmüyordu.
  static const _renkler = {
    'kritik': Color(0xFFD32F2F),
    'hata':   Color(0xFFE65100),
    'uyari':  Color(0xFFF57F17),
    'basari': Color(0xFF2E7D32),
    'bilgi':  Color(0xFF1565C0),
    'sistem': Color(0xFF546E7A),
  };
  static const _ikonlar = {
    'kritik': Icons.error_rounded,
    'hata':   Icons.error_outline,
    'uyari':  Icons.warning_amber_rounded,
    'basari': Icons.check_circle_outline,
    'bilgi':  Icons.info_outline,
    'sistem': Icons.settings_outlined,
  };

  Color get _renk => _renkler[bildirim.tur] ?? const Color(0xFF546E7A);
  IconData get _ikon => _ikonlar[bildirim.tur] ?? Icons.notifications_outlined;

  String _zamanFormat(DateTime dt) {
    final fark = DateTime.now().difference(dt);
    if (fark.inMinutes < 60)   return '${fark.inMinutes} dk önce';
    if (fark.inHours   < 24)   return '${fark.inHours} saat önce';
    if (fark.inDays    < 7)    return '${fark.inDays} gün önce';
    return DateFormat('dd.MM.yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    // 🔴 DÜZELTME: Kaydırma arka planı kırmızı "sil" ikonu gösteriyordu
    // ama onDismissed sadece okundu işaretliyordu (gerçek silme yok) —
    // kullanıcı bildirimi SİLDİĞİNİ düşünürken aslında sadece
    // okunmuş sayılıyordu. Görsel artık gerçek davranışla eşleşiyor.
    // Zaten okunmuş bir bildirim kaydırılamaz (yapacak bir şey yok).
    return Dismissible(
      key: Key('b_${bildirim.id}'),
      direction: bildirim.okundu ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async { onOku(); return false; },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.blue.shade400, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.done_all, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: bildirim.okundu ? null : onOku,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bildirim.okundu ? TsRenk.kart(context) : _renk.withAlpha(10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: bildirim.okundu ? Colors.transparent : _renk.withAlpha(51)),
            boxShadow: [BoxShadow(color: const Color(0x0A000000),
                blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: _renk.withAlpha(26), borderRadius: BorderRadius.circular(12)),
              child: Icon(_ikon, color: _renk, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(bildirim.baslik,
                    style: TextStyle(fontWeight: bildirim.okundu ? FontWeight.w500 : FontWeight.w700,
                        fontSize: 13, color: TsRenk.metinBirincil(context)))),
                if (!bildirim.okundu)
                  Container(width: 8, height: 8,
                      decoration: BoxDecoration(color: _renk, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 4),
              Text(bildirim.mesaj,
                  style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text(_zamanFormat(bildirim.zaman),
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
            ])),
          ]),
        ),
      ),
    );
  }
}
