// lib/ekranlar/kullanici/kullanici_ekle_ekrani.dart
// Kullanıcı ekleme + ekran kısıtlama yetki sistemi

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../modeller/kullanici_model.dart';
import '../../cekirdek/utils/sifre_hash.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';

// Tanımlı ekran/işlem yetkileri
class YetkiTanimlari {
  static const Map<String, Map<String, String>> yetkiler = {
    'satis': {'label': 'Hızlı Satış', 'grup': 'Satış'},
    'satis_liste': {'label': 'Satış Listesi', 'grup': 'Satış'},
    'satis_sil': {'label': 'Satış Sil/İptal', 'grup': 'Satış'},
    'satis_iade': {'label': 'İade İşlemi', 'grup': 'Satış'},
    'urun': {'label': 'Ürün Listesi', 'grup': 'Ürün'},
    'urun_ekle': {'label': 'Ürün Ekle/Düzenle', 'grup': 'Ürün'},
    'urun_sil': {'label': 'Ürün Sil', 'grup': 'Ürün'},
    'stok': {'label': 'Stok Listesi', 'grup': 'Stok'},
    'stok_sayim': {'label': 'Stok Sayım', 'grup': 'Stok'},
    'cari': {'label': 'Cari Listesi', 'grup': 'Cari'},
    'cari_ekle': {'label': 'Cari Ekle/Düzenle', 'grup': 'Cari'},
    'cari_hareket': {'label': 'Cari Hareket', 'grup': 'Cari'},
    'cari_hareket_sil': {'label': 'Cari Hareket Sil', 'grup': 'Cari'},
    'promosyon': {'label': 'Promosyon', 'grup': 'Diğer'},
    'fatura': {'label': 'Faturalar', 'grup': 'Diğer'},
    'gider': {'label': 'Gider Yönetimi', 'grup': 'Diğer'},
    'kasa': {'label': 'Kasa', 'grup': 'Diğer'},
    'rapor': {'label': 'Raporlar', 'grup': 'Rapor'},
    'rapor_kar': {'label': 'Kâr/Zarar Raporu', 'grup': 'Rapor'},
    'excel_export': {'label': 'Excel Dışa Aktarma', 'grup': 'Diğer'},
    'ayarlar': {'label': 'Ayarlar', 'grup': 'Sistem'},
    'kullanici': {'label': 'Kullanıcı Yönetimi', 'grup': 'Sistem'},
    'fiyat_degistir': {'label': 'Fiyat Değiştirme', 'grup': 'Ürün'},
    'iskonto_ver': {'label': 'İskonto Verme', 'grup': 'Satış'},
    'tedarik': {'label': 'Tedarik/Alım', 'grup': 'Stok'},
    // 🔴 Derin analizde bulundu: Borç Takip ve Toptan/Bayi modüllerinin
    // rotaları (/borc-*, /toptan/*) uygulama_router.dart'taki
    // _routeYetkiler haritasında HİÇ yoktu — bu kutucuklar
    // tanımlanmadan önce, yetkisi olmayan bir personel bile bu
    // ekranlara deep-link/geri-ileri gezinme ile doğrudan erişebiliyordu.
    'borc_takip': {'label': 'Borç Takip', 'grup': 'Cari'},
    'toptan': {'label': 'Toptan/Bayi Satış', 'grup': 'Satış'},
    // 🔴 Derin denetimde bulundu (P2): /sube, /finans, /onay-merkezi,
    // /risk-merkezi rotalarının hiç yetki kodu yoktu (bkz.
    // uygulama_router.dart._routeYetkiler).
    'sube': {'label': 'Şube Yönetimi', 'grup': 'Sistem'},
    'finans': {'label': 'Finans Merkezi', 'grup': 'Diğer'},
    'onay_merkezi': {'label': 'Onay Merkezi', 'grup': 'Diğer'},
    'risk_merkezi': {'label': 'Risk Merkezi', 'grup': 'Rapor'},
  };

