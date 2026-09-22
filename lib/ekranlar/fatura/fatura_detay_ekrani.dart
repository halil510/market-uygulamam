import 'package:go_router/go_router.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
// lib/ekranlar/fatura/fatura_detay_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart' as bc;
import 'package:intl/intl.dart';
import '../../cekirdek/utils/sayi_yaziya_cevir.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/fatura_deposu.dart';
import '../../modeller/fatura_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../depolar/ayarlar_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/gib_servisi.dart';
import '../../servisler/fatura_ebelge_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';

// God-class sertleştirmesi (2026-09-22, kullanıcı onayıyla): bu dosya
// 1284 satırdı. İçerik davranış DEĞİŞTİRİLMEDEN 2 parçaya ayrıldı:
//   - fatura_detay_pdf_ext.dart       → PDF/termal fiş üretim mantığı
//   - fatura_detay_islemler_ext.dart  → ödeme + e-Fatura/GİB diyalogları
part 'fatura_detay_pdf_ext.dart';
part 'fatura_detay_islemler_ext.dart';

// Fatura GİB'e (bir kez) başarıyla iletildi mi — 'gonderildi' (henüz GİB
// onayı sorgulanmamış) VEYA 'onaylandi' (GİB onayı sorgulanmış ve
// onaylanmış) ikisi de "artık tekrar gönderilemez" anlamına gelir.
// 'reddedildi'/'hata' BİLEREK bu listede DEĞİL — ikisi de kullanıcının
// düzeltip yeniden gönderebilmesi gereken durumlar (bkz. ETTN yeniden
// üretme notu — gib_servisi.dart _ettnFaturaIcin). 'gib_iptal' de
// BİLEREK dışında değil ama zaten UI'da ayrı ele alınıyor.
//
// 🔴 DÜZELTME (Madde 23 denetimi, 2026-09-20): 'gonderiliyor' BİLEREK
// EKLENDİ. Önceden bu durum bu listede YOKTU — bu, tam olarak "gönderim
// isteği GİB'e gitti ama yanıt uygulama tarafında hiç işlenemedi" (ör.
// gönderim sırasında çökme) senaryosunda "Durum Sorgula" butonunun
// DEVRE DIŞI kalmasına yol açıyordu — kullanıcı GİB'in gerçekte ne
// yaptığını SORGULAYAMIYOR, sadece kör kör tekrar "Gönder"e
// basabiliyordu. Artık bu durumda Sorgula AÇIK, Gönder KAPALI —
// kullanıcı önce gerçek durumu öğrenmeye zorlanıyor. Test edilebilirlik
// için top-level saf fonksiyon olarak tutulur (bkz. test/ekranlar/
// fatura_gonderilmis_mi_test.dart).
bool eFaturaGonderilmisMi(String? durum) =>
    durum == 'gonderildi' || durum == 'onaylandi' || durum == 'gib_iptal' ||
    durum == 'gonderiliyor';

class FaturaDetayEkrani extends ConsumerStatefulWidget {
  final int faturaId;
  const FaturaDetayEkrani({super.key, required this.faturaId});
  @override
  ConsumerState<FaturaDetayEkrani> createState() => _FaturaDetayEkraniState();
}

