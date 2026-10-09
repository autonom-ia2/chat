# Auditoria global de linha de base — Agentes de IA (baseline 03)

**Data da leitura:** 2026-10-09 (America/Sao_Paulo)  
**Worktree alvo:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Branch:** `docs/agentes-ia-prd`  
**HEAD local observado pelo coordenador:** `532a5b7beb56902d2a0168013a3e8b657ba31488`

## Escopo e limite desta rodada

Esta auditoria foi aberta como linha de base independente antes de qualquer PR. Ela deve comparar o candidato local com o estado atual e verificar cobertura dos blocos do redesign, chamadas entre frontend/backend e risco de regressão do fluxo existente.

Na primeira tentativa, o processo local atingiu o limite do sistema para abrir processos (`Too many open files`, erro 24). Depois, com o filesystem local disponível, li e conferi os recibos gerados por comandos read-only do coordenador: inventário, deriva de `main`, GitHub, deployments, comparação com `main`, congelamento da fonte 80 e localização dos snapshots. Não houve fetch, merge, rebase, reset, push, consulta a hosts de produção, banco, logs de cliente, secrets ou navegador real. A conclusão abaixo é uma linha de base delimitada; não atesta ausência universal de regressões.

## Evidência de checkout recebida

O coordenador registrou o inventário inicial do mesmo checkout em:

`/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd/.codex/preview/global-audit-20261009/inventory.json`

O inventário contém 518 caminhos expandidos: 195 rastreados e 323 não rastreados. O contador visual do `git status` foi reportado como 422 diretórios; ele não deve ser confundido com a contagem de caminhos do inventário. O checkout está muito sujo, portanto a comparação de regressão precisa usar a lista completa e separar redesign, mudanças compartilhadas e alterações alheias.

O SHA completo de `origin/main` foi confirmado no recibo GitHub como `28e1e0ac8b3835577f7469368f03a86d1a8dab0d`. O candidato local está 136 commits atrás; `main` mudou 666 caminhos desde a base local. Há 16 caminhos sobrepostos entre a deriva de `main` e o checkout, dos quais 15 estão classificados como sobreposição de produto. Essa sobreposição é risco de integração e precisa ser revisada antes de um PR; não autoriza rebase automático.

## Estado candidato local conhecido

O candidato local de gestão foi consolidado na fonte 80, com o mesmo HEAD acima e content SHA `f42aa58719a8923091ab565bd5903ad5c4d3e5b7e9841aa762a88179cf94c077`. O recibo anterior informa:

- 200 verificações de frontend/build;
- 276 exemplos de backend e formatos válidos;
- 42 arquivos de lint sem offenses na fonte 80;
- 124 jornadas de navegador em quatro perfis, 196 capturas e 18 destinos do portal;
- revisão independente R3 aprovada, sem R4;
- nenhuma migration nova no escopo da gestão;
- dados, IA e integrações usados na galeria são fictícios e locais.

Esses números são evidência de execução anterior e foram recebidos como recibo; não foram reexecutados aqui e não constituem prova de produção ou CI.

## Cobertura funcional e arquivos de risco

Os arquivos funcionais que o recibo anterior identifica como parte do candidato são:

| Área | Arquivos/ponto de entrada conhecido | Risco de regressão a conferir |
| --- | --- | --- |
| Citação e persistência | `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/panel/SettingsQuote.vue` e spec da mesma área | retorno completo do agente, estado local, segundo PATCH sem GET e preservação de horário |
| Handoff por equipe | `app/services/autonomia/agents/operate/handoff_router.rb` e `spec/services/autonomia/agents/operate/handoff_router_spec.rb` | agente nativo aberto, mesma equipe, equipe diferente, equipe desligada, fora da equipe, caixa fora do inbox e ausência de elegíveis |
| Atribuição online | `app/services/auto_assignment/agent_assignment_service.rb` e spec correspondente | coleção vazia do tracker deve resultar em lista vazia, sem alterar o caminho concorrente existente |
| Jornada e gestão | componentes das abas O que sabe, Onde atende, Ajustes, Testar e Ferramentas | chamadas, permissões, retorno de rota, seleção de múltiplas caixas e alinhamento do composer |
| Integração de canal | área central de Canais | conexão WhatsApp continua central; não criar QR/conexão dentro de Agentes |

