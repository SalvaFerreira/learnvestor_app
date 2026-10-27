# LearnVestor: app

Monorepo da **demo gratuita do LearnVestor no browser** (o "Duolingo da literacia financeira"): qualquer pessoa a pode experimentar em https://salvaferreira.github.io/LearnVestor_Website/demo/, sem instalar nada, sem login e sem pagamentos. A app para descarregar das lojas será um projeto à parte. A arquitetura e as decisões estão em [ARCHITECTURE.md](ARCHITECTURE.md).

```
App/
├── apps/mobile/            App Flutter (publicada como demo web; também compila para iOS e Android)
├── supabase/
│   ├── migrations/         Schema, RLS, lógica de jogo (RPCs), cron e permissões da API
│   ├── seeds/              10_content.sql (gerado) + 20_dev_market_data.sql (só local)
│   └── functions/          Edge Functions: market-data-sync, delete-account
├── packages/content/       Currículo, lições, conquistas e instrumentos como código (EN + PT)
├── tools/db-tests/         Testes da base de dados em PGlite (sem Docker) + API de demonstração (api.mjs)
├── tools/web-demo/         Build da demo no browser: app + API de demonstração a correr dentro da página
├── tools/e2e/              Percurso completo no browser (Playwright) sobre a demo
└── .github/workflows/      CI (testes em cada push) e deploy manual por ambiente
```

## Princípios

- **O servidor é que decide.** XP, vidas, streaks, dinheiro virtual e trades mudam apenas através de RPCs Postgres (`supabase/migrations/*_rpc.sql`). O cliente nunca escreve diretamente em saldos.
- **Tudo fechado por omissão.** Todas as tabelas têm RLS. Tudo o que fica exposto à API (tabelas e RPCs por role) está num só ficheiro: [`*_api_grants.sql`](supabase/migrations/20261023120800_api_grants.sql).
- **Sem contas e sem dinheiro real.** No primeiro arranque a app cria um utilizador anónimo do Supabase para o dispositivo, por isso não há email, código nem login. Os euros da carteira são virtuais e ganham-se nas lições. Não há subscrições nem compras: todas as lições são gratuitas, e as vidas e gemas só se ganham a jogar.

## Testar (não precisa de Docker nem de contas)

```bash
# Conteúdos: valida as lições e confirma que o SQL gerado está atualizado
cd packages/content && npm ci && npm run check

# Base de dados: aplica todas as migrações e seeds num Postgres em memória e testa
# RLS, permissões, lições, vidas, streaks, trades, câmbio, idempotência e RGPD
cd tools/db-tests && npm ci && npm test

# Edge Functions: type-check e testes
npx deno check supabase/functions/*/index.ts && npx deno test supabase/functions

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

Limitações da demo: os preços das ações são de exemplo (mantêm-se, mas a data é renovada a cada visita) e a classificação semanal mostra o visitante e quatro jogadores fictícios. Quando o esquema muda, a demo cria uma base de dados nova e o progresso antigo de cada visitante é descartado.

## Ver a app a funcionar com hot reload (sem Docker nem contas)

O `tools/db-tests/dev-server.mjs` serve a mesma API de demonstração por HTTP, para desenvolver com `flutter run`. A base de dados fica em memória e perde-se quando o servidor para.

```bash
cd tools/db-tests && npm ci && npm run dev      # API em http://127.0.0.1:54321

