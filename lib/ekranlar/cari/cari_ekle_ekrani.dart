import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
// lib/ekranlar/cari/cari_ekle_ekrani.dart
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "../../modeller/cari_model.dart";
import "../../depolar/cari_deposu.dart";
import "../../depolar/cari_adres_deposu.dart";
import "../../servisler/bildirim_servisi.dart";
import '../../tasarim_sistemi/ts_kart.dart';
import '../../cekirdek/utils/vergi_no_dogrulayici.dart';
import '../../modeller/fiyat_grubu_model.dart';
import '../../depolar/toptan_fiyat_deposu.dart';
import '../../widgetlar/ortak/il_ilce_alani.dart';

class CariEkleEkrani extends ConsumerStatefulWidget {
  final CariModel? duzenlenecekCari;
  const CariEkleEkrani({super.key, this.duzenlenecekCari});
  @override
  ConsumerState<CariEkleEkrani> createState() => _CariEkleEkraniState();
}

class _CariEkleEkraniState extends ConsumerState<CariEkleEkrani> {
  final _formKey = GlobalKey<FormState>();
  final CariDeposu _depo = CariDeposu();
  final _adresDepo = CariAdresDeposu();
  bool _kayit = false;
  String _cariTipi = 'Müşteri';

  final _unvanCtrl = TextEditingController();
  final _kodCtrl = TextEditingController();
  final _telefonCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _vergiDairesiCtrl = TextEditingController();
  final _vergiNoCtrl = TextEditingController();
  final _tcCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  final _vadeCtrl = TextEditingController();
  final _notlarCtrl = TextEditingController();
  final _adresCtrl = TextEditingController();
  final _ilCtrl = TextEditingController();
  final _ilceCtrl = TextEditingController();
  final _postaKoduCtrl = TextEditingController();
  bool _aktif = true;
  // Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
  // profesyonel sistem." Bu carinin müşteri tipi ve (varsa) bağlı
  // olduğu fiyat grubu.
  String _musteriTipi = 'Perakende';
  int? _fiyatGrubuId;
  List<FiyatGrubuModel> _fiyatGruplari = [];

  bool get _duzenle => widget.duzenlenecekCari != null;

  @override
  void initState() {
    super.initState();
    _fiyatGruplariYukle();
    if (_duzenle) {
      final c = widget.duzenlenecekCari!;
      _unvanCtrl.text = c.unvan;
      _kodCtrl.text = c.cariKodu ?? '';
      _telefonCtrl.text = c.telefon ?? '';
      _emailCtrl.text = c.email ?? '';
      _vergiDairesiCtrl.text = c.vergiDairesi ?? '';
      _vergiNoCtrl.text = c.vergiNo ?? '';
      _tcCtrl.text = c.tcKimlik ?? '';
      _limitCtrl.text = c.limitTutari.toString();
      _vadeCtrl.text = c.vadeGun.toString();
      _notlarCtrl.text = c.notlar ?? '';
      _cariTipi = c.cariTipi;
      _aktif = c.aktif;
      _musteriTipi = c.musteriTipi;
      _fiyatGrubuId = c.fiyatGrubuId;
      _adresYukle(c.id!);
    } else {
      _limitCtrl.text = '0';
      _vadeCtrl.text = '30';
      // ✅ Yeni kayıtta sonraki cari kodunu otomatik getir
      _otomatikKodGetir();
    }
  }

  Future<void> _fiyatGruplariYukle() async {
    final liste = await ToptanFiyatDeposu().gruplariGetir(sadeceAktif: true);
    if (mounted) setState(() => _fiyatGruplari = liste);
  }

