# LearnVestor: app Flutter

Flutter 3.38, com Riverpod 3 (estado), go_router (navegação), supabase_flutter (utilizador anónimo, RPCs e leituras) e fl_chart. É publicada como demo web: não há login nem compras, e no primeiro arranque a app cria um utilizador anónimo. Os textos estão em EN e PT (`lib/l10n/*.arb`, gerados com `flutter gen-l10n`).

## Configuração (`--dart-define`)

| Variável | Notas |
|---|---|
| `DEMO` | `true` gera a demo no browser: a app fala com a API de demonstração dentro da página. Usada pelo `tools/web-demo`. |
| `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` | Só para desenvolver com `flutter run` contra o `tools/db-tests/dev-server.mjs` (ver o [README principal](../../README.md)). |

## Estrutura

```
lib/
├── app/          MaterialApp, router (arranque → menu principal) e shell com navegação
├── core/         configuração, tema, formatação
├── data/         modelos (JSON das RPCs) e Repository (única porta para a API)
├── services/     DemoHttpClient: entrega os pedidos à API de demonstração dentro da página
├── state/        providers Riverpod
├── features/     start (cria o utilizador anónimo), home (menu principal, com reiniciar progresso e feedback), learn (+ lição), explore (+ trade), portfolio, tools
└── ui/           componentes partilhados e mensagens de erro localizadas
```

## Testes

```bash
flutter analyze
flutter test
```

- `test/lesson_session_test.dart` testa o motor da lição: repetição dos exercícios errados e envio apenas das respostas à primeira tentativa.
- `test/rpc_contract_test.dart` converte respostas **reais** das RPCs com os modelos da app. Para regenerar as fixtures: `cd ../../tools/db-tests && npm run fixtures`.

## Ligações externas

Os documentos legais e a caixa de feedback do website estão em `lib/core/config.dart`.
