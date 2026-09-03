# Módulo Cotação (Insurance / AGGER)

Épico: [#291](https://github.com/autonom-ia2/chat/issues/291). PRD completo em [PRD.md](./PRD.md).
Este README registra o que foi **decidido** e o que **diverge do PRD** depois de inspecionar o fork.

## Decisões travadas (Rodrigo, 2026-09-03)

| # | Decisão |
|---|---|
| 1 | Stack piloto: **hub2you** (`chat.hub2you.ai`). Autonomia depois, mesmo código. |
| 2 | **Todos os ramos**; product registry data-driven desde o início. |
| 3 | AGGER **sem CAPTCHA e sem MFA** → login automatizado com credencial da corretora em Secrets Manager. Takeover com browser remoto **fora do MVP**; falha inesperada → screenshot + handoff. |
| 4 | **B2C**: o cliente final da corretora conversa com o agente. |
| 5 | Conexões com identidade visual Chatwoot, **dentro da aba Conexões do módulo Cotação**. |
| 6 | **Um modo**: o agente cota e envia. Sem aprovação humana intermediária; handoff pelo `handoff_rule` existente. |
| 7 | Agente = `agent_type='insurance_quote'` **no módulo Agentes Autonom.ia** (builder, inbox binding, versões, playground, Desempenho reaproveitados). Instrução travada. |
| 8 | **SUSEP Foundation** (`/scoped-query`) como base de cobertura/condições gerais. |
| 9 | Connector: API/worker seguem blue/green; o browser com sessão AGGER é stateful, **um por conexão**, nunca dois vivos. |
| 10 | Chave OpenAI = a da conta (`Crm::Ai::CredentialResolver`, hook `crm_kanban_ai`). |
| 11 | Retenção de dados do cliente = política atual do CRM/agentes. |

A instrução da **Ana Maciel / GTA** (seguro viagem, B2B, n8n) é inspiração de estrutura — escopo antes de evidência, matriz de ferramentas, lista negativa de "proibido chamar cotação se…", validação do retorno campo a campo, classificação sucesso / falha de negócio / falha técnica, `conversation_closed_for_now` — não texto a copiar.

## Arquitetura do conector: máquina de adapters (decidido 03/09, noite)

O conector **não** é n8n nem os Lambdas antigos (`insurance-quoting-service`): ambos serviram só de mapa de endpoints. O conector é a **máquina de aprendizado de interfaces** no repo [`autonom-ia2/autonomia-adapters`](https://github.com/autonom-ia2/autonomia-adapters) (TypeScript, CLI `autonomia`):

```
autonomia <plataforma> <recurso> <ação>
  degrau 1  adapter determinístico   (AGGER: HTTP puro — sem browser)
  degrau 2  seletores de fallback     (Playwright versionado)
  degrau 3  fallback semântico        (Stagehand)
  degrau 4  Recovery Agent            (OpenAI gpt-5.4 high, chave de sistema) → adapter candidate → testes → canary
```

Nenhuma descida de degrau é silenciosa; só erro de formato (`protocol`) autoriza descer. Exit codes sysexits (77 auth, 75 timeout, 76 protocolo). O chat2you chama o CLI/API do connector como **ferramenta** do agente — por isso a Onda 2 (tool-calling) continua pré-requisito.

**Validado ao vivo em 03/09/2026** com a conta de teste: login + `pdocs` OK; `cfg/cobertura` devolve 10 ramos (auto confirmado; residencial, condomínio, empresarial, fiança, AP, vida, vida em grupo inferidos; 100 e 711 não identificados); `cfg/seguradora/config` devolve 23 seguradoras com `credenciaisValidas` (→ ready/auth_required) e comissão por ramo. `seguradorasMulti` (fonte de março) passou a responder 403 SigV4 — primeiro "portal mudou" real. Detalhe em autonom-ia2/chat#292.

## O que o PRD assume e não existe no fork

Verificado em `main` `a1b74f5d53`:

- **Tool-calling**: `Autonomia::Agents::Answerer#generate` faz uma chamada síncrona a `Crm::Ai::ResponsesClient` com JSON schema; a única tool é `WebSearch` built-in. Não há function tools nem loop. Sem isso o agente não chama `quote.*` nem a SUSEP → [#297](https://github.com/autonom-ia2/chat/issues/297).
- **Mensagem iniciada por evento**: o agente só responde a incoming (`MessageListener → ReplyJob` com debounce → `Responder`). O callback `quote.completed` precisa de um entry point novo.
- **Handoff de sistema**: hoje "passar para humano" é só texto da instrução (`Operate::Responder`).
- Duas stacks de produção (hub2you e autonomia); o PRD fala de "a EC2".

## Gate

Duas camadas, isoladas do sistema de features do Chatwoot (`Autonomia::Insurance::Config`):

```
INSURANCE_QUOTING_ENABLED=false            → módulo indisponível em todas as contas
INSURANCE_QUOTING_ENABLED=true + conta OFF → invisível para a conta
INSURANCE_QUOTING_ENABLED=true + conta ON  → disponível (admin-only)
```

Conta liga/desliga no SuperAdmin (`toggle_insurance`), marca em `accounts.internal_attributes['autonomia_insurance_enabled']`. Frontend lê `globalConfig.insuranceQuotingEnabled` + `account.autonomia_insurance_enabled`; backend aplica o mesmo gate nos controllers (`Autonomia::Insurance::Config.enabled?`).

## Ondas

| Onda | Escopo | Issues |
|---|---|---|
| 0 | Discovery AGGER com a conta de teste — **há endpoints JSON internos?** (decide browser × HTTP), login, sessão, ramos, PDF, 2 cotações paralelas | #292 |
| 1 | Fundação chat2you com AGGER mockado: gate, SuperAdmin, menu Cotação, `Insurance::Connection` + Secrets, UI Conexões, `agent_type` | #293 #294 #295 #296 |
| 2 | Tool-calling no Answerer, mensagem por evento, handoff de sistema, tool SUSEP | #297 |
| 3 | Máquina de adapters (`autonomia-adapters`): degraus 2-4, canary, Recovery Agent | — |
| 4 | Adapters por ramo | — |
| 5 | Agente de Cotação | — |
| 6 | Piloto hub2you → autonomia | — |

Ondas 0 e 1 correm em paralelo; a 2 começa após o PR 1 mergeado.

## Rollout / rollback

Feature OFF por padrão + gate por conta. Migrations aditivas. Rollback do chat2you = listener de volta ao blue (runbook `docs/rollback-chatwoot-4171.md`), sem impacto na sessão AGGER — o connector é serviço separado.
