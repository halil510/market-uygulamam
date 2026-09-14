// lib/ekranlar/satis/iade/iade_arama_widget.dart
import 'package:flutter/material.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/urun_model.dart';

// Renk sabitleri — ana iade_ekrani.dart'taki _R paletiyle aynı TsRenk
// semantik sabitlerine hizalandı (önceden burada FARKLI, sabit bir turuncu
// tonu vardı ve ekranın geri kalanıyla (İade Et butonu vb.) uyumsuzdu).
class _R {
  static const primary = TsRenk.primary;
  static const orange  = TsRenk.uyari;
}

class IadeAramaKutusu extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTemizle;
  final VoidCallback onBarkod;

  const IadeAramaKutusu({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onTemizle,
    required this.onBarkod,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(children: [
        Expanded(child: TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: 'Ürün adı veya barkod ara…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: onTemizle)
                : null,
            border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
            isDense: true,
          ),
        )),
        const SizedBox(width: 8),
        IconButton.filled(
          icon: const Icon(Icons.qr_code_scanner),
          style: IconButton.styleFrom(
              backgroundColor: _R.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          onPressed: onBarkod,
        ),
      ]),
    );
  }
}

class IadeAramaPanel extends StatelessWidget {
  final List<UrunModel> aramaListesi;
  final void Function(UrunModel) onSec;

  const IadeAramaPanel({
    super.key,
    required this.aramaListesi,
    required this.onSec,
  });

  @override
  Widget build(BuildContext context) {
    if (aramaListesi.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TsRenk.ayirac(context)),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: aramaListesi.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final u = aramaListesi[i];
            // ÖNCEDEN BURADA CİDDİ, GERÇEK BİR ÇÖKME HATASI VARDI:
            // u.ad / u.satisFiyat gibi UrunModel'de HİÇ VAR OLMAYAN alan
            // adları kullanılıyordu (gerçek adlar: urunAdi / satisFiyati).
            // `aramaListesi` dynamic olarak tiplendiği için bu derleme
            // hatası vermiyordu ama kullanıcı arama sonucuna her
            // tıkladığında (bu panel her render edildiğinde) uygulama
            // "NoSuchMethodError" ile çöküyordu. İade ekranındaki arama
            // özelliği baştan beri tamamen kullanılamaz durumdaydı.
            final ad = u.urunAdi.isNotEmpty ? u.urunAdi : '?';
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: _R.orange.withAlpha(26),
                child: Text(ad[0], style: const TextStyle(color: _R.orange, fontSize: 12)),
              ),
              title: Text(ad, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('${u.barkod ?? ''} • Stok: ${u.stok.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 11)),
              trailing: Text(ParaUtils.formatla(u.satisFiyati),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onTap: () => onSec(u),
            );
          },
        ),
      ),
    );
  }
}
