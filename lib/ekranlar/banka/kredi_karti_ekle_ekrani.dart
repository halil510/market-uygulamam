// lib/ekranlar/banka/kredi_karti_ekle_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../modeller/kredi_karti_model.dart';
import '../../modeller/banka_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class KrediKartiEkleEkrani extends ConsumerStatefulWidget {
  final KrediKartiModel? duzenlenecek;
  const KrediKartiEkleEkrani({super.key, this.duzenlenecek});

  @override
  ConsumerState<KrediKartiEkleEkrani> createState() => _KrediKartiEkleEkraniState();
}

class _KrediKartiEkleEkraniState extends ConsumerState<KrediKartiEkleEkrani> {
  final _formKey = GlobalKey<FormState>();
  final _adCtrl = TextEditingController();
  final _noCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  final _faizCtrl = TextEditingController(text: '0');

  BankaModel? _seciliBanka;
  int _taksitSayisi = 1;
  bool _aktif = true;
  bool _kayit = false;
  String _kartTipi = 'Diğer';

  DateTime? _kesimTarihi;
  DateTime? _sonOdemeTarihi;

  static const _kartTipleri = ['Bonus', 'World', 'Axess', 'Maximum', 'Paraf', 'Diğer'];
  static const _taksitSecenekleri = [1, 2, 3, 4, 6, 9, 12];

  @override
  void initState() {
    super.initState();
    if (widget.duzenlenecek != null) {
      _doldurAlanlar(widget.duzenlenecek!);
    }
  }

  void _doldurAlanlar(KrediKartiModel kart) {
    _adCtrl.text = kart.kartAdi;
    _noCtrl.text = kart.kartNoMaskeli;
    _limitCtrl.text = kart.kartLimit.toStringAsFixed(2);
    _faizCtrl.text = kart.faizOrani.toStringAsFixed(2);
    _taksitSayisi = kart.taksitSayisi;
    _aktif = kart.aktif;
    _kartTipi = kart.kartTipi;
    _kesimTarihi = kart.kesimTarihi;
    _sonOdemeTarihi = kart.sonOdemeTarihi;
  }

