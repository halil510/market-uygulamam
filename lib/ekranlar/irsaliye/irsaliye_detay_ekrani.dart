// lib/ekranlar/irsaliye/irsaliye_detay_ekrani.dart
//
// İrsaliye detayı, durum güncelleme ve e-İrsaliye gönder/sorgula —
// irsaliye_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
import '../../cekirdek/utils/hata_utils.dart';
import 'dart:async';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../widgetlar/ortak/onay_dialog.dart';
import '../../depolar/irsaliye_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/gib_servisi.dart';

/// e-İrsaliye "Gönder" kapalı / "Durum Sorgula" açık olmalı mı — fatura
/// tarafındaki [eFaturaGonderilmisMi] ile AYNI kural. 'gonderiliyor'
/// ÖNCEDEN burada yoktu: gönderim sırasında çökmüş bir irsaliye GİB'deki
/// gerçek durumu sorgulanmadan kör kör yeniden gönderilebiliyordu.
bool eIrsaliyeGonderilmisMi(String? durum) =>
    durum == 'gonderildi' || durum == 'onaylandi' || durum == 'gib_iptal' ||
    durum == 'gonderiliyor';

class IrsaliyeDetayEkrani extends ConsumerStatefulWidget {
  final int irsaliyeId;
  const IrsaliyeDetayEkrani({super.key, required this.irsaliyeId});

  @override
  ConsumerState<IrsaliyeDetayEkrani> createState() => _IrsaliyeDetayEkraniState();
}

