// lib/ekranlar/masa/widgets/masa_detay_icerik.dart
//
// Masa detayının GÖVDESİ: masa/sipariş özeti, sipariş kalem listesi ve eylem
// butonları — masa_detay_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
// Yalnız gösterir; adisyon/ödeme/hesap istendi eylemleri geri çağrıyla
// ekrandan gelir. Kalem silme kendi sağlayıcısını kullanır.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/masa_model.dart';
import '../../../modeller/masa_siparis_model.dart';
import '../../../saglayicilar/riverpod/masa_provider.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';


class MasaDetayIcerik extends StatelessWidget {
  final MasaModel masa;
  final MasaSiparisModel? siparis;
  final VoidCallback onAdisyon;
  final VoidCallback onHesapIstendi;
  final VoidCallback onOdeme;
  final VoidCallback onMusteriSec;
  final VoidCallback onMusteriKaldir;
  final bool islemAktif;

  const MasaDetayIcerik({super.key, 
    required this.masa,
    required this.siparis,
    required this.onAdisyon,
    required this.onHesapIstendi,
    required this.onOdeme,
    required this.onMusteriSec,
    required this.onMusteriKaldir,
    required this.islemAktif,
  });

  @override
  Widget build(BuildContext context) {
    final aktifSiparis = siparis != null && siparis!.kalemler.isNotEmpty;
    final toplam = siparis?.hesaplananToplam ?? 0;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8)],
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(masa.ad, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${masa.kategori} • ${masa.kapasite} Kişi',
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                if (siparis?.acilisZamani != null)
                  Text('Açılış: ${_formatSaat(siparis!.acilisZamani)}',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                // Müşteri (cari) — sipariş açıkken bağlanabilir; bağlıysa
                // ödemede 'Cari' (veresiye) yöntemi açılır.
                if (siparis != null) ...[
                  const SizedBox(height: 8),
                  siparis!.cariId != null
                      ? InputChip(
                          avatar: const Icon(Icons.person, size: 16),
                          label: Text(siparis!.cariAdi ?? 'Müşteri',
                              overflow: TextOverflow.ellipsis),
                          tooltip: 'Müşteriyi değiştir',
                          onPressed: islemAktif ? null : onMusteriSec,
                          onDeleted: islemAktif ? null : onMusteriKaldir,
                          deleteButtonTooltipMessage: 'Müşteriyi kaldır',
                        )
                      : ActionChip(
                          avatar: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                          label: const Text('Müşteri Ekle'),
                          onPressed: islemAktif ? null : onMusteriSec,
                        ),
                ],
              ]),
            ),
            if (aktifSiparis)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TsRenk.masaAcik.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Text('Toplam',
                      style: TextStyle(fontSize: 11, color: context.textSecondary)),
                  Text(ParaUtils.formatla(toplam),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: TsRenk.masaAcik)),
                ]),
              ),
          ]),
        ),

        Expanded(
          child: !aktifSiparis
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.receipt_long_outlined, size: 64, color: TsRenk.ayirac(context)),
                    const SizedBox(height: 12),
                    Text('Bu masada sipariş yok',
                        style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 15)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/masa/urun-ekle/${masa.id}'),
                      icon: const Icon(Icons.add),
                      label: const Text('Sipariş Başlat'),
                    ),
                  ]),
                )
              : _SiparisKalemListesi(
                  siparis: siparis!,
                  masaId: masa.id!,
                ),
        ),

        if (aktifSiparis)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: LayoutBuilder(builder: (context, c) {
                // Buton genişliği EKRAN değil bulunduğu alana göre hesaplanır
                // (masaüstünde sağ panel ~440 px; önceden pencere genişliğine
                // bakıldığı için butonlar panele sığmayıp taşıyordu).
                final alan = c.maxWidth.clamp(0.0, 720.0);
                final kucuk = (alan - 20) / 3;
                final buyuk = (alan - 10) / 2;
                return Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _ActionButton(
                    icon: Icons.add,
                    label: 'Ürün Ekle',
                    onTap: () => context.push('/masa/urun-ekle/${masa.id}'),
                    outlined: true,
                    genislik: kucuk,
                  ),
                  _ActionButton(
                    icon: Icons.receipt_long_outlined,
                    label: 'Adisyon',
                    onTap: onAdisyon,
                    isLoading: islemAktif,
                    outlined: true,
                    genislik: kucuk,
                  ),
                  _ActionButton(
                    icon: Icons.notifications_active_outlined,
                    label: 'Hesap İstendi',
                    onTap: onHesapIstendi,
                    outlined: true,
                    color: Colors.orange,
                    genislik: kucuk,
                  ),
                  _ActionButton(
                    icon: Icons.payments_outlined,
                    label: 'Ödeme Al',
                    onTap: onOdeme,
                    isLoading: islemAktif,
                    filled: true,
                    genislik: buyuk,
                  ),
                ],
              );
              }),
            ),
          ),
      ],
    );
  }

  String _formatSaat(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool outlined;
  final bool filled;
  final Color? color;
  final double? genislik;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.outlined = false,
    this.filled = false,
    this.color,
    this.genislik,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? const Color(0xFF6D4C41);
    final width = genislik ?? (MediaQuery.of(context).size.width - 60) / (filled ? 2 : 3);

    if (filled) {
      return SizedBox(
        width: width,
        child: FilledButton.icon(
          onPressed: isLoading ? null : onTap,
          icon: isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: btnColor,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onTap,
        icon: isLoading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: btnColor,
          side: BorderSide(color: btnColor),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ==================== SİPARİŞ KALEM LİSTESİ ====================
class _SiparisKalemListesi extends ConsumerStatefulWidget {
  final MasaSiparisModel siparis;
  final int masaId;

  const _SiparisKalemListesi({required this.siparis, required this.masaId});

  @override
  ConsumerState<_SiparisKalemListesi> createState() => _SiparisKalemListesiState();
}

class _SiparisKalemListesiState extends ConsumerState<_SiparisKalemListesi> {
  @override
  Widget build(BuildContext context) {
    final kalemler = widget.siparis.kalemler;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: kalemler.length,
      itemBuilder: (_, i) {
        final k = kalemler[i];
        final durumRenk = _durumRenk(k.durum);
        
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TsRenk.ayirac(context)),
            boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF6D4C41).withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  k.miktar == k.miktar.roundToDouble()
                      ? k.miktar.toInt().toString()
                      : k.miktar.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF6D4C41)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.urunAdi,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${ParaUtils.formatla(k.birimFiyat)} TL',
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                if (k.not_ != null && k.not_!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: TsRenk.zemin(TsRenk.uyari),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(k.not_!,
                        style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
                  ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(ParaUtils.formatla(k.toplam),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: TsRenk.masaAcik)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: durumRenk.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_durumEtiket(k.durum),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: durumRenk)),
              ),
            ]),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: () => _kalemSil(k.id!),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ]),
        );
      },
    );
  }

  Color _durumRenk(String durum) {
    switch (durum) {
      case 'beklemede': return const Color(0xFFD32F2F);
      case 'hazirlaniyor': return const Color(0xFFEF6C00);
      case 'hazir': return const Color(0xFF2E7D32);
      case 'servis_edildi': return const Color(0xFF9E9E9E);
      default: return context.textSecondary;
    }
  }

  String _durumEtiket(String durum) {
    switch (durum) {
      case 'beklemede': return 'Bekliyor';
      case 'hazirlaniyor': return 'Hazırlanıyor';
      case 'hazir': return 'Hazır';
      case 'servis_edildi': return 'Servis Edildi';
      default: return durum;
    }
  }

  Future<void> _kalemSil(int kalemId) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ürünü Sil'),
        content: const Text('Bu ürünü siparişten silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay == true) {
      await ref.read(masaSiparisProvider(widget.masaId).notifier).kalemSil(kalemId);
    }
  }
}
