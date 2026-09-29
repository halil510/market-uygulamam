// Gerçek Android cihazda çalışan Uygulama Robotu sarmalayıcısı.
//   flutter test integration_test/robot_cihaz_test.dart -d <cihaz> \
//     --dart-define=ROBOT=true
// Robot, test/robot altındaki aynı senaryoyu çalıştırır (bellek içi veritabanı,
// sahte eklenti kanalları); yalnız ekran boyutu/render/performans GERÇEK
// cihazdandır. Rapor konsola basılır.
import 'package:integration_test/integration_test.dart';
import '../test/robot/uygulama_robotu_test.dart' as robot;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  robot.main();
}
