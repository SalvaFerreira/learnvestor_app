# LearnVestor: o que falta para ir para produção

## Contexto

**O que já existe:** o MVP técnico em `App/`. O backend Supabase faz a lógica de jogo no servidor, com RLS e testes. Há Edge Functions para dados de mercado e eliminação de dados, e uma app Flutter sem login (utilizador anónimo por dispositivo) com onboarding, lições, carteira virtual e perfil. A app corre de ponta a ponta com o servidor de demonstração.

**O que falta**, em três dimensões:
1. **Usável:** a app nunca correu numa infraestrutura real, nem num telemóvel, nem nas lojas.
2. **Útil:** 10 lições não chegam para criar hábito, e falta ligar a aprendizagem a decisões reais.
3. **Escalável:** a base está preparada, mas há pontos que só aguentam até alguns milhares de utilizadores ativos.

**Decisões tomadas:**
- **App pública e gratuita** (decidido a 2026-10-27): sem login, sem subscrição, sem compras e sem paywall. Cada dispositivo tem um utilizador anónimo do Supabase; todas as lições são gratuitas. As vidas e as gemas mantêm-se como mecânica de jogo, mas só se ganham a jogar.
- Lançar **primeiro em Portugal**, com conteúdo PT-PT e temas locais.
- O conteúdo é criado com **rascunhos de IA e revisão humana**.
- O **B2B** (escolas e empresas) só avança **depois** de o B2C provar que retém utilizadores.

**Restrições que se mantêm:**
- Equipa de 1 a 3 devs e orçamento baixo.
- Nunca haverá investimento com dinheiro real.

---

## Progresso

**Feito em 27/10/2026** (não precisava de contas):
- **P0 #7:** moderação de usernames, com lista de termos bloqueados e reports.
- **"Reportar erro":** botão de bandeira em cada exercício e vistas de qualidade do conteúdo.
- **Modo Praticar:** sessões a partir dos erros, sem custo de vidas, que devolvem uma vida.
- **Novos tipos de exercício:** `match` (ligar pares) e `numeric` (cálculo).
- **Ferramentas:** calculadoras de juros compostos, fundo de emergência e custos de fundos.
- **Pipeline de conteúdo:**
  - currículo com 89 lições;
  - estados draft/reviewed e validade dos factos;
  - script de rascunhos com a Claude;
  - publicação apenas de lições revistas.
- **Conteúdo:** 13 lições novas em rascunho (23 no total) para revisão humana.
- **Qualidade:** E2E no browser a correr no CI; ícones, splash e nome da app.

**À espera das contas:** P0 #1, #2, #4 a #6, #8 a #10 (ambientes, proteção contra abuso, builds das lojas, dados de mercado, legal, observabilidade, analytics e push).

## 1. Lacunas por prioridade

### P0: bloqueiam o lançamento

| # | Lacuna | O que fazer | Onde |
|---|---|---|---|
| 1 | Sem ambientes reais | Projetos Supabase staging e prod (UE), Vault, secrets, deploy por GitHub Actions | `App/.github/workflows/deploy.yml`, `App/README.md` |
| 2 | Abuso de utilizadores anónimos | **Captcha Turnstile no início de sessão anónimo**, limite por IP (`anonymous_users`) e limpeza periódica de utilizadores anónimos inativos | `supabase/config.toml` (`[auth.captcha]`, `[auth.rate_limit]`), `start_screen.dart` |
| 3 | ~~Login~~ | Removido: a app não tem contas. O progresso fica ligado ao dispositivo e não passa para outro telemóvel. | — |
| 4 | Builds das lojas | Android SDK, Codemagic para iOS (sem Mac), bundle ids, assinatura, ícones e splash (`flutter_launcher_icons`, `flutter_native_splash`), `PrivacyInfo.xcprivacy`, formulário Data Safety, classificação etária, TestFlight e Play Internal Testing | `apps/mobile/android`, `apps/mobile/ios`, novo `codemagic.yaml` |
| 5 | Dados de mercado licenciados | Contratar um plano com direitos de exibição que cubra a **Euronext Lisboa**, e confirmar que a Galp, a EDP, o BCP e a Jerónimo Martins vêm com dados | `supabase/functions/_shared/market.ts` |
| 6 | Legal | Constituir a empresa. A privacidade e os termos do website já descrevem a app gratuita e sem conta (2026-10-27); falta acrescentar Sentry e PostHog quando forem ativados. Registo de atividades RGPD, DPAs e revisão por um jurista. O tom tem de ser educativo, sem recomendações (risco CMVM). | `LearnVestor_Website/docs/*.html`, `lib/core/config.dart` (`termsVersion`) |
| 7 | Nomes de utilizador públicos | A classificação mostra usernames, por isso é preciso uma lista de palavras proibidas, a opção de reportar e um admin para renomear | Nova migração (`private.is_username_allowed` + `username_reports`), `complete_onboarding` |
| 8 | Observabilidade | Sentry com DSN, alertas quando o `market-data-sync` falha ou as cotações ficam velhas, uptime monitor, PITR ativo e um runbook de incidentes | `market-data-sync/index.ts`, `20261023120700_cron.sql` |
| 9 | Analytics com consentimento | PostHog UE, ativado só se `consents.analytics = true`, com um plano de eventos (secção 4) | Novo `lib/services/analytics.dart` |
| 10 | Notificações | Push (FCM/APNs) para o lembrete de streak à hora local e para avisar que as vidas estão cheias, com tokens por dispositivo e preferências | Tabela `push_tokens`, Edge Function `send-reminders`, cron por hora |