O recibo relata correções anteriores de sete achados R1 e dois P1 de R2, além de preservação do composer e de múltiplas caixas existentes. O registro P1 de acesso/observabilidade ocorrido na rodada anterior é um problema da própria auditoria, não um bug do produto, e não entra como regressão. Isso reduz o risco conhecido, mas não substitui uma comparação independente com o estado efetivamente ativo hoje.

Depois da abertura deste relatório, o coordenador registrou a prova local `working-vs-source80.json`: a fonte 80 existe no M4 e 367 arquivos fora de `docs/` foram comparados por SHA-256, sem diferenças. Essa prova sustenta que nenhum código mudou desde o congelamento da fonte 80; ela não cobre a comparação com produção nem elimina as alterações documentais e não rastreadas do checkout.

## Matriz de blocos

Com os materiais disponíveis nesta rodada, a matriz segura é:

| Bloco | Evidência disponível | Situação de baseline |
| --- | --- | --- |
| F1 — lista e retomada | prévias locais anteriores e recibos de jornada | evidência local anterior; chamadas e permissões ainda precisam de conferência de contrato |
| F2–F3 — criação | recibos de criação e jornada | evidência local anterior; sem prova de runtime em produção |
| F4 — casca e resumo | recibo F4 e correções preservadas | evidência local anterior; sobreposição com `main` precisa de revisão de integração |
| F5 — O que sabe | fonte 80, 49 estados por perfil | evidência local anterior; sem atestado universal de regressão |
| F6 — Onde atende | fonte 80, cenários de múltiplas caixas | evidência local anterior; conexão permanece em Canais |
| F7 — Ajustes, Testar e Ferramentas | fonte 80, 18 destinos e 124 jornadas | evidência local anterior; backend/frontend e rotas precisam da leitura Git completa |

O material de retomada organiza o redesign em F1–F7; não há base segura neste parecer para inventar uma nomenclatura B1–B? diferente. A cobertura acima é a que pode ser atestada sem transformar recibos de implementação em cobertura inventada.

## Produção e release

Os metadados read-only do GitHub mostram a última referência de `main` e os dois deployments de produção associados ao SHA `28e1e0ac8b3835577f7469368f03a86d1a8dab0d`: deployment 6943966962 corresponde ao workflow `Deploy Hub2You Chatwoot Blue Green`, e deployment 6943966912 corresponde ao workflow `Deploy Autonomia Chatwoot Blue Green`; ambos têm estado `success` nos recibos, atualizados em 2026-10-08. Isso identifica a última release comprovável por metadados de implantação. Não prova o SHA efetivamente servido em runtime, porque não consultamos hosts, health checks autenticados ou dados de produção.

Logo:

- `HEAD` local não é release de produção;
- `origin/main` é a referência da última implantação registrada, mas não é prova independente do runtime;
- os recibos locais não provam CI verde para o candidato `532a5b7b`;
- não é possível afirmar “zero regressão em produção”;
- o pacote de release continua bloqueado até a checagem de CI, PR e implantação pela Automação.

## Estado dos gates da linha de base

1. **Concluído:** inventário read-only do checkout e SHA completo de `main`.
2. **Concluído:** metadados read-only dos dois deployments; runtime de produção continua não verificado.
3. **Concluído para o congelamento local:** `working-vs-source80.json` e `freeze-check-progress.json` registram 367 arquivos fora de `docs/` comparados por SHA-256, sem diferenças. Isso mostra que o checkout continua igual à fonte 80 nesses arquivos.
4. **Pendente:** classificar os 16 caminhos sobrepostos com `main` e separar definitivamente código do redesign, mudança compartilhada e trabalho alheio no inventário de 518 caminhos.
5. **Pendente:** fazer a conferência independente de contrato frontend/backend e de regressão funcional contra o comportamento ativo. Os recibos R3 e os testes locais são evidência anterior, não esse gate.

## Localização e proveniência dos snapshots

O snapshot fonte 80 (`20261008-203511-532a5b7b-f42aa58719-03f5a091`) está presente no M4 e no M2. O snapshot fonte 79 (`20261008-203022-532a5b7b-98d871bed3-0f5e2ad6`) está presente no M2, mas não no M4. O recibo de localização confirma que não houve cópia, restauração ou exclusão; a ausência da réplica local do M4 não invalida os recibos já executados no M2. Essa distinção evita tratar “snapshot ausente neste nó” como falha do produto.

Até os itens pendentes, o status correto é **baseline delimitada, com integração e runtime ainda não comprovados**. O recibo local R3 aprovado continua válido como evidência da execução anterior, mas não autoriza merge, fila, deploy ou produção.
