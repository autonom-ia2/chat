# Auditoria global — correções G01–G06 — R2 do mesmo revisor

**Data:** 09/10/2026  
**Escopo:** mesma R2 do bloco G01–G06. Não reabre F4/F5–F7, Composer, multicaixas ou achados fora deste bloco.  
**Worktree lida:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Branch/HEAD observado:** `docs/agentes-ia-prd` / `532a5b7beb56902d2a0168013a3e8b657ba31488`  
**Fonte:** working tree compartilhada; o HEAD é o baseline e não um content-SHA final, pois a implementação continua sem commit próprio congelado.  
**Revisor:** o mesmo da R1, independente do autor. Nenhum código de produto, banco, serviço, Git, PR ou produção foi alterado nesta revisão.

## Veredito

**R2 aprovada para o bloco de código e para a evidência JavaScript fornecida. Não há novo achado P0–P2 acionável em G01–G06.** O P1 da R1 foi corrigido no spec canônico de continuação. Não abro R3 por falha de código: a próxima etapa é somente fechar os gates de runtime/visual/Ruby dentro da infraestrutura disponível.

Esta aprovação é limitada ao código lido e aos recibos indicados abaixo. Não é aprovação de telas reais, CI completo, PR, merge, fila, deploy ou produção.

## Correção do P1 da R1 — G02

`app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentsContinue.integration.spec.js` agora importa e monta `AgentCreationPage` na rota `autonomia_agent_build` (`:7`, `:91-98`). O caso de erro 401/404 (`:321-367`) confirma:

- permanência em `autonomia_agent_build` no passo Conte;
- agente/contexto ainda visível e retry disponível;
- alerta `AGENTS.CREATION.errors.resume`;
- uma chamada de `resume` e nenhuma chamada de `autonomiaBuildThreads/start`;
- retry sem redirecionamento.

O spec mantém o painel legado apenas no caso explícito E2m manual (`:100-116`, `:369-387`). Os casos E3/Teste e E4/Ligue (`:282-319`) não chamam `resume` nem `start`; o caso Teste confirma também que não busca canais (`:310-313`). Isso alinha a cobertura com PRD §6.6/B3 e elimina a expectativa antiga `AGENTS.V2.errors.resume`/redirecionamento.

Não encontrei outro uso dessa expectativa antiga no spec corrigido. O achado P1 da R1 está encerrado.

## Resultado por correção

### G01 — renovar o teste após mudar a apresentação

**Aprovado na leitura estática.** `useAgentCreation.js:339-353` invalida `testValid` e `testResult` depois do PATCH aceito. `AgentCreationPage.vue:284-303` cria a nova revisão e impede seguir sem novo teste. `AgentTestPhone.vue:179-188` limpa a conversa visível, zera a última pergunta e mostra o aviso localizado. O contrato PRD §6.2.3/CA-TES-09 está preservado.

### G02 — entrada, retomada e canais

**Aprovado no código e no spec corrigido.** `AgentCreationPage.vue:381-389` busca canais só em `live`/`ready`, nunca em `tell`/`test`; `:417-430` reserva `resume` a Conte; `:432-447` mantém erro de canais na etapa com retry. `ready` continua necessário para hidratar os nomes exigidos pela tela Pronto do PRD §6.2.5. Não há motivo para reduzir a busca a `live` apenas.

### G03 — caixa única e múltiplas caixas

**Aprovado na leitura estática.** `AgentBuildGoLivePage.vue:66-98` seleciona a única caixa elegível, deixa múltiplas caixas sem seleção inicial e preserva a escolha explícita. `:102-121` permite várias caixas e envia todos os `inboxIds`; o modo interno envia lista vazia. O spec cobre uma, várias, desmarcação e atualização da lista.

### G04 — confiança da base de conhecimento

**Aprovado na leitura estática.** `PanelKnows.vue:43-65` usa `agent.config.knowledge_confidence`; a barra rotulada (`:233-267`) fica separada do contador de materiais (`:269-285`). Não há cálculo de confiança a partir de materiais. Inglês e pt-BR têm as chaves de rótulo. O spec cobre o caso representativo de 71%; os limites 70/40 não foram executados independentemente nesta revisão, sem defeito confirmado.

### G05 — aba ativa no celular

**Aprovado na leitura estática.** `AgentPanelShell.vue:71-92` revela a aba ativa na montagem, na troca de aba e na mudança de rota; `:94-115` preserva teclado e foco. O tablist usa rolagem horizontal interna em `:242-263`. Não há regressão introduzida no contrato de G05.

### G06 — gatilho da recusa registrada

**Aprovado estaticamente; execução Ruby ainda pendente.** `recusa_registro_spec.rb:271-280` contém o gatilho determinístico de `answerer.rb#skip_test_tool#1` pela superfície Playground/Teste, e `async_tool_helper.rb:103-110` restringe o catálogo ao slug correto. A varredura AST continua sendo a fonte dos IDs e não foi relaxada.

## Recibos e limites

- A coordenação informou execução JavaScript no M4: **227/227 em 40 arquivos, 11,78 s, exit 0**.
- A coordenação informou ESLint final com **0 erros e 159 warnings**, i18n com **13 catálogos/21.238 mensagens**, Guia com **196 fluxos, 189 telas e 0 sem explicação**, e build Vite de **40,90 s**. Um comando combinado havia retornado `exit 1` por formatação; a formatação foi corrigida e o ESLint final ficou sem erros. Registro tratado como recibo da coordenação, não como execução feita por este revisor.
- Ruby teve apenas checagem de sintaxe informada como OK; **RSpec não foi executado** nesta R2.
- A recaptura visual continua bloqueada pelo CLI do MacCluster exigir `manifestv2 sha256-workspace-v2`, enquanto os snapshots disponíveis são v1. Não houve bypass, migração improvisada, nova cópia ou declaração de telas aprovadas.
- Não executei RED, browser, serviço local, banco, rede de produção ou provedor de IA nesta revisão. Não afirmo aprovação visual nem funcional em produção.
- Não houve merge, enfileiramento, deploy ou mutação de produção.

## Encerramento

O P1 da R1 foi corrigido e não apareceu uma nova causa raiz no mesmo bloco. **Não iniciar R3 por este parecer.** Permanecem apenas os gates separados de Ruby, recaptura visual e qualquer validação de release; eles devem ser registrados com sua fonte, SHA, resultado e limite, sem transformar esta R2 de código/JS em aprovação de entrega.