### P1: dão valor real e retenção

**Conteúdo**, a maior lacuna:
- Passar de 10 para cerca de **60 lições na beta** e **120 a 150 no lançamento**.
- Pipeline descrito na secção 2.

**Prática e revisão espaçada:**
- Um separador "Praticar" que volta aos exercícios errados. As respostas já ficam guardadas em `lesson_attempts.answers`.
- Praticar dá XP e permite **recuperar vidas**, como no Duolingo.
- Nova RPC: `get_practice_session`.

**Mais tipos de exercício:**
- Pares a ligar (`match`).
- Resposta numérica (`numeric`, por exemplo "quanto tens ao fim de 2 anos?").
- **Simulador com slider** (juros compostos, inflação).
- Cenário com decisão.
- Implica alterar `packages/content/schema/lesson.schema.json`, `build.mjs`, `exercise_views.dart` e `lesson_session.dart`.

**Onboarding personalizado:**
- Objetivo do utilizador (poupar, perceber a reforma, primeiro investimento).
- Teste de nivelamento que desbloqueia unidades.

**Ficha de cada ação:**
- Gráfico histórico (`quotes_daily`, com backfill do fornecedor), capitalização, setor, dividendos, descrição educativa e "lições relacionadas".
- Ecrã novo em `features/explore/`.

**Ligar a aprendizagem à carteira:**
- **Missões diárias e semanais** (completar uma lição, ter 3 setores, comprar um ETF). Novas tabelas `quests` e `user_quests`, avaliadas nas RPCs.
- **Insights da carteira:** pontuação de diversificação, concentração e comparação com um índice global (VT). Sem recomendar nada; é para ensinar.

**Ferramentas úteis no dia a dia** (é aqui que a app passa a ter uso real fora do jogo):
- Calculadoras de juros compostos, fundo de emergência, custos de fundos (TER) e PPR / Certificados de Aforro, com as regras portuguesas.
- Orçamento simples 50/30/20.
- As calculadoras são públicas e podem viver também no website, para SEO.

**Social:**
- **Ligas semanais** de cerca de 30 pessoas, com promoção e descida de divisão (ainda em Postgres).
- Amigos e convites com recompensa em gemas (referral).
- Partilhar conquistas.

**Lições offline:**
- Fila local com Drift e bundles de conteúdo em cache.
- As RPCs já são idempotentes e reconciliam as vidas.

**Suporte:**
- "Reportar erro" em cada exercício (tabela `content_reports`).
- Feedback dentro da app e FAQ.

**Backoffice:**
- Pesquisar utilizadores e moderar usernames e reports.
- **Qualidade do conteúdo:** taxa de erro por exercício e abandono por lição, numa view SQL sobre `lesson_attempts`.

**Sem monetização:** a app é gratuita para todos. Os custos de infraestrutura e de dados de mercado têm de ser cobertos por outra via (a decidir).

**Acessibilidade:** semântica e labels, texto dinâmico, contraste e testes com leitor de ecrã.

