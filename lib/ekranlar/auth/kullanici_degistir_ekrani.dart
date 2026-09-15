// lib/ekranlar/auth/kullanici_degistir_ekrani.dart
// Modern — ValueNotifier, 0 setState, Riverpod ile giriş

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../depolar/kullanici_deposu.dart';
import '../../modeller/kullanici_model.dart';
import '../../saglayicilar/riverpod/auth_provider.dart'; // DOĞRU import
import '../../servisler/auth_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';

class KullaniciDegistirEkrani extends ConsumerStatefulWidget {
  const KullaniciDegistirEkrani({super.key});

  @override
  ConsumerState<KullaniciDegistirEkrani> createState() => _KullaniciDegistirEkraniState();
}

class _KullaniciDegistirEkraniState extends ConsumerState<KullaniciDegistirEkrani>
    with SingleTickerProviderStateMixin {
  final _depo = KullaniciDeposu();

  // ValueNotifier — sıfır setState
  final _kullanicilar   = ValueNotifier<List<KullaniciModel>>([]);
  final _secili         = ValueNotifier<KullaniciModel?>(null);
  final _pin            = ValueNotifier<String>('');
  final _hata           = ValueNotifier<String>('');
  final _yukleniyor     = ValueNotifier<bool>(true);
  final _girisYapiliyor = ValueNotifier<bool>(false);

  int       _hataliGiris = 0;
  bool      _kilitli     = false;
  DateTime? _kilitBitis;

  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 8)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() {
    _kullanicilar.dispose(); _secili.dispose(); _pin.dispose();
    _hata.dispose(); _yukleniyor.dispose(); _girisYapiliyor.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final liste = await _depo.tumunuGetir();
      if (!mounted) return;
      final mevcutId = AuthServisi().aktifId;
      _kullanicilar.value = liste.where((k) => k.aktif && k.id != mevcutId).toList();
    } catch (e) { /* ignore */ }
    _yukleniyor.value = false;
  }

  void _kullaniciSec(KullaniciModel k) {
    _secili.value    = k;
    _pin.value       = '';
    _hata.value      = '';
    _hataliGiris     = 0;
    _kilitli         = false;
  }

  void _rakamEkle(String r) {
    if (_pin.value.length < 12) _pin.value += r;
  }

  void _silSon() {
    if (_pin.value.isNotEmpty)
      _pin.value = _pin.value.substring(0, _pin.value.length - 1);
  }

  void _temizle() => _pin.value = '';

  Future<void> _girisYap() async {
    if (_secili.value == null || _pin.value.isEmpty) return;

    if (_kilitli && _kilitBitis != null) {
      if (DateTime.now().isBefore(_kilitBitis!)) {
        final kalan = _kilitBitis!.difference(DateTime.now()).inSeconds;
        _hata.value = 'Kilitli — $kalan saniye bekleyin';
        _shakeCtrl.forward(from: 0);
        return;
      }
      _kilitli = false; _hataliGiris = 0; _hata.value = '';
    }

    _girisYapiliyor.value = true;
    _hata.value = '';

    try {
      // Riverpod notifier'ını al
      final notifier = ref.read(authProvider.notifier);
      final sonuc = await notifier.girisYap(_secili.value!.kullaniciAdi, _pin.value);
      if (!mounted) return;

      if (sonuc == GirisSonucu.basarili) {
        AuthServisi().ayarlarDogrulamaTemizle();
        // bildir() kaldırıldı — state otomatik güncellenir
        while (Navigator.canPop(context)) Navigator.pop(context);
        context.go('/');
      } else {
        _hataliGiris++;
        _pin.value = '';
        _shakeCtrl.forward(from: 0);
        const max = UygSabitler.maxHataliGiris;
        if (_hataliGiris >= max) {
          _kilitli   = true;
          _kilitBitis = DateTime.now()
              .add(const Duration(seconds: UygSabitler.kilitSureSaniye));
          _hata.value = '${UygSabitler.kilitSureSaniye} saniye beklemeniz gerekiyor.';
        } else {
          _hata.value = 'Hatalı PIN ($_hataliGiris/$max)';
        }
      }
    } catch (e) {
      if (mounted) _hata.value = 'Hata: $e';
    } finally {
      if (mounted) _girisYapiliyor.value = false;
    }
  }

  Color _rolRenk(String rol) => switch (rol) {
    'admin'    => Colors.red,
    'mudur'    => Colors.purple,
    'kasiyer'  => Colors.blue,
    'depocu'   => Colors.brown,
    _          => context.textSecondary,
  };

  String _rolEtiket(String rol) => switch (rol) {
    'admin'    => 'Yönetici',
    'mudur'    => 'Müdür',
    'kasiyer'  => 'Kasiyer',
    'personel' => 'Personel',
    'depocu'   => 'Depocu',
    _          => rol,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Kullanıcı Değiştir',
        lider: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _yukleniyor,
        builder: (_, yukleniyor, __) {
          if (yukleniyor) return const TsYukleniyor();
          return ValueListenableBuilder<List<KullaniciModel>>(
            valueListenable: _kullanicilar,
            builder: (_, liste, __) {
              if (liste.isEmpty) return _bosEkran();
              return ValueListenableBuilder<KullaniciModel?>(
                valueListenable: _secili,
                builder: (_, secili, __) {
                  if (secili == null) return _kullaniciListesi(liste);
                  return _pinEkrani(secili);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _bosEkran() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.people_outline, size: 64, color: TsRenk.ayirac(context)),
      const SizedBox(height: 16),
      const Text('Başka aktif kullanıcı yok',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Ayarlar → Kullanıcılar bölümünden ekleyin',
          style: TextStyle(fontSize: 13, color: TsRenk.metinIkincil(context)),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _kullaniciListesi(List<KullaniciModel> liste) {
    final mevcut = AuthServisi().aktifKullanici;
    // ÖNCEDEN bu liste tabletlerde TAM GENİŞLİĞE yayılıyordu — kullanıcı
    // kartları aşırı geniş, dağınık görünüyordu. Artık Center +
    // ConstrainedBox ile makul bir genişlikte sınırlanıyor (geniş
    // ekranlarda ortalanıyor, telefon genişliğinde hiçbir fark
    // yaratmıyor).
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SafeArea(
      child: Column(children: [
        // Mevcut kullanıcı banner
        if (mevcut != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Color.fromARGB(20, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Color.fromARGB(51, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue)),
            ),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: Color.fromARGB(38, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
                child: Text(mevcut.adSoyad.isNotEmpty ? mevcut.adSoyad[0] : '?',
                    style: TextStyle(color: AppRenkler.primary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Aktif: ${mevcut.adSoyad}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  Text(_rolEtiket(mevcut.rol),
                      style: TextStyle(fontSize: 12, color: _rolRenk(mevcut.rol))),
                ]),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Geçiş yapılacak kullanıcıyı seçin',
              style: TextStyle(fontSize: 13, color: context.textSecondary)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: liste.length,
            itemBuilder: (_, i) {
              final k = liste[i];
              final renk = _rolRenk(k.rol);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: TsRenk.kart(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: TsRenk.ayirac(context)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: renk.withAlpha(31),
                    child: Text(k.adSoyad.isNotEmpty ? k.adSoyad[0].toUpperCase() : '?',
                        style: TextStyle(color: renk, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(k.adSoyad,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(k.kullaniciAdi,
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: renk.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_rolEtiket(k.rol),
                        style: TextStyle(fontSize: 11, color: renk, fontWeight: FontWeight.w700)),
                  ),
                  onTap: () => _kullaniciSec(k),
                ),
              );
            },
          ),
        ),
      ]),
        ),
      ),
    );
  }

  Widget _pinEkrani(KullaniciModel k) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Seçili kullanıcı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TsRenk.ayirac(context)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _rolRenk(k.rol).withAlpha(31),
                child: Text(k.adSoyad.isNotEmpty ? k.adSoyad[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 20, color: _rolRenk(k.rol),
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.adSoyad,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(_rolEtiket(k.rol),
                    style: TextStyle(fontSize: 12, color: _rolRenk(k.rol))),
              ])),
              TextButton(
                onPressed: () => _secili.value = null,
                child: const Text('Değiştir'),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // PIN dots
          ValueListenableBuilder<String>(
            valueListenable: _pin,
            builder: (_, pin, __) => AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(_shakeAnim.value, 0),
                child: child,
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: _hata,
                builder: (_, hata, __) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: hata.isNotEmpty ? Colors.red.shade50 : TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: hata.isNotEmpty ? Colors.red.shade300 : TsRenk.ayirac(context),
                        width: hata.isNotEmpty ? 1.5 : 1),
                  ),
                  child: pin.isEmpty
                      ? Text('PIN girin', textAlign: TextAlign.center,
                          style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 14))
                      : Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(pin.length, (_) => Container(
                            width: 12, height: 12,
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: const BoxDecoration(
                                color: AppRenkler.primary, shape: BoxShape.circle),
                          ))),
                ),
              ),
            ),
          ),

          // Hata
          ValueListenableBuilder<String>(
            valueListenable: _hata,
            builder: (_, hata, __) {
              if (hata.isEmpty) return const SizedBox(height: 8);
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(hata,
                      style: const TextStyle(fontSize: 12, color: Colors.red))),
                ]),
              );
            },
          ),

          const SizedBox(height: 16),

          // NumPad
          ...([
            ['1','2','3'], ['4','5','6'], ['7','8','9'], ['C','0','⌫']
          ].map((row) => Row(
            children: row.map((t) => Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Material(
                  color: t == 'C' ? Colors.red.shade50
                      : t == '⌫' ? Colors.orange.shade50
                      : TsRenk.arkaplan(context),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (t == '⌫') _silSon();
                      else if (t == 'C') _temizle();
                      else _rakamEkle(t);
                    },
                    child: Container(
                      height: 52, alignment: Alignment.center,
                      child: t == '⌫'
                          ? const Icon(Icons.backspace_outlined, color: Colors.orange, size: 20)
                          : t == 'C'
                              ? const Text('C', style: TextStyle(fontSize: 18,
                                  fontWeight: FontWeight.w700, color: Colors.red))
                              : Text(t, style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            )).toList(),
          ))),

          const SizedBox(height: 16),

          // Giriş Yap
          ValueListenableBuilder<bool>(
            valueListenable: _girisYapiliyor,
            builder: (_, yukleniyor, __) => ValueListenableBuilder<String>(
              valueListenable: _pin,
              builder: (_, pin, __) => SizedBox(width: double.infinity, height: 52, child: FilledButton(
                  onPressed: (yukleniyor || pin.isEmpty) ? null : _girisYap,
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: yukleniyor
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Giriş Yap',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                              color: Colors.white)),
                ),
              ),
            ),
          ),
        ]),
          ),
        ),
      ),
    );
  }
}