  Future<void> _adresYukle(int cariId) async {
    try {
      final a = await _adresDepo.varsayilanAdresGetir(cariId);
      if (a == null || !mounted) return;
      setState(() {
        _adresCtrl.text     = (a['adres'] as String?) ?? '';
        _ilCtrl.text        = (a['il'] as String?) ?? '';
        _ilceCtrl.text      = (a['ilce'] as String?) ?? '';
        _postaKoduCtrl.text = (a['posta_kodu'] as String?) ?? '';
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Adres yükleme hatası: $e');
    }
  }

  /// cari_adres tablosuna varsayılan adresi ekler/günceller (UPSERT).
  Future<void> _adresKaydet(int cariId) async {
    try {
      await _adresDepo.varsayilanAdresKaydet(
        cariId: cariId,
        adres: _adresCtrl.text.trim(),
        il: _ilCtrl.text.trim(),
        ilce: _ilceCtrl.text.trim(),
        postaKodu: _postaKoduCtrl.text.trim(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Adres kaydetme hatası: $e');
    }
  }

  Future<void> _otomatikKodGetir() async {
    try {  
      final depo = CariDeposu();
      final sonrakiNo = await depo.sonrakiCariNo();
      if (mounted) setState(() => _kodCtrl.text = 'CARIO-$sonrakiNo');
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kayit) return; // 🔴 çift tıklama koruması
    setState(() => _kayit = true);
    try {
      // 🔴🔴 KRİTİK DÜZELTME (aynı hata sınıfı — urun_ekle_ekrani.dart'ta
      // bulunan): Bu ekran DÜZENLEME modunda bile sıfırdan yeni bir
      // CariModel(...) oluşturuyordu. Modeldeki 'bakiye' alanı
      // KOŞULSUZ yazılıyor (toMap()) ve varsayılanı 0 — yani formda
      // hiç YER ALMADIĞI için, bu ekrandan HERHANGİ bir cari
      // düzenlemesi (ör. sadece telefon numarasını değiştirmek),
      // müşterinin/tedarikçinin TÜM BAKİYESİNİ SESSİZCE SIFIRLIYORDU.
      // Artık düzenleme modunda mevcut modelin copyWith()'i kullanılıyor.
      final cari = _duzenle
          ? widget.duzenlenecekCari!.copyWith(
        cariKodu: _kodCtrl.text.trim().isEmpty ? null : _kodCtrl.text.trim(),
        unvan: _unvanCtrl.text.trim(),
        cariTipi: _cariTipi,
        telefon: _telefonCtrl.text.trim().isEmpty ? null : _telefonCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        vergiDairesi: _vergiDairesiCtrl.text.trim().isEmpty ? null : _vergiDairesiCtrl.text.trim(),
        vergiNo: _vergiNoCtrl.text.trim().isEmpty ? null : _vergiNoCtrl.text.trim(),
        tcKimlik: _tcCtrl.text.trim().isEmpty ? null : _tcCtrl.text.trim(),
        limitTutari: ParaUtils.sayiCoz(_limitCtrl.text) ?? 0,
        vadeGun: ParaUtils.tamSayiCoz(_vadeCtrl.text) ?? 0,
        notlar: _notlarCtrl.text.trim().isEmpty ? null : _notlarCtrl.text.trim(),
        aktif: _aktif,
        musteriTipi: _musteriTipi,
        fiyatGrubuId: _musteriTipi == 'Perakende' ? null : _fiyatGrubuId,
      )
          : CariModel(
        unvan: _unvanCtrl.text.trim(),
        cariTipi: _cariTipi,
        cariKodu: _kodCtrl.text.trim().isEmpty ? null : _kodCtrl.text.trim(),
        telefon: _telefonCtrl.text.trim().isEmpty ? null : _telefonCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        vergiDairesi: _vergiDairesiCtrl.text.trim().isEmpty ? null : _vergiDairesiCtrl.text.trim(),
        vergiNo: _vergiNoCtrl.text.trim().isEmpty ? null : _vergiNoCtrl.text.trim(),
        tcKimlik: _tcCtrl.text.trim().isEmpty ? null : _tcCtrl.text.trim(),
        limitTutari: ParaUtils.sayiCoz(_limitCtrl.text) ?? 0,
        vadeGun: ParaUtils.tamSayiCoz(_vadeCtrl.text) ?? 0,
        notlar: _notlarCtrl.text.trim().isEmpty ? null : _notlarCtrl.text.trim(),
        aktif: _aktif,
        musteriTipi: _musteriTipi,
        fiyatGrubuId: _musteriTipi == 'Perakende' ? null : _fiyatGrubuId,
      );
      if (_duzenle) {
        await _depo.guncelle(cari);
        await _adresKaydet(cari.id!);
        if (mounted) BildirimServisi.basari(context, 'Cari güncellendi');
      } else {
        final yeniId = await _depo.ekle(cari);
        await _adresKaydet(yeniId);
        if (mounted) BildirimServisi.basari(context, 'Cari eklendi');
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  
  @override
  void dispose() {
    _unvanCtrl.dispose();
    _kodCtrl.dispose();
    _telefonCtrl.dispose();
    _emailCtrl.dispose();
    _vergiDairesiCtrl.dispose();
    _vergiNoCtrl.dispose();
    _tcCtrl.dispose();
    _limitCtrl.dispose();
    _vadeCtrl.dispose();
    _notlarCtrl.dispose();
    _adresCtrl.dispose();
    _ilCtrl.dispose();
    _ilceCtrl.dispose();
    _postaKoduCtrl.dispose();
    super.dispose();
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(_duzenle ? 'Cari Düzenle' : 'Yeni Cari'),
      ),
      body: TsResponsive.formSarmalayici(context: context, maxGenislik: 720, child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Cari tipi
            const SizedBox(height: 8),
            TsKart(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cari Tipi', style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600, color: context.textSecondary)),
                  const SizedBox(height: 8),
                  // 🔴 DÜZELTME: Önceden sadece 2 seçenekli SegmentedButton
                  // vardı (Müşteri/Tedarikçi) — ama model ve şema üçüncü
                  // bir değeri ("Hem Müşteri Hem Tedarikçi") destekliyor
                  // ve başka ekranlar (tahsilat_odeme_ekrani.dart,
                  // cari_hareket_ekrani.dart) bu değeri kontrol ediyor,
                  // ama UI'dan HİÇBİR ZAMAN seçilemiyordu. 3 uzun etiket
                  // SegmentedButton'da mobilde sıkışacağı için Dropdown'a
                  // çevrildi.
                  DropdownButtonFormField<String>(
                    value: _cariTipi,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'Müşteri', child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.person, size: 18), SizedBox(width: 8), Text('Müşteri'),
                      ])),
                      DropdownMenuItem(value: 'Tedarikçi', child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.local_shipping, size: 18), SizedBox(width: 8), Text('Tedarikçi'),
                      ])),
                      DropdownMenuItem(value: 'Hem Müşteri Hem Tedarikçi', child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.sync_alt, size: 18), SizedBox(width: 8), Text('Hem Müşteri Hem Tedarikçi'),
                      ])),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _cariTipi = v ?? 'Müşteri';
                        // 🔴 DÜZELTME: Saf Tedarikçi'ye geçilince
                        // musteriTipi'yi (Bayi/Toptan gibi) sıfırla —
                        // aksi hâlde bu tedarikçi toptan modülünün
                        // "bayi" listesinde yanlışlıkla görünebilirdi.
                        if (!_cariTipi.contains('Müşteri')) _musteriTipi = 'Perakende';
                      });
                    },
                  ),
                ]),
            ),
            const SizedBox(height: 16),
            _Alan(_unvanCtrl, 'Ünvan / Ad Soyad *', validator: (v) => v!.isEmpty ? 'Zorunlu alan' : null),
            _Alan(_kodCtrl, 'Cari Kodu'),
            _Alan(_telefonCtrl, 'Telefon', klavye: TextInputType.phone),
            _Alan(_emailCtrl, 'E-posta', klavye: TextInputType.emailAddress),
            const Divider(height: 24),
            _Alan(_vergiDairesiCtrl, 'Vergi Dairesi'),
            _Alan(_vergiNoCtrl, 'Vergi No (VKN — 10 hane)',
                klavye: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (v.trim().length != 10) return 'VKN 10 haneli olmalı';
                  return VergiNoDogrulayici.vknGecerliMi(v.trim())
                      ? null : 'Geçersiz VKN — rakamları kontrol edin';
                }),
            _Alan(_tcCtrl, 'TC Kimlik No',
                klavye: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (v.trim().length != 11) return 'TC Kimlik No 11 haneli olmalı';
                  return VergiNoDogrulayici.tcknGecerliMi(v.trim())
                      ? null : 'Geçersiz TC Kimlik No — rakamları kontrol edin';
                }),
            const Divider(height: 24),
            // ── Fatura Adresi (e-Fatura/e-Arşiv için) ─────────────────────────
            Row(children: [
              Icon(Icons.location_on_outlined, size: 16, color: context.textSecondary),
              const SizedBox(width: 6),
              Text('Fatura Adresi', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary)),
            ]),
            const SizedBox(height: 8),
            _Alan(_adresCtrl, 'Adres (Mahalle, Cadde/Sokak, No)', satirSayisi: 2),
            Row(children: [
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IlceAlani(controller: _ilceCtrl, ilController: _ilCtrl),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IlAlani(
                  controller: _ilCtrl,
                  // İl seçilince ilçe alanı o ile göre daralsın diye
                  // yeniden çizim tetikleniyor (IlceAlani her build'de
                  // güncel _ilCtrl.text'i okuyor).
                  onSecildi: (_) => setState(() {}),
                ),
              )),
            ]),
            _Alan(_postaKoduCtrl, 'Posta Kodu', klavye: TextInputType.number),
            const Divider(height: 24),
            _Alan(_limitCtrl, 'Kredi Limiti', klavye: const TextInputType.numberWithOptions(decimal: true)),
            _Alan(_vadeCtrl, 'Vade (gün)', klavye: TextInputType.number),
            const SizedBox(height: 12),
            // Kullanıcı isteği: "toptan satış — Ülker gibi firmaların
            // kullandığı profesyonel sistem." Bu carinin Perakende mi
            // yoksa Bayi/Toptan mı olduğu ve (öyleyse) fiyat grubu.
            // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "toptan
            // bölümde bayi/müşteri/tedarikçi doğru mu"): Bu dropdown
            // ÖNCEDEN cariTipi ne olursa olsun (Müşteri/Tedarikçi fark
            // etmeksizin) HER ZAMAN gösteriliyordu. Bu, saf bir
            // TEDARİKÇİ'ye "Bayi"/"Toptan" musteriTipi atanabilmesine
            // izin veriyordu — ki toptan modülü SADECE musteriTipi'ne
            // bakıp cariTipi'ni HİÇ kontrol etmediği için, bu tedarikçi
            // yanlışlıkla "toptan satış yapılabilecek bayi" listesinde
            // görünebiliyordu (mantıksız: bir tedarikçiye toptan satış
            // yapılmaz, ondan mal ALINIR). Artık bu alan SADECE cari
            // gerçekten müşteri olabiliyorsa (Müşteri veya Hem Müşteri
            // Hem Tedarikçi) gösteriliyor; saf Tedarikçi seçilirse
            // musteriTipi otomatik "Perakende"ye sıfırlanıyor.
            if (_cariTipi.contains('Müşteri')) ...[
              DropdownButtonFormField<String>(
                value: _musteriTipi,
                decoration: const InputDecoration(labelText: 'Müşteri Tipi', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Perakende', child: Text('Perakende')),
                  DropdownMenuItem(value: 'Bayi', child: Text('Bayi')),
                  DropdownMenuItem(value: 'Toptan', child: Text('Toptan')),
                ],
                onChanged: (v) => setState(() => _musteriTipi = v ?? 'Perakende'),
              ),
            ],
            if (_musteriTipi != 'Perakende') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _fiyatGrubuId,
                decoration: const InputDecoration(
                  labelText: 'Fiyat Grubu (opsiyonel)',
                  helperText: 'Seçilmezse bu carinin ürün fiyatları\n'
                      '"Toptan Fiyatı" alanından hesaplanır.',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Seçilmedi —')),
                  ..._fiyatGruplari.map((g) => DropdownMenuItem(value: g.id, child: Text(g.ad))),
                ],
                onChanged: (v) => setState(() => _fiyatGrubuId = v),
              ),
            ],
            const SizedBox(height: 12),
            _Alan(_notlarCtrl, 'Notlar', satirSayisi: 3),
            Row(children: [
              const Text('Aktif'),
              const Spacer(),
              Switch(value: _aktif, onChanged: (v) => setState(() => _aktif = v)),
            ]),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, height: 52, child: FilledButton(
                onPressed: _kayit ? null : _kaydet,
                child: _kayit
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_duzenle ? 'Güncelle' : 'Kaydet', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _Alan(TextEditingController ctrl, String label,
      {String? Function(String?)? validator,
       TextInputType? klavye, int satirSayisi = 1,
       IconData? ikon}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl, keyboardType: klavye,
        maxLines: satirSayisi,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: ikon != null ? Icon(ikon, size: 18) : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.borderColor)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.primary, width: 2)),
        ),
        validator: validator,
      ),
    );
}