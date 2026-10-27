# LearnVestor: app Flutter

Flutter 3.38, com Riverpod 3 (estado), go_router (navegação), supabase_flutter (auth, RPCs, Realtime), purchases_flutter (RevenueCat), fl_chart e Sentry. Os textos estão em EN e PT (`lib/l10n/*.arb`, gerados com `flutter gen-l10n`).

## Configuração (`--dart-define`)

| Variável | Obrigatória | Notas |
|---|---|---|
| `SUPABASE_URL` | sim | `https://<ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | sim | Chave pública do projeto (publishable/anon). Nunca uses a secret/service-role. |
| `REVENUECAT_APPLE_KEY`, `REVENUECAT_GOOGLE_KEY` | para compras | Chaves públicas do SDK. Sem elas, o paywall mostra que as compras não estão disponíveis. |
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
├── app/          MaterialApp, router (redireciona entre login, onboarding e app) e shell com navegação
├── core/         configuração, tema (cores dos mockups), formatação
├── data/         modelos (JSON das RPCs) e Repository (única porta para o Supabase)
├── services/     RevenueCat
├── state/        providers Riverpod
├── features/     auth, onboarding, home, learn (+ lição), explore (+ trade), portfolio, profile, paywall
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
- Produtos de subscrição e consumíveis criados no App Store Connect e na Play Console, com os mesmos ids da RevenueCat.
- A app já cumpre dois requisitos de revisão das lojas: a eliminação de conta está no Perfil e o aviso educativo aparece no onboarding.
- Ligações para os documentos legais: `lib/core/config.dart`.
