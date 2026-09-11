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

## Conexão (PR 2)

- Tabela `autonomia_insurance_connections` (uma por conta e provider). `username`/`password` cifrados com ActiveRecord::Encryption — **sem `ACTIVE_RECORD_ENCRYPTION_*` o model recusa gravar credencial** (a tela mostra o aviso e desabilita Conectar).
- **Cofre ligado em produção nas duas stacks em 03/09/2026** (chaves distintas por stack, geradas com `rails db:encryption:init`). Seguro para o que já existia porque o fork configura `support_unencrypted_data: true` + `extend_queries: true`: dado antigo em texto puro segue legível e só as gravações novas saem cifradas. Verificado ao vivo na conta 16 — `username`/`password` gravados como envelope `{"p":…}`.
- API (admin, gate ENV+conta): `GET|POST|DELETE /api/v1/accounts/:id/autonomia/insurance/connection`, `POST …/connection/reconnect`, `POST …/connection/scan`. A senha entra no POST e nunca volta (só `username_hint`).
- `Autonomia::Insurance::Connector.client` escolhe o transporte por `INSURANCE_CONNECTOR_MODE` (`mock` = contrato com o formato do CLI `autonomia agger`, sem AGGER). O transporte HTTP para o serviço do `autonomia-adapters` chega na Onda 3.
- `Connections::Sync` traduz erro do connector em `status` + `last_error` (`auth_required`/`offline`/`degraded`), nunca em 500.

## Aba Conexões — estado em 08/09/2026

Em produção. A tela responde, no topo, **quantos produtos a conta cota** — antes ela dizia só
"Conectado", que não é a pergunta do corretor.

