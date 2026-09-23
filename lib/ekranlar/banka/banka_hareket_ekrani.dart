// lib/ekranlar/banka/banka_hareket_ekrani.dart
// HESAP DETAYI + HAREKET LİSTESİ (Tek Ekran)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../modeller/banka_hesap_model.dart';
import '../../modeller/banka_hareket_model.dart';
import '../../depolar/banka_hesap_deposu.dart';
import '../../depolar/banka_hareket_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class BankaHareketEkrani extends ConsumerStatefulWidget {
  final int? hesapId;
  final int? krediKartiId;

  const BankaHareketEkrani({
    super.key,
    this.hesapId,
    this.krediKartiId,
  });

  @override
  ConsumerState<BankaHareketEkrani> createState() =>
      _BankaHareketEkraniState();
}

class _BankaHareketEkraniState extends ConsumerState<BankaHareketEkrani> {
  final _hesapDepo = BankaHesapDeposu();
  final _hareketDepo = BankaHareketDeposu();

  BankaHesapModel? _hesap;
  List<BankaHareketModel> _hareketler = [];
  bool _yukleniyor = true;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (widget.hesapId == null && widget.krediKartiId == null) {
      setState(() {
        _hata = 'Hesap veya Kredi Kartı ID gerekli';
        _yukleniyor = false;
      });
      return;
    }

    setState(() => _yukleniyor = true);
    try {
      // 1. Hesap bilgilerini al (sadece hesapId varsa)
      BankaHesapModel? hesap;
      if (widget.hesapId != null) {
        hesap = await _hesapDepo.idileGetir(widget.hesapId!);
      }

      // 2. Hareketleri al
      final hareketler = await _hareketDepo.hareketleriGetir(
        hesapId: widget.hesapId,
        krediKartiId: widget.krediKartiId,
        limit: 100,
      );

      if (mounted) {
        setState(() {
          _hesap = hesap;
          _hareketler = hareketler;
          _yukleniyor = false;
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
          _hata = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Scaffold(
        body: TsYukleniyor(),
      );
    }

    if (_hata != null) {
      return Scaffold(
        appBar: TsAppBar(
        baslik: 'Hata',
        gradyanli: false,
      ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 12),
              Text('Hata: $_hata', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _yukle,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(
          _hesap != null ? _hesap!.hesapAdi : 'Hareketler',
          style: const TextStyle(fontSize: 15),
        ),
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _yukle,
            tooltip: 'Yenile',
          ),
          // Kredi kartı ise hareket ekleme butonu gösterilmez (manuel)
          if (widget.hesapId != null)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: _hareketEkleDialog,
              tooltip: 'Hareket Ekle',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _yukle,
        child: Column(
          children: [
            // ---- HESAP ÖZET KARTI (Varsa) ----
            if (_hesap != null) _hesapOzetKarti(_hesap!),

            // ---- HAREKET LİSTESİ BAŞLIĞI ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Text(
                    'Hareketler',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '${_hareketler.length} kayıt',
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)),
                  ),
                ],
              ),
            ),

            // ---- LİSTE ----
            Expanded(
              child: _hareketler.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_outlined, size: 64, color: context.textSecondary),
                          SizedBox(height: 12),
                          Text('Henüz hareket yok', style: TextStyle(color: context.textSecondary)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _hareketler.length,
                      separatorBuilder: (_, __) => const Divider(height: 4),
                      itemBuilder: (_, i) => _hareketKarti(_hareketler[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- HESAP ÖZET KARTI ----
  Widget _hesapOzetKarti(BankaHesapModel h) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppRenkler.primary, AppRenkler.primary.withAlpha(179)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4C4361EE),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  h.hesapAdi,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(51),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  h.paraBirimi,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ozetKalem('Bakiye', ParaUtils.formatla(h.bakiye),
                  h.bakiye >= 0 ? Colors.greenAccent : Colors.redAccent),
              _ozetKalem('Kullanılabilir', ParaUtils.formatla(h.kullanilabilirBakiye),
                  Colors.white70),
              _ozetKalem('Hesap No', h.hesapNo, Colors.white70),
            ],
          ),
          if (h.iban != null) ...[
            const SizedBox(height: 4),
            Text(
              'IBAN: ${h.iban}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _ozetKalem(String label, String deger, Color renk) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white54, fontSize: 10)),
        Text(
          deger,
          style: TextStyle(
            color: renk,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ---- HAREKET KARTI ----
  Widget _hareketKarti(BankaHareketModel hareket) {
    // ÖNCEDEN BURADA CİDDİ BİR GÖRÜNTÜLEME HATASI VARDI: yön (giriş/çıkış)
    // `hareket.tutar > 0` kontrolüyle belirleniyordu — ama tutar HER ZAMAN
    // pozitif kaydediliyor (bkz. banka_hareket_deposu.dart: bakiye hesabı
    // `islemTipi`'ne göre yapılıyor, tutar sadece büyüklüğü tutuyor). Bu
    // yüzden her işlem, gerçekte "Giden" (para çıkışı) olsa bile ekranda
    // hep "Gelen" (yeşil, aşağı ok) gibi görünüyordu. Artık gerçek
    // işlem tipine bakılıyor.
    final giris = hareket.islemTipi == 'Gelen';
    final renk = giris ? Colors.green : Colors.red;
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TsRenk.arkaplan(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: renk.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              giris ? Icons.arrow_downward : Icons.arrow_upward,
              color: renk,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hareket.islemTipi,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (hareket.aciklama != null && hareket.aciklama!.isNotEmpty)
                  Text(
                    hareket.aciklama!,
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  fmt.format(hareket.tarih),
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${giris ? '+' : '-'}${ParaUtils.formatla(hareket.tutar)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: renk,
                ),
              ),
              if (hareket.sonrakiBakiye != null)
                Text(
                  'Bakiye: ${ParaUtils.formatla(hareket.sonrakiBakiye!)}',
                  style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- MANUEL HAREKET EKLE (Sadece hesap varsa) ----
  Future<void> _hareketEkleDialog() async {
    if (widget.hesapId == null) return;

    String tip = 'Gelen';
    final ctrl = TextEditingController();
    final aciklamaCtrl = TextEditingController();

    final sonuc = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Yeni Hareket Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: tip,
                decoration: const InputDecoration(
                  labelText: 'İşlem Tipi',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Gelen', child: Text('Gelen (Para Yatır)')),
                  DropdownMenuItem(value: 'Giden', child: Text('Giden (Para Çek)')),
                ],
                onChanged: (v) => setState(() => tip = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tutar (TL)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: aciklamaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Açıklama (Opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final tutar = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (tutar == null || tutar <= 0) return;
                Navigator.pop(ctx, {
                  'tip': tip,
                  'tutar': tutar,
                  'aciklama': aciklamaCtrl.text.trim(),
                });
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (sonuc == null || !mounted) return;

    try {
      await _hareketDepo.ekle(
        BankaHareketModel(
          bankaHesapId: widget.hesapId!,
          islemTipi: sonuc['tip'] as String,
          tutar: sonuc['tutar'] as double,
          aciklama: (sonuc['aciklama'] as String).isEmpty
              ? null
              : sonuc['aciklama'] as String,
          tarih: DateTime.now(),
        ),
      );
      await _yukle();
      if (mounted) {
        BildirimServisi.basari(context, 'Hareket eklendi');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }
}