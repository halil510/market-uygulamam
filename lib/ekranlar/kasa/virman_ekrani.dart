// lib/ekranlar/kasa/virman_ekrani.dart — Hesaplar arası virman
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/kasa_deposu.dart';
import '../../depolar/banka_hesap_deposu.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart';
import '../../modeller/banka_hesap_model.dart';
import '../../modeller/kredi_karti_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/virman_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class VirmanEkrani extends ConsumerStatefulWidget {
  const VirmanEkrani({super.key});
  @override
  ConsumerState<VirmanEkrani> createState() => _VirmanEkraniState();
}

class _VirmanEkraniState extends ConsumerState<VirmanEkrani> {
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  final _depo = KasaDeposu();
  final _virmanServisi = VirmanServisi();
  double _kasaBakiye = 0;
  String _kaynakHesap = 'Kasa';
  String _hedefHesap  = 'Banka';
  bool _islem = false;
  bool _yukleniyor = true;

  // 🔴 DÜZELTME (Madde 11 — Kredi Kartı/Banka Mutabakatı denetimi,
  // 2026-09-16): bu ekran ÖNCEDEN "Banka" veya "Kredi Kartı" taraf
  // olduğunda O TARAFA HİÇ YAZMIYORDU — sadece Kasa tarafı (varsa)
  // kaydediliyordu, diğer taraf sessizce hiçbir yere işlenmiyordu.
  // Kasa↔Banka/Kredi Kartı virmanlarında (en sık kullanılan senaryo)
  // kullanıcıya "✓ virman yapıldı" BAŞARI mesajı gösterilirken banka
  // hesabı/kart limiti GERÇEKTE HİÇ değişmiyordu — para sessizce
  // kayboluyordu. Artık Kasa/Banka/Kredi Kartı arasındaki HER ikili
  // kombinasyon TEK transaction'da, HER İKİ tarafı da güncelleyerek
  // yazılıyor. "Havale/EFT" ve "Diğer" bu uygulamada bakiyesi takip
  // edilen gerçek bir hesap DEĞİL (salt kategori etiketi) — bunlar
  // taraf olduğunda dürüstçe "kısmi kaydedildi" uyarısı gösterilmeye
  // devam ediyor (yanlış bir "hesap" icat edilmedi).
  static const _gercekHesaplar = {'Kasa', 'Banka', 'Kredi Kartı'};
  static const _hesaplar = ['Kasa', 'Banka', 'Kredi Kartı', 'Havale/EFT', 'Diğer'];

