# LearnVestor: arquitetura da demo no browser

## Objetivo

O LearnVestor é o "Duolingo da literacia financeira": lições curtas e gamificadas e uma carteira de ações virtual. Este repositório é a **demo gratuita**, que qualquer pessoa experimenta no browser em https://salvaferreira.github.io/LearnVestor_Website/demo/.

Requisitos da demo:
- **Abre logo no menu principal:** sem instalação, sem registo, sem login e sem onboarding.
- **Gratuita e sem pagamentos:** não há subscrições, compras nem anúncios, e todas as lições estão disponíveis.
- **Sem servidor:** é publicada como ficheiros estáticos (GitHub Pages). Custa 0 €, não há contas de utilizador para gerir e nada pode ser abusado.
- **Privada:** os dados de cada visitante ficam no browser dele. Nada é enviado para um servidor.
- **Fiel ao produto:** as regras de jogo são as de um backend a sério (Postgres com RLS e RPCs), e não uma simulação no cliente.
- **Nunca há dinheiro real:** os euros da carteira são virtuais e ganham-se nas lições. O tom é sempre educativo, sem recomendações de investimento.

## O que o visitante pode fazer

- **Aprender:** 5 trilhos (Dinheiro no dia a dia, Impostos e Estado, Investimento, Mente do investidor, Avançado) com unidades e lições desbloqueadas por ordem. O trilho de Impostos só aparece a quem tem o browser configurado para Portugal. Há 7 tipos de exercício: informação, escolha múltipla, verdadeiro/falso, preencher o espaço, ordenar, ligar pares e cálculo numérico.
- **Jogar:** XP e níveis, objetivo diário, sequência de dias (streak), 6 vidas que regeneram com o tempo, gemas e 11 conquistas. Uma sessão de prática com os erros anteriores devolve uma vida.
- **Investir a fingir:** começa com 100 € virtuais e ganha mais nas lições. Pode comprar e vender 36 ações e ETFs (com preços de exemplo, em várias moedas) e ver a carteira e o histórico.
- **Calcular:** juros compostos, fundo de emergência e impacto das comissões.
- **Escolher a língua:** um botão EN/PT na barra de topo muda os textos e o conteúdo das lições.
- **Recomeçar:** "Reiniciar progresso", no menu principal, apaga tudo e começa de novo, com as vidas cheias.
- **Dar feedback:** um botão abre a caixa de feedback do website.

## 1. Visão geral

```
 Browser do visitante
 ┌────────────────────────────────────────────────────────────────────┐
 │  App Flutter (build web, DEMO=true)                                │
 │    Repository → supabase_flutter → DemoHttpClient                  │
 │                                        │  window.learnvestorDemoApi│
 │  demo_api.js                           ▼                           │
 │    API de demonstração (tools/db-tests/api.mjs)                    │
 │      Auth anónima · RPCs · leituras com filtros · delete-account   │
 │                                        │                           │
 │    PGlite: Postgres em WASM, com as migrações, seeds,              │
 │    RLS e RPCs reais                    │                           │
 │                                        ▼                           │
 │    IndexedDB (os dados do visitante, persistem entre visitas)      │
 └────────────────────────────────────────────────────────────────────┘
        ▲ ficheiros estáticos                     ▲ CanvasKit
   GitHub Pages (LearnVestor_Website/docs/demo)   CDN da Google (gstatic)
```

A app é escrita como um cliente Supabase normal: autentica-se, chama RPCs e lê tabelas pela API REST. No modo demo, o `supabase_flutter` recebe um cliente HTTP (`DemoHttpClient`) que entrega cada pedido a uma função JavaScript na própria página, em vez de o enviar para a rede. Essa função implementa a parte da API do Supabase que a app usa, sobre um Postgres que corre no browser.

## 2. Mapa do repositório