class _IrsaliyeDetayEkraniState extends ConsumerState<IrsaliyeDetayEkrani> {
  Map<String, dynamic>? _irsaliye;
  List<Map<String, dynamic>> _kalemler = [];
  bool _yukleniyor = true;
  bool _islemDevam = false;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final (bas, kalemler) = await IrsaliyeDeposu().detayGetir(widget.irsaliyeId);
      if (!mounted) return;
      setState(() {
        _irsaliye  = bas;
        _kalemler  = kalemler;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _durumGuncelle(String yeniDurum) async {
    if (yeniDurum == 'İptal') {
      final onay = await OnayDialog.goster(context,
          baslik: 'İrsaliyeyi İptal Et',
          icerik: 'Bu irsaliye iptal edilecek. Emin misiniz?',
          onayYazi: 'İptal Et', onayRengi: Colors.red);
      if (!onay || !mounted) return;
    }
    try {
      // 🔴 Derin analizde bulundu: last_updated hiç ayarlanmıyordu,
      // BulutManager hiç çağrılmıyordu — bkz. IrsaliyeDeposu.durumGuncelle.
      await IrsaliyeDeposu().durumGuncelle(widget.irsaliyeId, yeniDurum);
      await _yukle();
      if (!mounted) return;
      BildirimServisi.basari(context, 'Durum güncellendi: $yeniDurum');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: ${bildirimMetniniSadelestir(e.toString())}');
    }
  }

  bool get _eIrsaliyeGonderilmis =>
      eIrsaliyeGonderilmisMi(_irsaliye?['e_irsaliye_durum']?.toString());

  // ── e-İrsaliye Gönder ────────────────────────────────────────────────────
  // Ayarlar > Fatura Ayarları'ndaki "e-İrsaliye Aktif" anahtarı ÖNCEDEN hiçbir
  // koda bağlı değildi (bkz. gib_servisi.dart'taki geniş not) — bu, o
  // eksikliği kapatan ilk gerçek gönderim noktası.
  Future<void> _eIrsaliyeGonder() async {
    if (_irsaliye == null || !mounted || _islemDevam || _eIrsaliyeGonderilmis) return;
    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('e-İrsaliye Gönder'),
        content: Text(
          '${_irsaliye!['irsaliye_no'] ?? "İrsaliye"} GİB sistemine '
          'e-İrsaliye olarak gönderilecek.\n\nOnaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gönder')),
        ],
      ));
    if (onay != true || !mounted) return;

    setState(() => _islemDevam = true);
    try {
      final irsaliyeDepo = IrsaliyeDeposu();
      // Reddedilmiş bir denemeden sonra yeniden gönderiliyorsa deneme
      // sayacını artır (bkz. gib_servisi.dart'taki ETTN notu — faturalar
      // ile AYNI mantık).
      final oncekiReddedildi = _irsaliye!['e_irsaliye_durum'] == 'reddedildi';
      await irsaliyeDepo.eIrsaliyeGonderimeHazirla(
        widget.irsaliyeId,
        oncekiReddedildi: oncekiReddedildi,
        mevcutDenemeNo: (_irsaliye!['e_irsaliye_deneme_no'] as int?) ?? 0,
      );
      if (oncekiReddedildi) await _yukle();

      final gib = GibServisi();
      await gib.ayarlariYukle();
      final sonuc = await gib.irsaliyeGonder(irsaliye: _irsaliye!, kalemler: _kalemler);
      await irsaliyeDepo.eIrsaliyeSonucKaydet(widget.irsaliyeId,
          basarili: sonuc.basarili, uuid: sonuc.uuid);
      await _yukle();
      if (!mounted) return;
      if (sonuc.basarili) {
        BildirimServisi.basari(context, 'e-İrsaliye gönderildi ✓');
      } else {
        BildirimServisi.hata(context, sonuc.hata ?? 'Gönderim başarısız');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: ${bildirimMetniniSadelestir(e.toString())}');
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }

  Future<void> _eIrsaliyeDurumSorgula() async {
    if (_irsaliye == null) return;
    final gib = GibServisi();
    final eDurum = _irsaliye!['e_irsaliye_durum']?.toString();
    // 'gonderiliyor'da kalmış (gönderim sırasında çökme) irsaliyenin ETTN'si
    // DB'de null olabilir — deterministik olduğu için yeniden hesaplanır
    // (fatura tarafındaki FaturaEbelgeServisi.ettnBelirle ile aynı mantık).
    final kayitli = _irsaliye!['e_irsaliye_uuid']?.toString();
    final uuid = (kayitli != null && kayitli.isNotEmpty)
        ? kayitli
        : eDurum == 'gonderiliyor' ? gib.ettnIrsaliyeHesapla(_irsaliye!) : null;
    if (uuid == null) return;
    setState(() => _islemDevam = true);
    try {
      await gib.ayarlariYukle();
      final sonuc = await gib.durumSorgula(uuid,
          referansId: widget.irsaliyeId, referansTuru: 'irsaliye');
      final durum = sonuc?.durum;
      if (durum != null) {
        await IrsaliyeDeposu().eIrsaliyeDurumGuncelle(widget.irsaliyeId, durum, uuid: uuid);
        await _yukle();
      }
      if (mounted) {
        final aciklama = sonuc?.aciklama;
        if (durum == 'reddedildi') {
          BildirimServisi.hata(context,
              'GİB Reddetti${aciklama != null ? ' — Sebep: $aciklama' : ''}');
        } else {
          BildirimServisi.basari(context,
              'Durum: ${durum ?? "Bilinmiyor"}${aciklama != null ? ' — $aciklama' : ''}');
        }
      }
    } on GibBelgeBulunamadi {
      // GİB'e hiç ulaşmamış: 'hata'ya çek, Gönder tekrar açılsın (aynı
      // deneme_no → aynı ETTN, mükerrer belge oluşmaz).
      if (eDurum == 'gonderiliyor') {
        await IrsaliyeDeposu().eIrsaliyeDurumGuncelle(widget.irsaliyeId, 'hata');
        await _yukle();
      }
      if (mounted) {
        BildirimServisi.uyari(context,
            'Bu irsaliye GİB\'e hiç ulaşmamış. Güvenle yeniden gönderebilirsiniz.');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: ${bildirimMetniniSadelestir(e.toString())}');
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Scaffold(body: Center(child: AppYukleniyor()));
    }
    if (_irsaliye == null) {
      return const Scaffold(
        appBar: TsAppBar(
        gradyanli: false,
      ),
        body: BosEkran(ikon: Icons.inbox_outlined, baslik: 'Bulunamadı'),
      );
    }

    final durum  = _irsaliye!['durum']?.toString() ?? 'Bekliyor';
    final tarih  = DateTime.tryParse(_irsaliye!['tarih']?.toString() ?? '');
    final toplam = (_irsaliye!['toplam_tutar'] as num?)?.toDouble() ?? 0;
    final eDurum = _irsaliye!['e_irsaliye_durum']?.toString() ?? 'hazir';
    final eRenk  = eDurum == 'onaylandi' ? Colors.teal
                 : eDurum == 'gonderildi' ? Colors.green
                 : eDurum == 'gonderiliyor' ? Colors.blue
                 : eDurum == 'reddedildi' ? Colors.red
                 : eDurum == 'gib_iptal' ? Colors.grey
                 : eDurum == 'hata' ? Colors.red : Colors.orange;
    final eEtiket = eDurum == 'onaylandi' ? 'GİB Onayladı'
                  : eDurum == 'gonderildi' ? 'e-İrsaliye Gönderildi'
                  : eDurum == 'gonderiliyor' ? 'Gönderiliyor'
                  : eDurum == 'reddedildi' ? 'GİB Reddetti'
                  : eDurum == 'gib_iptal' ? 'GİB\'de İptal'
                  : eDurum == 'hata' ? 'Gönderim Hatası' : 'e-İrsaliye Gönderilmedi';

    return Scaffold(
      appBar: TsAppBar(
        baslikWidget: Text(_irsaliye!['irsaliye_no']?.toString() ?? 'İrsaliye'),
        aksiyonlar: [
          if (_irsaliye!['e_irsaliye_uuid'] != null || eDurum == 'gonderiliyor')
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'GİB Durum Sorgula',
              onPressed: _islemDevam ? null : _eIrsaliyeDurumSorgula,
            ),
          IconButton(
            icon: Icon(
              eDurum == 'onaylandi' ? Icons.verified_outlined
                  : eDurum == 'gonderildi' ? Icons.cloud_done_outlined
                  : eDurum == 'reddedildi' ? Icons.cancel_outlined
                  : Icons.send_outlined,
              color: eRenk,
            ),
            tooltip: _eIrsaliyeGonderilmis ? eEtiket : 'e-İrsaliye Gönder',
            onPressed: (_islemDevam || _eIrsaliyeGonderilmis) ? null : _eIrsaliyeGonder,
          ),
          PopupMenuButton<String>(
            onSelected: _durumGuncelle,
            itemBuilder: (_) => ['Hazırlanıyor', 'Yolda', 'Teslim Edildi', 'İptal']
                .map((d) => PopupMenuItem(value: d, child: Text(d)))
                .toList(),
          ),
        ],
        gradyanli: false,
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Color.fromARGB(76, Theme.of(context).colorScheme.surfaceVariant.red, Theme.of(context).colorScheme.surfaceVariant.green, Theme.of(context).colorScheme.surfaceVariant.blue),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Müşteri',
                    style: TextStyle(fontSize: 11, color: context.textSecondary)),
                Text(_irsaliye!['cari_adi']?.toString() ?? 'Belirtilmemiş',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Tarih',
                    style: TextStyle(fontSize: 11, color: context.textSecondary)),
                Text(tarih != null ? _fmt.format(tarih) : '-',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Wrap(spacing: 6, children: [
                Chip(
                  label: Text(durum),
                  backgroundColor: durum == 'Teslim Edildi'
                      ? TsRenk.zemin(TsRenk.basarili, opaklik: 0.18)
                      : TsRenk.zemin(TsRenk.uyari, opaklik: 0.18),
                ),
                Chip(
                  label: Text(eEtiket, style: TextStyle(fontSize: 11, color: eRenk)),
                  backgroundColor: Color.fromARGB(26, eRenk.red, eRenk.green, eRenk.blue),
                  side: BorderSide(color: Color.fromARGB(102, eRenk.red, eRenk.green, eRenk.blue)),
                ),
              ]),
              Text(ParaUtils.formatla(toplam),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18)),
            ]),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _kalemler.length,
            itemBuilder: (_, i) {
              final k      = _kalemler[i];
              final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
              final bf     = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: ListTile(
                  title: Text(
                    k['urun_adi']?.toString() ??
                        k['urun_adi_db']?.toString() ?? '-',
                  ),
                  subtitle: Text(
                      '${miktar.toStringAsFixed(2)} adet × ${ParaUtils.formatla(bf)}'),
                  trailing: Text(
                    ParaUtils.formatla(miktar * bf),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
