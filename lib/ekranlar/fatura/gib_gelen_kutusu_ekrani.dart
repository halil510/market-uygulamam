// lib/ekranlar/fatura/gib_gelen_kutusu_ekrani.dart
//
// Kullanıcı sorusu: "gelen fatura ve giden fatura listeleme var mı?"
// Bu ekran, BAŞKA e-Fatura mükelleflerinin GİB üzerinden size
// gönderdiği GERÇEK gelen faturaları gösterir (manuel girilen "Alış
// Faturası" kayıtlarından farklı olarak) ve GİB'in yasal olarak
// zorunlu kıldığı "Uygulama Yanıtı" (Kabul/Red) verilmesini sağlar.
import 'package:flutter/material.dart';
import '../../servisler/gib_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class GibGelenKutusuEkrani extends StatefulWidget {
  const GibGelenKutusuEkrani({super.key});

  @override
  State<GibGelenKutusuEkrani> createState() => _GibGelenKutusuEkraniState();
}

class _GibGelenKutusuEkraniState extends State<GibGelenKutusuEkrani> {
  final _gib = GibServisi();
  List<Map<String, dynamic>> _faturalar = [];
  bool _yukleniyor = true;
  String? _hata;
  final Set<String> _yanitlaniyor = {}; // 🔴 çift tıklama koruması (resmi GİB işlemi)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    setState(() { _yukleniyor = true; _hata = null; });
    await _gib.ayarlariYukle();
    if (!_gib.ayarliMi) {
      if (mounted) setState(() {
        _yukleniyor = false;
        _hata = 'GİB entegratör ayarları yapılmamış. Önce Ayarlar > GİB E-Fatura ekranından '
            'API bilgilerinizi girin.';
      });
      return;
    }
    // 🔴 DÜZELTME (GİB Fatura denetimi, 2026-09-20): gelenFaturalariGetir()
    // artık gerçek bir ağ/API hatasında exception fırlatıyor (önceden
    // sessizce [] dönüyordu) — burada yakalanıp _hata alanı dolduruluyor,
    // böylece "gelen fatura yok" ile "sorgu başarısız oldu" ekranda
    // artık AYRIŞIYOR.
    try {
      final liste = await _gib.gelenFaturalariGetir();
      if (!mounted) return;
      setState(() { _faturalar = liste; _yukleniyor = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _yukleniyor = false;
        _hata = 'Gelen kutusu sorgulanamadı: $e';
      });
    }
  }

  Future<void> _yanitla(Map<String, dynamic> fatura, bool kabul) async {
    final uuid = fatura['uuid']?.toString() ?? fatura['UUID']?.toString() ?? '';
    if (uuid.isEmpty) {
      BildirimServisi.hata(context, 'Fatura kimliği (UUID) bulunamadı.');
      return;
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(kabul ? 'Faturayı Kabul Et' : 'Faturayı Reddet'),
        content: Text(kabul
            ? 'Bu faturayı kabul ettiğinizi GİB\'e bildirmek istiyor musunuz? '
              'Bu işlem geri alınamaz.'
            : 'Bu faturayı reddettiğinizi GİB\'e bildirmek istiyor musunuz? '
              'Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kabul ? Colors.green : Colors.red),
            child: Text(kabul ? 'Kabul Et' : 'Reddet'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    if (_yanitlaniyor.contains(uuid)) return; // zaten işleniyor
    setState(() => _yanitlaniyor.add(uuid));

    final basarili = await _gib.uygulamaYanitiGonder(uuid, kabul: kabul);
    if (!mounted) return;
    setState(() => _yanitlaniyor.remove(uuid));
    if (basarili) {
      BildirimServisi.basari(context, kabul ? 'Fatura kabul edildi ✓' : 'Fatura reddedildi');
      _yukle();
    } else {
      BildirimServisi.hata(context, 'Yanıt gönderilemedi — entegratör bağlantınızı kontrol edin.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'GİB Gelen Kutusu',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle),
        ],
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : _hata != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.settings_outlined, size: 56, color: TsRenk.metinIkincil(context)),
                      const SizedBox(height: 16),
                      Text(_hata!, textAlign: TextAlign.center,
                          style: TextStyle(color: TsRenk.metinIkincil(context))),
                    ]),
                  ),
                )
              : _faturalar.isEmpty
                  ? const TsBosDurum(
                      ikon: Icons.inbox_outlined,
                      baslik: 'Gelen fatura yok',
                      altyazi: 'Son 30 gün içinde size gönderilmiş bir e-Fatura bulunamadı',
                    )
                  : RefreshIndicator(
                      onRefresh: _yukle,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(TsBosluk.lg),
                        itemCount: _faturalar.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _gelenFaturaKarti(_faturalar[i]),
                      ),
                    ),
    );
  }

  Widget _gelenFaturaKarti(Map<String, dynamic> f) {
    final gonderen = f['senderName'] ?? f['title'] ?? f['Title'] ?? 'Bilinmeyen Gönderen';
    final faturaNo = f['invoiceNumber'] ?? f['documentNumber'] ?? '-';
    final tutar = f['payableAmount'] ?? f['totalAmount'];
    final tarih = f['issueDate'] ?? f['date'];
    final durum = (f['status'] ?? f['applicationResponse'])?.toString();
    final yanitlanmis = durum == 'accepted' || durum == 'rejected';

    return TsKart(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.purple.withAlpha(26), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.south_west, color: Colors.purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gonderen.toString(),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('Fatura No: $faturaNo',
                style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
          ])),
          if (tutar != null)
            Text('${tutar.toString()} ₺',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        if (tarih != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.calendar_today, size: 12, color: TsRenk.metinIkincil(context)),
            const SizedBox(width: 4),
            Text(tarih.toString(), style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
          ]),
        ],
        const SizedBox(height: 10),
        if (yanitlanmis)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: (durum == 'accepted' ? Colors.green : Colors.red).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              durum == 'accepted' ? '✓ Kabul Edildi' : '✗ Reddedildi',
              textAlign: TextAlign.center,
              style: TsMetin.kucukVurgu.copyWith(color: durum == 'accepted' ? Colors.green.shade700 : Colors.red.shade700),
            ),
          )
        else
          Builder(builder: (context) {
            final uuid = f['uuid']?.toString() ?? f['UUID']?.toString() ?? '';
            final isleniyor = _yanitlaniyor.contains(uuid);
            return Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isleniyor ? null : () => _yanitla(f, false),
                  icon: isleniyor
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.close, size: 16, color: Colors.red),
                  label: const Text('Reddet', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: isleniyor ? null : () => _yanitla(f, true),
                  icon: isleniyor
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Kabul Et'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
            ]);
          }),
      ]),
    );
  }
}
