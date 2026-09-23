// lib/ekranlar/masa/qr_menu_ekrani.dart
import 'package:flutter/material.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/services.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/masa/qr_menu_servisi.dart';

class QrMenuEkrani extends StatefulWidget {
  final int masaId;
  final String masaAdi;
  
  const QrMenuEkrani({
    super.key,
    required this.masaId,
    required this.masaAdi,
  });

  @override
  State<QrMenuEkrani> createState() => _QrMenuEkraniState();
}

class _QrMenuEkraniState extends State<QrMenuEkrani> {
  final _urunDepo = UrunDeposu();
  final _servis = QrMenuServisi();
  List<UrunModel> _urunler = [];
  List<String> _kategoriler = [];
  String _seciliKategori = 'Tümü';
  bool _yukleniyor = true;
  bool _gonderiliyor = false;

  final Map<int, _SepetKalem> _sepet = {};
  
  @override
  void initState() {
    super.initState();
    _yukle();
  }
  
  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final urunler = await _urunDepo.tumunuGetir();
      final kategoriler = urunler
          .map((u) => u.anaGrup ?? 'Diğer')
          .toSet()
          .toList()
        ..sort();
      setState(() {
        _urunler = urunler;
        _kategoriler = ['Tümü', ...kategoriler];
        _yukleniyor = false;
      });
    } catch (e) {
      setState(() => _yukleniyor = false);
    }
  }
  
  List<UrunModel> get _filtrelenmis {
    if (_seciliKategori == 'Tümü') return _urunler;
    return _urunler.where((u) => (u.anaGrup ?? 'Diğer') == _seciliKategori).toList();
  }
  
  int get _sepetAdet => _sepet.values.fold(0, (s, k) => s + k.miktar);
  double get _sepetToplam => _sepet.values.fold(0.0, (s, k) => s + (k.urun.satisFiyati * k.miktar));
  
  void _sepeteEkle(UrunModel urun) {
    setState(() {
      if (_sepet.containsKey(urun.id)) {
        _sepet[urun.id]!.miktar++;
      } else {
        _sepet[urun.id!] = _SepetKalem(urun: urun, miktar: 1);
      }
    });
    HapticFeedback.lightImpact();
  }
  
  void _sepettenCikar(int urunId) {
    setState(() {
      if (_sepet.containsKey(urunId)) {
        if (_sepet[urunId]!.miktar <= 1) {
          _sepet.remove(urunId);
        } else {
          _sepet[urunId]!.miktar--;
        }
      }
    });
  }
  
  Future<void> _siparisGonder() async {
    // 🔴 Derin analizde bulundu: çift-tıklama/gönderim koruması yoktu —
    // dialog kapandıktan sonra kullanıcı butona tekrar dokunursa aynı
    // sepet iki kez kaydedilebiliyordu. Ayrıca musteriSiparisKaydet()
    // çağrısının etrafında try/catch yoktu — bir hata (ör. DB kilidi)
    // sessizce yutulur, kullanıcı sepeti boşalmış/başarı mesajı
    // olmadan ekranda asılı kalırdı.
    if (_sepet.isEmpty || _gonderiliyor) return;

    final musteriAdiCtrl = TextEditingController();
    final musteriTelCtrl = TextEditingController();
    final notCtrl = TextEditingController();
    
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Siparişi Onayla'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: musteriAdiCtrl,
            decoration: const InputDecoration(labelText: 'Adınız Soyadınız', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: musteriTelCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Not (Özel istek)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sipariş Gönder'),
          ),
        ],
      ),
    );
    
    if (onay != true) return;

    final kalemler = _sepet.values.map((k) => {
      'urun_id': k.urun.id,
      'urun_adi': k.urun.urunAdi,
      'miktar': k.miktar,
      'birim_fiyat': k.urun.satisFiyati,
      'kdv_oran': double.tryParse(k.urun.kdvOran) ?? 18,
      'not': notCtrl.text.trim(),
    }).toList();

    setState(() => _gonderiliyor = true);
    try {
      await _servis.musteriSiparisKaydet(
        masaId: widget.masaId,
        kalemler: kalemler,
        musteriAdi: musteriAdiCtrl.text.trim(),
        musteriTel: musteriTelCtrl.text.trim(),
        not: notCtrl.text.trim(),
      );

      setState(() => _sepet.clear());

      if (mounted) {
        basariMesaji(context, 'Siparişiniz alındı! Teşekkür ederiz.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) hataMesaji(context, 'Sipariş gönderilemedi: $e');
    } finally {
      if (mounted) setState(() => _gonderiliyor = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🔴 DÜZELTME: sabit #F5F5F5 idi — dosyanın geri kalanı zaten
      // context.cardBg/textSecondary kullanıyordu, bu satır atlanmıştı.
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Masa ${widget.masaAdi} - Menü',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: AppYukleniyor())
          : Column(children: [
              // Kategori çipleri
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: _kategoriler.map((k) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(k),
                      selected: _seciliKategori == k,
                      onSelected: (_) => setState(() => _seciliKategori = k),
                      selectedColor: TsRenk.masaAcik,
                      labelStyle: TextStyle(
                        color: _seciliKategori == k ? Colors.white : context.textSecondary,
                      ),
                    ),
                  )).toList(),
                ),
              ),
              // Ürün grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    // Telefonda 2 kolon; tablet/PC’de sığdığı kadar (sabit 2 idi).
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 1.1,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: _filtrelenmis.length,
                  itemBuilder: (_, i) {
                    final u = _filtrelenmis[i];
                    final sepette = _sepet.containsKey(u.id);
                    final adet = sepette ? _sepet[u.id]!.miktar : 0;
                    return _UrunKartiMusteri(
                      urun: u,
                      sepette: sepette,
                      adet: adet,
                      onEkle: () => _sepeteEkle(u),
                      onCikar: () => _sepettenCikar(u.id!),
                    );
                  },
                ),
              ),
              // Sepet bottom bar
              if (_sepet.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -4))],
                  ),
                  child: SafeArea(
                    child: Row(children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$_sepetAdet ürün', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                        Text(ParaUtils.formatla(_sepetToplam),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      ]),
                      const Spacer(),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _gonderiliyor ? null : _siparisGonder,
                          icon: _gonderiliyor
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send),
                          label: Text(_gonderiliyor ? 'Gönderiliyor...' : 'Sipariş Gönder'),
                          style: FilledButton.styleFrom(
                            backgroundColor: TsRenk.basarili,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

class _SepetKalem {
  final UrunModel urun;
  int miktar;
  _SepetKalem({required this.urun, required this.miktar});
}

class _UrunKartiMusteri extends StatelessWidget {
  final UrunModel urun;
  final bool sepette;
  final int adet;
  final VoidCallback onEkle;
  final VoidCallback onCikar;
  
  const _UrunKartiMusteri({
    required this.urun,
    required this.sepette,
    required this.adet,
    required this.onEkle,
    required this.onCikar,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: sepette ? Border.all(color: TsRenk.masaAcik, width: 2) : null,
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ürün görseli
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [TsRenk.masaAcik.withAlpha(26), TsRenk.masaAcik.withAlpha(13)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Center(
                child: Text(
                  urun.urunAdi.isNotEmpty ? urun.urunAdi[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: TsRenk.masaAcik),
                ),
              ),
            ),
          ),
          // Ürün bilgisi
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(urun.urunAdi,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(ParaUtils.formatla(urun.satisFiyati),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: TsRenk.primaryKoyu)),
                  const Spacer(),
                  if (sepette)
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      GestureDetector(
                        onTap: onCikar,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.remove, size: 14, color: Colors.white),
                        ),
                      ),
                      Text('$adet', style: const TextStyle(fontWeight: FontWeight.w700)),
                      GestureDetector(
                        onTap: onEkle,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                          child: const Icon(Icons.add, size: 14, color: Colors.white),
                        ),
                      ),
                    ])
                  else
                    GestureDetector(
                      onTap: onEkle,
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: TsRenk.masaAcik,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, size: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}