  // Rol bazlı varsayılan yetkiler
  static Set<String> rolVarsayilanlari(String rol) {
    switch (rol) {
      case 'admin':
        return yetkiler.keys.toSet();
      case 'mudur':
        return yetkiler.keys.where((k) => !['kullanici', 'ayarlar'].contains(k)).toSet();
      case 'kasiyer':
        return {'satis', 'satis_liste', 'satis_iade', 'urun', 'cari', 'cari_hareket', 'stok', 'promosyon'};
      case 'personel':
        return {'satis', 'urun', 'cari', 'stok'};
      case 'depocu':
        return {'urun', 'stok', 'stok_sayim', 'tedarik'};
      default:
        return {'satis', 'urun'};
    }
  }
}

class KullaniciEkleEkrani extends ConsumerStatefulWidget {
  final KullaniciModel? duzenlenecek;
  const KullaniciEkleEkrani({super.key, this.duzenlenecek});
  @override
  ConsumerState<KullaniciEkleEkrani> createState() => _KullaniciEkleEkraniState();
}

class _KullaniciEkleEkraniState extends ConsumerState<KullaniciEkleEkrani>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _depo = KullaniciDeposu();
  late final TabController _tab;

  final _adCtrl = TextEditingController();
  final _uAdCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();

  String _rol = 'kasiyer';
  bool _aktif = true;
  bool _sifreGoster = false;
  bool _kayit = false;
  Set<String> _yetkiler = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    if (widget.duzenlenecek != null) {
      _doldur(widget.duzenlenecek!);
      _mevcutYetkileriYukle(widget.duzenlenecek!.id!);
    } else {
      _yetkiler = YetkiTanimlari.rolVarsayilanlari('kasiyer');
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _adCtrl.dispose();
    _uAdCtrl.dispose();
    _sifreCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  void _doldur(KullaniciModel k) {
    _adCtrl.text = k.adSoyad;
    _uAdCtrl.text = k.kullaniciAdi;
    _emailCtrl.text = k.email ?? '';
    _telCtrl.text = k.telefon ?? '';
    _rol = k.rol;
    _aktif = k.aktif;
  }

  // 🔴 KOMPLE DERİN ANALİZ — mimari borç pilot düzeltmesi: bu ekran
  // ÖNCEDEN 'roller_yetki' tablosuna doğrudan `Veritabani().db` ile
  // (SCREEN→DATABASE, depo katmanı atlanarak) erişiyordu. Mantık AYNEN
  // korunarak `KullaniciDeposu.yetkileriniGetir()`/`.yetkileriKaydet()`e
  // taşındı (bkz. o dosyadaki kök neden notu — depodaki eski metod
  // hiç kullanılmıyordu ve senkron bildirimi eksikti, ekranın DOĞRU
  // mantığı artık depoda).
  Future<void> _mevcutYetkileriYukle(int kullaniciId) async {
    try {
      final yetkiler = await _depo.yetkileriniGetir(kullaniciId);
      if (!mounted) return;
      setState(() => _yetkiler = yetkiler);
    } catch (_) {
      if (!mounted) return;
      setState(() => _yetkiler = YetkiTanimlari.rolVarsayilanlari(_rol));
    }
  }

  Future<void> _kaydet() async {
    // Tab 1'e geçerek form validate edilmeli
    _tab.animateTo(0);
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      BildirimServisi.uyari(context, 'Lütfen zorunlu alanları doldurun');
      return;
    }

    // 🔴🔴 GÜVENLİK DÜZELTMESİ (derin analizde bulundu): bu ekrana
    // erişebilen (ör. 'kullanici' yetkisi verilmiş ama admin OLMAYAN
    // bir müdür) HERHANGİ bir kullanıcı, rol açılır menüsünden 'admin'i
    // seçip kendine veya başka birine tam yetki verebiliyordu — hiçbir
    // kontrol yapan kullanıcının KENDİ rolünü aşan bir yetki atamasını
    // engellemiyordu. Artık admin rolü sadece zaten admin olan biri
    // tarafından atanabiliyor.
    if (_rol == 'admin' && !ref.read(authProvider).isAdmin) {
      BildirimServisi.hata(context, 'Sadece admin, başka bir hesaba admin rolü atayabilir');
      return;
    }

    if (!mounted) return;
    setState(() => _kayit = true);
    try {
      int kullaniciId;

      if (widget.duzenlenecek == null) {
        // YENİ KULLANICI
        final yeniTuz = SifreHash.tuzUret();
        final sifreHash = SifreHash.hashleTuzlu(_sifreCtrl.text.trim(), yeniTuz);
        final model = KullaniciModel(
          kullaniciAdi: _uAdCtrl.text.trim(),
          sifreHash: sifreHash,
          tuz: yeniTuz,
          adSoyad: _adCtrl.text.trim(),
          rol: _rol,
          aktif: _aktif,
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          telefon: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        );
        kullaniciId = await _depo.ekle(model);
      } else {
        // KULLANICI GÜNCELLE
        String yeniSifreHash;
        String? yeniTuz;
        if (_sifreCtrl.text.trim().isNotEmpty) {
          yeniTuz = SifreHash.tuzUret();
          yeniSifreHash = SifreHash.hashleTuzlu(_sifreCtrl.text.trim(), yeniTuz);
        } else {
          yeniSifreHash = widget.duzenlenecek!.sifreHash;
          yeniTuz = widget.duzenlenecek!.tuz;
        }

        final model = KullaniciModel(
          id: widget.duzenlenecek!.id,
          kullaniciAdi: _uAdCtrl.text.trim(),
          sifreHash: yeniSifreHash,
          tuz: yeniTuz,
          adSoyad: _adCtrl.text.trim(),
          rol: _rol,
          aktif: _aktif,
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          telefon: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        );
        await _depo.guncelle(model);
        kullaniciId = widget.duzenlenecek!.id!;
      }

      // Yetkileri kaydet
      await _depo.yetkileriKaydet(kullaniciId, _yetkiler);

      if (mounted) {
        BildirimServisi.basari(
          context,
          widget.duzenlenecek == null ? 'Kullanıcı eklendi' : 'Kullanıcı güncellendi',
        );
        Navigator.pop(context, true);
      }
    } on Exception catch (e) {
      if (mounted) {
        final msg = e.toString().contains('UNIQUE') 
            ? 'Bu kullanıcı adı zaten kayıtlı!'
            : 'Kayıt hatası: $e';
        BildirimServisi.hata(context, msg);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gruplar = YetkiTanimlari.yetkiler.values
        .map((v) => v['grup']!)
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(widget.duzenlenecek == null ? 'Kullanıcı Ekle' : 'Kullanıcı Düzenle'),
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            onPressed: _kayit ? null : _kaydet,
            tooltip: 'Kaydet',
          )
        ],
        alt: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Bilgiler'),
            Tab(icon: Icon(Icons.security), text: 'Yetkiler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── TAB 1: Temel Bilgiler ──────────────────────────────────────
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _alan(_adCtrl, 'Ad Soyad *', Icons.person, zorunlu: true),
                const SizedBox(height: TsBosluk.md),
                _alan(_uAdCtrl, 'Kullanıcı Adı *', Icons.account_circle, zorunlu: true),
                const SizedBox(height: TsBosluk.md),
                TextFormField(
                  controller: _sifreCtrl,
                  obscureText: !_sifreGoster,
                  decoration: InputDecoration(
                    labelText: widget.duzenlenecek == null
                        ? 'Şifre *'
                        : 'Yeni Şifre (boş = değiştirme)',
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: Icon(_sifreGoster ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _sifreGoster = !_sifreGoster),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  ),
                  validator: widget.duzenlenecek == null
                      ? (v) => (v == null || v.length < 4) ? 'En az 4 karakter' : null
                      : null,
                ),
                const SizedBox(height: TsBosluk.md),
                _alan(_emailCtrl, 'E-posta', Icons.email),
                const SizedBox(height: TsBosluk.md),
                _alan(_telCtrl, 'Telefon', Icons.phone),
                const SizedBox(height: TsBosluk.lg),
                DropdownButtonFormField<String>(
                  value: _rol,
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    prefixIcon: const Icon(Icons.security),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: TsRenk.arkaplan(context),
                  ),
                  // 🔴 Derin analizde bulundu: 'Admin' seçeneği, ekrana
                  // erişebilen HERKESE (ör. 'kullanici' yetkisi verilmiş
                  // bir müdüre) gösteriliyordu — kaydetme sırasında artık
                  // engelleniyor (bkz. _kaydet()), ama kafa karıştırmamak
                  // için sadece gerçekten admin olana gösteriliyor. Zaten
                  // 'admin' rolündeki bir kullanıcı düzenlenirken (mevcut
                  // _rol=='admin') öge listeden hiç düşürülmez — aksi
                  // halde DropdownButtonFormField'ın value'su listede
                  // bulunamayıp çökerdi.
                  items: [
                    if (ref.watch(authProvider).isAdmin || _rol == 'admin')
                      const DropdownMenuItem(value: 'admin', child: Text('Admin (Tüm Yetkiler)')),
                    const DropdownMenuItem(value: 'mudur', child: Text('Müdür')),
                    const DropdownMenuItem(value: 'kasiyer', child: Text('Kasiyer')),
                    const DropdownMenuItem(value: 'personel', child: Text('Personel')),
                    const DropdownMenuItem(value: 'depocu', child: Text('Depocu')),
                  ],
                  onChanged: (v) => setState(() {
                    _rol = v!;
                    _yetkiler = YetkiTanimlari.rolVarsayilanlari(v);
                  }),
                ),
                const SizedBox(height: TsBosluk.lg),
                TsKart(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Hesap Aktif',
                        style: TextStyle(fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
                    subtitle: Text('Pasif kullanıcılar giriş yapamaz',
                        style: TextStyle(color: TsRenk.metinIkincil(context))),
                    value: _aktif,
                    onChanged: (v) => setState(() => _aktif = v),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),

          // ── TAB 2: Yetki Kısıtlama ──────────────────────────────────────
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TsKart(
                  padding: const EdgeInsets.all(12),
                  vurguRenk: TsRenk.bilgi,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: TsRenk.bilgi, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'İşaretli ekranlar bu kullanıcı için erişilebilir olacak. '
                          'İşaretsiz ekranlara erişim engellenecektir.',
                          style: TextStyle(fontSize: 12, color: TsRenk.bilgi),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        setState(() => _yetkiler = YetkiTanimlari.yetkiler.keys.toSet()),
                    child: const Text('Tümünü Seç'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _yetkiler.clear()),
                    child: const Text('Tümünü Kaldır'),
                  ),
                ],
              ),
              ...gruplar.map((grup) {
                final grupYetkiler = YetkiTanimlari.yetkiler.entries
                    .where((e) => e.value['grup'] == grup)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: TsRenk.primaryKoyu,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            grup,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TsRenk.primaryKoyu,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...grupYetkiler.map((e) => CheckboxListTile(
                      dense: true,
                      title: Text(e.value['label']!, style: const TextStyle(fontSize: 13)),
                      value: _yetkiler.contains(e.key),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() {
                        if (v!) {
                          _yetkiler.add(e.key);
                        } else {
                          _yetkiler.remove(e.key);
                        }
                      }),
                    )),
                  ],
                );
              }),
              const SizedBox(height: 80),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _kayit ? null : _kaydet,
        icon: _kayit
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.save),
        label: const Text('Kaydet'),
      ),
    );
  }

  Widget _alan(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool zorunlu = false,
  }) {
    return TsInput(
      etiket: label,
      controller: ctrl,
      oncilIkon: icon,
      dogrula: zorunlu ? (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null : null,
    );
  }
}