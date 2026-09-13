// lib/widgetlar/ortak/yonetici_sifre_dialogu.dart
//
// Borç Silme gibi geri alınması zor/riskli işlemlerden HEMEN ÖNCE, o an
// oturum açmış müdür/admin'in KENDİ şifresini yeniden girmesini ister —
// masada bırakılmış açık bir oturumda yanlışlıkla (veya art niyetle)
// tetiklenen bir dokunuşun geri döndürülemez bir işlem yapmasını
// engelleyen son bir sürtünme adımı. Doğrulama mekanizması
// ayarlar_giris_ekrani.dart'taki "kendi şifresiyle doğrula" deseniyle
// AYNI (KullaniciDeposu.girisKontrol — yan etkisiz, lockout burada
// uygulanmıyor, zaten ekrana admin/müdür olarak girilmiş olması
// gerekiyor).
//
// ÇAĞIRAN TARAF SORUMLULUĞU: bu dialog SADECE "gerçekten sen misin"
// diye sorar — kullanıcının müdür/admin OLUP OLMADIĞINI kontrol etmez.
// Bu yüzden çağıran taraf, dialogu göstermeden ÖNCE (buton görünürlüğü)
// VE eylemi uygulamadan hemen önce AuthServisi().isMudur kontrolü
// yapmalıdır.
import 'package:flutter/material.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../servisler/auth_servisi.dart';

Future<bool> yoneticiSifresiIleOnayIste(
  BuildContext context, {
  required String baslik,
  required String aciklama,
}) async {
  final ctrl = TextEditingController();
  String hata = '';
  bool dogruluyor = false;

  final sonuc = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.lock_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(baslik)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(aciklama, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '${AuthServisi().aktifAd} — Şifreniz',
                border: const OutlineInputBorder(),
                errorText: hata.isEmpty ? null : hata,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: Colors.red),
            onPressed: dogruluyor
                ? null
                : () async {
                    if (ctrl.text.isEmpty) return;
                    ss(() { dogruluyor = true; hata = ''; });
                    final kullanici = AuthServisi().aktifKullanici;
                    final gecerli = kullanici != null &&
                        await KullaniciDeposu().girisKontrol(
                                kullanici.kullaniciAdi, ctrl.text) !=
                            null;
                    if (!ctx.mounted) return;
                    if (gecerli) {
                      Navigator.pop(ctx, true);
                    } else {
                      ss(() { dogruluyor = false; hata = 'Hatalı şifre'; });
                    }
                  },
            child: dogruluyor
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Onayla', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
  return sonuc == true;
}
