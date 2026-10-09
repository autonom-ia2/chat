# Auditoria global 04/10 — criação e retomada de agentes

**Data:** 2026-10-09  
**Escopo:** Escolha → Conte (guiado, manual e materiais) → Teste → Ligue (múltiplas caixas) → Pronto; sair/retomar; deep links; rascunhos; invalidação; erros e indisponibilidade; conexão de WhatsApp pela área central de Canais.  
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Branch/HEAD:** `docs/agentes-ia-prd` / `532a5b7beb56902d2a0168013a3e8b657ba31488`  
**Responsável:** auditoria global 04 — criação e retomada

## Conclusão executiva

A estrutura visual da jornada aprovada está presente nas telas finais 54 e o código implementa os principais passos, inclusive seleção múltipla no Ligue, teste assíncrono e conexão de WhatsApp fora de Agentes. A auditoria estática encontrou **quatro P1 e dois P2** que precisam ser tratados antes de considerar a jornada pronta:

1. limpar a conversa não revoga a validade do teste;
2. mudar a apresentação deixa o histórico antigo visível e reutilizável;
3. terminar de adicionar/copiar material pode invalidar no backend sem atualizar o estado da tela;
4. agente criado pela API/Guia sem thread do Construtor não consegue entrar por E3/E4;
5. erro transitório ao carregar canais expulsa a pessoa para a lista;
6. com um único canal livre, a tela não o marca automaticamente.

Os três primeiros quebram a regra de que o teste representa a instrução e a conversa atuais. O quarto quebra a retomada prevista para agentes criados fora da tela nova. O quinto é uma falha de recuperação. O sexto é uma regressão de simplicidade e de aceite do Ligue.

## Evidência e limites

- Foram lidos o HANDOFF, o PRD nas seções indicadas e o documento de causas raiz C1–C15. As regras relevantes são PRD §6.2.3, §6.2.4, §6.6, BE-08/BE-11/BE-13 e CA-TES-05/CA-TES-09/CA-LIG-03/CA-LIG-09/CA-LIG-12.
- Foram inspecionadas as telas reais já capturadas na rodada final 54: `creation54/criacao-01-escolha-chromium-1440-light.png`, `criacao-02-conte-retomada-chromium-1440-light.png`, `criacao-04-teste-valido-chromium-1440-light.png`, `criacao-06-ligue-chromium-1440-light.png`, `criacao-10-sem-canal-chromium-1440-light.png` e `criacao-08-pronto-chromium-1440-light.png`. Elas comprovam a apresentação aprovada, mas são evidência histórica da fonte80; não substituem uma nova execução.
- A porta local da criação (`59720`) estava indisponível nesta rodada. Não iniciei serviço, navegador, banco, teste pesado ou rede de produção. Portanto, não afirmo que os gatilhos foram reproduzidos em runtime nesta rodada.
- A comparação de fonte, inventário e baseline foi coordenada pelo root em `.codex/preview/global-audit-20261009/`; este relatório não altera produto, snapshot, banco, branch, produção ou segredo.
- A auditoria visual usa capturas reais. Ela não é uma certificação completa de acessibilidade; teclado, leitor de tela, contraste e responsividade precisam do gate próprio.

## Achados

### CRI-01 — P1 — “Limpar conversa” mantém o teste válido

**Gatilho:** responder uma pergunta com sucesso e clicar em **Limpar conversa** no Teste.

**Mecanismo:** `AgentCreationPage.vue:291-294` zera somente `testMessages` e `testError`. Não altera `testValid`, `testResult` nem a sessão de teste no backend. O `useAgentCreation.js:550-551` mantém `testValid` em uma ref separada, e o `AgentTestPhone.vue:290-293` apenas emite o evento de limpeza. O botão de continuar depende de `testValid` (`AgentTestPhone.vue:302-305`).

**Efeito:** a pessoa vê a conversa vazia, mas o botão **Está bom, continuar** continua liberado; ela pode ir ao Ligue sem uma resposta concluída na conversa atual. Isso contraria PRD §6.2.3, §6.6 e CA-TES-05: teste válido é resposta concluída na conversa atual e limpar deve deixar a conversa sem validade.

**Ajuste mínimo sugerido:** centralizar “nova sessão de teste” em uma operação que limpe o transcript, revogue `testValid`/`testResult` e, se o contrato exigir, gere a sessão nova no backend. O botão só volta após nova resposta concluída.

**Confiança:** alta — fluxo estático direto e regra explícita do PRD. **Cobertura atual:** não há spec da combinação resposta válida → limpar → tentar continuar.

### CRI-02 — P1 — alterar a apresentação não reinicia o transcript

**Gatilho:** obter uma resposta válida, editar Nome ou Primeira mensagem no topo do Teste e salvar.

**Mecanismo:** `useAgentCreation.js:328-336` revoga `testValid` antes do PATCH, mas `AgentCreationPage.vue:268-277` só incrementa `presentationRevision`. O watcher de `AgentTestPhone.vue:175-184` atualiza apenas `savedName`/`savedGreeting`; ele não limpa `props.messages`. Em novo envio, `AgentTestPhone.vue:245-260` monta `history` com todo o transcript que ficou na tela.

