# LearnVestor: app

Monorepo da **demo gratuita do LearnVestor no browser** (o "Duolingo da literacia financeira"): qualquer pessoa a pode experimentar em https://salvaferreira.github.io/LearnVestor_Website/demo/, sem instalar nada, sem login e sem pagamentos. A arquitetura e as decisões estão em [ARCHITECTURE.md](ARCHITECTURE.md).

```
App/
├── apps/mobile/            App Flutter, publicada como demo web
├── supabase/
│   ├── migrations/         Schema, RLS, lógica de jogo (RPCs) e permissões da API
│   └── seeds/              10_content.sql (gerado) + 20_dev_market_data.sql (preços de exemplo)
├── packages/content/       Currículo, lições, conquistas e instrumentos como código (EN + PT)
├── tools/db-tests/         API de demonstração (api.mjs), testes da base de dados em PGlite e servidor de desenvolvimento
├── tools/web-demo/         Build da demo no browser: app + API de demonstração a correr dentro da página
├── tools/e2e/              Percurso completo no browser (Playwright) sobre a demo
└── .github/workflows/      CI (testes em cada push)
```

## Princípios

- **O servidor é que decide.** XP, vidas, streaks, dinheiro virtual e trades mudam apenas através de RPCs Postgres (`supabase/migrations/*_rpc.sql`). Na demo, esse Postgres corre dentro do browser. O cliente nunca escreve diretamente em saldos.
- **Tudo fechado por omissão.** Todas as tabelas têm RLS. Tudo o que fica exposto à API (tabelas e RPCs por role) está num só ficheiro: [`*_api_grants.sql`](supabase/migrations/20261023120800_api_grants.sql).
- **Sem contas e sem dinheiro real.** No primeiro arranque a app cria um utilizador anónimo, por isso não há email, código nem login. Os euros da carteira são virtuais e ganham-se nas lições. Não há subscrições nem compras: todas as lições são gratuitas, e as vidas e gemas só se ganham a jogar.

## Testar (não precisa de Docker nem de contas)

```bash
# Conteúdos: valida as lições e confirma que o SQL gerado está atualizado
cd packages/content && npm ci && npm run check

# Base de dados: aplica todas as migrações e seeds num Postgres em memória e testa
# RLS, permissões, lições, vidas, streaks, prática, trades, câmbio, idempotência e a API da demo
cd tools/db-tests && npm ci && npm test

# App: análise estática, testes unitários, de widgets e de contrato com respostas reais das RPCs
cd apps/mobile && flutter pub get && flutter analyze && flutter test

# E2E: sobre a demo construída e servida (ver secção seguinte)
cd tools/e2e && npm ci && CHROME_PATH="<caminho do Chrome>" npm test
```

Sempre que mudares o JSON devolvido por uma RPC, regenera as fixtures do teste de contrato da app com `cd tools/db-tests && npm run fixtures`.

## Demo no browser (o que é publicado)

A demo não precisa de servidor. O `tools/web-demo` junta a build web da app (com `--dart-define=DEMO=true`) e a API de demonstração (`tools/db-tests/api.mjs`), que corre as **migrações e RPCs reais** num Postgres em WASM (PGlite) dentro do browser. No modo demo, o cliente Supabase da app envia todos os pedidos para essa API, sem rede. Cada visitante tem a sua base de dados, guardada no IndexedDB do browser, por isso o progresso sobrevive a um refresh. Custa 0 € e não tem contas para gerir.

```bash
cd tools/db-tests && npm ci
cd ../web-demo && npm ci
npm run build                     # → tools/web-demo/dist (servir com qualquer servidor estático)
npx http-server dist -p 51973     # e abrir http://127.0.0.1:51973
```

**Publicar no website** (GitHub Pages do repositório LearnVestor_Website), depois de mudares a app, as migrações ou o conteúdo:

```bash
cd tools/web-demo
npm run build -- --out ../../../LearnVestor_Website/docs/demo --base-href LearnVestor_Website/demo
# depois: commit e push no repositório LearnVestor_Website
```

Os preços das ações são de exemplo (mantêm-se, mas a data é renovada a cada visita). Quando o esquema muda, a demo cria uma base de dados nova e o progresso antigo de cada visitante é descartado.

## Desenvolver com hot reload

O `tools/db-tests/dev-server.mjs` serve a mesma API de demonstração por HTTP, para desenvolver com `flutter run` sem refazer a build da demo. A base de dados fica em memória e perde-se quando o servidor para.

```bash
cd tools/db-tests && npm ci && npm run dev      # API em http://127.0.0.1:54321

cd apps/mobile
flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=dev
```

## Conteúdos: currículo → rascunho com IA → revisão

Tudo em `packages/content`:

1. **Currículo** ([`content/curriculum.yaml`](packages/content/content/curriculum.yaml)). É a fonte única de trilhos, unidades, ordem das lições e regiões (por exemplo, o trilho de Impostos é só para PT). Cada lição planeada tem objetivos, factos-chave e fontes oficiais. `npm run status` mostra o que está planeado, em rascunho e revisto.
2. **Rascunho com IA.**
   - `npm run draft -- --next 5` (ou `-- <id-da-lição>` / `-- --unit <unidade>`) gera a lição em PT e EN com a Claude, já validada, com `status: "draft"`.
   - Precisa de `ANTHROPIC_API_KEY`.
   - `--dry-run` mostra só o prompt, sem chamar a API.
3. **Revisão humana.** Confirma os factos nas fontes listadas e corrige a linguagem. Depois muda para `"status": "reviewed"` e acrescenta `"review": { "by": "nome", "date": "AAAA-MM-DD" }`. Factos que mudam todos os anos levam `valid_until`; depois dessa data o build falha até a lição ser revista de novo.
4. `npm run build` gera `supabase/seeds/10_content.sql`, com todas as lições. Faz commit deste ficheiro e volta a publicar a demo. Se uma lição já existente mudar, aumenta o `version`: as versões são imutáveis.

Tipos de exercício: `info`, `multiple_choice`, `true_false`, `fill_blank`, `order`, `match` (ligar pares) e `numeric` (cálculo).

## App Flutter

Ver [apps/mobile/README.md](apps/mobile/README.md).

## O que ainda não está feito

- **Revisão humana das 23 lições em rascunho** e redação das restantes 66 do currículo.
- **Preços de exemplo:** os preços das ações estão fixos em `supabase/seeds/20_dev_market_data.sql`; convém atualizá-los de vez em quando.
