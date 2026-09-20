// lib/ekranlar/ayarlar/donem_yonetimi_ekrani.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — Dönem Yönetimi
// ekranı (Madde 3, 2026-09-16, kullanıcı onaylı mimari plan raporu).
//
// Bu ekran, o zamana kadar sadece kod/servis seviyesinde var olan
// DonemDevirServisi'ni (FAZ 1-4) İLK KEZ bir arayüzden tetiklenebilir
// yapar. Madde 3'ün istediği butonlar: [Yıl Sonu Kontrolü] [Yedek Al]
// [Devir Sihirbazını Başlat] [Arşivleri Gör] [Geçmiş Dönemler].
//
// 🔴 DÜRÜSTLÜK NOTU: "Arşivleri Gör" butonu KASITLI olarak devre dışı —
// gerçek arşivleme (Supabase _arsiv tabloları, SQLite ikinci salt-okunur
// bağlantı) henüz kurulmadı. Sahte/boş bir ekran açmak yerine, dokunca
// bunu açıkça söylüyor. "Devir Sihirbazını Başlat" bir tam sihirbaz
// (çok adımlı wizard UI) DEĞİL — şube seçip onaylayan tek bir diyalog;
// DonemDevirServisi'nin ürettiği sonucu (checkpoint + kontrol listesi)
// olduğu gibi gösterir.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/donem_deposu.dart';
import '../../depolar/sube_deposu.dart';
import '../../modeller/donem_model.dart';
import '../../servisler/donem_devir_servisi.dart';
import '../../servisler/veri_sagligi_servisi.dart' show SaglikDurum;
import '../../servisler/yedekleme_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../widgetlar/ortak/onay_dialog.dart';

class DonemYonetimiEkrani extends StatefulWidget {
  const DonemYonetimiEkrani({super.key});

  @override
  State<DonemYonetimiEkrani> createState() => _DonemYonetimiEkraniState();
}

class _DonemYonetimiEkraniState extends State<DonemYonetimiEkrani> {
  final _donemDepo = DonemDeposu();
  final _devirServisi = DonemDevirServisi();

  bool _yukleniyor = true;
  bool _isleniyor = false;
  DonemModel? _aktifDonem;
  List<DonemSubeDurumuModel> _subeDurumlari = [];
  List<DonemModel> _gecmisDonemler = [];
  List<DevirKontrolSonucu>? _sonKontrolSonuclari;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final aktif = await _donemDepo.aktifDonemGetir();
      final tumu = await _donemDepo.tumunuGetir();
      List<DonemSubeDurumuModel> subeDurumlari = [];
      if (aktif?.id != null) {
        subeDurumlari = await _donemDepo.subeDurumlariGetir(aktif!.id!);
      }
      if (!mounted) return;
      setState(() {
        _aktifDonem = aktif;
        _gecmisDonemler = tumu;
        _subeDurumlari = subeDurumlari;
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ilkDonemiAc() async {
    final yil = DateTime.now().year;
    final onay = await OnayDialog.goster(context,
        baslik: '$yil Dönemini Aç',
        icerik: 'Sistemde henüz açık bir dönem yok. $yil yılı için bir '
            'dönem kaydı oluşturulacak. Bu, mevcut satış/stok/cari '
            'verilerinizi ETKİLEMEZ — sadece yıl sonu devir sisteminin '
            'takip edeceği bir dönem kaydıdır.',
        onayYazi: 'Dönemi Aç', ikon: Icons.event_available_outlined);
    if (!onay || !mounted) return;

    setState(() => _isleniyor = true);
    try {
      await _donemDepo.donemOlustur(DonemModel(
        donemYili: yil,
        baslangicTarihi: DateTime(yil, 1, 1),
        bitisTarihi: DateTime(yil, 12, 31, 23, 59, 59),
      ));
      if (mounted) BildirimServisi.basari(context, '$yil dönemi açıldı ✓');
      await _yukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Dönem açılamadı: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  Future<int?> _subeSecDialog() async {
    final subeler = await SubeDeposu().aktifOlanlariGetir();
    if (!mounted) return null;
    if (subeler.isEmpty) {
      BildirimServisi.uyari(context, 'Aktif şube bulunamadı');
      return null;
    }
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hangi Şube?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: subeler.map((s) {
              final id = s['id'] as int;
              final ad = s['sube_adi'] as String? ?? 'Şube $id';
              return ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(ad),
                onTap: () => Navigator.pop(ctx, id),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        ],
      ),
    );
  }

  Future<void> _yilSonuKontrolu() async {
    final subeId = await _subeSecDialog();
    if (subeId == null || !mounted) return;
    setState(() { _isleniyor = true; _sonKontrolSonuclari = null; });
    try {
      final sonuclar = await _devirServisi.kontrolleriCalistir(subeId: subeId);
      if (!mounted) return;
      setState(() => _sonKontrolSonuclari = sonuclar);
      final kritik = sonuclar.where((k) => k.engelliyorMu).length;
      if (kritik > 0) {
        _kritikSorunSnackbariGoster('$kritik kritik sorun bulundu — aşağıda listelendi');
      } else {
        BildirimServisi.basari(context, 'Kontrol tamamlandı, kritik sorun yok ✓');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kontrol başarısız: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  // 🔴 DÜZELTME (Yıl Sonu Devir denetimi, 2026-09-20): devir/kontrol FAZ
  // 1'i, VeriSagligiServisi.tumKontrolleriCalistir()'in TÜM kontrollerini
  // (kasa/banka/cari/stok mutabakatı, DB bütünlüğü vb.) SIFIR TOLERANSLA
  // devralıyor — bu KASITLI ve doğru (rules doc Madde 4: "CRITICAL hata
  // varsa devir başlatılmamalı"). Ancak önceden kullanıcıya sadece bir
  // toast + aşağıda gömülü bir liste gösteriliyordu; hangi ekrana gidip
  // sorunu ÇÖZECEĞİ (Veri Sağlığı Merkezi, çoğu kalemde "Tek Tıkla
  // Düzelt" içerir) belirtilmiyordu. Artık kritik sonuç anında doğrudan
  // /ayarlar/veri-sagligi'ye götüren bir aksiyon butonu sunuluyor.
  void _kritikSorunSnackbariGoster(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(mesaj)),
        ]),
        backgroundColor: const Color(0xFFE63946),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Veri Sağlığına Git',
          textColor: Colors.white,
          onPressed: () => context.push('/ayarlar/veri-sagligi'),
        ),
      ),
    );
  }

