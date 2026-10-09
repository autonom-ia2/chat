# Auditoria global — correções G01–G06 — R1 independente

**Data:** 09/10/2026  
**Escopo:** somente G01–G06 da auditoria global. Esta é uma R1 nova; não reabre F4/F5–F7, Composer, multicaixas nem outros achados fora do bloco.  
**Worktree lida:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Branch/HEAD observado:** `docs/agentes-ia-prd` / `532a5b7beb56902d2a0168013a3e8b657ba31488`  
**Fonte:** working tree compartilhada com implementação ainda não congelada em um commit próprio; o HEAD é a identificação do baseline, não um hash de conteúdo final.  
**Revisor:** independente do autor. Nenhum código de produto, spec, snapshot, banco, serviço, Git, PR ou ambiente de produção foi alterado por esta revisão.

## Veredito R1

**R1 reprovada como pacote de validação até corrigir o achado P1 abaixo.** A implementação lida para G01, G03, G04, G05 e G06 não apresentou defeito funcional confirmado na leitura estática. G02 também tem o caminho novo coerente com o PRD, mas conserva um teste de integração legado que aprova explicitamente o comportamento que o redesign precisa retirar. Enquanto esse teste permanecer, a suíte pode ficar verde sem exercitar a rota nova e sem detectar o redirecionamento indevido.

Depois de corrigir o spec, a próxima etapa é a **mesma R2**. Se a R2 voltar a falhar, deve-se parar para causa raiz e fazer a R3 final; outra reprovação encerra o bloco sem nova rodada. Este parecer não autoriza PR, merge, fila, deploy ou produção.

## Achado acionável

### P1 — G02: teste de integração legado aprova o redirecionamento proibido

**Gatilho:** executar o caso de hidratação com resposta 401 ou 404 no spec `app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentsContinue.integration.spec.js:246-272`.

**Evidência:** o arquivo importa o `AgentPanelPage` antigo (`:5-6`), monta a rota antiga `autonomia_agent_build` com esse painel (`:77-110`) e espera que 401/404 mande a pessoa para `autonomia_agents_index` (`:261`). Também espera a chave removida `AGENTS.V2.errors.resume` (`:262`). Esse teste não monta `AgentCreationPage`, que é a entrada atual da jornada.

**Contrato atual lido:** `app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.vue:417-427` reserva a retomada ao passo **Conte** e mantém a etapa com erro localizado/retry quando a retomada falha. A chave usada é `AGENTS.CREATION.errors.resume`. Para Teste/Ligue, o arquivo não chama `resume`; a hidratação do agente permanece separada da leitura de canais.

**Efeito:** o teste valida a implementação antiga, contradiz B3/PRD §6.6 e pode produzir um falso verde mesmo que a rota nova volte a expulsar a pessoa para a lista. A cobertura canônica também fica sem a prova integrada de permanecer em `build/:step`, preservar o agente/contexto, exibir o erro e não chamar `start`/criar uma thread artificial.

**Causa raiz:** duplicação de contrato durante a migração: a página nova foi corrigida, mas o spec de continuação ficou preso ao painel, rota e chave de tradução anteriores. O problema é de alinhamento do teste com a fonte oficial da jornada, não uma evidência de que o código novo ainda redirecione.

**Correção mínima exigida:** migrar o caso para `AgentCreationPage`/rota nova e afirmar permanência na etapa, erro localizado, retry e ausência de `autonomiaBuildThreads/start`. Se a rota antiga continuar coberta por compatibilidade, separar esse caso e não usá-lo como prova do contrato G02. Não voltar a aceitar 401/404 como redirecionamento automático.

**Base:** PRD §6.6 e B3; `docs/audit/2026-10-09-agentes-global-consolidado.md:31`; `docs/audit/2026-10-09-agentes-global-06-contratos-criacao.md:31-45`. **Confiança:** alta.

## Resultado por correção

### G01 — renovar o teste após mudar a apresentação

**Status estático:** sem achado funcional confirmado.

`useAgentCreation.js:339-353` só invalida `testValid` e `testResult` depois que o PATCH de nome/saudação aceita a alteração. `AgentCreationPage.vue:284-303` incrementa `presentationRevision` e impede o avanço sem um novo teste. `AgentTestPhone.vue:179-188` limpa a sessão visível, zera a última pergunta e mostra o aviso localizado quando a revisão muda. Isso atende PRD §6.2.3/CA-TES-09 no caminho lido.

**Limite:** os specs lidos verificam invalidação, evento de limpeza e aviso; não há, nesta revisão, execução de browser nem prova integrada de uma resposta atrasada chegando depois de uma edição. Não trato essa lacuna como defeito confirmado sem reprodução.

### G02 — entrada, retomada e carregamento de canais

**Status do produto lido:** caminho novo coerente, com o P1 de validação acima.