**Efeito:** o gate impede a publicação imediata, mas a conversa antiga continua aparecendo e é enviada como histórico quando a pessoa testa de novo. O PRD exige que a anterior desapareça, que a conversa recomece e que a primeira resposta nova contenha a saudação nova (§6.2.3, linhas 201–204; §6.6, linhas 446–455; CA-TES-09).

**Ajuste mínimo sugerido:** quando o PATCH de apresentação vencer, emitir a mesma operação de nova sessão do CRI-01 antes de permitir novo envio; o histórico enviado deve ser o da sessão nova.

**Confiança:** alta. **Variação relacionada:** trocar Teste → Conte → Teste no mesmo agente também não limpa `testMessages`: o watcher de `AgentCreationPage.vue:388-402` só reseta estado quando muda o `agentId`.

### CRI-03 — P1 — material processado invalida no backend, mas a tela fica com projeção antiga

**Gatilho:** depois de um teste válido, anexar arquivo, colar link ou copiar material de outro agente e aguardar a ingestão/revisão.

**Mecanismo:** o front apenas cria/copía e recarrega a lista de fontes: `useAgentCreation.js:218-235` e `279-297`. `sources_controller.rb:20-28` e `161-166` enfileira a ingestão. Ao terminar, `ProcessJob:57-68` chama `MaterialProjection.invalidate_if_digest_changed!`, que invalida o teste atual em estado de rascunho (`material_projection.rb:23-30`). Porém, nenhum desses caminhos atualiza `autonomiaAgents/show` nem `testValid` na tela; o refresh do agente ocorre no teste (`useAgentCreation.js:304-319`) e no carregamento da entrada, não após o material.

**Efeito:** durante a janela de ingestão, a tela pode continuar mostrando a validade antiga e permitir avançar para Ligue. O backend deve recusar a publicação sem teste atual, mas a pessoa recebe a falha tarde, como `missing_test`, em vez de ver “aprendeu material novo; teste de novo” no Teste. O histórico antigo também pode continuar na tela. Isso contraria PRD §6.6, linhas 436 e 446–455, a mensagem de material da §6.2.3 e CA-LIG-12.

**Ajuste mínimo sugerido:** após attach/copy/link, atualizar a projeção do agente e observar o estado de material até a ingestão/revisão terminar; quando a versão/digest mudar, limpar a sessão do Teste, revogar o gate e mostrar o motivo. O servidor continua sendo o gate final.

**Confiança:** alta para a defasagem do front; a invalidação assíncrona do servidor está comprovada no código. **Gap:** sem job/serviço local nesta rodada, não medi o tempo entre criação, ingestão e atualização.

### CRI-04 — P1 — agente de API/Guia sem thread não retoma E3/E4

**Gatilho:** abrir diretamente `/build/test` ou `/build/live` para agente guiado criado pela API/Guia com instrução, mas sem conversa do Construtor.

**Mecanismo:** `AgentCreationPage.vue:347-364` carrega agente e canais e, para todo agente não manual, chama `resume(agentId)`. `BuildThreadsController#resume` (`build_threads_controller.rb:1247-1252`) procura a thread mais recente com `first!`. Não havendo thread, a exceção cai no `catch` de `AgentCreationPage.vue:380-384`, que alerta e redireciona para a lista.

**Efeito:** o agente previsto pelo PRD para entrar em E3 com instrução (“Legado e rascunhos sem conversa do Construtor”, §6.6, linhas 463–466) não chega ao Teste nem ao Ligue. A lista pode continuar mostrando E3/E4, mas o deep link falha.

**Ajuste mínimo sugerido:** tratar “sem thread” como estado válido para agente com instrução: carregar o agente, não chamar `resume` quando não há thread e permitir Teste/Ligue; reservar erro para falhas reais de autorização/rede. Alternativamente, criar uma sessão de teste explícita sem fabricar conversa do Construtor, conforme o contrato do estado.

**Confiança:** alta para o caminho de exceção; a existência de agentes API/Guia sem conversa é requisito explícito do PRD. **Cobertura atual:** não há caso de deep link sem thread no spec do entry.

### CRI-05 — P2 — falha de canais expulsa a pessoa da jornada

**Gatilho:** abrir uma etapa existente com uma falha transitória no GET de canais, mesmo com o GET do agente respondendo.

**Mecanismo:** `AgentCreationPage.vue:347-351` usa `Promise.all([loadAgent, loadChannels])`. Qualquer rejeição cai em `380-384`, que exibe alerta e faz `goToList()`. Não há retry contextual nem tela de erro dentro da etapa.

**Efeito:** uma falha de rede/canais deixa a pessoa fora de Conte, Teste ou Ligue, sem saber se o rascunho foi preservado. Isso é particularmente ruim para deep links e retomada; a lista tem retry, mas a etapa perdeu o contexto.

