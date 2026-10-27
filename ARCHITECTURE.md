# LearnVestor: arquitetura técnica para um produto global

## Contexto

**O que existe hoje:** só o website estático em `LearnVestor_Website/docs/`, alojado no GitHub Pages. A página tem uma waitlist que **não guarda emails**: em [script.js:260-280](LearnVestor_Website/docs/script.js#L260-L280) o envio é simulado com `setTimeout` e `console.log`. Há também 4 mockups da app e documentos legais (privacidade, termos, disclaimer). Estes documentos já referem Supabase e Finnhub e fixam a idade mínima em 16 anos. Ainda não existe código da app.

**O negócio:** é um "Duolingo da literacia financeira", mobile-first (iOS e Android). Tem estas peças:
- **Lições gamificadas**, organizadas em trilhos (Banks, Investment, Advanced) e unidades com nós bloqueados.
- **Mecânicas de jogo:** XP, níveis ("Beginner Investor"), estrelas, streaks, vidas (6/6, que regeneram) e conquistas.
- **Economia virtual:** cada lição dá XP e euros virtuais (ex.: +30 XP e +45€).
- **Portfólio simulado:** os euros virtuais compram ações reais (AAPL, MSFT…) a preços reais. A app mostra o valor total, o dinheiro disponível, as posições e o histórico.
- **Explore:** pesquisa de empresas e categorias (Technology, Finance, Healthcare…).

**Decisões já tomadas:**
- Ainda não há app; parte-se do zero.
- A equipa tem 1 a 3 devs e o orçamento é baixo.
- A receita vem do modelo freemium com subscrição, de compras in-app e de B2B (escolas e empresas).
- **Nunca haverá investimento com dinheiro real.** O único dinheiro real é a monetização. Isto mantém a app fora da regulação financeira (MiFID, SEC, licenças de corretagem).

**Princípio orientador:** com 1 a 3 devs, a arquitetura deve ser um **monólito modular sobre serviços geridos**, e não microserviços. O objetivo é lançar depressa, gastar pouco por utilizador e ter um caminho de crescimento claro até milhões de utilizadores sem reescrever nada.

---

## 1. Visão geral da arquitetura

```
 ┌───────────────┐   ┌────────────────────┐   ┌──────────────────────┐
 │ App Flutter   │   │ Web (Next.js)      │   │ Backoffice / CMS     │
 │ iOS + Android │   │ landing, checkout  │   │ conteúdos, suporte   │
 │               │   │ web, painel B2B    │   │                      │
 └──────┬────────┘   └─────────┬──────────┘   └──────────┬───────────┘
        │  HTTPS (JWT)         │                         │
        ▼                      ▼                         ▼
 ┌────────────────────────────────────────────────────────────────────┐
 │ Cloudflare: DNS, WAF, CDN (bundles de lições, imagens), rate limit │
 └──────────────────────────────┬─────────────────────────────────────┘
                                ▼
 ┌────────────────────────────────────────────────────────────────────┐
 │ SUPABASE (região UE, Frankfurt)                                    │
 │  • Auth (Apple, Google, email/magic link)                          │
 │  • Postgres + RLS: dados de utilizador, progresso, portfólio, B2B  │
 │  • RPC / Edge Functions: lógica de jogo autoritativa no servidor   │
 │  • Realtime: preços e ligas em tempo real                          │
 │  • Storage: assets de conteúdo                                     │
 └───────┬───────────────────────┬───────────────────────┬────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
 ┌───────────────┐   ┌──────────────────────┐   ┌─────────────────────┐
 │ Redis         │   │ Market Data Worker   │   │ Webhooks            │
 │ (Upstash)     │   │ (cron) → fornecedor  │   │ RevenueCat, Stripe  │
 │ ligas, cache  │   │ de dados → cache     │   │ → entitlements      │
 └───────────────┘   └──────────────────────┘   └─────────────────────┘

 Serviços de apoio: PostHog (analytics, feature flags, testes A/B),
 Sentry (erros), FCM/APNs via OneSignal (push), Resend (email),
 Crowdin (traduções)
```

---

## 2. Stack tecnológica (recomendação final)

| Camada | Escolha | Porquê |
|---|---|---|
| App mobile | **Flutter 3 + Riverpod + go_router**, com **Drift** (SQLite) para offline | Um único código para iOS e Android, ótimo para UI animada e gamificada. Os mockups já seguem este estilo. Drift permite fazer lições sem rede. |
| Animações | **Rive** (mascote, celebrações) e **Lottie** | O "fator Duolingo" depende muito de micro-animações. |
| Backend | **Supabase**: Postgres 16, Auth, RLS, Edge Functions (Deno/TS), Realtime, Storage | Já está referido nos documentos legais, é barato no início e é Postgres puro (sem lock-in). Uma equipa pequena não precisa de gerir servidores. |
| Lógica de negócio | **Funções Postgres (RPC, `security definer`)** para mutações críticas e **Edge Functions** para integrações externas | Transações atómicas junto aos dados (XP, vidas, trades) e menos latência. |
| Cache e leaderboards | **Redis (Upstash, serverless)** | Os sorted sets servem as ligas semanais. Também guarda a cache de cotações. Paga-se por pedido. |
| Web | **Next.js (App Router) na Vercel ou Cloudflare Pages** | Landing com SEO e i18n, checkout web, painel B2B para professores e RH, e área de conta. |
| CMS de conteúdos | **Payload CMS** (self-hosted, sobre o mesmo Postgres) ou, numa primeira fase, **tabelas Supabase com um admin simples** | Autores criam lições sem deploy. As lições são versionadas e publicadas como bundles JSON. |
| Pagamentos | **RevenueCat** (App Store, Google Play e Web Billing) e **Stripe** (faturação B2B) | Ver secção 6. |
| Analytics e experiências | **PostHog Cloud UE** | Eventos de produto, funis, retenção, feature flags e testes A/B (preços, onboarding). |
| Observabilidade | **Sentry** (app, web, edge) e logs do Supabase | Crashes e erros com contexto. |
| Notificações | **FCM/APNs via OneSignal**; email transacional e de ciclo de vida via **Resend + Loops** | Lembretes de streak à hora local do utilizador. |
| CI/CD | **GitHub Actions**, **Supabase CLI** (migrações), **Codemagic** ou Fastlane (builds de lojas) e **Shorebird** (patches OTA em Flutter) | Deploys reprodutíveis e correções sem esperar pela revisão das lojas. |
| Repositório | **Monorepo**: `apps/mobile`, `apps/web`, `supabase/` (migrations, functions, seed), `packages/content-schema` | Uma equipa e um repositório, com o schema de conteúdos partilhado. |

---

## 3. Modelo de dados (Postgres)

**Identidade e organizações (multi-tenant para B2B)**
- `profiles`: id (= auth.uid), username, país, locale, fuso horário, data de nascimento ou faixa etária, moeda de exibição, created_at.
- `organizations`: escolas e empresas. `org_members`: papel (owner, admin, teacher, student, employee). `org_groups`: turmas ou equipas. `org_seats`: licenças.
- `consents`: termos, marketing e analytics, com versão e data (exigido pelo RGPD).

**Conteúdo (só leitura para o cliente, publicado pelo CMS)**
- `tracks`, `units`, `lessons` e `lesson_versions`. Cada versão guarda o conteúdo em JSON validado por schema, com exercícios de escolha múltipla, ordenação, completar frases e pequenas simulações.
- `lesson_translations` (locale, conteúdo). `content_regions`: a lição só aparece em certos países. Isto é necessário porque o trilho "Banks" e os temas de impostos variam de país para país.
- Os conteúdos publicados geram **bundles JSON imutáveis por versão e locale**, servidos via CDN. A app descarrega-os e guarda-os em cache para uso offline.

**Gamificação (estado autoritativo no servidor)**
- `user_stats`: XP total, nível, saldo de gemas, `hearts`, `hearts_updated_at`, `streak_current`, `streak_longest`, `streak_last_day` (data local), `streak_freezes`.
- `lesson_attempts`: utilizador, versão da lição, resultado, estrelas, XP ganho, duração e respostas. É **particionada por mês**.
- `achievements` (definição e regra) e `user_achievements`.
- `xp_events` e `currency_ledger`: **ledger append-only** de tudo o que dá ou tira XP, gemas e euros virtuais. Serve de auditoria e anti-batota. Os saldos nunca são escritos diretamente.
- `leagues`, `league_members` e `league_weeks`. O ranking em tempo real vive no Redis e o resultado final no Postgres.

**Portfólio virtual**
- `portfolios`: utilizador, saldo de caixa em EUR virtual. Fica preparado para vários portfólios, como desafios de turma no B2B.
- `trades`: símbolo, quantidade (numérico fracionário), preço, moeda, taxa de câmbio usada, timestamp e preço de referência do servidor.
- `positions`: materializada a partir de `trades`, com custo médio.
- `portfolio_snapshots`: valor diário, para o gráfico, calculado por um cron.
- `instruments`: universo curado (ticker, bolsa, moeda, setor, logo). `quotes_latest` (cache) e `quotes_daily` (fecho diário).

**Monetização**
- `entitlements`: utilizador ou org, produto, origem (apple, google, stripe, b2b), validade, estado. Esta tabela é atualizada **apenas pelos webhooks**.
- `purchases`: compras de consumíveis (gemas, streak freezes), com id de transação único para garantir idempotência.

**Regras transversais**
- Todas as tabelas têm **RLS ativo** e cada utilizador só lê os seus dados.
- Professores leem os agregados dos seus grupos através de *views* com `security_barrier`.
- Todas as mutações sensíveis passam por RPC. O cliente nunca faz `UPDATE` direto em saldos, XP ou vidas.

---

## 4. Lógica de jogo: autoritativa e escalável

Princípio: **o cliente é uma vista, o servidor decide.** Isto impede batota (XP infinito, vidas, comprar ações a preços falsos) e protege os leaderboards, que valem muito para a retenção.

- **Completar uma lição:** a RPC `complete_lesson(attempt)` corre numa única transação. Valida o attempt (versão, duração mínima plausível, respostas contra as soluções no servidor) e grava o resultado. Atualiza XP, nível, estrelas, streak e ledger, avalia as conquistas e devolve o novo estado.
- **Vidas:** não há cron por utilizador. O valor é calculado *lazily* a partir de `hearts`, `hearts_updated_at` e da taxa de regeneração. Utilizadores com subscrição Premium têm vidas ilimitadas, verificadas por `entitlements`.
- **Streak:** é calculada com base na **data local do utilizador** (fuso horário guardado no perfil e validado). Os streak freezes são consumidos automaticamente. Um job diário por fuso horário envia os lembretes.
- **Ligas semanais:** grupos de cerca de 30 utilizadores com nível de atividade semelhante. Cada `ZINCRBY` no Redis acontece no momento em que o XP é atribuído. No fecho da semana, um cron promove ou despromove os jogadores e persiste o resultado.
- **Trades virtuais:** a RPC `place_trade(symbol, qty)` usa **o preço que está na cache do servidor**, nunca o enviado pelo cliente. Converte a moeda com a taxa do dia, valida o saldo e grava o trade e o ledger.
- **Offline:** as lições podem ser feitas offline e ficam numa fila no Drift. A sincronização envia os attempts com uma `idempotency_key`. O servidor reconcilia e aplica regras de plausibilidade.

---

## 5. Dados de mercado (o ponto mais caro e arriscado)

**Problemas atuais:**
1. Chamar o Finnhub a partir do cliente expõe a API key e esgota o limite (o plano gratuito tem cerca de 60 pedidos por minuto).
2. **O plano gratuito ou pessoal não permite redistribuição comercial**, e mostrar cotações a milhares de utilizadores é redistribuição.
3. Os mockups mostram **$238.99 e €238.99 para a mesma ação**, ou seja, falta conversão cambial.

**Solução:**
- **Universo curado** de cerca de 300 a 1000 instrumentos (grandes empresas dos EUA e da Europa, ETFs populares). Para fins educativos não é preciso o mercado inteiro.
- **O Market Data Worker** é uma Edge Function ou um Cloud Run job agendado. Faz pedidos em lote ao fornecedor a cada 1 a 5 minutos durante o horário de mercado e grava em Redis (`quotes_latest`) e Postgres (`quotes_daily`). Publica alterações via Supabase Realtime para os ecrãs abertos. **O custo é fixo, independentemente do número de utilizadores.**
- **Dados com atraso de 15 minutos ou de fecho diário são suficientes** para educação e são muito mais baratos de licenciar do que tempo real.
- **Fornecedor:** contratar um plano comercial com direitos de exibição, seja o Finnhub comercial, o Twelve Data, o EODHD ou o Polygon. O fornecedor fica escondido atrás de uma interface `MarketDataProvider` para poder ser trocado. **Os termos de redistribuição têm de ser confirmados antes do lançamento.**
- **Câmbio:** taxas diárias do BCE (gratuitas). Os preços são guardados na moeda nativa e mostrados na moeda de exibição do utilizador.
- **Logos:** guardados em cache no Storage e na CDN, sem hotlinking.

---

## 6. Sistema de pagamentos

**Regra fundamental:** subscrições e bens digitais comprados **dentro da app iOS ou Android têm de usar a App Store ou o Google Play**, sob pena de rejeição. As exceções são limitadas, como links externos nos EUA. O web checkout serve de complemento.

| Canal | Ferramenta | Uso |
|---|---|---|
| iOS e Android | **RevenueCat** sobre StoreKit 2 e Play Billing | Subscrição "LearnVestor Plus" (mensal ou anual, com trial de 7 dias) e consumíveis (gemas, streak freezes, recargas de vidas). |
| Web (B2C) | **RevenueCat Web Billing** (usa o Stripe por baixo) | Checkout web com margem maior (cerca de 3% em vez de 15 a 30%). O entitlement é partilhado com a app. |
| B2B | **Stripe Billing + Stripe Invoicing + Stripe Tax** | Licenças anuais por lugar para escolas e empresas, com fatura, transferência ou cartão. O IVA e os impostos globais são calculados automaticamente. |

**Fluxo:**
1. A compra é feita na loja ou no Stripe.
2. O RevenueCat ou o Stripe envia um webhook para uma Edge Function, que verifica a assinatura.
3. A função faz um upsert idempotente em `entitlements` e `purchases`.
4. A app lê o entitlement do backend, que é a fonte da verdade, e não apenas o SDK local.

**Pontos-chave:**
- **Preços regionais por paridade de poder de compra:** usar as tabelas de preços por país das lojas. Isto é decisivo para crescer fora da UE e dos EUA.
- **Sem dinheiro real dentro do jogo:** os euros virtuais **não se compram nem se levantam**. Só se ganham a aprender. As gemas são compráveis, mas não convertíveis em dinheiro. Isto evita problemas regulatórios e de jogo.
- **Paywall:** gerido por remote config e testes A/B no RevenueCat ou PostHog, para testar preços sem lançar uma nova versão.
- **Faturação e IVA:** as lojas são *merchant of record* para as vendas in-app. No Stripe, o Stripe Tax trata o IVA OSS da UE.

---

## 7. Segurança

**Autenticação**
- Supabase Auth com Sign in with Apple (obrigatório quando há login social no iOS), Google e email por magic link ou OTP.
- **SSO** (Google Workspace, Microsoft Entra, SAML) para clientes B2B.
- Admins e staff com **MFA obrigatória**.
- Os tokens ficam no `flutter_secure_storage` (Keychain/Keystore). Os JWT são de curta duração e têm refresh rotativo.

**Autorização**
- RLS em todas as tabelas, com testes automáticos às policies (pgTAP).
- A `service_role` key **nunca** vai para o cliente.
- Papéis B2B aplicados via `org_members` nas policies.

**Integridade do cliente**
- **Firebase App Check** (com App Attest e Play Integrity) nas Edge Functions, para dificultar bots e clientes modificados.
- Validação de plausibilidade nos attempts.
- Rate limiting por utilizador e por IP (Cloudflare e Redis).

**Dados**
- TLS em todo o lado e encriptação em repouso (Supabase).
- Backups com **PITR**.
- Segredos guardados no Supabase Vault e nos GitHub Secrets.
- Mínimo de dados pessoais: sem morada, sem dados bancários (os pagamentos ficam nas lojas e no Stripe) e data de nascimento só como faixa etária.

**Webhooks e APIs**
- Verificação de assinatura (Stripe, RevenueCat), idempotência e replay protection.

**Aplicação**
- Seguir o OWASP MASVS (mobile) e o ASVS (web).
- Dependabot e varrimento de segredos no CI.
- Ofuscação de builds Flutter (`--obfuscate`).
- Pentest antes do lançamento B2B.

**Auditoria**
- `audit_log` para ações de admin e staff.
- Ledger imutável da economia virtual.

**Conformidade**
- **RGPD:** dados alojados na UE, DPA com todos os subprocessadores, exportação e eliminação de conta *self-service* (as lojas também exigem eliminação in-app), registo de consentimentos e banner de cookies na web.
- **Menores:** o B2C mantém o mínimo de 16 anos. A idade de consentimento digital varia entre 13 e 16 anos consoante o país da UE, e nos EUA aplica-se a COPPA abaixo dos 13 anos. Para **escolas** com alunos mais novos, criar **contas geridas pela organização**, com consentimento da escola, dados mínimos, sem ligas públicas, sem anúncios e sem marketing.
- **Rever com um jurista** antes do lançamento B2B em escolas, incluindo a FERPA nos EUA.
- **Regulação financeira:** manter "educational only", sem recomendações personalizadas. Os disclaimers existentes já cobrem isto. Se for adicionado um tutor de IA, ele deve ter guardrails que o impeçam de dar conselhos de investimento personalizados.

---

## 8. Escalabilidade (de 0 a milhões)

**Estimativa:**
- 1 milhão de utilizadores ativos mensais dá cerca de 250 mil utilizadores ativos diários e cerca de 1 milhão de lições por dia.
- Isso corresponde a cerca de 12 escritas por segundo em média e entre 100 e 200 em pico (lembretes a uma hora fixa).
- **Um único Postgres bem indexado aguenta isto à vontade.**
- O tráfego pesado (conteúdo e imagens) vai para a **CDN** e as cotações para o **Redis**, com custo fixo.

| Fase | Utilizadores | Infraestrutura | Custo mensal estimado |
|---|---|---|---|
| MVP e beta | até 10 mil | Supabase Pro, Upstash grátis ou barato, Vercel Hobby/Pro, Sentry e PostHog grátis | cerca de 50 a 150 € mais dados de mercado |
| Lançamento | 10 a 200 mil | Supabase Pro com compute maior, Upstash pago, OneSignal | cerca de 300 a 1.000 € mais dados de mercado |
| Crescimento | 200 mil a 2 milhões | Supabase Team, read replicas, PgBouncer, tabelas de eventos particionadas | cerca de 2 a 8 mil € |
| Escala | mais de 2 milhões | Workers pesados movidos para Cloud Run ou Fly, data warehouse (BigQuery ou ClickHouse) via CDC, multi-região só para leitura e CDN | conforme a receita |

Estes custos são ordens de grandeza e devem ser confirmados nas páginas de preços atuais. Os dados de mercado com licença comercial podem ir de dezenas a centenas de euros por mês.

**Táticas:**
- Particionar `lesson_attempts`, `xp_events` e `currency_ledger` por mês.
- Bundles de conteúdo imutáveis com cache longa.
- Contadores agregados em `user_stats`, em vez de `COUNT(*)`.
- Jobs pesados (snapshots de portfólio, fecho de ligas, emails) em cron e filas (`pg_cron` com `pgmq` no próprio Supabase).
- Feature flags para lançamentos graduais.
- Uma vez que é Postgres puro, migrar para Postgres self-managed (RDS, Cloud SQL) continua a ser uma opção sem reescrita.

---

## 9. Internacionalização (produto global)

- **Interface:** Flutter `intl` e ARB. A app começa em EN e PT, seguidas de ES, FR, DE e PT-BR.
- **Traduções:** gestão no Crowdin, com tradução assistida por IA e **revisão humana do conteúdo financeiro**.
- **Conteúdo localizado, não só traduzido:**
  - Os trilhos têm uma parte universal (risco, juro composto, ETFs) e uma parte regional (bancos, impostos, reforma por país), através de `content_regions`.
  - Moeda de exibição e formatos numéricos seguem o locale.
- **Datas:** guardadas sempre em UTC, com o fuso horário do utilizador para streaks e notificações.

---

## 10. B2B (escolas e empresas)

- **Painel web em Next.js:**
  - Criar a organização e convidar membros por código de turma, CSV ou SSO.
  - Atribuir trilhos e definir prazos.
  - Ver progresso e relatórios, com exportação para CSV.
  - Organizar desafios de portfólio por turma.
- **Licenciamento:** lugares sincronizados com a subscrição Stripe. Os membros de uma organização com licença recebem automaticamente o entitlement "Plus".
- **Mais tarde:** integrações LTI 1.3 (Moodle, Canvas) e Google Classroom, e SCIM para empresas.

---

## 11. Extras recomendados (fase 2)

- **Tutor de IA:** explica porque é que uma resposta está errada e responde a perguntas sobre a lição. Corre numa Edge Function com Claude (por exemplo `claude-haiku-5-5`, pelo custo), com limites por plano (mais uso para o Plus), prompt de sistema restrito a educação e proibição de recomendações de investimento. Os resultados frequentes ficam em cache.
- **Apoio à criação de conteúdo com IA no CMS:** gerar rascunhos de exercícios e traduções, sempre com revisão humana.
- **Dimensão social:** amigos, seguir utilizadores e partilhar conquistas com deep links e um card de imagem gerado no servidor.

---

## 12. Roadmap de execução

1. **Semanas 0 a 2, fundações**
   - Monorepo, projeto Supabase UE (dev, staging, prod), CI e migrações.
   - Corrigir a waitlist do website para gravar no Supabase ou no Loops.
   - Migrar a landing para Next.js com i18n (ou manter o HTML e adicionar apenas o endpoint).
2. **Semanas 2 a 10, MVP**
   - Auth e onboarding.
   - Motor de lições (schema JSON e 5 tipos de exercício).
   - XP, níveis, vidas, streak e conquistas no servidor.
   - Portfólio virtual com o worker de dados de mercado e câmbio.
   - PostHog e Sentry.
   - Beta fechado (TestFlight e Play Internal) com a waitlist.
3. **Semanas 10 a 16, monetização e lançamento**
   - RevenueCat, paywall e Plus; consumíveis.
   - Notificações.
   - Ligas.
   - Eliminação e exportação de conta.
   - Revisão legal.
   - Lançamento nas lojas em PT e EN.
4. **Meses 4 a 9:** checkout web, mais idiomas e conteúdo regional, painel B2B com Stripe Invoicing, SSO e tutor de IA.
5. **Mais tarde:** LTI e Classroom, read replicas e data warehouse, conforme o crescimento.

---

## 13. Verificação e validação da arquitetura

- **Segurança:**
  - Testes pgTAP às RLS policies: um utilizador A não consegue ler nem escrever dados do utilizador B, e um professor só vê o seu grupo.
  - Testes que confirmam que o cliente não consegue fazer `UPDATE` direto a `user_stats` nem a `portfolios`.
- **Lógica de jogo:**
  - Testes unitários e de integração às RPC: streak a atravessar fusos horários e mudança de hora, regeneração de vidas, idempotência de attempts offline, trade com saldo insuficiente e trade com preço do servidor.
- **Pagamentos:**
  - Sandbox da App Store e do Play com o RevenueCat.
  - `stripe trigger` para os webhooks.
  - Confirmar que os entitlements são criados, renovados e revogados, e que um webhook repetido não duplica nada.
- **Carga:**
  - k6 contra staging, simulando 200 escritas por segundo em `complete_lesson` e 5 mil utilizadores com Realtime de cotações.
  - Verificar a latência p95 e a ausência de saturação de ligações.
- **Dados de mercado:** o worker respeita o rate limit do fornecedor e a app nunca contacta o fornecedor diretamente (confirmar com um proxy como mitmproxy).
- **Conformidade:** checklist de RGPD (exportação, eliminação, consentimentos) e checklist de revisão da App Store (eliminação de conta, Sign in with Apple, IAP).
