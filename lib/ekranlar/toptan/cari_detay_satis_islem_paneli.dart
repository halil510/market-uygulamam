// lib/ekranlar/toptan/cari_detay_satis_islem_paneli.dart
// cari_detay_paneli.dart'ın parçası — bir satış satırına dokununca
// açılan "Satış İşlemleri" yandan paneli (god-class sertleştirmesi,
// 2026-09-22). _CariDetayPaneliState'in private üyelerine ihtiyacı
// yoktu (tüm veri parametre olarak geliyor) — bu yüzden part-of ama
// extension DEĞİL, doğrudan bağımsız top-level tanımlar. Davranış
// birebir korundu.
part of 'cari_detay_paneli.dart';

/// Kullanıcı isteği: "alt panel değil yandan açılır olacak,
/// profesyoneller gibi." Araştırma sonucu: bu, "Stacked Master-Detail"
/// (yığılmalı ana-detay) deseni — cari paneli üstüne, bir üst katman
/// olarak (mevcut panel yerini almadan, ÜSTÜNE yığılarak) yeni bir
/// yandan panel açılıyor. Burada satışın özeti + net, düzgün boyutlu
/// işlem butonları (Detay/Faturalandır/İade Et/Çoğalt) var — önceki
/// hâldeki sıkışık ikon şeridi YERİNE.
Future<void> satisIslemPaneliAc(
  BuildContext context,
  SatisModel satis,
  CariModel cari, {
  required Future<void> Function() onDetay,
  required Future<void> Function() onFaturalandir,
  required Future<void> Function() onIadeEt,
  required Future<void> Function() onCogalt,
  required Future<void> Function() onSil,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black.withAlpha(80),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (c, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (c, anim, secAnim, child) {
      final ekranGenislik = MediaQuery.of(c).size.width;
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: Material(
            elevation: 16,
            child: SizedBox(
              width: ekranGenislik > 700 ? ekranGenislik * 0.42 : ekranGenislik * 0.86,
              height: double.infinity,
              child: _SatisIslemPaneli(
                satis: satis, cari: cari,
                onDetay: onDetay, onFaturalandir: onFaturalandir,
                onIadeEt: onIadeEt, onCogalt: onCogalt, onSil: onSil,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SatisIslemPaneli extends StatelessWidget {
  final SatisModel satis;
  final CariModel cari;
  final Future<void> Function() onDetay;
  final Future<void> Function() onFaturalandir;
  final Future<void> Function() onIadeEt;
  final Future<void> Function() onCogalt;
  final Future<void> Function() onSil;

  const _SatisIslemPaneli({
    required this.satis, required this.cari,
    required this.onDetay, required this.onFaturalandir,
    required this.onIadeEt, required this.onCogalt, required this.onSil,
  });

  /// Butona basınca: önce BU paneli kapat, sonra asıl işlemi yap
  /// (ör. iade ekranına git) — iki panelin üst üste açık kalmaması için.
  void _kapatVeCalistir(BuildContext context, Future<void> Function() aksiyon) {
    Navigator.pop(context);
    aksiyon();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Satış İşlemleri',
        lider: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        gradyanli: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Fiş özeti ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4E342E), Color(0xFF6D4C41)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(satis.fisNo ?? '—', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(DateFormat('dd.MM.yyyy HH:mm').format(satis.tarih), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Tutar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Text(ParaUtils.formatla(satis.genelToplam),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Text('Cari', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Flexible(
                  child: Text(cari.unvan, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          Text('İŞLEMLER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              letterSpacing: 0.4, color: context.textSecondary)),
          const SizedBox(height: 10),
          // ── Net, düzgün boyutlu işlem butonları ─────────────────
          _islemButonu(context, 'Fiş Detayını Gör', 'Kalemleri ve tam dökümü görüntüle',
              Icons.receipt_long_outlined, AppRenkler.primary, () => _kapatVeCalistir(context, onDetay)),
          const SizedBox(height: 10),
          _islemButonu(context, 'Faturalandır', 'Bu satıştan e-Fatura/e-Arşiv oluştur',
              Icons.description_outlined, Colors.purple, () => _kapatVeCalistir(context, onFaturalandir)),
          const SizedBox(height: 10),
          _islemButonu(context, 'İade Et', 'Bu satıştaki ürünleri iade al',
              Icons.undo, Colors.orange, () => _kapatVeCalistir(context, onIadeEt)),
          const SizedBox(height: 10),
          _islemButonu(context, 'Çoğalt (Tekrar Sipariş)', 'Aynı kalemlerle güncel fiyattan yeni satış başlat',
              Icons.copy_all_outlined, Colors.blue, () => _kapatVeCalistir(context, onCogalt)),
          const SizedBox(height: 10),
          _islemButonu(context, 'Satışı Sil', 'Faturalandırılmamışsa siler; stok/kasa/bakiye otomatik geri alınır',
              Icons.delete_outline, TsRenk.hata, () => _kapatVeCalistir(context, onSil)),
        ]),
      ),
    );
  }

  Widget _islemButonu(BuildContext context, String baslik, String aciklama, IconData ikon, Color renk, VoidCallback onTap) {
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: renk.withAlpha(60))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: renk.withAlpha(30), shape: BoxShape.circle),
              child: Icon(ikon, color: renk, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(baslik, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text(aciklama, style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
              ]),
            ),
            Icon(Icons.chevron_right, color: context.textHint),
          ]),
        ),
      ),
    );
  }
}
