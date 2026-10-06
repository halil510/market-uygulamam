// lib/ekranlar/ayarlar/yazici_ayar_widgetlari.dart
//
// yazici_ayar_ekrani.dart'ın parçası (part/part of) — ekranın state'siz yardımcı
// widget sınıfları (kartlar, butonlar, giriş alanı). Birebir aynı kod.
part of 'yazici_ayar_ekrani.dart';

// ═════════════════════════════════════════════════════════════════════════════
// YARDIMCI WIDGETlar
// ═════════════════════════════════════════════════════════════════════════════

/// Aktif bağlantı durumu kartı
class _BaglantiDurumKarti extends StatelessWidget {
  final YazdirmaServisi yazdirma;
  final VoidCallback onKes;
  const _BaglantiDurumKarti({required this.yazdirma, required this.onKes});

  @override
  Widget build(BuildContext context) {
    final bagliMi = yazdirma.bagliMi;
    final renk    = bagliMi ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: renk.shade300),
        boxShadow: [BoxShadow(
          color: Color.fromARGB(20, renk.red, renk.green, renk.blue),
          blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color.fromARGB(30, renk.red, renk.green, renk.blue),
            shape: BoxShape.circle),
          child: Icon(bagliMi ? Icons.print : Icons.print_disabled,
              color: renk.shade700, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bagliMi ? 'Yazıcı Bağlı' : 'Yazıcı Bağlı Değil',
              style: TextStyle(fontWeight: FontWeight.w700,
                  color: renk.shade800, fontSize: 14)),
          if (bagliMi)
            Text(yazdirma.baglantiDurumu,
                style: TextStyle(fontSize: 12, color: renk.shade600)),
          if (!bagliMi)
            Text('Aşağıdan bir yazıcı seçin',
                style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
        ])),
        if (bagliMi)
          OutlinedButton.icon(
            onPressed: onKes,
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text('Kes', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
      ]),
    );
  }
}

/// Bulunan cihaz kartı (WiFi IP veya BT cihazı)
class _CihazKarti extends StatelessWidget {
  final IconData ikon;
  final MaterialColor renkTon;
  final String baslik, altBaslik, aksiyonEtiket;
  final Color aksiyonRenk;
  final bool altBaslikMono;
  final VoidCallback onAksiyon;

  const _CihazKarti({
    required this.ikon, required this.renkTon,
    required this.baslik, required this.altBaslik,
    required this.aksiyonEtiket, required this.aksiyonRenk,
    required this.onAksiyon, this.altBaslikMono = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.borderColor),
      boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6)],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Color.fromARGB(30, renkTon.red, renkTon.green, renkTon.blue),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(ikon, color: renkTon.shade700, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text(altBaslik,
            style: TextStyle(
              fontSize: 11,
              color: TsRenk.metinIkincil(context),
              fontFamily: altBaslikMono ? 'monospace' : null)),
      ])),
      FilledButton(
        onPressed: onAksiyon,
        style: FilledButton.styleFrom(
          backgroundColor: aksiyonRenk,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(0, 36),
        ),
        child: Text(aksiyonEtiket, style: TsMetin.kucukVurgu),
      ),
    ]),
  );
}

/// Kayıtlı yazıcı kartı (bağlan + sil)
class _KayitliYaziciKarti extends StatelessWidget {
  final YaziciModel yazici;
  final VoidCallback onSil;
  const _KayitliYaziciKarti({required this.yazici, required this.onSil});

  @override
  Widget build(BuildContext context) {
    final wifimi = yazici.tur == 'ag';
    final renk   = wifimi ? Colors.blue : Colors.purple;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color.fromARGB(25, renk.red, renk.green, renk.blue),
            borderRadius: BorderRadius.circular(12)),
          child: Icon(wifimi ? Icons.wifi : Icons.bluetooth,
              color: renk.shade600, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(yazici.adi, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(wifimi
              ? '${yazici.ip ?? "?"}:${yazici.port}'
              : (yazici.cihazId ?? ''),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: Color(0xFF607D8B))),
        ])),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
          onPressed: onSil,
          tooltip: 'Kaldır',
          style: IconButton.styleFrom(
            backgroundColor: TsRenk.zemin(TsRenk.hata),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      ]),
    );
  }
}

/// Bölüm başlığı (Fiş tab içinde kart bazlı gruplar)
class _KartBolum extends StatelessWidget {
  final String baslik;
  final IconData ikon;
  final Color renk;
  final List<Widget> children;
  const _KartBolum({required this.baslik, required this.ikon,
      required this.renk, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.borderColor),
      boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Başlık satırı
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Color.fromARGB(18, renk.red, renk.green, renk.blue),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(bottom: BorderSide(color: context.borderColor)),
        ),
        child: Row(children: [
          Icon(ikon, size: 18, color: renk),
          const SizedBox(width: 8),
          Text(baslik, style: TextStyle(fontWeight: FontWeight.w800,
              fontSize: 13, color: renk)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    ]),
  );
}

/// Liste bölüm başlığı + sayı rozeti
class _Seksiyon extends StatelessWidget {
  final String baslik;
  final int sayi;
  const _Seksiyon({required this.baslik, required this.sayi});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    const SizedBox(width: 8),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppRenkler.primary.withAlpha(31),
        borderRadius: BorderRadius.circular(10)),
      child: Text('$sayi', style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, color: AppRenkler.primary)),
    ),
  ]);
}

/// Bilgi kutusu
class _BilgiKutu extends StatelessWidget {
  final Color renk;
  final IconData ikon;
  final String mesaj;
  const _BilgiKutu({required this.renk, required this.ikon, required this.mesaj});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color.fromARGB(18, renk.red, renk.green, renk.blue),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Color.fromARGB(50, renk.red, renk.green, renk.blue)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(ikon, size: 16, color: renk),
      const SizedBox(width: 8),
      Expanded(child: Text(mesaj,
          style: TextStyle(fontSize: 12,
              color: Color.fromARGB(200, renk.red, renk.green, renk.blue)))),
    ]),
  );
}

/// Aksiyon butonu
class _ActionButon extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color renk;
  final bool outlined;
  final bool loading;
  final bool genislik;

  const _ActionButon({
    required this.label, required this.renk,
    this.icon, this.onTap,
    this.outlined = false, this.loading = false, this.genislik = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(
                strokeWidth: 2, color: outlined ? renk : Colors.white)),
            const SizedBox(width: 8),
            Text(label),
          ])
        : icon != null
          ? Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18), const SizedBox(width: 6), Text(label),
            ])
          : Text(label);

    final style = outlined
        ? OutlinedButton.styleFrom(
            foregroundColor: renk, side: BorderSide(color: renk),
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))
        : FilledButton.styleFrom(
            backgroundColor: renk, foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));

    return SizedBox(
      width: genislik ? double.infinity : null,
      child: outlined
          ? OutlinedButton(onPressed: onTap, style: style, child: child)
          : FilledButton(onPressed: onTap, style: style, child: child),
    );
  }
}

/// TextField yardımcısı
Widget _inputField(
  BuildContext context,
  TextEditingController ctrl, String label, String hint, IconData ikon, {
  TextInputType tip = TextInputType.text,
  List<TextInputFormatter> fmt = const [],
}) => TextField(
  controller: ctrl, keyboardType: tip, inputFormatters: fmt,
  decoration: InputDecoration(
    labelText: label, hintText: hint,
    prefixIcon: Icon(ikon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: TsRenk.ayirac(context))),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _blue, width: 1.5)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  ),
);