### P2: crescimento e escala (depois do lançamento, guiado por métricas)

**Escala:**
- Load test k6 em staging.
- `pg_stat_statements` e revisão de índices.
- **Cache do caminho de aprendizagem:** o conteúdo vai como bundle imutável no Storage/CDN e só o progresso vem da RPC.
- **Preços em tempo real por Realtime Broadcast**, enviado pela função de sync. O `postgres_changes` atual avalia a RLS por subscritor e não escala.
- **Classificações em Redis** a partir de cerca de 50 mil utilizadores ativos semanais.
- Particionar `xp_events`, `lesson_attempts` e `currency_ledger`.
- Réplica de leitura.

**Novos mercados:** PT-BR (conteúdo regional próprio: Tesouro Direto, IR, B3), depois EN e ES.

**Tutor de IA ("explica o meu erro"):**
- Edge Function com Claude, com limite diário por utilizador e sem conselhos de investimento personalizados.

**B2B:**
- Organizações, turmas e lugares (seats).
- Painel do professor em Next.js, com atribuição de trilhos e relatórios.
- Contas geridas por escolas para menores de 16, com consentimento da escola.
- Piloto com 1 ou 2 escolas portuguesas.

**Aquisição:**
- Website em Next.js com SEO (glossário financeiro, calculadoras, artigos).
- ASO.

---

## 2. Pipeline de conteúdo (IA + revisão humana)

**Currículo Portugal**, cerca de 150 lições em 5 trilhos e 16 unidades:

| Trilho | Unidades (exemplos de lições) |
|---|---|
| **Dinheiro no dia a dia** | Orçamento (50/30/20, despesas fixas e variáveis) · Bancos (conta à ordem, poupança, depósitos a prazo, Fundo de Garantia) · Pagamentos e fraudes (cartões, MB Way, phishing) · Crédito (TAN vs TAEG, crédito ao consumo, cartões de crédito, crédito habitação, Euribor e spread) |
| **Impostos e Estado** (PT) | Recibo de vencimento (bruto vs líquido, Segurança Social, retenção na fonte) · IRS (escalões, deduções, IRS Jovem, mais-valias a 28 %) · Poupança do Estado (Certificados de Aforro e do Tesouro) · Reforma (Segurança Social, PPR e benefícios fiscais) |
| **Investimento** | Fundamentos (o que já existe) · Ações e bolsa (ordens, dividendos, Euronext Lisboa) · Obrigações e juros · ETFs (acumulação vs distribuição, domicílio, custos) |
| **Mente do investidor** | Enviesamentos (FOMO, aversão à perda, ancoragem) · Burlas (esquemas Ponzi, alertas CMVM, "demasiado bom para ser verdade") · Cripto: riscos |
| **Avançado** | Ler as contas de uma empresa · Avaliação (P/E, dividend yield) · Construir e rebalancear uma carteira · Independência financeira e longo prazo |

**Fluxo:**
1. **Currículo como código.** Um ficheiro `packages/content/curriculum.yaml` define trilhos, unidades e lições, com objetivos de aprendizagem e factos-chave.
2. **Rascunho com IA.** O script `packages/content/scripts/draft.mjs` chama a API da Claude e gera o JSON da lição em PT e EN, já no schema, com o estado `draft`.
3. **Validação automática.** O `npm run check` atual é alargado com campos novos:
   - `status` (draft, reviewed, published)
   - `reviewed_by`
   - `sources` (por exemplo Portal das Finanças, Banco de Portugal, CMVM)
   - `valid_until`, para factos que mudam todos os anos, como os escalões de IRS
4. **Revisão humana**, feita por ti ou por um especialista, com uma checklist:
   - exatidão
   - linguagem para iniciantes
   - nenhuma recomendação de produto
   - fontes citadas
5. **Publicação.** Só as lições `reviewed` são compiladas para SQL. O CI falha se houver factos com `valid_until` já passado.
6. **Melhoria contínua.** A view de qualidade (taxa de erro por exercício) e os `content_reports` alimentam as revisões.

**Ritmo:** cerca de 10 a 15 lições revistas por semana. Isso dá 60 em 4 a 5 semanas, e 150 até ao lançamento.

---

## 3. Fases e critérios de saída