  List<BankaHesapModel> _bankaHesaplari = [];
  List<KrediKartiModel> _krediKartlari  = [];
  BankaHesapModel? _seciliBanka;
  KrediKartiModel? _seciliKart;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  Future<void> _verileriYukle() async {
    setState(() => _yukleniyor = true);
    try {
      final bakiye  = await _depo.guncelBakiye();
      final bankalar = await BankaHesapDeposu().tumunuGetir();
      final kartlar  = await KrediKartiDeposu().tumunuGetir();
      if (!mounted) return;
      setState(() {
        _kasaBakiye = bakiye;
        _bankaHesaplari = bankalar;
        _krediKartlari  = kartlar;
        _seciliBanka ??= bankalar.isNotEmpty ? bankalar.first : null;
        _seciliKart  ??= kartlar.isNotEmpty ? kartlar.first : null;
        _yukleniyor = false;
      });
    } catch (_) {
      // sessizce geç — kartlar/eşleri boş gelirse ilgili uyarı zaten
      // gösteriliyor, ekranı bloklamaz
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  bool get _bankaGerekli => _kaynakHesap == 'Banka' || _hedefHesap == 'Banka';
  bool get _kartGerekli  => _kaynakHesap == 'Kredi Kartı' || _hedefHesap == 'Kredi Kartı';

  Future<void> _virmanYap() async {
    final tutar = double.tryParse(_tutarCtrl.text.replaceAll(',', '.')) ?? 0;
    if (tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli tutar girin');
      return;
    }
    if (_kaynakHesap == _hedefHesap) {
      BildirimServisi.uyari(context, 'Kaynak ve hedef farklı olmalı');
      return;
    }
    // 🔴 Derin analizde bulundu: Kasa çıkış tarafındaysa mevcut bakiyeyi
    // aşıp aşmadığı hiç kontrol edilmiyordu — kasayı negatife düşüren bir
    // virman hiçbir uyarı olmadan onaylanabiliyordu.
    if (_kaynakHesap == 'Kasa' && tutar > _kasaBakiye + 0.01) {
      BildirimServisi.uyari(context,
          'Kasa bakiyesi (${ParaUtils.formatla(_kasaBakiye)}) yetersiz');
      return;
    }
    if (_bankaGerekli && _seciliBanka == null) {
      BildirimServisi.uyari(context, 'Bir banka hesabı seçin');
      return;
    }
    if (_kaynakHesap == 'Banka' && _seciliBanka != null &&
        tutar > _seciliBanka!.bakiye + 0.01) {
      BildirimServisi.uyari(context,
          '${_seciliBanka!.hesapAdi} bakiyesi (${ParaUtils.formatla(_seciliBanka!.bakiye)}) yetersiz');
      return;
    }
    if (_kartGerekli && _seciliKart == null) {
      BildirimServisi.uyari(context, 'Bir kredi kartı seçin');
      return;
    }
    if (_kaynakHesap == 'Kredi Kartı' && _seciliKart != null &&
        tutar > _seciliKart!.kalanLimit + 0.01) {
      BildirimServisi.uyari(context,
          '${_seciliKart!.kartAdi} kalan limiti (${ParaUtils.formatla(_seciliKart!.kalanLimit)}) yetersiz');
      return;
    }

    setState(() => _islem = true);
    try {
      final acik = _aciklamaCtrl.text.isEmpty
          ? '$_kaynakHesap → $_hedefHesap Virman'
          : _aciklamaCtrl.text;

      final kasaDahil = _kaynakHesap == 'Kasa' || _hedefHesap == 'Kasa';
      final ikiTarafDaGercek =
          _gercekHesaplar.contains(_kaynakHesap) && _gercekHesaplar.contains(_hedefHesap);

      await _virmanServisi.virmanYap(
        kaynakHesap: _kaynakHesap,
        hedefHesap: _hedefHesap,
        tutar: tutar,
        aciklama: acik,
        seciliBanka: _seciliBanka,
        seciliKart: _seciliKart,
      );

      if (kasaDahil) {
        await _kasaBakiyeYukleTek();
      }
      // ÖNCEDEN Kasa Raporu ekranı (başka bir sekmede/ekranda açıksa)
      // virman sonrası eski veriyi göstermeye devam ederdi. Cari
      // bakiyesinde bulunan AYNI sınıf soruna karşı önlem.
      ref.invalidate(kasaRaporProvider);
      await _verileriYukle();

      _tutarCtrl.clear();
      _aciklamaCtrl.clear();
      if (mounted) {
        if (ikiTarafDaGercek) {
          BildirimServisi.basari(context, '${ParaUtils.formatla(tutar)} virman yapıldı ✓');
        } else if (kasaDahil || _bankaGerekli || _kartGerekli) {
          // Bir taraf gerçek bir hesap (Kasa/Banka/Kredi Kartı), diğeri
          // (Havale/EFT, Diğer) bakiyesi takip edilen bir varlık DEĞİL —
          // sadece gerçek taraf kaydedildi, kullanıcı yanlış bir "tam
          // virman" izlenimine kapılmasın diye açıkça bilgilendiriliyor.
          BildirimServisi.uyari(context,
              '${ParaUtils.formatla(tutar)} tutarındaki hareket sadece '
              '$_kaynakHesap/$_hedefHesap tarafında (gerçek hesabı olan) '
              'kaydedildi. "Havale/EFT" ve "Diğer" bu uygulamada bakiyesi '
              'takip edilen bir hesap değildir.');
        } else {
          BildirimServisi.uyari(context,
              'Bu iki kategori arasında (Havale/EFT, Diğer) bakiyesi '
              'takip edilen bir hesap olmadığından hiçbir yere '
              'kaydedilmedi.');
        }
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Virman yapılamadı: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _kasaBakiyeYukleTek() async {
    try {
      final b = await _depo.guncelBakiye();
      if (mounted) setState(() => _kasaBakiye = b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TsRenk.arkaplan(context),
    appBar: const TsAppBar(baslik: 'Virman', gradyanli: true),
    body: _yukleniyor
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(TsBosluk.lg), children: [
      // Kasa bakiye kartı
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [TsRenk.primaryKoyu, TsRenk.primary]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kasa Bakiyesi', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text(ParaUtils.formatla(_kasaBakiye),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
      const SizedBox(height: TsBosluk.xl),

      // Hesap seçimi
      TsKart(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.hata), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.arrow_upward, color: TsRenk.hata, size: 18)),
            const SizedBox(width: 10),
            Text('Kaynak Hesap', style: TextStyle(fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
            const Spacer(),
            DropdownButton<String>(
              value: _kaynakHesap,
              underline: const SizedBox.shrink(),
              items: _hesaplar.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
              onChanged: (v) => setState(() => _kaynakHesap = v!)),
          ]),
          const SizedBox(height: 8),
          Center(child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TsRenk.ayirac(context), shape: BoxShape.circle),
            child: Icon(Icons.swap_vert, color: TsRenk.metinIkincil(context)))),
          const SizedBox(height: 8),
          Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.basarili), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.arrow_downward, color: TsRenk.basarili, size: 18)),
            const SizedBox(width: 10),
            Text('Hedef Hesap', style: TextStyle(fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
            const Spacer(),
            DropdownButton<String>(
              value: _hedefHesap,
              underline: const SizedBox.shrink(),
              items: _hesaplar.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
              onChanged: (v) => setState(() => _hedefHesap = v!)),
          ]),
        ]),
      ),

      // Banka hesabı seçimi — Kasa/Kredi Kartı seçicileriyle AYNI desen
      // (tahsilat_odeme_ekrani.dart, borc_odeme_bottom_sheet.dart).
      if (_bankaGerekli) ...[
        const SizedBox(height: TsBosluk.md),
        if (_bankaHesaplari.isNotEmpty)
          DropdownButtonFormField<BankaHesapModel>(
            initialValue: _seciliBanka,
            decoration: const InputDecoration(
                labelText: 'Hangi Banka Hesabı?', border: OutlineInputBorder()),
            items: _bankaHesaplari
                .map((h) => DropdownMenuItem(
                    value: h,
                    child: Text('${h.hesapAdi} (${ParaUtils.formatla(h.bakiye)})',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _seciliBanka = v),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.uyari), borderRadius: BorderRadius.circular(10)),
            child: Text('Kayıtlı banka hesabı bulunamadı. Önce Banka Hesapları ekranından bir hesap ekleyin.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
          ),
      ],

      // Kredi kartı seçimi
      if (_kartGerekli) ...[
        const SizedBox(height: TsBosluk.md),
        if (_krediKartlari.isNotEmpty)
          DropdownButtonFormField<KrediKartiModel>(
            initialValue: _seciliKart,
            decoration: const InputDecoration(
                labelText: 'Hangi Kredi Kartı?', border: OutlineInputBorder()),
            items: _krediKartlari
                .map((k) => DropdownMenuItem(
                    value: k,
                    child: Text('${k.kartAdi} (Kalan: ${ParaUtils.formatla(k.kalanLimit)})',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _seciliKart = v),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.uyari), borderRadius: BorderRadius.circular(10)),
            child: Text('Kayıtlı kredi kartı bulunamadı. Önce Kredi Kartları ekranından bir kart ekleyin.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
          ),
      ],

      // "Havale/EFT" veya "Diğer" taraf olduğunda gerçek hesap olmadığını
      // önceden (işlem yapmadan) açıklayan bilgi notu.
      if ((!_gercekHesaplar.contains(_kaynakHesap) || !_gercekHesaplar.contains(_hedefHesap)))
        Padding(
          padding: const EdgeInsets.only(top: TsBosluk.md),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.bilgi), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '"Havale/EFT" ve "Diğer" bu uygulamada bakiyesi takip edilen '
                'bir hesap değildir — sadece Kasa/Banka/Kredi Kartı tarafı '
                '(varsa) kaydedilir.',
                style: TextStyle(fontSize: 11, color: Colors.blue.shade800))),
            ]),
          ),
        ),

      const SizedBox(height: TsBosluk.md),
      TsInput(
        etiket: 'Virman Tutarı (₺)',
        controller: _tutarCtrl,
        oncilIkon: Icons.attach_money,
        klavyeTuru: const TextInputType.numberWithOptions(decimal: true),
      ),
      const SizedBox(height: TsBosluk.sm),
      TsInput(
        etiket: 'Açıklama (İsteğe bağlı)',
        controller: _aciklamaCtrl,
        oncilIkon: Icons.notes_outlined,
      ),
      const SizedBox(height: TsBosluk.xl),
      SizedBox(
        height: 54,
        child: TsButon(
          metin: 'Virmanı Gerçekleştir',
          ikon: Icons.swap_horiz,
          tamGenislik: true,
          yukleniyor: _islem,
          onPressed: _islem ? null : _virmanYap,
        ),
      ),
    ]),
  );
}