`AgentCreationPage.vue:381-389` carrega canais somente em `live` ou `ready`, nunca em `tell`/`test`; `:417-430` chama `resume` apenas em `tell` para agentes não manuais; `:432-447` mantém falha de canais dentro da etapa e oferece retry. O carregamento em `ready` é necessário para hidratar os nomes das caixas quando a tela “Pronto” é aberta diretamente, pois o PRD §6.2.5 exige mostrar o canal. Reduzir sem prova para `live` apenas quebraria essa reabertura.

**Cobertura lida:** `AgentCreationPage.spec.js:273-290` cobre API/Guia no Teste sem `resume`; `:292-322` cobre 404 de retomada permanecendo em Conte; `:324-344` garante que Teste não busque canais; `:346-381` cobre retry de canais no Ligue. O spec legado do P1 continua contraditório.

### G03 — caixa única e múltiplas caixas

**Status estático:** sem achado funcional confirmado.

`AgentBuildGoLivePage.vue:66-98` marca automaticamente a única caixa elegível, começa vazio quando há duas ou mais e preserva uma escolha explícita durante atualizações da lista. `:102-121` permite marcar/desmarcar várias caixas e envia todos os `inboxIds`; o caminho interno envia lista vazia. `AgentBuildGoLivePage.spec.js:48-116` cobre as variantes de uma e várias caixas. A regra de conexão continua fora de Agentes, conforme D7.

### G04 — confiança da base de conhecimento legível

**Status estático:** sem achado funcional confirmado.

`PanelKnows.vue:43-65` lê `agent.config.knowledge_confidence`, limita apenas a apresentação a 0–100 e rotula a qualidade; não calcula a confiança a partir da contagem de materiais. O template separa barra/aria-label de confiança (`:233-267`) do contador “N de 30 materiais” (`:269-285`). As chaves existem em inglês e pt-BR (`agents.json:372-378`). Os limiares 70/40 são usados apenas para o rótulo textual; o spec lido cobre o caso representativo de 71%, sem execução independente dos limites. Não encontrei conflito com CA-SAB-01.

### G05 — aba ativa no celular

**Status estático:** sem achado funcional confirmado.

`AgentPanelShell.vue:71-92` leva a aba ativa à área visível na montagem, na troca de aba e na mudança de rota, sem tomar foco. `:94-115` mantém navegação por setas/Home/End e só depois foca a nova aba. O tablist mantém `overflow-x-auto`, alvo mínimo e atributos ARIA em `:242-263`. A leitura atende o requisito de G05 para a variante móvel; não foi feita nova captura nesta R1.

### G06 — gatilho para a recusa registrada

**Status estático:** sem achado confirmado; execução Ruby pendente.

`spec/services/autonomia/agents/tools/recusa_registro_spec.rb:271-280` registra o ID estável `answerer.rb#skip_test_tool#1` com uma sequência realista: registra a ferramenta assíncrona, faz o modelo devolver a chamada e executa `Autonomia::Agents::Playground` na superfície de Teste. `spec/support/async_tool_helper.rb:103-110` limita o catálogo ao slug dessa ferramenta. A varredura AST (`spec/support/varredura_de_recusas.rb:78-104`) é a fonte dos IDs e não foi relaxada.

**Limite:** não alego que o RSpec, a prova RED anterior ou a bateria Ruby foram executados por esta revisão. A validação Ruby final informada pela coordenação está bloqueada pelo CLI do MacCluster exigir `manifestv2 sha256-workspace-v2`, enquanto os manifestos disponíveis são v1. Isso mantém G06 como leitura estática, não como aprovação de runtime.

## Evidência e limites da rodada

- Código, specs e contratos foram lidos na worktree indicada. O working tree contém alterações de várias frentes e não estava congelado em um commit próprio; por isso o HEAD informado acima não é um content-SHA final.
- Não executei RED, RSpec, browser, serviço local, banco, rede de produção ou provedor de IA nesta revisão. Não afirmo telas novas aprovadas.
- A coordenação informou uma execução JS no M4 de 225/225 em 40 arquivos; isso é recibo externo a esta leitura e não substitui a validação Ruby, as capturas novas ou a prova integrada do G02.
- A incompatibilidade do manifest do MacCluster é um bloqueio de infraestrutura de validação. Não deve ser contornada com migração improvisada, `allowlegacy`, novo snapshot sem necessidade ou bypass.
- Não houve merge, enfileiramento, deploy ou alteração em produção.

## Ação para a R2

1. Atualizar o spec legado do P1 para a rota/página nova e eliminar a expectativa `AGENTS.V2.errors.resume`/redirecionamento automático.
2. Reexecutar a validação oficial na fonte congelada que a coordenação fornecer, distinguindo testes realmente executados, capturas vistas e limitações do MacCluster.
3. Fazer a mesma R2 com este revisor. Se ainda falhar, parar, registrar a causa raiz e voltar uma única vez para a R3 final; nova reprovação encerra o bloco.
