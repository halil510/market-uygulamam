// lib/ekranlar/masa/rezervasyon_ekrani.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../modeller/masa_model.dart';
import '../../modeller/rezervasyon_model.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../../servisler/masa/rezervasyon_servisi.dart';
import '../../servisler/bildirim_servisi.dart';

class RezervasyonEkrani extends ConsumerStatefulWidget {
  const RezervasyonEkrani({super.key});

  @override
  ConsumerState<RezervasyonEkrani> createState() => _RezervasyonEkraniState();
}

class _RezervasyonEkraniState extends ConsumerState<RezervasyonEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _rezervasyonServisi = RezervasyonServisi();
  List<RezervasyonModel> _rezervasyonlar = [];
  List<RezervasyonModel> _bekleyenler = [];
  bool _yukleniyor = true;
  DateTime _seciliTarih = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _yukle();
    _periyodikKontrol();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final bekleyenler = await _rezervasyonServisi.bekleyenler();
      final bugunku = await _rezervasyonServisi.tariheGoreGetir(_seciliTarih);
      if (!mounted) return;
      setState(() {
        _bekleyenler = bekleyenler;
        _rezervasyonlar = bugunku;
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _periyodikKontrol() {
    Future.delayed(const Duration(minutes: 1), () {
      // ÖNCEDEN BURADA CİDDİ BİR BELLEK SIZINTISI VARDI: bu fonksiyon
      // kendini sonsuza kadar tekrar çağırıyordu — widget dispose
      // olduktan sonra bile (kullanıcı ekrandan çıksa bile) her dakika
      // arka planda çalışmaya devam ediyordu, uygulama kapatılana kadar
      // asla durmuyordu. Artık `mounted` kontrolü ile widget dispose
      // olduğunda zincir kendiliğinden duruyor.
      if (!mounted) return;
      _yaklasanlariKontrol();
      _periyodikKontrol();
    });
  }

  Future<void> _yaklasanlariKontrol() async {
    final yaklasanlar = await _rezervasyonServisi.yaklasanRezervasyonlar();
    if (yaklasanlar.isNotEmpty && mounted) {
      for (final r in yaklasanlar) {
        if (r.durum == RezervasyonDurum.onaylandi) {
          BildirimServisi.uyari(context,
              '⚠️ ${r.musteriAdi} rezervasyonu 20 dk içinde (Masa ${r.masaAdi})');
        }
      }
    }
  }

  Future<void> _rezervasyonEkle() async {
    final masalar = ref.read(masaListesiProvider).valueOrNull ?? [];
    RezervasyonModel? yeniRezervasyon;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RezervasyonFormSheet(
        masalar: masalar,
        onKaydet: (rez) => yeniRezervasyon = rez,
      ),
    );
    
    if (yeniRezervasyon != null && mounted) {
      await _rezervasyonServisi.ekle(yeniRezervasyon!);
      await _yukle();
      if (mounted) {
        BildirimServisi.basari(context, 'Rezervasyon oluşturuldu');
        // SMS hatırlatma gönder (opsiyonel)
        // await _rezervasyonServisi.hatirlatmaGonder(yeniRezervasyon!);
      }
    }
  }

  Future<void> _durumDegistir(RezervasyonModel r, RezervasyonDurum yeniDurum) async {
    await _rezervasyonServisi.durumGuncelle(r.id!, yeniDurum);
    if (!mounted) return;
    await _yukle();
    if (!mounted) return;
    ref.read(masaListesiProvider.notifier).yukle();
    BildirimServisi.basari(context, 'Durum güncellendi: ${yeniDurum.label}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Rezervasyonlar',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _yukle,
          ),
        ],
        alt: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Bekleyen', icon: Icon(Icons.schedule)),
            Tab(text: 'Takvim', icon: Icon(Icons.calendar_today)),
            Tab(text: 'Tümü', icon: Icon(Icons.list)),
          ],
        ),
        modul: TsModul.masa,
      ),
      body: _yukleniyor
          ? const Center(child: AppYukleniyor())
          : TabBarView(
              controller: _tabController,
              children: [
                _bekleyenTab(),
                _takvimTab(),
                _tumRezervasyonlarTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: TsRenk.masaAcik,
        foregroundColor: Colors.white,
        onPressed: _rezervasyonEkle,
        icon: const Icon(Icons.add),
        label: const Text('Rezervasyon Al'),
      ),
    );
  }

  Widget _bekleyenTab() {
    if (_bekleyenler.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.event_busy, size: 64, color: context.textSecondary),
          SizedBox(height: 12),
          Text('Bekleyen rezervasyon yok', style: TextStyle(color: context.textSecondary)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _bekleyenler.length,
      itemBuilder: (_, i) => _RezervasyonKarti(
        rezervasyon: _bekleyenler[i],
        onDurumDegistir: (d) => _durumDegistir(_bekleyenler[i], d),
      ),
    );
  }

  Widget _takvimTab() {
    return Column(children: [
      // Tarih seçici
      Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _seciliTarih = _seciliTarih.subtract(const Duration(days: 1));
                  _yukle();
                });
              },
            ),
            Text(
              _formatTarih(_seciliTarih),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _seciliTarih = _seciliTarih.add(const Duration(days: 1));
                  _yukle();
                });
              },
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            '${_rezervasyonlar.length} rezervasyon',
            style: TextStyle(fontSize: 13, color: TsRenk.metinIkincil(context)),
          ),
        ]),
      ),
      // Liste
      Expanded(
        child: _rezervasyonlar.isEmpty
            ? const Center(child: Text('Bu tarihte rezervasyon yok'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _rezervasyonlar.length,
                itemBuilder: (_, i) => _RezervasyonKarti(
                  rezervasyon: _rezervasyonlar[i],
                  onDurumDegistir: (d) => _durumDegistir(_rezervasyonlar[i], d),
                ),
              ),
      ),
    ]);
  }

  Widget _tumRezervasyonlarTab() {
    // Tüm rezervasyonlar için API - şimdilik bekleyenler + bugünküler
    final tum = [..._bekleyenler, ..._rezervasyonlar];
    final unique = tum.toSet().toList();
    if (unique.isEmpty) {
      return const Center(child: Text('Rezervasyon bulunamadı'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: unique.length,
      itemBuilder: (_, i) => _RezervasyonKarti(
        rezervasyon: unique[i],
        onDurumDegistir: (d) => _durumDegistir(unique[i], d),
      ),
    );
  }

  String _formatTarih(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Bugün, ${t.day}.${t.month}.${t.year}';
    }
    return '${t.day}.${t.month}.${t.year}';
  }
}

