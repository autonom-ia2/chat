# B3/BE-05 — causa raiz da revisão normal de código

**Data:** 2026-10-07
**Alvo:** snapshot 23 em `/Users/Shared/maccluster-workspaces/chat2you/20261007-184308-532a5b7b-9803329751-205ae53c/src`
**SHA do alvo:** `9803329751ae3fce6fd8cec442e77faa9170b38434587aac62a8e81438e480ad`
**Escopo:** revisão normal única de código da subfatia BE-05/B3.
**Estado:** PARADO; nenhum código de produto foi alterado nesta revisão.

## Causa registrada antes de qualquer correção

O desenho B3 fechou a retomada como um fluxo completo: o painel existente deve chamar o GET nested, abrir somente depois da hidratação, exibir a thread real e enviar na mesma thread. A implementação do backend, do cliente API e da ação de store foi adicionada, mas o consumidor real do botão **Mudar conversando** permaneceu no fluxo legado.

Em `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelTune.vue:209-214`, o comentário e `openReconverse` ainda dizem que a thread será criada sob demanda, executam `RESET` e abrem a gaveta vazia. Em `:228-239`, quando o store está sem thread — condição garantida pelo `RESET` — o primeiro envio despacha `autonomiaBuildThreads/start`, que faz POST de criação.

A causa é integração incompleta entre a nova API/store e o chamador existente do painel. Os testes do módulo do store cobrem `resume` isoladamente, mas não cobrem o ciclo `PanelTune → resume → thread existente → send`; portanto o verde do store não prova a jornada real.

## Correção mínima necessária

Migrar somente o ciclo do painel existente: ao clicar no botão, despachar `autonomiaBuildThreads/resume({ agentId })` e abrir a gaveta apenas após uma resposta bem-sucedida. O primeiro envio dessa gaveta deve exigir o id hidratado e usar `send`; não deve cair em `start`. A ação `start` continua válida para a criação inicial em `AgentBuilderPage`. Acrescentar uma prova do componente/integração que confirme o GET nested, o histórico e o id real, sem POST de criação; 401/404/422 devem manter a tela do agente e não abrir uma conversa vazia.

Não executar testes ou alterar produto durante esta revisão. Uma correção deve ser precedida pelo protocolo de causa e seguida pela única checagem limitada autorizada; o residual desta revisão exige parada antes dessa etapa.

## Resultado

O achado e seu efeito estão registrados no relatório `revisoes/B3-BE05-codigo-normal.md`. Nenhum merge, fila, deploy, produção, banco ou PR foi executado.

## Causa complementar registrada antes da correção — RED24

O RED24 reproduziu a falha no consumidor real, depois da API e do store já
estarem disponíveis. A evidência é o job `m2-5b21fa1517a94a7887c481f452e60242`,
ticket M4 `4321c51e2fe647999eddbf4714d1bf0c`, JSON
`/tmp/chat2you-agentes-frontend-check24.json` (SHA-256
`d2271baed017208243cc26214f1bfec3879f36747be8d3abc66cd652a132776e`): a suíte
executou 65 casos, passou 47, e deixou 4 suites sem coleta por módulos F0
ausentes. No bloco de `PanelTune`, 3 de 7 casos passaram e 4 falharam nos
cenários de histórico/retomada e nos erros 401/404/422.

A causa complementar é de compatibilidade de produto: a integração BE-05 não
pode substituir globalmente o caminho legado. O fluxo novo só deve ser ativado
quando `currentAccount.autonomia_agents_redesign === true`; com a flag desligada,
`RESET` e a criação inicial por `start` continuam sendo o contrato antigo. A
remoção global de `start` ou de `RESET` criaria regressão para contas ainda fora
do redesign. No fluxo novo, o painel deve hidratar por `resume` antes de abrir,
recusar envio sem `threadId` antes de fazer upload ou POST, e não abrir em
401/404/422. O modo manual não deve iniciar uma thread guiada.

O mesmo bloco ainda corrige a violação visual comprovada nos dois arquivos
tocados: três usos de `Select` em `PanelTune.vue` e um em
`AgentAudienceForm.vue` ainda apontavam para o componente que renderiza
`<select>` nativo, apesar da regra de escolha única. Eles serão trocados pelo
`ChoiceSelect` existente, preservando `v-model`, opções e rótulos acessíveis.