cd apps/mobile
flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=dev
```

A app abre logo no menu principal, sem login. Os preços são de exemplo e não há Realtime. Serve só para demonstração e não substitui o Supabase.

## Conteúdos: currículo → rascunho com IA → revisão → publicação

Tudo em `packages/content`:

1. **Currículo** ([`content/curriculum.yaml`](packages/content/content/curriculum.yaml)). É a fonte única de trilhos, unidades, ordem das lições e regiões (por exemplo, o trilho de Impostos é só para PT). Cada lição planeada tem objetivos, factos-chave e fontes oficiais. `npm run status` mostra o que está planeado, em rascunho e revisto.
2. **Rascunho com IA.**
   - `npm run draft -- --next 5` (ou `-- <id-da-lição>` / `-- --unit <unidade>`) gera a lição em PT e EN com a Claude, já validada, com `status: "draft"`.
   - Precisa de `ANTHROPIC_API_KEY`.
   - `--dry-run` mostra só o prompt, sem chamar a API.
3. **Revisão humana.** Confirma os factos nas fontes listadas e corrige a linguagem. Depois muda para `"status": "reviewed"` e acrescenta `"review": { "by": "nome", "date": "AAAA-MM-DD" }`. Factos que mudam todos os anos levam `valid_until`; depois dessa data o build falha até a lição ser revista de novo.
4. `npm run build` gera `supabase/seeds/10_content.sql`, com todas as lições, incluindo rascunhos, para desenvolvimento. Faz commit deste ficheiro.
5. **Publicação.** O workflow de deploy corre `npm run publish:db`, que **só publica lições revistas**. Se uma lição já publicada mudar, aumenta o `version`: as versões são imutáveis e o publish recusa conteúdo alterado sem bump.

Tipos de exercício: `info`, `multiple_choice`, `true_false`, `fill_blank`, `order`, `match` (ligar pares) e `numeric` (cálculo).

**Qualidade do conteúdo em produção**, no SQL Editor:
- `private.exercise_quality`: taxa de erro à primeira tentativa por exercício.
- `private.lesson_funnel`: lições iniciadas vs concluídas.
- `private.open_content_reports`: erros reportados pelos utilizadores no botão de bandeira.

## Correr localmente com o Supabase completo (precisa de Docker)

```bash
npx supabase start                      # Postgres, Auth, Realtime e Studio
npx supabase db reset                   # migrações + seeds (conteúdo + preços de exemplo)
cp supabase/functions/.env.example supabase/functions/.env   # e preenche
npx supabase functions serve --env-file supabase/functions/.env

cd apps/mobile
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key do "supabase start">
```

## Opcional: correr o mesmo backend num Supabase real

A demo não precisa disto. As migrações são de um projeto Supabase normal, por isso o mesmo backend pode correr na cloud (por exemplo, para uma futura app nas lojas):

1. **Projeto Supabase** na região **UE (Frankfurt)**, com o plano Pro em produção (backups com PITR). Depois:
   ```bash
   npx supabase link --project-ref <ref>
   npx supabase db push
   DATABASE_URL=<connection string> npm run publish:db --prefix packages/content
   npx supabase functions deploy
   npx supabase secrets set --env-file supabase/functions/.env
   ```
2. **Segredos do cron**, no SQL Editor (o `cron_secret` tem de ser igual ao `CRON_SECRET` das functions):
   ```sql
   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
   select vault.create_secret('<mesmo valor do CRON_SECRET>', 'cron_secret');
   ```
3. **Auth.** Em Authentication > Sign In / Providers, ativa **Allow anonymous sign-ins** e desativa o email. Ativa também um **captcha** (Turnstile) e confirma o limite de inícios anónimos por IP, para evitar que bots criem utilizadores em massa.
4. **Dados de mercado.** Cria uma conta Finnhub (ou outro fornecedor) com um **plano comercial que permita mostrar cotações numa app**. O plano gratuito não permite redistribuição. Para trocar de fornecedor, basta implementar `MarketDataProvider` em `supabase/functions/_shared/market.ts`.
5. **GitHub.** Cria os environments `staging` e `production` com os secrets listados em [`deploy.yml`](.github/workflows/deploy.yml). A partir daí, o deploy faz-se em Actions > Deploy backend.

## Builds da app

Ver [apps/mobile/README.md](apps/mobile/README.md).

## O que ainda não está feito

- **Revisão humana das 23 lições em rascunho** e redação das restantes 66 do currículo.
- **Preços de exemplo:** os preços das ações estão fixos em `supabase/seeds/20_dev_market_data.sql`; convém atualizá-los de vez em quando.
