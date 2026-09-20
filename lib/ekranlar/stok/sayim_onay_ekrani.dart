// lib/ekranlar/stok/sayim_onay_ekrani.dart
//
// Sayım Onay Sistemi (Madde 13 denetimi, 2026-09-16) — kasiyer/personel
// bir stok sayımını "Uygula"ya bastığında (stok_sayim_ekrani.dart),
// Müdür/Admin DEĞİLSE stok DEĞİŞMEZ — sayım 'gecici_sayim' tablosunda
// BEKLER. Bu ekran o bekleyen listeyi Müdür/Admin'e gösterir:
//
//   Sayım → Fark hesapla → Onaya gönder → Yetkili onayı →
//   Stok düzeltme hareketi → Audit → Sync
//
// zincirinin "Yetkili onayı" adımı burada gerçekleşir. Onaylanınca
// StokDeposu.geciciSayimUygula() çağrılır — bu, HER satır için gerçek
// stokDuzelt() (stok_hareket + urunler.stok + BulutManager.upsert →
// audit log + sync) çalıştırır, yani Audit/Sync adımları zaten mevcut
// altyapı üzerinden otomatik sağlanır.
//
// Route seviyesinde MudurYetkiKorumasi ile korunuyor (uygulama_router.
// dart) — deep-link ile kasiyer buraya gelse bile "Erişim Kısıtlı" görür.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/stok_sayim_provider.dart';
import '../../depolar/stok_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/onay_dialog.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';

class SayimOnayEkrani extends ConsumerStatefulWidget {
  const SayimOnayEkrani({super.key});

  @override
  ConsumerState<SayimOnayEkrani> createState() => _SayimOnayEkraniState();
}

class _SayimOnayEkraniState extends ConsumerState<SayimOnayEkrani> {
  final _stokDepo = StokDeposu();
  bool _isleniyor = false;

  Future<void> _onayla() async {
    final onay = await OnayDialog.goster(context,
        baslik: 'Sayımı Onayla',
        icerik: 'Bekleyen tüm sayım kalemleri için stok güncellenecek. '
            'Bu işlem geri alınamaz (yeni bir "Sayım" hareketi olarak '
            'kaydedilir). Onaylıyor musunuz?',
        onayYazi: 'Onayla ve Uygula', onayRengi: Colors.green.shade700,
        ikon: Icons.check_circle_outline);
    if (!onay || !mounted) return;

    setState(() => _isleniyor = true);
    try {
      final kullaniciId = AuthServisi().aktifKullanici?.id ?? 0;
      await _stokDepo.geciciSayimUygula(kullaniciId);
      ref.invalidate(sayimGecmisProvider);
      if (mounted) BildirimServisi.basari(context, 'Sayım onaylandı, stok güncellendi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Onaylanamadı: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  Future<void> _reddet() async {
    final onay = await OnayDialog.goster(context,
        baslik: 'Sayımı Reddet',
        icerik: 'Bekleyen TÜM sayım kalemleri silinecek — stokta HİÇBİR '
            'değişiklik yapılmayacak. Sayımı yapan kişi baştan saymalı. '
            'Devam edilsin mi?',
        onayYazi: 'Reddet', onayRengi: Colors.red.shade700,
        ikon: Icons.cancel_outlined);
    if (!onay || !mounted) return;

    setState(() => _isleniyor = true);
    try {
      await _stokDepo.geciciSayimReddet();
      ref.invalidate(sayimGecmisProvider);
      if (mounted) BildirimServisi.basari(context, 'Sayım reddedildi, stok değişmedi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Reddedilemedi: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sayimGecmisProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Bekleyen Sayım Onayları'),
      body: async.when(
        loading: () => const Center(child: AppYukleniyor()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (liste) {
          if (liste.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: TsRenk.ayirac(context)),
                const SizedBox(height: 16),
                Text('Bekleyen sayım onayı yok',
                    style: TextStyle(color: TsRenk.metinIkincil(context))),
              ]),
            );
          }

          final toplamFark = liste.fold<double>(
              0, (s, r) => s + (((r['yeni_stok'] as num?) ?? 0) - ((r['mevcut_stok'] as num?) ?? 0)));

          return Column(children: [
            Container(
              width: double.infinity,
              color: Color.fromARGB(15, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '${liste.length} ürün onay bekliyor · net fark: ${toplamFark.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppRenkler.primary),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: liste.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final r = liste[i];
                  final mevcut = ((r['mevcut_stok'] as num?) ?? 0).toDouble();
                  final yeni = ((r['yeni_stok'] as num?) ?? 0).toDouble();
                  final fark = yeni - mevcut;
                  final sayanAdi = r['sayan_adi'] as String?;
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TsRenk.ayirac(context)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['urun_adi']}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            'Mevcut: ${mevcut.toStringAsFixed(0)} ${r['birim_adi'] ?? ''} → '
                            'Sayılan: ${yeni.toStringAsFixed(0)} ${r['birim_adi'] ?? ''}',
                            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
                          ),
                          if (sayanAdi != null && sayanAdi.trim().isNotEmpty)
                            Text('Sayan: $sayanAdi',
                                style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
                        ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: fark == 0
                              ? TsRenk.arkaplan(context)
                              : (fark > 0 ? Colors.green.shade50 : Colors.red.shade50),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${fark > 0 ? '+' : ''}${fark.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13,
                            color: fark == 0
                                ? TsRenk.metinIkincil(context)
                                : (fark > 0 ? Colors.green.shade700 : Colors.red.shade700),
                          ),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ]);
        },
      ),
      bottomNavigationBar: ref.watch(sayimGecmisProvider).maybeWhen(
            data: (liste) => liste.isEmpty
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isleniyor ? null : _reddet,
                            icon: const Icon(Icons.close),
                            label: const Text('Reddet'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isleniyor ? null : _onayla,
                            icon: _isleniyor
                                ? const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.check),
                            label: const Text('Onayla'),
                            style: FilledButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
            orElse: () => null,
          ),
    );
  }
}