| Fase | Quando (1 a 3 devs) | Entregáveis | Só avança quando |
|---|---|---|---|
| **A. Fundações de produção** | Semanas 1 a 3 | P0 1, 2, 5, 7, 8; empresa e legal iniciados; pipeline de conteúdo a funcionar | Staging com deploy automático; início anónimo com captcha; cotações reais da Euronext Lisboa |
| **B. Beta fechado** (com a waitlist) | Semanas 4 a 10 | P0 3, 4, 9, 10; 60 lições; prática; ficha de ação; missões; reportar erro; backoffice mínimo; TestFlight e Play Internal | Ativação (1ª lição no dia 0) ≥ 60 %; D7 ≥ 20 %; crash-free ≥ 99,5 %; zero erros de conteúdo graves por resolver |
| **C. Lançamento público em Portugal** | Semanas 11 a 18 | 120 a 150 lições; ligas; ferramentas e calculadoras; offline; legal final; ASO; email de lançamento para a waitlist | D30 ≥ 10 %; estabilidade com 10 mil utilizadores (load test) |
| **D. Crescimento** | Meses 5 a 9 | P2 por ordem de impacto: escala conforme as métricas, PT-BR, tutor de IA, referral, website SEO e piloto B2B | Retenção estável e financiamento a cobrir os custos de infraestrutura e de dados |

As metas de retenção são referências para apps de aprendizagem e devem ser ajustadas com os dados reais da beta.

---

## 4. Analytics (eventos mínimos, só com consentimento)

- **Aquisição e ativação:** `first_open`, `onboarding_completed` (objetivo, nível), `lesson_started`, `lesson_completed` (lição, estrelas, erros, duração), `lesson_failed`.
- **Hábito:** `streak_extended`, `streak_lost`, `practice_completed`, `notification_opened`.
- **Valor:** `trade_placed`, `quest_completed`, `tool_used` (calculadora).
- **Vidas:** `out_of_hearts`, `hearts_refilled`.
- **Funis a acompanhar:** 1ª abertura → 1ª lição → D1 → D7; lição → missão → trade.

---

## 5. Custos mensais estimados no lançamento (a confirmar nas páginas de preços)

Supabase Pro com compute pequeno (cerca de 25 a 60 €), dados de mercado com licença (cerca de 50 a 200 €), Sentry e PostHog nos escalões gratuitos ou baixos (0 a 50 €), Codemagic (free tier ou cerca de 50 €) e domínio. **Total: cerca de 150 a 400 € por mês.**

Custos únicos: Apple Developer 99 $/ano, Google Play 25 $, jurista e constituição da empresa.

---

## 6. Riscos principais

| Risco | Mitigação |
|---|---|
| Erros financeiros ou fiscais no conteúdo | Revisão humana obrigatória; fontes oficiais; `valid_until` com revisão anual; botão "reportar erro" |
| Ser visto como aconselhamento financeiro (CMVM) | Linguagem educativa; nenhuma recomendação de produtos ou corretoras; disclaimers; parcerias com corretoras só com parecer jurídico |
| Licença de dados de mercado | Contrato antes da beta pública; fornecedor trocável via `MarketDataProvider` |
| Retenção fraca ("cansaço de gamificação") | Prática, missões, ferramentas úteis e conteúdo local; decidir com base nos dados da beta |
| Revisão das lojas (apps de finanças) | Aviso educativo bem visível; nada de dinheiro real; eliminação de conta; política de privacidade completa |
| Abuso (bots a criar utilizadores anónimos) | Captcha no início anónimo; rate limits já nas RPCs; App Check / Play Integrity na fase C |

---

## 7. Verificação contínua

- **Cada nova RPC ou tabela:** testes em `App/tools/db-tests/tests/`, grants em `*_api_grants.sql` e `npm run fixtures` para o teste de contrato da app.
- **E2E no CI:** transformar o percurso Playwright (feito à mão nesta sessão) em `App/tools/e2e/`. Corre no CI contra o `dev-server.mjs`: 1ª abertura sem login, onboarding, lição, trade e perfil.
- **Staging:** smoke test após cada deploy, cron de mercado monitorizado e load test k6 antes do lançamento.
- **Beta:** painel PostHog com os funis da secção 4 e crash-free no Sentry, revistos todas as semanas.