**Ajuste mínimo sugerido:** separar o carregamento obrigatório do agente dos dados opcionais de canais; manter a etapa, exibir erro localizado e oferecer retry. Em Ligue, o erro deve impedir publicar até atualizar os canais; em Conte/Teste, não deve bloquear a edição/teste quando canais não são necessários.

**Confiança:** média-alta — comportamento de rejeição e redirecionamento é direto; a natureza transitória depende do ambiente. **Cobertura atual:** sem spec de falha de `loadChannels` com `loadAgent` bem-sucedido.

### CRI-06 — P2 — um canal livre não é marcado automaticamente

**Gatilho:** chegar ao Ligue com exatamente um canal elegível e livre.

**Mecanismo:** `AgentBuildGoLivePage.vue:21` começa com `selectedChannelIds=[]`; o watcher `65-76` apenas remove seleções que deixaram de estar disponíveis. Não existe ramo para selecionar automaticamente o único canal. O spec atual afirma o comportamento oposto em `AgentBuildGoLivePage.spec.js:48-60`, esperando os dois canais inicialmente com `aria-checked="false"`.

**Efeito:** a pessoa precisa descobrir e clicar no único canal antes de ligar. O PRD/CA-LIG-03 exige um canal livre já marcado, e nenhum canal marcado quando há vários; a regra reduz uma decisão desnecessária para uma pessoa leiga.

**Ajuste mínimo sugerido:** no estado inicial da lista, selecionar o único canal livre; preservar seleção vazia quando houver dois ou mais. Atualizar o spec para cobrir 0/1/2+ canais e impedir remarcação indevida após refresh.

**Confiança:** alta. **Prova visual:** a captura `criacao-06-ligue...png` mostra a seleção múltipla final, mas não prova o caso de um canal; o contrato textual e o spec são suficientes para o achado.

## Relação com as causas raiz C1–C15

Esta classificação é do mecanismo observado nesta auditoria, não uma substituição da análise de causas:

- **CRI-01, CRI-02 e CRI-03:** C11 (regra por efeito não aplicada de forma única) e C3 (sessão/estado de criação não modelado de forma suficiente no front). CRI-03 também materializa C8: o sistema assíncrono muda o estado, mas a tela não acompanha o ator externo.
- **CRI-04:** C3 e C8. O contrato prevê E3/E4 sem thread, mas o entry deriva o caminho da existência de uma thread e o `resume` não diferencia ausência legítima de erro.
- **CRI-05:** C3 (recuperação da etapa não é estado persistente da jornada). O carregamento composto transforma uma falha de dependência em saída da jornada.
- **CRI-06:** C11 (variante de um canal livre não cruzada com a variante de vários canais) e C6 (desenho novo sem o mesmo passe de cobertura dos casos previstos).

## O que foi confirmado no escopo

- **Escolha:** o componente novo oferece as variantes previstas e segue a jornada de criação; não encontrei `<select>` nativo neste percurso.
- **Conte:** conversa, materiais anexados, links sugeridos e cópia de material usam componentes reais e estados de erro/retry locais. O Continue depende de `readyForTest`.
- **Teste assíncrono:** `useAgentCreation.js:299-326` chama o endpoint de teste e atualiza a projeção do agente após a resposta; o cliente de polling trata a resposta assíncrona. O achado CRI-02 é sobre sessão/histórico após mudança, não sobre o 202.
- **Ligue:** `AgentBuildGoLivePage.vue:80-98` aceita várias caixas e emite `inboxIds`; `ChannelRadioList` marca opções como checkbox. A captura final 54 mostra duas caixas escolhidas. A correção não deve colocar QR ou conexão de WhatsApp nessa tela.
- **Sem canal:** `AgentBuildGoLivePage.vue:254-264` mostra o atalho **Abrir Canais** quando não há opção elegível. Isso está alinhado ao PRD §6.2.4/CA-LIG-09 e à decisão D7; não há achado contra a conexão central.
- **Pronto:** a tela exibe confirmação, volta à lista e caminho de desempenho; a captura final 54 comprova o caso com duas caixas. Não atesto aqui o caso de interno/sem caixa em runtime.

## Cobertura e próximos gates

Antes de uma rodada de implementação, a revisão deve criar casos para:

1. resposta válida → limpar → botão bloqueado até nova resposta;
2. resposta válida → alterar nome/saudação → transcript limpo, primeira resposta nova e teste válido só depois dela;
3. material novo em pending/processing/ready/rejected → motivo visível e retorno ao Teste;
4. API/Guia com instrução e sem thread → deep link Teste/Ligue funcionando;
5. agente OK + canais 5xx/offline → etapa preservada, retry local e nenhum publish;
6. 0, 1 e 2+ canais livres, além de canal ocupado e seleção múltipla.

Esses casos precisam ser validados na tela construída, com capturas novas em ordem de jornada. O estado atual não permite declarar “zero regressões”: a prova visual é histórica e a porta local estava indisponível. Nenhum merge, fila, deploy ou produção foi executado ou solicitado neste relatório.
