# Handoff de IA para humano (CRM AI)

Quando o gatilho do funil é atendido, a conversa passa da IA para uma pessoa.
Configurado por pipeline/etapa em `metadata.ai.handoff` — a etapa sobrepõe o funil.

## O gatilho manda

O texto em `trigger` é quem decide o que conta. Ele pode ser satisfeito por:

- **fala do cliente** — *"quero falar com um atendente"*
- **fala do atendente ou do bot** — *"encaminhei seu pedido para a equipe"*

Escreva o gatilho descrevendo o que deve acontecer. Se ele fala de uma ação do
atendente, só conta encaminhamento **já afirmado**; oferta e condicional não
disparam (*"posso encaminhar se quiser"* não vale). Mensagem informativa de fila
ou rotina (*"aguarde"*, *"em breve retornaremos"*) também não conta por si só.

Com `trigger` vazio, vale o critério conservador: só pedido explícito do cliente.

## Modos

| `handoff_mode` | Comportamento |
|---|---|
| `r2_direct` (padrão) | atribui a conversa a um agente e silencia o bot |
| `r3_invite` | **não** atribui: adiciona como participante, notifica e abre um ciclo com prazo de pega (`pickup_threshold_seconds`, padrão 900s) |

## Seleção do agente

- `pool_type: inbox` — todos os membros da caixa
- `pool_type: user` + `pool_id` — uma pessoa específica
- `mode: round_robin` equilibra por conversas abertas; `direct` tenta casar o nome sugerido pela IA
- `prefer_online: true` restringe a quem está online

Se ninguém elegível está online, **o pedido não se perde**: fica guardado em
`metadata.ai.handoff_hold` e o `Crm::Ai::HandoffDrainJob` retenta a cada ~2 min,
atribuindo assim que alguém ficar disponível.

## Presença online — `PRESENCE_DURATION`

`prefer_online` depende da presença registrada no Redis, que o navegador renova
periodicamente. O padrão do upstream é **20s**, mas navegadores limitam timers de
abas em segundo plano a cerca de **1 execução por minuto** — com 20s o agente
aparecia offline durante boa parte do tempo, mesmo com o Chatwoot aberto.

Produção usa **`PRESENCE_DURATION=90`** (SSM `/chatwoot/prod/env`, ambas as contas),
que cobre o intervalo real de ~59s com folga. Aumentar demais faz quem fechou o
navegador continuar "online" e receber conversas sem estar lá.

O toggle **"Marcar offline automaticamente"** (`account_users.auto_offline`)
controla isso por usuário: ligado, a presença depende do ping do navegador;
desligado, vale o status escolhido no menu.

## Diagnóstico

Estado fica no card, em `metadata.ai`:

| Campo | Significa |
|---|---|
| `last_handoff_at` | quando o handoff aconteceu (cooldown de 6h) |
| `last_handoff_mode` | `direct` ou `invite` — origem do carimbo |
| `handoff_hold` | pedido guardado esperando alguém online |
| `handoff` / `handoffs` | ciclos de convite (só `r3_invite`) |

Erros aparecem no worker como `[CRM AI handoff]`. Atenção: o `Evaluator` captura
exceções para nunca quebrar a avaliação — uma falha no handoff **não** interrompe
o fluxo e só se manifesta no log.

**Cooldown.** Há uma janela de 6h entre handoffs do mesmo card. Ela é dispensada
quando alguém assumiu e a conversa voltou a ficar sem responsável — o operador
devolveu ao bot de propósito. No `r3_invite` isso é decidido pelo ciclo
(`picked_up_at`); no `r2_direct`, por `last_handoff_at` + conversa sem responsável.

Chaves de presença no Redis usam prefixo `alfred:`:

```
alfred:ONLINE_PRESENCE::<conta>::USERS   sorted set, score = epoch do último ping
alfred:ONLINE_STATUS::<conta>            hash, user_id => online|busy|offline
```

## Armadilha de namespace

`Crm::Ai::HandoffExecutor` usa a forma aninhada (`module Crm; module Ai`), então
constantes são resolvidas pelo escopo léxico. Como existe `Crm::Conversations`,
referenciar `Conversations::AssignmentService` sem `::` resolve para
`Crm::Conversations::AssignmentService` e levanta `NameError`. Sempre use `::`
para constantes de raiz dentro desse namespace. Arquivos em forma compacta
(`class Crm::FollowUps::X`) não têm esse problema.
