//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<flutter_bluetooth_basic/FlutterBluetoothBasicPlugin.h>)
#import <flutter_bluetooth_basic/FlutterBluetoothBasicPlugin.h>
#else
@import flutter_bluetooth_basic;
#endif

#if __has_include(<path_provider/FLTPathProviderPlugin.h>)
#import <path_provider/FLTPathProviderPlugin.h>
#else
@import path_provider;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FlutterBluetoothBasicPlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterBluetoothBasicPlugin"]];
  [FLTPathProviderPlugin registerWithRegistrar:[registry registrarForPlugin:@"FLTPathProviderPlugin"]];
}

@end