  Future<void> _yedekAl() async {
    setState(() => _isleniyor = true);
    try {
      await YedeklemeServisi().yedekAl();
      if (mounted) BildirimServisi.basari(context, 'Yedek alındı ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yedek alınamadı: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  Future<void> _devirSihirbaziniBaslat() async {
    final subeId = await _subeSecDialog();
    if (subeId == null || !mounted) return;

    final onay = await OnayDialog.goster(context,
        baslik: 'Yıl Sonu Devrini Başlat',
        icerik: 'Bu işlem: (1) yıl sonu kontrollerini çalıştırır, (2) tam '
            'bir yedek alır, (3) satış/stok/cari/kasa/banka '
            'hareketlerini bu dönemin arşiv dosyasına KOPYALAR ve '
            'kopyayı doğrular, (4) stok/cari/kasa/banka kapanış '
            'değerlerinin anlık görüntüsünü kaydeder, (5) bu şubenin '
            'dönemini kapatır.\n\n'
            'ÖNEMLİ: Bu sürümde arşivleme SADECE KOPYALAMADIR — mevcut '
            'satış/stok/cari hareketleriniz aktif veritabanında OLDUĞU '
            'GİBİ KALIR, hiçbir şey silinmez veya taşınmaz. Kritik bir '
            'kontrol ya da arşiv doğrulaması başarısız olursa işlem '
            'güvenle durur, hiçbir veri değişmez.',
        onayYazi: 'Devri Başlat', onayRengi: Colors.orange,
        ikon: Icons.warning_amber_rounded);
    if (!onay || !mounted) return;

    setState(() { _isleniyor = true; _sonKontrolSonuclari = null; });
    try {
      final sonuc = await _devirServisi.devirBaslatVeyaDevamEt(subeId: subeId);
      if (!mounted) return;
      setState(() => _sonKontrolSonuclari = sonuc.kontroller);

      if (sonuc.checkpoint.tamamlandiMi) {
        BildirimServisi.basari(context, 'Devir tamamlandı ✓ (${sonuc.checkpoint.devirId})');
      } else if (sonuc.checkpoint.basarisizMi) {
        _kritikSorunSnackbariGoster(
            sonuc.checkpoint.hataMesaji ?? 'Devir başarısız oldu.');
      } else {
        BildirimServisi.uyari(context,
            'Devir kısmen ilerledi (faz ${sonuc.checkpoint.mevcutFaz}/10) — '
            'tekrar başlatınca kaldığı yerden devam eder.');
      }
      await _yukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Devir başlatılamadı: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  void _arsivleriGor() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.construction_outlined, color: Colors.orange),
          SizedBox(width: 8),
          Text('Henüz Mevcut Değil'),
        ]),
        content: const Text(
            'Gerçek arşiv görüntüleme (geçmiş yılların salt-okunur '
            'verilerini incelemek) bu sürümde henüz kurulmadı. Kapanan '
            'dönemlerin kapanış bakiyelerini "Geçmiş Dönemler" '
            'listesinden görebilirsiniz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  void _gecmisDonemDetayGoster(DonemModel donem) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GecmisDonemDetaySayfasi(donem: donem, donemDepo: _donemDepo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Dönem Yönetimi / Yıl Sonu Devir',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Yenile',
              onPressed: _yukleniyor ? null : _yukle),
        ],
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_aktifDonem == null)
                    _AktifDonemYokKarti(isleniyor: _isleniyor, onAc: _ilkDonemiAc)
                  else ...[
                    _AktifDonemKarti(donem: _aktifDonem!, subeDurumlari: _subeDurumlari),
                    const SizedBox(height: 16),
                    _AksiyonButonlari(
                      isleniyor: _isleniyor,
                      onKontrol: _yilSonuKontrolu,
                      onYedek: _yedekAl,
                      onDevir: _devirSihirbaziniBaslat,
                      onArsiv: _arsivleriGor,
                    ),
                  ],
                  if (_sonKontrolSonuclari != null) ...[
                    const SizedBox(height: 20),
                    Text('Son Kontrol Sonuçları',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                            color: context.textPrimary)),
                    const SizedBox(height: 8),
                    for (final k in _sonKontrolSonuclari!) _KontrolSatiri(kontrol: k),
                  ],
                  const SizedBox(height: 20),
                  Text('Geçmiş Dönemler (${_gecmisDonemler.length})',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                          color: context.textPrimary)),
                  const SizedBox(height: 8),
                  if (_gecmisDonemler.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Henüz dönem kaydı yok.',
                          style: TextStyle(color: context.textSecondary)),
                    )
                  else
                    for (final d in _gecmisDonemler)
                      _DonemSatiri(donem: d, onTap: () => _gecmisDonemDetayGoster(d)),
                ],
              ),
            ),
    );
  }
}

