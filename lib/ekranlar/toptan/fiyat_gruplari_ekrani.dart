// lib/ekranlar/toptan/fiyat_gruplari_ekrani.dart
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/toptan_fiyat_deposu.dart';
import '../../modeller/fiyat_grubu_model.dart';
import 'fiyat_grubu_detay_ekrani.dart';

class FiyatGruplariEkrani extends StatefulWidget {
  const FiyatGruplariEkrani({super.key});

  @override
  State<FiyatGruplariEkrani> createState() => _FiyatGruplariEkraniState();
}

class _FiyatGruplariEkraniState extends State<FiyatGruplariEkrani> {
  final _depo = ToptanFiyatDeposu();
  List<FiyatGrubuModel> _gruplar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final liste = await _depo.gruplariGetir();
    if (!mounted) return;
    setState(() { _gruplar = liste; _yukleniyor = false; });
  }

  Future<void> _duzenle([FiyatGrubuModel? mevcut]) async {
    final adCtrl = TextEditingController(text: mevcut?.ad ?? '');
    final aciklamaCtrl = TextEditingController(text: mevcut?.aciklama ?? '');
    final iskontoCtrl = TextEditingController(
        text: mevcut != null ? mevcut.varsayilanIskontoOrani.toStringAsFixed(0) : '0');

    final kaydedildi = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(mevcut == null ? 'Yeni Fiyat Grubu' : 'Fiyat Grubunu Düzenle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: adCtrl,
            decoration: const InputDecoration(labelText: 'Grup Adı', hintText: 'Örn: Altın Bayi'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: aciklamaCtrl,
            decoration: const InputDecoration(labelText: 'Açıklama (opsiyonel)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: iskontoCtrl,
            decoration: const InputDecoration(
              labelText: 'Varsayılan İskonto Oranı (%)',
              helperText: 'Ürüne özel fiyat girilmemişse, perakende\n'
                  'fiyattan bu oranda indirim uygulanır.',
              suffixText: '%',
            ),
            keyboardType: TextInputType.number,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (kaydedildi != true) return;
    if (adCtrl.text.trim().isEmpty) return;

    final grup = FiyatGrubuModel(
      id: mevcut?.id,
      globalId: mevcut?.globalId,
      ad: adCtrl.text.trim(),
      aciklama: aciklamaCtrl.text.trim().isEmpty ? null : aciklamaCtrl.text.trim(),
      varsayilanIskontoOrani: double.tryParse(iskontoCtrl.text.replaceAll(',', '.')) ?? 0,
    );
    if (mevcut == null) {
      await _depo.grupEkle(grup);
    } else {
      await _depo.grupGuncelle(grup);
    }
    await _yukle();
  }

  Future<void> _sil(FiyatGrubuModel g) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Fiyat Grubunu Sil'),
        content: Text('"${g.ad}" grubu silinsin mi? Bu gruba bağlı cariler '
            '"Perakende" fiyatlandırmasına döner.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true || g.id == null) return;
    await _depo.grupSil(g.id!);
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Fiyat Grupları (Bayi Tipleri)',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _duzenle(),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Grup'),
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : Column(children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: context.inputFill, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 18, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                      'Bayilerinizi gruplayın (Altın/Gümüş/Bronz gibi). Her cariyi '
                      'bir gruba atayıp, ürünlerde gruba özel fiyat tanımlayabilirsiniz.',
                      style: TextStyle(fontSize: 12, color: context.textSecondary))),
                ]),
              ),
              Expanded(
                child: _gruplar.isEmpty
                    ? Center(child: Text('Henüz fiyat grubu yok.\n"Yeni Grup" ile başlayın.',
                        textAlign: TextAlign.center, style: TextStyle(color: context.textHint)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        itemCount: _gruplar.length,
                        itemBuilder: (c, i) {
                          final g = _gruplar[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: context.cardBg,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
                            ),
                            // 🔴 YENİ: Karta dokununca artık gerçek fiyat
                            // yönetim ekranına gidiyor — önceden bu grupta
                            // hangi ürünün kaç TL olduğunu belirlemenin
                            // hiçbir yolu yoktu.
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => FiyatGrubuDetayEkrani(grup: g))).then((_) => _yukle()),
                              child: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: AppRenkler.primary.withAlpha(30), shape: BoxShape.circle),
                                child: const Icon(Icons.storefront_outlined, color: AppRenkler.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(g.ad, style: TextStyle(fontWeight: FontWeight.w700,
                                      fontSize: 15, color: context.textPrimary)),
                                  if (g.aciklama != null)
                                    Text(g.aciklama!, style: TextStyle(fontSize: 12, color: context.textSecondary)),
                                  if (g.varsayilanIskontoOrani > 0)
                                    Text('Varsayılan iskonto: %${g.varsayilanIskontoOrani.toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                              IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _duzenle(g)),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _sil(g)),
                            ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}
