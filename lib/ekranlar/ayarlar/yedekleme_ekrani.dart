// lib/ekranlar/ayarlar/yedekleme_ekrani.dart
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../servisler/yedekleme_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../depolar/ayarlar_deposu.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';

class YedeklemeEkrani extends ConsumerStatefulWidget {
  const YedeklemeEkrani({super.key});
  @override
  ConsumerState<YedeklemeEkrani> createState() => _YedeklemeEkraniState();
}

class _YedeklemeEkraniState extends ConsumerState<YedeklemeEkrani> {
  final _servis = YedeklemeServisi();
  final _ayarlarDepo = AyarlarDeposu();

  List<YedekBilgi> _yedekler     = [];
  DateTime?        _sonOtomatik;
  bool             _yukleniyor   = true;
  bool             _isleniyor    = false;
  bool             _geriYukleniyor = false;
  String           _sikligi      = 'gunluk';
  String           _klasor       = '';
  String?          _ekKlasor;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final liste = await _servis.yedekListesi();
      final son   = await _servis.sonOtomatikYedekTarihi();
      final sikligi = await _ayarlarDepo.getir('yedek_sikligi') ?? 'gunluk';
      final klasor = await _servis.yedekKlasoru();
      final ek     = await _servis.ekKlasor();
      if (!mounted) return;
      setState(() {
        _yedekler    = liste;
        _sonOtomatik = son;
        _sikligi     = sikligi;
        _klasor      = klasor;
        _ekKlasor    = ek;
        _yukleniyor  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _yedekAl() async {
    if (!mounted) return;
    if (_isleniyor) return;
    setState(() => _isleniyor = true);
    try {
      final yol = await _servis.yedekAl();
      await _yukle();
      if (!mounted) return;
      final ekHata = _servis.sonEkKopyaHatasi;
      if (ekHata != null) {
        BildirimServisi.hata(context, 'Yedek alındı ama $ekHata');
        return;
      }
      BildirimServisi.basari(context,
          _ekKlasor == null ? 'Yedek alındı ✓' : 'Yedek alındı ve ek klasöre kopyalandı ✓');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Yedek Alındı'),
          content: const Text('Yedeği paylaşmak ister misiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hayır')),
            FilledButton.icon(
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Paylaş'),
              onPressed: () { Navigator.pop(ctx); _servis.paylasYedek(yol); },
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yedek alınamadı: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  Future<void> _sikligiFDegistir(String deger) async {
    try {
      await _ayarlarDepo.kaydet('yedek_sikligi', deger);
      if (!mounted) return;
      setState(() => _sikligi = deger);
      BildirimServisi.basari(context, 'Yedek sıklığı kaydedildi');
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _ekKlasorSec() async {
    try {
      final yol = await FilePicker.getDirectoryPath(
          dialogTitle: 'Yedeklerin ayrıca kopyalanacağı klasörü seçin (USB / ikinci disk)');
      if (yol == null) return;
      if (p.equals(yol, _klasor)) {
        if (mounted) {
          BildirimServisi.hata(context, 'Bu zaten varsayılan yedek klasörü — farklı bir klasör seçin');
        }
        return;
      }
      await _servis.ekKlasorKaydet(yol);
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Ek yedek klasörü kaydedildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Klasör seçilemedi: $e');
    }
  }

  Future<void> _ekKlasorKaldir() async {
    await _servis.ekKlasorKaydet(null);
    await _yukle();
  }

  Future<void> _dosyadanGeriYukle() async {
    try {
      final dosya = await FilePicker.pickFile(
        dialogTitle: 'Geri yüklenecek yedek dosyasını seçin (barkopro_....zip)',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (dosya?.path == null) return;
      final yol = dosya!.path!;
      await _geriYukleYol(yol, p.basename(yol));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Dosya seçilemedi: $e');
    }
  }

  Future<void> _geriYukle(YedekBilgi y) => _geriYukleYol(y.yol, '${y.tarihStr} tarihli yedek');

  Future<void> _geriYukleYol(String yol, String etiket) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: TsRenk.uyari), SizedBox(width: 8),
          Text('Geri Yükle'),
        ]),
        content: Text('$etiket geri yüklenecek.\n\nMevcut veriler bu yedekle değiştirilecek '
            '(mevcut halin güvenlik kopyası saklanır). Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: TsRenk.uyari),
            child: const Text('Geri Yükle'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    // 🔴 DEEP_AUDIT_REPORT madde 7 (Reauth kapsamı): yedek geri yükleme
    // TÜM aktif veritabanının üzerine yazan, geri dönüşü zor bir işlem —
    // ama önceden sadece basit bir onay diyaloğu vardı, cari/borç silme
    // gibi yeniden kimlik doğrulama (Madde 15) istemiyordu. Masada
    // bırakılmış açık bir oturumda yanlışlıkla tetiklenirse tüm günün
    // verisi kaybolabilirdi.
    final onaylandi = await yoneticiSifresiIleOnayIste(
      context,
      baslik: 'Yedek Geri Yükleme Onayı',
      aciklama: '$etiket geri yüklenecek — mevcut '
          'TÜM veriler bu yedekle DEĞİŞTİRİLECEK. Devam etmek için '
          'şifrenizi girin.',
    );
    if (!onaylandi || !mounted) return;
    if (!ref.read(authProvider).isMudur) return; // savunma: eylem anında ikinci kez doğrula

    setState(() => _isleniyor = _geriYukleniyor = true);
    try {
      await _servis.yedekiGeriYukle(yol);
    } catch (e) {
      if (mounted) {
        setState(() => _isleniyor = _geriYukleniyor = false);
        BildirimServisi.hata(context, 'Geri yükleme yapılamadı, mevcut veriler değişmedi.\n$e');
      }
      return;
    }
    if (!mounted) return;
    // Açık ekranlar/önbellekler eski veriyi tutuyor; temiz başlangıç şart.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Geri Yükleme Tamamlandı'),
        content: Text(Platform.isWindows
            ? 'Veriler yedekten yüklendi. Uygulama şimdi yeniden başlatılacak.'
            : 'Veriler yedekten yüklendi. Uygulamayı tamamen kapatıp yeniden açın.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Platform.isWindows ? 'Yeniden Başlat' : 'Tamam'),
          ),
        ],
      ),
    );
    if (Platform.isWindows) {
      await Process.start(Platform.resolvedExecutable, const [],
          mode: ProcessStartMode.detached);
      exit(0);
    }
    if (mounted) setState(() => _isleniyor = _geriYukleniyor = false);
  }

  Future<void> _sil(YedekBilgi y) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Yedeği Sil'),
        content: Text(y.dosyaAdi),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: TsRenk.hata),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    try { await File(y.yol).delete(); } catch (e) { /* ignore */ }
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Yedekleme',
        aksiyonlar: [IconButton(icon: const Icon(Icons.refresh), onPressed: _yukle)],
        geriTusu: false,
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : ListView(padding: const EdgeInsets.all(16), children: [

              // Durum + yedek al butonu
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [TsRenk.bilgi, TsRenk.bilgi],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.backup, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Son Otomatik Yedek',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(
                        _sonOtomatik != null
                            ? DateFormat('dd.MM.yyyy HH:mm').format(_sonOtomatik!)
                            : 'Henüz yedek alınmadı',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ])),
                    Column(children: [
                      Text('${_yedekler.length}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const Text('yedek', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isleniyor ? null : _yedekAl,
                      icon: _isleniyor
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: TsRenk.bilgi))
                          : const Icon(Icons.backup),
                      label: Text(_geriYukleniyor
                          ? 'Geri yükleniyor...'
                          : _isleniyor ? 'Yedekleniyor...' : 'Şimdi Yedek Al'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: TsRenk.bilgi,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Sıklık seçimi
              DecoratedBox(
                decoration: BoxDecoration(
                  color: TsRenk.kart(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: TsRenk.ayirac(context)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Otomatik Yedek Sıklığı',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Her gece 23:30\'da kontrol edilir',
                        style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _siklikBtn('gunluk',   'Günlük',   Icons.today)),
                      const SizedBox(width: 10),
                      Expanded(child: _siklikBtn('haftalik', 'Haftalık', Icons.calendar_view_week)),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              _klasorKarti(),
              const SizedBox(height: 16),

              // Yedek listesi
              if (_yedekler.isEmpty)
                Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    Icon(Icons.folder_open, size: 56, color: TsRenk.ayirac(context)),
                    const SizedBox(height: 12),
                    Text('Henüz yedek yok',
                        style: TextStyle(color: TsRenk.metinIkincil(context))),
                  ]),
                ))
              else ...[
                Text('Yedekler (${_yedekler.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                ..._yedekler.map((y) => _yedekKarti(y)),
              ],
            ]),
    );
  }

  Widget _klasorKarti() {
    final ikincil = TsRenk.metinIkincil(context);
    // Ek klasör: dart:io ile doğrudan yazılabilen masaüstü yolları. Android'de
    // seçilen klasör çoğu zaman uygulamaya yazma izni vermez.
    final ekDestekli = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Yedek Klasörü',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          Text('Yedekler her zaman buraya alınır:',
              style: TextStyle(fontSize: 12, color: ikincil)),
          SelectableText(_klasor, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (ekDestekli) ...[
            const SizedBox(height: 12),
            Text('Ek kopya (USB / ikinci disk) — bilgisayar bozulursa yedek orada kalır:',
                style: TextStyle(fontSize: 12, color: ikincil)),
            Text(_ekKlasor ?? 'Seçilmedi',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: _ekKlasor == null ? TsRenk.uyari : null)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _isleniyor ? null : _ekKlasorSec,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: Text(_ekKlasor == null ? 'Ek Klasör Seç' : 'Değiştir'),
              ),
              if (_ekKlasor != null)
                TextButton(
                  onPressed: _isleniyor ? null : _ekKlasorKaldir,
                  child: const Text('Kaldır'),
                ),
            ]),
          ],
          const Divider(height: 24),
          OutlinedButton.icon(
            onPressed: _isleniyor ? null : _dosyadanGeriYukle,
            icon: const Icon(Icons.file_open_outlined, size: 18, color: TsRenk.uyari),
            label: const Text('Dosyadan Geri Yükle (.zip)'),
          ),
        ]),
      ),
    );
  }

  Widget _siklikBtn(String deger, String etiket, IconData ikon) {
    final secili = _sikligi == deger;
    return GestureDetector(
      onTap: () => _sikligiFDegistir(deger),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: secili ? TsRenk.bilgi : TsRenk.arkaplan(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: secili ? TsRenk.bilgi : TsRenk.ayirac(context)),
        ),
        child: Column(children: [
          Icon(ikon, color: secili ? Colors.white : TsRenk.metinIkincil(context), size: 22),
          const SizedBox(height: 4),
          Text(etiket, style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 12,
              color: secili ? Colors.white : TsRenk.metinIkincil(context))),
        ]),
      ),
    );
  }

  Widget _yedekKarti(YedekBilgi y) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TsRenk.ayirac(context)),
    ),
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: y.otomatik ? TsRenk.zemin(TsRenk.basarili) : TsRenk.zemin(TsRenk.bilgi),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          y.otomatik ? Icons.auto_mode : Icons.backup,
          color: y.otomatik ? TsRenk.basarili : TsRenk.bilgi,
          size: 20,
        ),
      ),
      title: Text(y.tarihStr,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Row(children: [
        Text(y.otomatik ? 'Otomatik' : 'Manuel',
            style: TextStyle(fontSize: 11,
                color: y.otomatik ? TsRenk.basarili : TsRenk.bilgi)),
        Text(' • ', style: TextStyle(fontSize: 11, color: context.textSecondary)),
        Text(y.boyutStr, style: TextStyle(fontSize: 11, color: context.textSecondary)),
        if (y.ekKlasorde)
          Text(' • ek klasörde', style: TextStyle(fontSize: 11, color: context.textSecondary)),
      ]),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (v) {
          if (v == 'paylas') _servis.paylasYedek(y.yol);
          if (v == 'geri')   _geriYukle(y);
          if (v == 'sil')    _sil(y);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'paylas', child: Row(children: [
            Icon(Icons.share, size: 18), SizedBox(width: 8), Text('Paylaş')])),
          const PopupMenuItem(value: 'geri', child: Row(children: [
            Icon(Icons.restore, size: 18, color: TsRenk.uyari), SizedBox(width: 8),
            Text('Geri Yükle', style: TextStyle(color: TsRenk.uyari))])),
          const PopupMenuItem(value: 'sil', child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: TsRenk.hata), SizedBox(width: 8),
            Text('Sil', style: TextStyle(color: TsRenk.hata))])),
        ],
      ),
    ),
  );
}