| Pasta | O que tem |
|---|---|
| `apps/mobile/` | App Flutter (Riverpod, go_router, supabase_flutter, fl_chart). Textos em EN e PT (`lib/l10n/*.arb`). `lib/services/demo_http_client*.dart` liga a app à API da demo. |
| `supabase/migrations/` | Esquema, RLS, lógica de jogo (RPCs) e permissões da API. |
| `supabase/seeds/` | `10_content.sql` (gerado a partir do conteúdo) e `20_dev_market_data.sql` (preços de exemplo). |
| `packages/content/` | Currículo, lições, conquistas e instrumentos como código, com validação e geração do SQL. |
| `tools/db-tests/` | `db.mjs` e `api.mjs` (núcleo partilhado entre Node e browser), testes da base de dados em PGlite, fixtures para a app e `dev-server.mjs` para desenvolvimento. |
| `tools/web-demo/` | Build da demo: junta a app, a API e o PGlite numa pasta estática. |
| `tools/e2e/` | Percurso completo no browser (Playwright) sobre a demo construída. |

## 3. Base de dados

Postgres organizado como num projeto Supabase: o esquema `public` é a superfície da API e o esquema `private` guarda a configuração e as funções internas.

- **Perfil e estado:** `profiles` (língua, fuso horário, país, objetivo diário) e `user_stats` (XP, nível, gemas, vidas, streak).
- **Conteúdo versionado:** `tracks`, `units` e `lessons`, com traduções. `lesson_versions` guarda as respostas certas, que o cliente nunca lê diretamente. As versões publicadas são imutáveis, por isso cada tentativa referencia exatamente o que o visitante viu.
- **Aprendizagem:** `lesson_attempts`, `lesson_progress` (melhores estrelas), `practice_sessions`, `xp_events` e `currency_ledger`. Os dois últimos são registos só de acrescentar, de tudo o que deu ou tirou XP, gemas e euros.
- **Mercado e carteira:** `instruments`, `quotes_latest`, `quotes_daily`, `fx_rates`, `portfolios`, `positions`, `trades` e `portfolio_snapshots`.
- **Conquistas:** `achievements` e `user_achievements`.
- **Configuração do jogo:** uma linha em `private.game_config` (vidas, regeneração, limites de XP, custos em gemas, dinheiro inicial…).

**Segurança e permissões:** todas as tabelas têm RLS. Tudo o que a API expõe a cada papel (tabelas e RPCs) está num único ficheiro, [`*_api_grants.sql`](supabase/migrations/20261023120800_api_grants.sql). O resto fica revogado por omissão.

## 4. Lógica de jogo

**O servidor é que decide.** Na demo, o "servidor" é o Postgres dentro da página. O cliente nunca escreve em saldos: XP, vidas, streaks, gemas, euros e trades só mudam através de RPCs (`*_rpc.sql`, `*_practice.sql`). Isto mantém as regras num único sítio, testado.

- **Lições:** `start_lesson` verifica a ordem de desbloqueio e a região, e devolve os exercícios na língua pedida. `complete_lesson` corrige com as respostas certas guardadas no servidor (só conta a primeira tentativa), desconta as vidas em falta e atribui estrelas, XP (com limite diário e menos XP em repetições), euros, streak e conquistas. Rejeita tentativas demasiado rápidas.
- **Vidas:** não há tarefas periódicas. O valor é calculado quando é pedido, a partir de `hearts`, `hearts_updated_at` e da taxa de regeneração. Recuperam-se com o tempo, com gemas ou com uma boa sessão de prática.
- **Streak:** conta dias no fuso horário do visitante. As mudanças de fuso estão limitadas a uma por dia.
- **Trades:** `place_trade` usa o preço guardado no servidor, nunca o do cliente. Converte a moeda com a taxa do dia, valida o saldo ou a posição e é idempotente (pedidos repetidos não duplicam a compra).

## 5. Conteúdo

O conteúdo é código, em `packages/content`:
1. `content/curriculum.yaml` é a fonte única dos trilhos, unidades, ordem das lições e regiões. Cada lição planeada tem objetivos, factos e fontes oficiais.
2. Os rascunhos são gerados com IA (`npm run draft`, em PT e EN) e revistos por uma pessoa, que confirma os factos nas fontes. Factos que mudam todos os anos levam `valid_until`.
3. `npm run build` valida tudo e gera `supabase/seeds/10_content.sql`. Hoje há 23 lições em rascunho, de 89 planeadas.

## 6. A API de demonstração