// Rezervasyon Form Sheet
class _RezervasyonFormSheet extends StatefulWidget {
  final List<MasaModel> masalar;
  final Function(RezervasyonModel) onKaydet;

  const _RezervasyonFormSheet({required this.masalar, required this.onKaydet});

  @override
  State<_RezervasyonFormSheet> createState() => _RezervasyonFormSheetState();
}

class _RezervasyonFormSheetState extends State<_RezervasyonFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _musteriAdiCtrl = TextEditingController();
  final _telefonCtrl = TextEditingController();
  final _notCtrl = TextEditingController();
  
  MasaModel? _seciliMasa;
  int _kisiSayisi = 2;
  DateTime _tarih = DateTime.now();
  TimeOfDay _saat = TimeOfDay.now();
  bool _yukleniyor = false;

  @override
  void dispose() {
    _musteriAdiCtrl.dispose();
    _telefonCtrl.dispose();
    _notCtrl.dispose();
    super.dispose();
  }

  Future<void> _tarihSec() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tarih,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (d != null) setState(() => _tarih = d);
  }

  Future<void> _saatSec() async {
    final s = await showTimePicker(
      context: context,
      initialTime: _saat,
    );
    if (s != null) setState(() => _saat = s);
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;
    if (_seciliMasa == null) {
      BildirimServisi.uyari(context, 'Lütfen masa seçin');
      return;
    }

    setState(() => _yukleniyor = true);
    
    final rezervasyon = RezervasyonModel(
      masaId: _seciliMasa!.id!,
      masaAdi: _seciliMasa!.ad,
      musteriAdi: _musteriAdiCtrl.text.trim(),
      telefon: _telefonCtrl.text.trim(),
      kisiSayisi: _kisiSayisi,
      tarih: _tarih,
      saat: DateTime(_tarih.year, _tarih.month, _tarih.day, _saat.hour, _saat.minute),
      not_: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
      durum: RezervasyonDurum.beklemede,
    );
    
    widget.onKaydet(rezervasyon);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: Column(children: [
          // Tutma çubuğu
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: TsRenk.ayirac(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Yeni Rezervasyon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          // Form alanları
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                // Müşteri adı
                TextFormField(
                  controller: _musteriAdiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Müşteri Adı Soyadı *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 12),
                // Telefon
                TextFormField(
                  controller: _telefonCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon *',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 12),
                // Masa seçimi
                DropdownButtonFormField<MasaModel>(
                  value: _seciliMasa,
                  decoration: const InputDecoration(
                    labelText: 'Masa Seç *',
                    prefixIcon: Icon(Icons.table_restaurant),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.masalar.map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('${m.ad} (${m.kapasite} kişi)'),
                  )).toList(),
                  onChanged: (v) => setState(() => _seciliMasa = v),
                  validator: (v) => v == null ? 'Masa seçin' : null,
                ),
                const SizedBox(height: 12),
                // Kişi sayısı
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _kisiSayisi,
                      decoration: const InputDecoration(
                        labelText: 'Kişi Sayısı',
                        prefixIcon: Icon(Icons.people),
                        border: OutlineInputBorder(),
                      ),
                      items: [1,2,3,4,5,6,8,10,12].map((k) => DropdownMenuItem(
                        value: k,
                        child: Text('$k kişi'),
                      )).toList(),
                      onChanged: (v) => setState(() => _kisiSayisi = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _tarihSec,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text('${_tarih.day}/${_tarih.month}'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                // Saat
                OutlinedButton.icon(
                  onPressed: _saatSec,
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text('${_saat.hour.toString().padLeft(2, '0')}:${_saat.minute.toString().padLeft(2, '0')}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),
                // Not
                TextFormField(
                  controller: _notCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Not (isteğe bağlı)',
                    hintText: 'Özel istek, doğum günü vb.',
                    prefixIcon: Icon(Icons.note_add),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
          // Butonlar
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              border: Border(top: BorderSide(color: TsRenk.ayirac(context))),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _yukleniyor ? null : _kaydet,
                  child: _yukleniyor
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Rezervasyon Oluştur'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// Rezervasyon Kartı
class _RezervasyonKarti extends StatelessWidget {
  final RezervasyonModel rezervasyon;
  final Function(RezervasyonDurum) onDurumDegistir;

  const _RezervasyonKarti({required this.rezervasyon, required this.onDurumDegistir});

  @override
  Widget build(BuildContext context) {
    final renk = rezervasyon.durum.renk;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: renk.withAlpha(51)),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Üst satır
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: renk.withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(rezervasyon.durum.ikon, color: renk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rezervasyon.musteriAdi,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text('Masa: ${rezervasyon.masaAdi} • ${rezervasyon.kisiSayisi} kişi',
                  style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: renk.withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(rezervasyon.durum.label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
          ),
        ]),
        const SizedBox(height: 8),
        // Tarih ve saat
        Row(children: [
          Icon(Icons.calendar_today, size: 14, color: TsRenk.metinIkincil(context)),
          const SizedBox(width: 4),
          Text('${_formatTarih(rezervasyon.tarih)}', style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          const SizedBox(width: 16),
          Icon(Icons.access_time, size: 14, color: TsRenk.metinIkincil(context)),
          const SizedBox(width: 4),
          Text('${_formatSaat(rezervasyon.saat)}', style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          const Spacer(),
          if (rezervasyon.telefon.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone, size: 16),
              // 🔴 DÜZELTME (derin analiz — kırık buton): "Ara" tooltip'i
              // gösterip dokununca hiçbir şey olmuyordu (`onPressed: () {}`).
              // Projede zaten kurulu olan url_launcher ile telefon
              // uygulaması açılıyor artık (aynı kalıp urun_ekle_ekrani.dart
              // ve ai_asistan_ayar_ekrani.dart'ta da kullanılıyor).
              onPressed: () async {
                final uri = Uri(scheme: 'tel', path: rezervasyon.telefon);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else if (context.mounted) {
                  BildirimServisi.uyari(context, 'Arama başlatılamadı');
                }
              },
              tooltip: 'Ara',
            ),
        ]),
        if (rezervasyon.not_ != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TsRenk.zemin(TsRenk.uyari),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.note, size: 14, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(child: Text(rezervasyon.not_!, style: TextStyle(fontSize: 11, color: Colors.orange.shade800))),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        // Durum butonları (sadece bekleyen/onaylandı için)
        if (rezervasyon.durum == RezervasyonDurum.beklemede ||
            rezervasyon.durum == RezervasyonDurum.onaylandi)
          Row(children: [
            if (rezervasyon.durum == RezervasyonDurum.beklemede)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onDurumDegistir(RezervasyonDurum.onaylandi),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Onayla'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                ),
              ),
            if (rezervasyon.durum == RezervasyonDurum.beklemede) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onDurumDegistir(RezervasyonDurum.iptal),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('İptal'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
            if (rezervasyon.durum == RezervasyonDurum.onaylandi) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onDurumDegistir(RezervasyonDurum.geldi),
                  icon: const Icon(Icons.login, size: 16),
                  label: const Text('Geldi'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
            ],
          ]),
      ]),
    );
  }

  String _formatTarih(DateTime t) => '${t.day}.${t.month}.${t.year}';
  String _formatSaat(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}