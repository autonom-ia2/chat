# Auditoria global 05/10 — gestão de Agentes de IA

**Data:** 2026-10-09  
**Escopo:** jornada completa de gestão: lista → painel → O que sabe/FAQ → Testar →
Onde atende → Ajustes → Versões → Ferramentas → pausar/ligar/excluir; estados,
permissões, persistência, retomada, confirmações, falhas assíncronas e variantes
`external`, `internal`, `both` e `insurance_quote`.  
**Worktree auditada:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Branch/HEAD observado:** `docs/agentes-ia-prd` / `532a5b7beb56902d2a0168013a3e8b657ba31488`

## Resultado

A jornada de gestão do redesign tem cobertura funcional e visual suficiente nas
evidências locais disponíveis: 124/124 verificações nativas em quatro perfis,
196 capturas (49 estados × desktop/mobile × claro/escuro), 18 destinos do
portal com autenticação HTTP 200, erro de página vazio e a tela de múltiplas
caixas confirmada. O fluxo de Testar mostra a caixa de mensagem e o botão de
envio alinhados nas capturas finais. A conexão de uma segunda caixa aparece em
`gestao-08a-canais-multiplos-...` e permanece fora do fluxo de QR, como exige o
PRD.

Não repeti a suíte de escrita da jornada: ela já consta no recibo canônico F4/F5–F7
e a verificação nova foi somente leitura. O verificador fresco do portal terminou
com `verified=true`, `snapshotGuard=true`, branch, HEAD, banco e hash do snapshot
corretos; não iniciou serviço nem alterou fixture. Isso sustenta a gestão local,
mas não é prova universal de ausência de regressão em produção.

## Achados que bloqueiam a entrega

### P1-GEST-01 — a árvore candidata perde a API ativa do Autonom.ia Connect Agents

- **Arquivo/linha:** `config/routes.rb:67-99` (árvore candidata). O bloco
  `api/v1/autonomia/connect/agents` não existe nessa árvore. Na base atual de
  referência `28e1e0ac8b`, ele está em `config/routes.rb:69-76`.
- **Gatilho:** qualquer chamada do conector para
  `GET /api/v1/autonomia/connect/agents/accounts`, `POST .../integration`,
  `POST .../integration/rotate` ou `DELETE .../integration` depois de um
  deploy produzido a partir desta árvore.
- **Efeito:** a rota deixa de alcançar
  `app/controllers/api/v1/autonomia/connect/agents_controller.rb`; a conta não
  pode ser listada, o token não é provisionado/rotacionado e a revogação falha
  como rota inexistente. O contrato e os casos estão cobertos pelo spec
  `spec/enterprise/requests/api/v1/autonomia/connect/agents_spec.rb` na base.
- **Causa raiz:** a branch está 136 commits atrás da base usada nesta auditoria
  e `config/routes.rb` é um caminho em sobreposição. A preparação do redesign
  carregou a árvore antiga e, ao mesmo tempo, adicionou as rotas novas de
  Agentes; a diferença da base atual remove o bloco do conector. É drift de
  integração, não uma decisão do redesign.
- **Correção mínima proposta:** bloquear o PR até reconciliar a branch com a
  base vigente, preservando explicitamente o bloco de Connect e validando as
  quatro rotas junto com as rotas novas de Agentes. Não resolver apagando o
  bloco ou aceitando um diff de `config/routes.rb` que o remova.
- **Confiança:** alta. Evidência direta por comparação de árvore e pelo
  controller/spec existentes na base `28e1e0ac8b`.

### P1-GEST-02 — operações interativas Meta Ads são descartadas pelo serviço

- **Arquivo/linha:** `app/services/crm/ai/interactive_operation.rb:16-42` da
  árvore candidata não autoriza nem executa `meta_ads_daily_action` e
  `meta_ads_quote_message`. Na base `28e1e0ac8b`, os casos existem nas linhas
  24-25 e 42-43, com autorização e implementação nas linhas 103-142.
- **Gatilho:** uma solicitação assíncrona existente com `operation` igual a
  `meta_ads_daily_action` ou `meta_ads_quote_message` após o deploy da árvore
  candidata.
- **Efeito:** `authorize!` cai em `unknown_interactive_operation`; a operação
  não chega ao resultado do painel/WhatsApp. Os controllers e specs ativos da
  base são `app/controllers/api/v1/accounts/crm/meta_ads_ai_controller.rb`,
  `meta_ads_advisor_actions_controller.rb`,
  `meta_ads_whatsapp_reports_controller.rb` e os specs correspondentes.
- **Causa raiz:** o mesmo drift de base do achado P1-GEST-01. O redesign
  introduziu o módulo de teste de Agentes no serviço, mas a árvore também ficou
  sem as operações Meta Ads que a base atual já usa. O caminho removido aparece
  na comparação contra `28e1e0ac8b`; não há evidência de que essa remoção faça
  parte do escopo de Agentes.
- **Correção mínima proposta:** reconciliar a base antes do PR e manter os dois
  casos Meta Ads e seus helpers; rodar os três specs Meta Ads e o spec do fluxo
  assíncrono de Agentes depois da integração. Não aceitar a remoção como efeito
  colateral da reorganização do serviço.
- **Confiança:** alta. Os casos, controllers e specs existem na base atual; a
  árvore candidata não contém os casos.

## Evidência e limites

- Capturas de referência auditadas: `.codex/preview/agents/screenshots/gestao/source80-final/gestao-02-conhecimento-estados-chromium-1440-light.png`,
  `gestao-08a-canais-multiplos-chromium-1440-light.png` e
  `gestao-23h-teste-material-handoff-chromium-1440-light.png`, além do conjunto
  completo indicado no recibo canônico.
- A rodada fresca do portal registrou apenas ruído de shell já conhecido:
  `GET /enterprise/api/v1/accounts/1/limits` respondeu 404,
  `GET /api/v1/accounts/1/crm/follow_ups/reminders` respondeu 401 e houve
  `POST /auth/sign_in` abortado durante redirecionamentos. As 18 autenticações,
  perfis e painéis esperados foram 200; `pageErrors=[]`. Não classifiquei esses
  requests genéricos como defeito do redesign sem evidência de impacto na
  jornada.
- A auditoria não executou banco de produção, não alterou dados, não executou
  QR/conexão real, não fez merge/deploy e não declarou aceite visual do Rodrigo.

## Parecer

**Pendente / bloqueado para PR:** a gestão de Agentes está coberta no escopo
local, incluindo múltiplas caixas e Testar, mas a árvore candidata precisa
primeiro recuperar os dois contratos de produção acima. Depois da reconciliação,
repetir somente as verificações específicas desses contratos e a rodada de
revisão prevista no handoff; não repetir a suíte inteira sem novo achado.
