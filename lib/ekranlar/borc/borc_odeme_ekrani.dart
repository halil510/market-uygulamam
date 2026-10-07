// lib/ekranlar/borc/borc_odeme_ekrani.dart
//
// Bağımsız ödeme rotası: /borc-odeme (borç seçimi) ve /borc-odeme/:id.
//
// 🔴 DÜZELTME (derin analiz 2026-10-07):
//  • Ödeme penceresi post-frame callback'te try/catch olmadan açılıyordu:
//    banka/kart listesi okunamazsa hata kayboluyor, gövdedeki TsYukleniyor
//    sonsuza dek dönüyordu. Artık borcOdemePenceresiAc() hatayı bildirir.
//  • Ekran sadece `extra` ile gelen BorcModel'le açılabiliyordu; :id yok
//    sayılıyordu, borç verilmezse geri dönülüyordu. Artık borç sırasıyla
//    `extra`dan, id'den yüklenir; hiçbiri yoksa ödenecek borç seçilir.
//  • Her durum (yükleniyor / hata / bulunamadı / boş liste) kullanıcıya
//    görünür ve "Tekrar Dene" ile kurtarılabilir.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../cekirdek/utils/hata_utils.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/borc_deposu.dart';
import '../../modeller/borc_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'widgets/borc_odeme_baslatici.dart';

class BorcOdemeEkrani extends StatefulWidget {
  /// Ödenecek borç zaten elinizdeyse (ör. listeden geçiş) doğrudan verilir.
  final BorcModel? borc;

  /// Yalnızca id biliniyorsa (derin link) borç veritabanından yüklenir.
  final int? borcId;

  const BorcOdemeEkrani({super.key, this.borc, this.borcId});

  @override
  State<BorcOdemeEkrani> createState() => _BorcOdemeEkraniState();
}

class _BorcOdemeEkraniState extends State<BorcOdemeEkrani> {
  final _depo = BorcDeposu();
  late Future<List<BorcModel>> _borclar;

  /// Tek borç modunda (borç veya id verilmiş) ödeme penceresi otomatik açılır.
  bool get _tekBorcModu => widget.borc != null || widget.borcId != null;

  @override
  void initState() {
    super.initState();
    _borclar = _borclariYukle();
    if (_tekBorcModu) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tekBorcOdemesi());
    }
  }

  Future<List<BorcModel>> _borclariYukle() async {
    final verilen = widget.borc;
    if (verilen != null) return [verilen];
    final id = widget.borcId;
    if (id != null) {
      final borc = await _depo.idileGetir(id);
      return borc == null ? const [] : [borc];
    }
    return _depo.tumunuGetir(sadeceAktif: true);
  }

  void _yenidenYukle() => setState(() => _borclar = _borclariYukle());

  /// Tek borç modu: borç yüklenince pencereyi aç, kapanınca sonucu döndür.
  Future<void> _tekBorcOdemesi() async {
    final List<BorcModel> liste;
    try {
      liste = await _borclar;
    } catch (_) {
      return; // hata durumu build()'de gösteriliyor
    }
    if (liste.isEmpty || !mounted) return;
    final odendi = await borcOdemePenceresiAc(context, liste.first);
    if (mounted && context.canPop()) context.pop(odendi);
  }

  /// Seçim modu: seçilen borcu öde, liste güncel kalan tutarla yenilensin.
  Future<void> _secilenBorcuOde(BorcModel borc) async {
    final odendi = await borcOdemePenceresiAc(context, borc);
    if (!odendi || !mounted) return;
    BildirimServisi.basari(context, '${borc.baslik} için ödeme kaydedildi ✓');
    _yenidenYukle();
  }

  @override
  Widget build(BuildContext context) {
    final baslik = widget.borc != null
        ? 'Ödeme Yap - ${widget.borc!.baslik}'
        : (_tekBorcModu ? 'Ödeme Yap' : 'Ödenecek Borcu Seçin');
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(baslik: baslik, gradyanli: false),
      body: FutureBuilder<List<BorcModel>>(
        future: _borclar,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const TsYukleniyor();
          }
          if (snap.hasError) {
            return TsBosDurum(
              ikon: Icons.error_outline,
              renk: TsRenk.hata,
              baslik: 'Borç bilgisi yüklenemedi',
              altyazi: kullaniciyaHataMetni(snap.error!),
              aksiyonMetni: 'Tekrar Dene',
              aksiyon: _yenidenYukle,
            );
          }
          final liste = snap.data ?? const <BorcModel>[];
          if (liste.isEmpty) {
            return TsBosDurum(
              ikon: _tekBorcModu ? Icons.search_off : Icons.task_alt,
              baslik: _tekBorcModu ? 'Borç bulunamadı' : 'Ödenecek borç yok',
              altyazi: _tekBorcModu
                  ? 'Bu borç silinmiş veya tamamen ödenmiş olabilir.'
                  : 'Tüm borçlar ödenmiş görünüyor.',
            );
          }
          if (_tekBorcModu) {
            return _TekBorcBekleme(
              borc: liste.first,
              onOdemeAc: _tekBorcOdemesi,
            );
          }
          return _BorcSecimListesi(borclar: liste, onSec: _secilenBorcuOde);
        },
      ),
    );
  }
}

/// Tek borç modunda pencere kapatılmış ama ekran açık kaldıysa (geri
/// dönülecek sayfa yok — derin link) ödemeyi yeniden açma imkânı.
class _TekBorcBekleme extends StatelessWidget {
  final BorcModel borc;
  final VoidCallback onOdemeAc;

  const _TekBorcBekleme({required this.borc, required this.onOdemeAc});

  @override
  Widget build(BuildContext context) {
    return TsBosDurum(
      ikon: Icons.payments_outlined,
      baslik: borc.baslik,
      altyazi: 'Kalan: ${ParaUtils.formatla(borc.kalanTutar)}',
      aksiyonMetni: 'Ödeme Yap',
      aksiyon: onOdemeAc,
    );
  }
}

class _BorcSecimListesi extends StatelessWidget {
  final List<BorcModel> borclar;
  final ValueChanged<BorcModel> onSec;

  const _BorcSecimListesi({required this.borclar, required this.onSec});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: borclar.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _BorcSatiri(borc: borclar[i], onSec: onSec),
    );
  }
}

class _BorcSatiri extends StatelessWidget {
  final BorcModel borc;
  final ValueChanged<BorcModel> onSec;

  const _BorcSatiri({required this.borc, required this.onSec});

  @override
  Widget build(BuildContext context) {
    final gecikti = borc.vadesiGecti;
    return TsKart.liste(
      baslik: borc.baslik,
      altBaslik: gecikti
          ? 'Vadesi ${-borc.kalanGun} gün geçti'
          : 'Son ödeme: ${borc.kalanGun} gün sonra',
      deger: ParaUtils.formatla(borc.kalanTutar),
      ikon: Icon(
        gecikti ? Icons.warning_amber_rounded : Icons.receipt_long_outlined,
        color: gecikti ? TsRenk.hata : null,
      ),
      onTap: () => onSec(borc),
    );
  }
}
