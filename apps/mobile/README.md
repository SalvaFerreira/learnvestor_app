# LearnVestor: app Flutter

Flutter 3.38, com Riverpod 3 (estado), go_router (navegação), supabase_flutter (utilizador anónimo, RPCs, Realtime), fl_chart e Sentry. Não há login nem compras: no primeiro arranque a app cria um utilizador anónimo para o dispositivo. Os textos estão em EN e PT (`lib/l10n/*.arb`, gerados com `flutter gen-l10n`).

## Configuração (`--dart-define`)

| Variável | Obrigatória | Notas |
|---|---|---|
| `SUPABASE_URL` | sim (exceto na demo) | `https://<ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | sim (exceto na demo) | Chave pública do projeto (publishable/anon). Nunca uses a secret/service-role. |
| `DEMO` | não | `true` gera a demo no browser: a app fala com a API de demonstração dentro da página e não precisa de `SUPABASE_URL` nem de chave. Usada pelo `tools/web-demo`. |
| `SENTRY_DSN` | não | Ativa o reporte de erros, sem dados pessoais. |
| `APP_ENV` | não | `development`, `staging` ou `production` (aparece no Sentry). |

O mais simples é guardar estes valores num ficheiro por ambiente e usar `--dart-define-from-file`:

```bash
flutter run --dart-define-from-file=env/staging.json
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/production.json
flutter build ipa --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/production.json
```

(`env/*.json` não deve ir para o git.)

## Estrutura

```
lib/
├── app/          MaterialApp, router (redireciona entre arranque, onboarding e app) e shell com navegação
├── core/         configuração, tema (cores dos mockups), formatação
├── data/         modelos (JSON das RPCs) e Repository (única porta para o Supabase)
├── state/        providers Riverpod
├── features/     start (cria o utilizador anónimo), onboarding, home, learn (+ lição), explore (+ trade), portfolio, profile, tools
└── ui/           componentes partilhados e mensagens de erro localizadas
```

## Testes

```bash
flutter analyze
flutter test
```

- `test/lesson_session_test.dart` testa o motor da lição: repetição dos exercícios errados e envio apenas das respostas à primeira tentativa.
- `test/rpc_contract_test.dart` converte respostas **reais** das RPCs com os modelos da app. Para regenerar as fixtures: `cd ../../tools/db-tests && npm run fixtures`.

## Antes de publicar nas lojas

- Ícones, splash screen e nomes da app: `app.learnvestor.learnvestor` em `android/app/build.gradle.kts` e no projeto iOS.
- A app já cumpre dois requisitos de revisão das lojas: a eliminação dos dados está no Perfil e o aviso educativo aparece no onboarding. Como não há login nem compras, não é preciso Sign in with Apple nem IAP.
- Ligações para os documentos legais: `lib/core/config.dart`.
