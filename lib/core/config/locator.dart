import 'package:deepseek_function_call_example/core/config/env.dart';
import 'package:flutter_deepseek/flutter_deepseek.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'locator.config.dart';

final locator = GetIt.instance;

@module
abstract class RegisterModule {
  @lazySingleton
  DeepSeekClient deepSeekClient() => DeepSeekClient(apiKey: Env.apiKey);
}

@InjectableInit()
void configureDependencies() => locator.init();