class _AktifDonemYokKarti extends StatelessWidget {
  final bool isleniyor;
  final VoidCallback onAc;
  const _AktifDonemYokKarti({required this.isleniyor, required this.onAc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event_busy_outlined, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(child: Text('Açık bir dönem yok',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange.shade900))),
        ]),
        const SizedBox(height: 8),
        Text('Yıl sonu devir sistemini kullanabilmek için önce bir dönem açılmalı.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isleniyor ? null : onAc,
            icon: const Icon(Icons.add),
            label: Text('${DateTime.now().year} Dönemini Aç'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
        ),
      ]),
    );
  }
}

class _AktifDonemKarti extends StatelessWidget {
  final DonemModel donem;
  final List<DonemSubeDurumuModel> subeDurumlari;
  const _AktifDonemKarti({required this.donem, required this.subeDurumlari});

  @override
  Widget build(BuildContext context) {
    final kapanan = subeDurumlari.where((d) => d.durum == DonemDurumu.kapali || d.durum == DonemDurumu.arsivlendi).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [TsRenk.primaryKoyu, TsRenk.primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_today_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Text('${donem.donemYili} Dönemi',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const Spacer(),
          _DurumRozeti(durum: donem.durum),
        ]),
        const SizedBox(height: 12),
        _bilgiSatiri('Başlangıç', _tarihFormat(donem.baslangicTarihi)),
        _bilgiSatiri('Bitiş', _tarihFormat(donem.bitisTarihi)),
        if (donem.kapanisTarihi != null)
          _bilgiSatiri('Kapanış', _tarihFormat(donem.kapanisTarihi!)),
        if (subeDurumlari.isNotEmpty)
          _bilgiSatiri('Şube Durumu', '$kapanan / ${subeDurumlari.length} şube kapandı'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _mikroRozet('Yedek', donem.backupDurumu),
          _mikroRozet('Arşiv', donem.arsivDurumu),
          _mikroRozet('Devir', donem.devirDurumu),
        ]),
      ]),
    );
  }

  Widget _bilgiSatiri(String etiket, String deger) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          SizedBox(width: 90, child: Text(etiket, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Text(deger, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _mikroRozet(String etiket, String durum) {
    final renk = durum == AltDurum.tamamlandi
        ? Colors.greenAccent
        : durum == AltDurum.hatali
            ? Colors.redAccent
            : Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(10)),
      child: Text('$etiket: $durum', style: TextStyle(color: renk, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  String _tarihFormat(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

class _DurumRozeti extends StatelessWidget {
  final String durum;
  const _DurumRozeti({required this.durum});

  @override
  Widget build(BuildContext context) {
    final renk = switch (durum) {
      DonemDurumu.acik => Colors.greenAccent,
      DonemDurumu.kapaniyor => Colors.orangeAccent,
      DonemDurumu.kapali => Colors.white70,
      DonemDurumu.arsivlendi => Colors.blueGrey.shade100,
      _ => Colors.white70,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.white.withAlpha(35), borderRadius: BorderRadius.circular(20)),
      child: Text(durum, style: TextStyle(color: renk, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _AksiyonButonlari extends StatelessWidget {
  final bool isleniyor;
  final VoidCallback onKontrol;
  final VoidCallback onYedek;
  final VoidCallback onDevir;
  final VoidCallback onArsiv;
  const _AksiyonButonlari({
    required this.isleniyor,
    required this.onKontrol,
    required this.onYedek,
    required this.onDevir,
    required this.onArsiv,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isleniyor ? null : onKontrol,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Yıl Sonu Kontrolü'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isleniyor ? null : onYedek,
            icon: const Icon(Icons.backup_outlined, size: 18),
            label: const Text('Yedek Al'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: isleniyor ? null : onDevir,
          icon: isleniyor
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.swap_horiz),
          label: const Text('Devir Sihirbazını Başlat'),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: onArsiv,
          icon: Icon(Icons.archive_outlined, size: 18, color: context.textSecondary),
          label: Text('Arşivleri Gör', style: TextStyle(color: context.textSecondary)),
        ),
      ),
    ]);
  }
}

class _KontrolSatiri extends StatelessWidget {
  final DevirKontrolSonucu kontrol;
  const _KontrolSatiri({required this.kontrol});

  @override
  Widget build(BuildContext context) {
    final renk = switch (kontrol.durum) {
      SaglikDurum.yesil => Colors.green,
      SaglikDurum.sari => Colors.orange,
      SaglikDurum.kirmizi => Colors.red,
    };
    final ikon = switch (kontrol.durum) {
      SaglikDurum.yesil => Icons.check_circle,
      SaglikDurum.sari => Icons.warning_amber_rounded,
      SaglikDurum.kirmizi => Icons.error,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: renk.withAlpha(60)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon, color: renk, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kontrol.baslik, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: context.textPrimary)),
            Text(kontrol.mesaj, style: TextStyle(fontSize: 11, color: context.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}

class _DonemSatiri extends StatelessWidget {
  final DonemModel donem;
  final VoidCallback onTap;
  const _DonemSatiri({required this.donem, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text('${donem.donemYili}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(donem.durum, style: TextStyle(fontSize: 11, color: context.textSecondary)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Madde 3: "Geçmiş dönemler salt okunur açılmalı." Bu sayfa sadece
/// GÖSTERİR — hiçbir düzenleme/silme aksiyonu içermez.
class _GecmisDonemDetaySayfasi extends StatefulWidget {
  final DonemModel donem;
  final DonemDeposu donemDepo;
  const _GecmisDonemDetaySayfasi({required this.donem, required this.donemDepo});

  @override
  State<_GecmisDonemDetaySayfasi> createState() => _GecmisDonemDetaySayfasiState();
}

class _GecmisDonemDetaySayfasiState extends State<_GecmisDonemDetaySayfasi> {
  List<DonemSubeDurumuModel> _subeDurumlari = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (widget.donem.id == null) {
      setState(() => _yukleniyor = false);
      return;
    }
    final liste = await widget.donemDepo.subeDurumlariGetir(widget.donem.id!);
    if (mounted) setState(() { _subeDurumlari = liste; _yukleniyor = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: _yukleniyor
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: scrollController,
                children: [
                  Row(children: [
                    Icon(Icons.lock_outline, size: 18, color: context.textSecondary),
                    const SizedBox(width: 6),
                    Text('${widget.donem.donemYili} — Salt Okunur',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: context.textPrimary)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Genel durum: ${widget.donem.durum}',
                      style: TextStyle(fontSize: 13, color: context.textSecondary)),
                  const Divider(height: 24),
                  Text('Şube Durumları', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
                  const SizedBox(height: 8),
                  if (_subeDurumlari.isEmpty)
                    Text('Bu döneme ait şube kaydı yok.', style: TextStyle(color: context.textSecondary))
                  else
                    for (final s in _subeDurumlari)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(
                            s.durum == DonemDurumu.kapali || s.durum == DonemDurumu.arsivlendi
                                ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 16,
                            color: s.durum == DonemDurumu.kapali || s.durum == DonemDurumu.arsivlendi
                                ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text('Şube #${s.subeId} — ${s.durum}', style: const TextStyle(fontSize: 13)),
                        ]),
                      ),
                ],
              ),
      ),
    );
  }
}