O que foi **medido** em 08/09: a stack hub2you roda a imagem `5787ed1bbeca…` (= `5787ed1`, o revert do
#348), lida do `docker ps` da instância `i-08e99d6608864590b`. A stack autonomia **não foi verificada**
daqui: ela vive na conta AWS 140023375763 e esta máquina só tem credencial da 354307071110 — nenhum
alvo `cw-auto-*` responde por este perfil. Quem conferir lá, confirme o mesmo SHA antes de tratar as
duas como iguais.

- **Produto com o nome do PORTAL**, não com o nosso slug. O ramo 46 é o caso: slug `fianca_locaticia`,
  portal "Aluguel". Fiança locatícia é outro produto no catálogo da AGGER (id 23, anotado em
  `capabilities.ts`) — o corretor lia na tela um produto diferente do que ia cotar. O slug não muda,
  porque já viajou para o banco; o rótulo passou a viajar junto.
- **Seguradora recusada aparece pelo nome**, com o custo dito. A string (`CAPABILITIES.MONEY_LEFT`)
  tem plural próprio: "Azul está fora por credencial recusada — uma seguradora a menos em cada
  cotação de Automóvel".
- **Contagem com denominador** ("N de M seguradoras", nunca só "N"), código do ramo ao lado do nome, e as cinco camadas de
  verificação num `<details>` fechado.
- A camada de credenciais responde **pelo scan**, carimbada com a data dele — antes dizia "não
  verificado" tendo o veredito três linhas abaixo.

### Handoff ("Abrir o AGGER logado") — ENCERRADO

O botão foi a produção em 08/09 e **saiu no mesmo dia** (#347, revertido em #348). Decisão do Rodrigo:
**não seguimos com isto no projeto.**

| | |
|---|---|
| Abre uma cotação existente já autenticada | **sim** |
| Derruba a sessão do agente | **não** — medido três vezes |
| Permite cotar do zero | **não** |

A terceira linha é a que encerra. A autenticação do link vale só para o componente de resultados:
recarregar a home leva a `/login`, e **clicar em "Cotações"** — navegação interna, sem reload — leva a
`/login` também.

**O portal não persiste sessão.** Sete gravações em `localStorage`, nenhuma de token ou credencial; o
mesmo no login normal. Isso elimina tanto "achar a rota que persiste" quanto "injetar a sessão": não há
chave onde escrever. Medição completa em `autonom-ia2/autonomia-adapters` →
`docs/agger/sessao-e-handoff.md` §5.

Saiu daqui tudo que só existia para o botão: rota, ação, `portal_link` nos connectors,
`record_last_quote!`, client JS e i18n. O comentário no ponto onde ele estava guarda o porquê.

**Não reabrir sem** SSO da AGGER, ou medição que contrarie a de 08/09.

## Medir para cobrar e para mostrar retorno (entrega 7, 11/09/2026)

**Dois números, nunca um.** Uma cotação aciona TODAS as seguradoras que a corretora habilitou — nas
três cotações reais da conta de teste lidas em 11/09/2026 (`agger quote result`) foram **dezessete**
em cada uma: renovação 11 cotaram + 6 recusaram; moto 2 + 15; caminhão 1 + 15 + 1 credencial
recusada. Contar execuções e chamá-las de consultas foi o erro do teto de "8 por hora" removido em
10/09 (8 execuções eram até 136 consultas).

**De onde sai o número.** Da linha da execução (`autonomia_agent_tool_runs`), que já registra o
número da cotação no portal e quem cotou. Desde esta entrega o handle guarda também
`seguradoras_acionadas` — os códigos de TODAS as seguradoras que o portal pôs na cotação, gravados a
cada consulta como UNIÃO (o portal responde em pedaços; a foto da última consulta apagaria
seguradoras já pagas). Nada de novo é consultado no portal: o dado já vinha no `quote/result`.

### Quem roda, e como

| Quem | Onde | O quê |
|---|---|---|
| Operação Autonom.ia (cobrar) | Super Admin → **Quote Measurement** (`/super_admin/insurance_measurement`) | todas as corretoras, uma linha cada, no período escolhido |
| Corretora / nós, pela conta (mostrar retorno) | `GET /api/v1/accounts/:id/autonomia/insurance/measurement` | a própria conta |

A página do Super Admin é o caminho **sem engenheiro**: abre, escolhe as duas datas, lê a tabela.
Sem token, sem `curl`, sem console. O endpoint da conta existe para a corretora ver o mesmo número
que a fatura dela usa — as duas superfícies leem a MESMA `Autonomia::Insurance::Medida`, porque dois
números diferentes para o mesmo mês, um na fatura e outro na tela do cliente, seriam pior do que
número nenhum.

```bash
# Setembro inteiro de uma conta. Sem `from`, os 30 dias que terminam em `to`; sem os dois, os que terminam hoje.
curl -s -H "api_access_token: $TOKEN" \
  "https://<host>/api/v1/accounts/16/autonomia/insurance/measurement?from=2026-09-01&to=2026-09-30"
```

```jsonc
{"payload": {
  "account_id": 16,
  "from": "2026-09-01T00:00:00-03:00", "to": "2026-09-30T23:59:59-03:00",  // a janela usada, de volta
  "timezone": "America/Sao_Paulo",  // em que fuso as datas foram lidas
  "quotes": 3,                  // cotações que EXISTEM no portal (o número voltou)
  "insurers_called": 51,        // 3 x 17 — a unidade que a corretora paga
  "insurers_with_price": 14,    // das acionadas, quantas devolveram preço
  "quotes_with_proposal": 0,    // COTAÇÕES que viraram proposta individual (termo 3): entrega 8 (ver abaixo)
  "proposals_issued": 0,        // soma dos códigos de seguradora com proposta — NÃO é a linha da fatura
  "unknown": {                  // o que a medida NÃO sabe, nunca somado nos totais
    "quotes_without_measure": 0,      // cotação aberta cujo nº de seguradoras não foi lido
    "quotes_without_confirmation": 0, // envio sem confirmação: pode existir no portal sem o nº aqui
    "quotes_possibly_duplicated": 0   // pode haver uma a mais no portal do que a contada
  }
}}
```

Gate: feature ligada + conta marcada + **administrador**, como todo endpoint do módulo. Data
ilegível responde `422 periodo_invalido` — nunca "então são os últimos 30 dias" em silêncio: um
número de cobrança de uma janela que ninguém pediu é pior do que erro nenhum. O formato é SÓ
`AAAA-MM-DD`, e o texto inteiro: `2026-09-01T10:00:00` também é 422, e não "01/09 a partir da
meia-noite" com a hora descartada em silêncio. Duas datas invertidas respondem "a data inicial é
posterior à final"; só `from`, e ainda no futuro no fuso da conta (`from=hoje` à 01h UTC para uma
corretora em São Paulo, onde ainda são 22h de ontem), responde "a data inicial está no futuro" — a
frase culpa a data que foi escrita, não uma final que ninguém mandou.

**Fuso.** As datas são lidas no `reporting_timezone` da conta (o mesmo dos relatórios do Chatwoot)
quando ela tem um; sem ele, no fuso da instalação. "Setembro" da corretora termina às 23h59 dela — ler
pelo nosso fuso jogaria para outubro toda cotação feita depois das 21h de 30/09 em São Paulo. A
resposta devolve `timezone` e os instantes exatos. A tela do Super Admin lê **cada corretora no fuso
dela** pelo mesmo caminho (`Medida#por_conta` monta uma `Medida.new(conta:)` por corretora) e mostra o
fuso na coluna de cada linha: é o que faz a fatura e a tela da corretora baterem no último dia do mês.
A corretora cujo dia ainda não começou no fuso dela (só `from`, nas primeiras horas UTC, fuso atrás
do da instalação) simplesmente não aparece na página nesse instante — é "nenhuma execução" para ela,
não erro da página inteira. E o relógio da instalação não decide o dia de ninguém nessa tela:
`from=amanhã` para a instalação já é hoje para a corretora em UTC+14, e a cotação dela aparece na
página com o mesmo 1/17 que a API da conta responde; se o dia não começou para nenhuma corretora, a
página diz "nenhuma cotação no período", não "período inválido". Só a API de UMA conta recusa data
inicial no futuro — no fuso dessa conta. Sem `from`, "30 dias" são trinta DATAS contando a final:
`to=2026-06-30` começa em 01/06, e a cotação das 23h de 31/05 é de maio.

### `quotes_with_proposal` é zero, e o contador é real

A ferramenta de **proposta por seguradora** é a entrega 8; ela ainda não existe, então nada escreve
o contador e ele lê zero em dado real. O contador em si está ligado: a medida lê
`InsuranceQuote::PROPOSTAS_KEY` (`propostas` no handle, os códigos das seguradoras cuja proposta
saiu) e devolve DOIS números, porque o termo 3 pergunta "quantas **cotações** viraram proposta
individual" e a soma dos códigos responde outra pergunta:

- `quotes_with_proposal` (`cotacoes_com_proposta`) — cotações cuja lista tem pelo menos um código.
  Uma cotação com duas propostas é UMA. **É a linha da fatura.**
- `proposals_issued` (`propostas_emitidas`) — a soma dos códigos. A mesma cotação conta dois.

**Ponto de registro da entrega 8:** o handle da execução, na passada que gerar a proposta —
`quote/proposal` com `insurer_code` é o caminho, e `comparison_pdf` já usa o mesmo endpoint SEM
código para o comparativo. Escrever a lista lá faz os dois contadores contarem sem mudar uma linha.

### Isto não é freio

A medida informa; quem decide volume é a corretora que paga. Nenhum caminho de cotação a consulta, e
`medida_nao_e_freio_spec` reprova (por AST, em `app/**` e no overlay `enterprise/app/**`) qualquer
referência à medida fora das superfícies de leitura. O teto de execuções continua não existindo, e a
guarda tem três partes: `async_config_sem_teto_de_execucoes_spec` pega a constante pelo nome;
`bound_async_spec` pega o comportamento no ACEITE (vinte execuções na última hora, 340 seguradoras, e
a vigésima primeira é aceita); `async_run_job_spec` pega o comportamento no JOB, onde a chamada paga
acontece (com as mesmas vinte, a submissão e a consulta seguem e a execução termina em `done`).

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
