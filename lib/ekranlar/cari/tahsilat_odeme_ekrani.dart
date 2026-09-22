import 'dart:async';
import 'package:flutter/foundation.dart';
import "../../veri/database/veritabani.dart";
import "../../servisler/yazdirma_servisi.dart";
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/ts_kart.dart';
// lib/ekranlar/cari/tahsilat_odeme_ekrani.dart
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "../../modeller/cari_model.dart";
import "../../depolar/cari_deposu.dart";
import "../../depolar/banka_hesap_deposu.dart";
import "../../depolar/kredi_karti_deposu.dart";
import "../../modeller/banka_hesap_model.dart";
import "../../modeller/kredi_karti_model.dart";
import "../../servisler/auth_servisi.dart";
import "../../servisler/bildirim_servisi.dart";
import "../../servisler/cari_tahsilat_odeme_servisi.dart";
import "../../cekirdek/utils/para_utils.dart";

class TahsilatOdemeEkrani extends ConsumerStatefulWidget {
  final int cariId;
  const TahsilatOdemeEkrani({super.key, required this.cariId});
  @override
  ConsumerState<TahsilatOdemeEkrani> createState() =>
      _TahsilatOdemeEkraniState();
}

class _TahsilatOdemeEkraniState extends ConsumerState<TahsilatOdemeEkrani> {
  final CariDeposu _depo = CariDeposu();
  CariModel? _cari;
  bool _yukleniyor = true, _islem = false;
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  String _islemTipi = 'Tahsilat';
  String _odemeTuru = 'Nakit';
  // 🔴 DÜZELTME (kullanıcı bulgusu): "Banka"/"Kredi Kartı" seçilebiliyordu
  // ama HANGİ banka hesabı / HANGİ kart olduğu hiç sorulmuyordu, ve bu
  // seçimler gerçek bir banka/kart hareketi de OLUŞTURMUYORDU — sadece
  // cari bakiyesi değişiyor, şirketin gerçek banka/kart durumu hiç
  // etkilenmiyordu (para "kayboluyordu"). BorcOdemeIslemServisi'ndeki
  // AYNI, doğru çalışan desen buraya da taşındı.
  List<BankaHesapModel> _bankaHesaplari = [];
  List<KrediKartiModel> _krediKartlari = [];
  BankaHesapModel? _secilenHesap;
  KrediKartiModel? _secilenKart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    try {
      final c = await _depo.idileGetir(widget.cariId);
      final hesaplar = await BankaHesapDeposu().tumunuGetir();
      final kartlar = await KrediKartiDeposu().tumunuGetir();
      if (!mounted) return;
      setState(() {
        _cari = c;
        _bankaHesaplari = hesaplar;
        _krediKartlari = kartlar;
        if (hesaplar.isNotEmpty) _secilenHesap = hesaplar.first;
        if (kartlar.isNotEmpty) _secilenKart = kartlar.first;
        _yukleniyor = false;
      });
    } catch (e) {
      // 🔴 DÜZELTME: Hata durumunda _yukleniyor hiç false yapılmıyordu
      // — cari çekilemezse ekran SONSUZA KADAR "yükleniyor" durumunda
      // kalıyordu, kullanıcıya hiçbir geri bildirim/çıkış yolu yoktu.
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) {
        setState(() => _yukleniyor = false);
        BildirimServisi.hata(context, 'Cari bilgisi yüklenemedi: $e');
      }
    }
  }

  Widget _segmentButton() {
    final tedarikci = _cari?.cariTipi == 'Tedarikci';
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
          value: 'Tahsilat',
          label: Text(tedarikci ? 'Ödeme Yaptım' : 'Tahsilat'),
          icon: const Icon(Icons.add_circle_outline),
        ),
        ButtonSegment(
          value: 'Odeme',
          label: Text(tedarikci ? 'Borç Ekle' : 'İade/Ödeme'),
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ],
      selected: {_islemTipi},
      onSelectionChanged: (s) => setState(() => _islemTipi = s.first),
    );
  }

  // 🔴 YENİ: Bu ekran hem müşteri hem tedarikçi için kullanıldığından,
  // "para gerçekten hareket ediyor mu" ve "hangi yönde" ayrı ayrı
  // belirlenmeli:
  //   - Tedarikçi + "Ödeme Yaptım" (Tahsilat)  → PARA ÇIKAR (gerçek ödeme)
  //   - Tedarikçi + "Borç Ekle" (Odeme)        → para hareketi YOK (sadece
  //     veresiye borç kaydı — henüz ödeme yapılmadı)
  //   - Müşteri + "Tahsilat"                   → PARA GİRER
  //   - Müşteri + "İade/Ödeme" (Odeme)         → PARA ÇIKAR (iade)
  bool get _tedarikci => _cari?.cariTipi == 'Tedarikci';

  bool get _paraHareketEdiyor {
    if (_tedarikci && _islemTipi == 'Odeme') return false; // sadece borç kaydı
    return true;
  }

  bool get _paraCikiyor {
    if (_tedarikci && _islemTipi == 'Tahsilat') return true; // Ödeme Yaptım
    if (!_tedarikci && _islemTipi == 'Odeme') return true; // İade/Ödeme
    return false; // müşteri tahsilatı = para girer
  }

  bool get _bankaSecimiGerekli =>
      _paraHareketEdiyor && (_odemeTuru == 'Banka' || _odemeTuru == 'Havale');
  bool get _kartSecimiGerekli =>
      _paraHareketEdiyor && _odemeTuru == 'Kredi Kartı';

  Future<void> _kaydet() async {
    if (_islem) return; // en başta — onay diyaloğu açıkken tekrar tetiklenmesin
    final tutar = ParaUtils.sayiCoz(_tutarCtrl.text);
    if (tutar == null || tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli tutar girin');
      return;
    }
    if (_bankaSecimiGerekli && _secilenHesap == null) {
      BildirimServisi.uyari(context, 'Banka hesabı seçiniz');
      return;
    }
    if (_kartSecimiGerekli && _secilenKart == null) {
      BildirimServisi.uyari(context, 'Kredi kartı seçiniz');
      return;
    }
    // 🔴 YENİ (kullanıcı bulgusu — "yanlış ödeme ve tahsilat
    // girmesin"): Saf bir müşteride "İade/Ödeme" (para ÇIKIŞI) veya
    // saf bir tedarikçide "Ödeme Yaptım" YERİNE aslında "Tahsilat"
    // (para GİRİŞİ, yani tedarikçiden para topladığınızı) kaydetmek
    // her zaman GEÇERSİZ değildir (iade gibi durumlar olabilir) ama
    // GENELDE bir yazım/seçim hatasıdır — bu yüzden tamamen
    // ENGELLEMEK yerine, kullanıcıya AÇIK bir onay soruyoruz.
    final cariTipi = _cari?.cariTipi ?? '';
    final safMusteri = cariTipi == 'Müşteri';
    final safTedarikci = cariTipi == 'Tedarikci' || cariTipi == 'Tedarikçi';
    final olagandisi = (safMusteri && _islemTipi == 'Odeme') ||
        (safTedarikci && _islemTipi == 'Tahsilat');
    if (olagandisi) {
      final devamEt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Emin misiniz?'),
          ]),
          content: Text(safMusteri
              ? 'Bu cari bir MÜŞTERİ. Normalde müşteriden "Tahsilat" yapılır. '
                  'Şimdi ona "Ödeme/İade" kaydetmek üzeresiniz — bu genelde '
                  'bir iade durumudur, yanlışlıkla seçtiyseniz İptal\'e basın.'
              : 'Bu cari bir TEDARİKÇİ. Normalde tedarikçiye "Ödeme" '
                  'yapılır. Şimdi ondan "Tahsilat" kaydetmek üzeresiniz — bu '
                  'genelde bir iade/düzeltme durumudur, yanlışlıkla '
                  'seçtiyseniz İptal\'e basın.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Evet, Devam Et'),
            ),
          ],
        ),
      );
      if (devamEt != true) return;
    }
    setState(() => _islem = true);
    try {
      final kasiyer = AuthServisi().aktifAd;

      // ══════════════════════════════════════════════════════════════════
      // 🆕 MAKBUZ İÇİN: bakiyeyi işlemden ÖNCE yakala.
      // hareketEkle() bakiyeyi yeniden hesaplayıp güncelliyor; sonradan
      // okursak "eski bakiye"yi kaybederiz.
      // ══════════════════════════════════════════════════════════════════
      final oncekiBakiye = _cari?.bakiye ?? 0;

      // 🆕 Makbuz no artık YAZDIRMADAN ÖNCE değil, KAYITTAN ÖNCE üretilip
      // cari_hareket.fis_no'ya yazılıyor — Cari Detay'dan sonradan
      // "tekrar yazdır" denildiğinde orijinal makbuz numarası kurtarılabilsin
      // diye (kullanıcı isteği 2026-09-22). "Borç Ekle" (paraHareketEdiyor
      // false) için makbuz üretilmiyor — zaten hiç basılmıyor.
      final makbuzNo = _paraHareketEdiyor
          ? await Veritabani()
              .fisNoUret(_islemTipi == 'Tahsilat' ? 'tahsilat' : 'tediye')
          : null;

      // Cari hareket + (varsa) gerçek para hareketi (kasa/banka/kredi
      // kartı) artık CariTahsilatOdemeServisi'nde TEK bir db.transaction()
      // içinde atomik olarak yürütülüyor — bkz. o servisin doc yorumu,
      // davranış birebir korundu.
      await CariTahsilatOdemeServisi().kaydet(
        cariId: widget.cariId,
        cariUnvan: _cari?.unvan ?? 'Cari',
        islemTipi: _islemTipi,
        tutar: tutar,
        odemeTuru: _odemeTuru,
        kullanici: kasiyer,
        paraHareketEdiyor: _paraHareketEdiyor,
        paraCikiyor: _paraCikiyor,
        aciklama: _aciklamaCtrl.text,
        bankaHesapId: _secilenHesap?.id,
        krediKartiId: _secilenKart?.id,
        fisNo: makbuzNo,
      );
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah —
      // "kaydet dediğimde çok uzun dönüp duruyor"): para hareketi zaten
      // yukarıda GERÇEKTEN veritabanına yazıldı — ekranın kapanması BUNA
      // bağlı olmalı, fiziksel yazıcının Bluetooth/WiFi/USB üzerinden
      // yanıt vermesine DEĞİL. Yazıcı bağlı/açık değilse makbuzYazdir()
      // içindeki bağlantı denemeleri (her biri 6-12sn timeout, kopya
      // sayısı kadar tekrar) "Kaydet" düğmesini onlarca saniye kilitli
      // tutuyordu. Artık kayıt biter bitmez ekran hemen kapanıyor,
      // yazdırma ARKA PLANDA (beklemeden) tetikleniyor — hata olursa
      // (madde 2'de eklenen) Cari Detay'daki yazdır ikonuyla tekrar
      // basılabilir, kullanıcıyı burada bekletmenin bir faydası yok.
      if (_paraHareketEdiyor) {
        unawaited(() async {
          try {
            final guncelCari = await _depo.idileGetir(widget.cariId);
            await YazdirmaServisi().makbuzYazdir(
              makbuzNo: makbuzNo!,
              tarih: DateTime.now(),
              cariUnvan: _cari?.unvan ?? 'Cari',
              tutar: tutar,
              odemeTuru: _odemeTuru,
              islemTipi: _islemTipi,
              aciklama: _aciklamaCtrl.text.trim().isEmpty
                  ? null
                  : _aciklamaCtrl.text.trim(),
              kesenKisi: kasiyer,
              oncekiBakiye: oncekiBakiye,
              sonBakiye: guncelCari?.bakiye,
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Makbuz arka plan yazdırma hatası: $e');
            }
          }
        }());
      }

      if (mounted) {
        // ÖNCEDEN BURADA hiçbir provider geçersiz kılınmıyordu — ekran
        // sadece geri dönüyordu, ama Cari Detay/Liste ekranları hâlâ
        // ÖNBELLEĞE ALINMIŞ (eski) bakiyeyi gösteriyordu. Kullanıcının
        // "tahsilat/ödeme yaptığımda bakiyeler hemen yenilenmiyor,
        // çıkıp tekrar girmem gerekiyor" şikayeti tam olarak buydu.
        // cari_detay_ekrani.dart'ın KENDİSİ başka yerlerde zaten bu
        // deseni kullanıyor — aynısı burada da uygulanıyor.
        ref.invalidate(cariDetayProvider(widget.cariId));
        ref.read(carilerProvider.notifier).yukle();
        BildirimServisi.basari(context, '$_islemTipi kaydedildi');
        context.pop();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor)
      return Scaffold(
          backgroundColor: context.scaffoldBg, body: const AppYukleniyor());
    if (_cari == null)
      return Scaffold(
          appBar: TsAppBar(
            gradyanli: false,
          ),
          body:
              const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Bulunamadı'));
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: '${_cari!.unvan} - Tahsilat/Ödeme',
        gradyanli: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TsKart(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bakiye:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(ParaUtils.formatla(_cari!.bakiye.abs()),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _cari!.bakiye > 0 ? Colors.red : Colors.green)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _segmentButton(),
          const SizedBox(height: 16),
          TextField(
            controller: _tutarCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
                labelText: 'Tutar',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _odemeTuru,
            decoration: const InputDecoration(
                labelText: 'Ödeme Şekli', border: OutlineInputBorder()),
            items: ['Nakit', 'Banka', 'Kredi Kartı', 'Çek', 'Havale']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _odemeTuru = v!),
          ),
          const SizedBox(height: 12),
          if (_bankaSecimiGerekli) ...[
            if (_bankaHesaplari.isNotEmpty)
              DropdownButtonFormField<BankaHesapModel>(
                value: _secilenHesap,
                decoration: const InputDecoration(
                    labelText: 'Hangi Hesaptan?', border: OutlineInputBorder()),
                items: _bankaHesaplari
                    .map((h) => DropdownMenuItem(
                        value: h,
                        child:
                            Text(h.hesapAdi, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _secilenHesap = v),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: TsRenk.zemin(TsRenk.uyari),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    'Banka hesabı bulunamadı. Önce bir hesap ekleyin veya "Nakit" seçin.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade800)),
              ),
            const SizedBox(height: 12),
          ],
          if (_kartSecimiGerekli) ...[
            if (_krediKartlari.isNotEmpty)
              DropdownButtonFormField<KrediKartiModel>(
                value: _secilenKart,
                decoration: const InputDecoration(
                    labelText: 'Hangi Kart?', border: OutlineInputBorder()),
                items: _krediKartlari
                    .map((k) => DropdownMenuItem(
                        value: k,
                        child:
                            Text(k.kartAdi, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _secilenKart = v),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: TsRenk.zemin(TsRenk.uyari),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    'Kredi kartı bulunamadı. Önce bir kart ekleyin veya başka yöntem seçin.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade800)),
              ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _aciklamaCtrl,
            decoration: const InputDecoration(
                labelText: 'Açıklama (opsiyonel)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _islem ? null : _kaydet,
              child: _islem
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('$_islemTipi Kaydet',
                      style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