class _FaturaDetayEkraniState extends ConsumerState<FaturaDetayEkrani> {
  final _depo = FaturaDeposu();
  // Madde 2 mimari denetimi: e-Belge (taslak/onay/gönderim/hata) durum
  // makinesinin ETTN/DB/GİB orkestrasyonu artık burada DEĞİL, bu serviste
  // — ekran sadece dialog/loading/bildirim göstermekten sorumlu.
  final _eBelge = FaturaEBelgeServisi();
  FaturaModel? _fatura;
  bool _yukleniyor = true;
  // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): ne ödeme kaydetme ne
  // de e-Fatura gönderme butonunda çift-tıklama koruması vardı. e-Fatura
  // gönderiminde durum ('gonderildi') ancak ağ çağrısı DÖNDÜKTEN sonra
  // güncelleniyordu — hızlı bir çift dokunma, ilk gönderim hâlâ
  // sürerken İKİNCİ bir GİB gönderimini (yasal bağlayıcılığı olan bir
  // e-belge için) başlatabilirdi. Tek bir bayrak, ilk await'ten ÖNCE
  // set edilip her iki işlemi de korur.
  bool _islemDevam = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final f = await _depo.idileGetir(widget.faturaId);
      if (!mounted) return;
      setState(() { _fatura = f; _yukleniyor = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _yukleniyor = false);
        BildirimServisi.hata(context, 'Fatura yüklenemedi: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Scaffold(body: TsYukleniyor());
    }
    if (_fatura == null) {
      return Scaffold(
appBar: TsAppBar(
        baslik: 'Fatura Detay',
        gradyanli: false,
      ),
        body: const Center(child: Text('Fatura bulunamadi')),
      );
    }

    final f   = _fatura!;
    final fmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(f.faturaNo ?? 'Fatura'),
        aksiyonlar: [
          IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Önizleme',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _FaturaOnizlemeEkrani(
                    pdfBytes: _pdfBytes, faturaNo: f.faturaNo ?? 'Fatura'),
              ))),
          IconButton(
              icon: Image.asset("assets/images/pdf_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf)),
              tooltip: 'PDF',
              onPressed: _pdfGoster),
          IconButton(
              icon: const Icon(Icons.payment),
              tooltip: 'Odeme Kaydet',
              onPressed: (f.kalanTutar > 0 && !_islemDevam) ? _odemeKaydet : null),
          // 🔴 DÜZELTME (erp_roadmap madde 38 — e-Belge durum makinesi,
          // GERÇEK BULGU): "Durum Sorgula" GİB'den 'onaylandi' dönüp bunu
          // kaydettiğinde (eFaturaDurumGuncelle), bu iki buton SADECE
          // 'gonderildi' değerine bakıyordu — 'onaylandi' o kontrolden
          // GEÇMİYORDU. Sonuç: GİB tarafından ONAYLANMIŞ bir fatura,
          // "e-Fatura Gönder" butonu tekrar AKTİFLEŞTİĞİ için yanlışlıkla
          // İKİNCİ KEZ GİB'e gönderilebiliyordu — mükerrer gönderim riski.
          IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: eFaturaGonderilmisMi(f.eFaturaDurum) ? _durumSorgula : null,
              tooltip: 'Durum Sorgula',
            ),
            IconButton(
              icon: Icon(_durumIkonu(f.eFaturaDurum), color: _durumRengi(f.eFaturaDurum)),
              tooltip: eFaturaGonderilmisMi(f.eFaturaDurum)
                  ? 'e-Fatura ${_durumEtiketi(f.eFaturaDurum)}'
                  : f.eFaturaDurum == 'reddedildi'
                      ? 'GİB Reddetti — Yeniden Gönder'
                      : 'e-Fatura Gönder',
              onPressed: (eFaturaGonderilmisMi(f.eFaturaDurum) || _islemDevam) ? null : _efaturaGonder),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Diğer',
            onSelected: (v) {
              if (v == 'eposta') _epostaGonder();
              if (v == '80mm') _pdf80mmGoster();
              if (v == 'a4') _pdfGosterA4();
              if (v == 'gib_iptal') _gibIptalEt();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'eposta', child: Row(children: [
                Icon(Icons.email_outlined, size: 18), SizedBox(width: 8),
                Text('E-posta ile Gönder'),
              ])),
              const PopupMenuItem(value: '80mm', child: Row(children: [
                Icon(Icons.receipt_long_outlined, size: 18), SizedBox(width: 8),
                Text('80mm Fiş Yazdır'),
              ])),
              const PopupMenuItem(value: 'a4', child: Row(children: [
                Icon(Icons.description_outlined, size: 18), SizedBox(width: 8),
                Text('A4 Yazdır'),
              ])),
              if (f.eFaturaDurum == 'gonderildi' || f.eFaturaDurum == 'onaylandi')
                const PopupMenuItem(value: 'gib_iptal', child: Row(children: [
                  Icon(Icons.block_outlined, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('GİB\'de İptal Et', style: TextStyle(color: Colors.red)),
                ])),
            ],
          ),
        ],
        gradyanli: false,
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        // Fatura başlık kartı
        Container(
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: TsRenk.ayirac(context))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Text(f.faturaNo ?? '-',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                Wrap(spacing: 6, children: [
                  _eFaturaDurumChip(f.eFaturaDurum),
                  _durumuChip(f.odemeDurumu),
                ]),
              ]),
              const SizedBox(height: 8),
              _bilgiSatiri('Tarih', fmt.format(f.tarih)),
              if (f.vadeTarihi != null)
                _bilgiSatiri('Vade', fmt.format(f.vadeTarihi!)),
              _bilgiSatiri('Tip', f.faturaTipi ?? '-'),
              _bilgiSatiri('Cari', f.cariUnvan ?? '-'),
              if (f.cariVergiNo != null)
                _bilgiSatiri('VKN', f.cariVergiNo!),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Kalemler
        ...f.detaylar.map((d) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))),
          child: ListTile(
            dense: true,
            title: Text(d.urunAdi,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${d.miktar.toStringAsFixed(0)} x '
                '${ParaUtils.formatla(d.birimFiyat)}  KDV:%${d.kdvOrani.toStringAsFixed(0)}'),
            trailing: Text(ParaUtils.formatla(d.toplamTutar),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        )),
        const SizedBox(height: 12),

        // Toplam
        Container(
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: TsRenk.ayirac(context))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Not: "Ara Toplam" BİLEREK indirim UYGULANMADAN ÖNCEKİ brüt
              // tutar olarak gösteriliyor (toplamAraToplam zaten net
              // saklanıyor) — aksi halde alttaki "Iskonto" satırı ikinci
              // kez düşülmüş gibi görünüp toplam tutmazdı.
              _toplamSatir('Ara Toplam', f.toplamAraToplam + f.toplamIskonto),
              if (f.toplamIskonto > 0)
                _toplamSatir('Iskonto', -f.toplamIskonto, renk: Colors.red),
              _toplamSatir('KDV', f.toplamKdv),
              const Divider(height: 16),
              _toplamSatir('GENEL TOPLAM', f.genelToplam,
                  bold: true, renk: TsRenk.primaryKoyu),
              if (f.odenenTutar > 0) ...[
                const SizedBox(height: 4),
                _toplamSatir('Odenen', f.odenenTutar, renk: Colors.green),
                _toplamSatir('Kalan', f.kalanTutar,
                    bold: true,
                    renk: f.kalanTutar > 0 ? Colors.red : Colors.green),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 24),

        // Ödeme butonu
        if (f.kalanTutar > 0)
          FilledButton.icon(
            onPressed: _islemDevam ? null : _odemeKaydet,
            icon: const Icon(Icons.payment),
            label: Text('Odeme Kaydet (${ParaUtils.formatla(f.kalanTutar)})'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
      ]),
    );
  }

  Widget _bilgiSatiri(String lbl, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(width: 60,
          child: Text(lbl,
              style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)))),
      Text(val,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _eFaturaDurumChip(String? eDurum) {
    final renk = _durumRengi(eDurum);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: Color.fromARGB(26, renk.red, renk.green, renk.blue),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color.fromARGB(102, renk.red, renk.green, renk.blue))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_durumIkonu(eDurum), size: 13, color: renk),
        const SizedBox(width: 4),
        Text(_durumEtiketi(eDurum),
            style: TextStyle(color: renk, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _durumuChip(String durum) {
    Color renk;
    String etiket;
    switch (durum) {
      case 'odendi':    renk = Colors.green; etiket = 'Odendi'; break;
      case 'kismi':     renk = Colors.orange; etiket = 'Kismi'; break;
      default:          renk = Colors.red; etiket = 'Beklemede';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: Color.fromARGB(26, renk.red, renk.green, renk.blue),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color.fromARGB(102, renk.red, renk.green, renk.blue))),
      child: Text(etiket,
          style: TextStyle(color: renk, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _toplamSatir(String lbl, double val,
      {bool bold = false, Color? renk}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Text(lbl, style: TextStyle(
            fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
        Text(ParaUtils.formatla(val), style: TextStyle(
            fontSize: bold ? 15 : 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: renk)),
      ]),
    );
}

// ── Fatura Önizleme Ekranı ──────────────────────────────────────────────
// "E-Fatura Ön İzleme" — yazdırmadan/göndermeden önce GİB formatındaki
// PDF çıktısının tam ekran önizlemesi.
class _FaturaOnizlemeEkrani extends StatelessWidget {
  final Future<Uint8List> Function() pdfBytes;
  final String faturaNo;
  const _FaturaOnizlemeEkrani({required this.pdfBytes, required this.faturaNo});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.borderColor,
    appBar: TsAppBar(
        baslik: 'e-Fatura Ön İzleme',
      ),
    body: PdfPreview(
      build: (format) => pdfBytes(),
      pdfFileName: 'Fatura_$faturaNo.pdf',
      canChangePageFormat: false,
      canChangeOrientation: false,
      allowPrinting: true,
      allowSharing: true,
      useActions: true,
    ),
  );
}