  void _seciliBankayiAyarla(List<BankaModel> bankalar) {
    if (widget.duzenlenecek != null && _seciliBanka == null && bankalar.isNotEmpty) {
      final banka = bankalar.firstWhere(
        (b) => b.id == widget.duzenlenecek!.bankaId,
        orElse: () => bankalar.first,
      );
      if (banka.id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _seciliBanka = banka);
        });
      }
    }
  }

  @override
  void dispose() {
    _adCtrl.dispose();
    _noCtrl.dispose();
    _limitCtrl.dispose();
    _faizCtrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) {
      BildirimServisi.uyari(context, 'Zorunlu alanları doldurun');
      return;
    }
    if (_seciliBanka == null) {
      BildirimServisi.uyari(context, 'Lütfen bir banka seçin');
      return;
    }

    setState(() => _kayit = true);
    try {
      // 🔴🔴 KRİTİK DÜZELTME (CariModel/UrunModel'de bulunan AYNI hata
      // sınıfı): Düzenleme modunda bile sıfırdan yeni bir
      // KrediKartiModel(...) oluşturuluyordu — 'kullanilan_limit' ve
      // 'kalan_limit' formda hiç yer almadığı için, kartın adını/
      // limitini değiştirmek bile o kartın GÜNCEL KULLANIM TUTARINI
      // sessizce sıfıra düşürüyordu. Artık düzenleme modunda mevcut
      // modelin copyWith()'i kullanılıyor.
      final kart = widget.duzenlenecek != null
          ? widget.duzenlenecek!.copyWith(
        bankaId: _seciliBanka!.id!,
        kartAdi: _adCtrl.text.trim(),
        kartNoMaskeli: KrediKartiModel.maskele(_noCtrl.text.trim()),
        kartTipi: _kartTipi,
        kartLimit: double.tryParse(_limitCtrl.text.replaceAll(',', '.')) ?? 0,
        faizOrani: double.tryParse(_faizCtrl.text.replaceAll(',', '.')) ?? 0,
        taksitSayisi: _taksitSayisi,
        aktif: _aktif,
        kesimTarihi: _kesimTarihi,
        sonOdemeTarihi: _sonOdemeTarihi,
      )
          : KrediKartiModel(
        bankaId: _seciliBanka!.id!,
        kartAdi: _adCtrl.text.trim(),
        kartNoMaskeli: KrediKartiModel.maskele(_noCtrl.text.trim()),
        kartTipi: _kartTipi,
        kartLimit: double.tryParse(_limitCtrl.text.replaceAll(',', '.')) ?? 0,
        faizOrani: double.tryParse(_faizCtrl.text.replaceAll(',', '.')) ?? 0,
        taksitSayisi: _taksitSayisi,
        aktif: _aktif,
        kesimTarihi: _kesimTarihi,
        sonOdemeTarihi: _sonOdemeTarihi,
      );
      if (widget.duzenlenecek == null) {
        await KrediKartiDeposu().ekle(kart);
      } else {
        await KrediKartiDeposu().guncelle(kart);
      }
      if (mounted) {
        ref.invalidate(krediKartlariProvider);
        ref.invalidate(tumKrediKartlariProvider);
        ref.invalidate(krediKartlariToplamProvider);
        ref.invalidate(borcDashboardProvider);
        ref.invalidate(borcOzetProvider);
        BildirimServisi.basari(context, 'Kredi kartı kaydedildi ✓');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  Future<void> _tarihSec({required bool kesim}) async {
    final initialDate = kesim
        ? (_kesimTarihi ?? DateTime.now())
        : (_sonOdemeTarihi ?? DateTime.now().add(const Duration(days: 30)));
    final d = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (d != null) {
      setState(() {
        if (kesim) {
          _kesimTarihi = d;
        } else {
          _sonOdemeTarihi = d;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bankalarAsync = ref.watch(bankalarProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: widget.duzenlenecek == null ? 'Kredi Kartı Ekle' : 'Kredi Kartı Düzenle',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            onPressed: _kayit ? null : _kaydet,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(TsBosluk.lg),
          children: [
            bankalarAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Bankalar yüklenemedi: $err',
                  style: TextStyle(color: TsRenk.hata)),
              data: (bankalar) {
                _seciliBankayiAyarla(bankalar);
                return DropdownButtonFormField<BankaModel>(
                  value: _seciliBanka,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Banka *',
                    prefixIcon: const Icon(Icons.business),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: TsRenk.arkaplan(context),
                  ),
                  items: bankalar.map((b) => DropdownMenuItem(value: b, child: Text(b.ad))).toList(),
                  onChanged: (v) => setState(() => _seciliBanka = v),
                  validator: (v) => v == null ? 'Banka seçin' : null,
                );
              },
            ),
            const SizedBox(height: TsBosluk.md),
            TsInput(etiket: 'Kart Adı *', controller: _adCtrl, oncilIkon: Icons.credit_card,
                dogrula: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null),
            const SizedBox(height: TsBosluk.md),
            TsInput(etiket: 'Kart Numarası *', controller: _noCtrl, oncilIkon: Icons.numbers,
                dogrula: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(children: [
                Icon(Icons.lock_outline, size: 13, color: TsRenk.metinIkincil(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('Güvenlik için sadece son 4 hane kaydedilir, tam numara saklanmaz.',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                ),
              ]),
            ),
            const SizedBox(height: TsBosluk.md),
            TsInput(etiket: 'Limit (TL) *', controller: _limitCtrl, oncilIkon: Icons.attach_money,
                klavyeTuru: const TextInputType.numberWithOptions(decimal: true),
                dogrula: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null),
            const SizedBox(height: TsBosluk.md),
            DropdownButtonFormField<String>(
              value: _kartTipi,
              decoration: InputDecoration(
                labelText: 'Kart Tipi',
                prefixIcon: const Icon(Icons.category),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.arkaplan(context),
              ),
              items: _kartTipleri.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _kartTipi = v!),
            ),
            const SizedBox(height: TsBosluk.md),
            TsInput(etiket: 'Faiz Oranı (%)', controller: _faizCtrl, oncilIkon: Icons.percent,
                klavyeTuru: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: TsBosluk.md),
            DropdownButtonFormField<int>(
              value: _taksitSayisi,
              decoration: InputDecoration(
                labelText: 'Taksit Sayısı',
                prefixIcon: const Icon(Icons.timeline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.arkaplan(context),
              ),
              items: _taksitSecenekleri.map((t) => DropdownMenuItem(value: t, child: Text('$t Taksit'))).toList(),
              onChanged: (v) => setState(() => _taksitSayisi = v!),
            ),
            const SizedBox(height: TsBosluk.md),
            _tarihAlani('Kesim Tarihi', _kesimTarihi, () => _tarihSec(kesim: true)),
            const SizedBox(height: TsBosluk.md),
            _tarihAlani('Son Ödeme Tarihi', _sonOdemeTarihi, () => _tarihSec(kesim: false)),
            const SizedBox(height: TsBosluk.md),
            TsKart(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Text('Aktif', style: TextStyle(fontSize: 14, color: TsRenk.metinBirincil(context))),
                const Spacer(),
                Switch(value: _aktif, onChanged: (v) => setState(() => _aktif = v)),
              ]),
            ),
            const SizedBox(height: TsBosluk.xl),
            SizedBox(
              height: 54,
              child: TsButon(
                metin: 'Kaydet',
                ikon: Icons.save_outlined,
                tamGenislik: true,
                yukleniyor: _kayit,
                onPressed: _kayit ? null : _kaydet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarihAlani(String label, DateTime? deger, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: TsRenk.arkaplan(context),
      ),
      child: Text(deger != null ? _formatTarih(deger) : 'Seçiniz',
          style: TextStyle(color: deger != null ? TsRenk.metinBirincil(context) : TsRenk.metinIkincil(context))),
    ),
  );

  String _formatTarih(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}