[`tools/db-tests/api.mjs`](tools/db-tests/api.mjs) não usa APIs do Node, por isso corre igual no browser e no Node. Implementa:
- **Auth:** início de sessão anónimo (`/auth/v1/signup` sem email), renovação do token, utilizador e logout. Os tokens são JWT HS256 assinados com WebCrypto. O segredo e os refresh tokens ficam em tabelas da própria base de dados (`auth.demo_secret` e `auth.refresh_tokens`), por isso a sessão sobrevive a um refresh da página.
- **REST:** chamadas a RPCs, leituras com filtros `eq` e ordenação, e atualização de campos do perfil. Corre tudo com o papel e o utilizador do pedido, por isso aplica a RLS como no Supabase.
- **Funções:** `delete-account`, que é o "Reiniciar progresso": apaga o utilizador e a app cria um novo.

Não há Realtime: a app lê as cotações uma vez por REST.

## 7. Persistência no browser

- Na primeira visita, `demo_api.js` descarrega o PGlite (cerca de 14 MB), aplica as migrações e os seeds e cria quatro jogadores fictícios.
- A base de dados fica no IndexedDB com um nome que inclui uma impressão digital do esquema (`learnvestor-demo-<hash>`). Quando as migrações ou o conteúdo mudam, a demo publicada começa numa base de dados nova e apaga as antigas, em vez de correr código novo sobre tabelas antigas.
- Se uma primeira visita for interrompida a meio, a base de dados incompleta é apagada e criada de novo.
- Depois de cada pedido que altera dados, a API força a gravação no IndexedDB antes de responder. O que a app mostra como feito sobrevive a um refresh.
- Em cada visita, as cotações de exemplo recebem a data atual, para as compras nunca falharem por preços "velhos".
- Se o IndexedDB não estiver disponível (algumas janelas privadas), a demo funciona na mesma em memória, mas nada fica guardado.

## 8. Build e publicação

`tools/web-demo/build.mjs`:
1. Gera um módulo com o esquema (o stub do Supabase, as migrações e os seeds) e a sua impressão digital.
2. Faz `flutter build web --dart-define=DEMO=true` com o `--base-href` do sítio onde vai ser servida.
3. Junta o `demo_api.js` (a API e o PGlite empacotados com esbuild) e os ficheiros `pglite.wasm` e `pglite.data`.
4. Acrescenta o `demo_api.js` ao `index.html`, antes do arranque do Flutter.

O resultado tem cerca de 22 MB, porque o CanvasKit vem do CDN da Google. A demo é publicada em `LearnVestor_Website/docs/demo`, e o comando está no [README](README.md).

## 9. Qualidade

- **Conteúdo:** `npm run check` valida as lições e confirma que o SQL gerado está atualizado.
- **Base de dados:** testes em PGlite (sem Docker) a RLS, permissões, lições, vidas, streaks, prática, trades, câmbio, idempotência e à própria API da demo (sessões que sobrevivem a reinícios, tokens falsificados, reiniciar o progresso).
- **App:** `flutter analyze`, testes unitários e de widgets, e um teste de contrato que converte respostas reais das RPCs com os modelos da app (`npm run fixtures`).
- **E2E:** o CI constrói a demo e percorre-a no Chromium: menu principal sem login, troca EN/PT, lição com um erro, prática, calculadoras, compra de uma ação, carteira, refresh da página e reiniciar o progresso.

## 10. Website, waitlist e feedback

O website (repositório LearnVestor_Website, GitHub Pages) apresenta o produto e liga à demo. A waitlist e a caixa de feedback são do website, não da demo. Os dois formulários enviam para o Formspree (`FORMSPREE_ENDPOINT` em `docs/script.js`), que manda cada envio por email e o guarda no painel do Formspree. Cada envio leva o tipo (`waitlist` ou `feedback`), a origem (`website` ou `demo`) e o idioma do browser. Não há base de dados nem servidor do website.

## 11. Limitações conhecidas

- Os preços das ações são de exemplo e não mudam com o mercado.
- O progresso pertence a um browser: noutro browser ou depois de apagar os dados do site, a demo começa do zero.
- A primeira visita descarrega cerca de 22 MB.
