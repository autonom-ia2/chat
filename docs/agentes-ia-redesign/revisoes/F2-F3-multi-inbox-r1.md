# Revisão R1 — composer do Teste e múltiplas caixas no Ligue

**Data:** 2026-10-08  
**Fonte visual:** rodada 53, snapshot `20261008-103248-532a5b7b-a52da2fa5d-0f32aeaa`, SHA de conteúdo `a52da2fa5dfc6673743d31f1d4c2fdd32e63b6f4d5306aa0aa8eb3d8a649cfde`.  
**Escopo:** somente os dois ajustes solicitados: alinhamento do composer na etapa Teste e associação de uma ou mais caixas existentes na etapa Ligue, incluindo Pronto. Revisei as 12 capturas afetadas em resolução original nos quatro perfis (1440/400, claro/escuro) e comparei com o baseline da rodada 50. Não alterei aplicação, testes ou serviços.

## Achado

### F2-F3-MULTI-R1-01 — médio — placeholder do composer é cortado no mobile

**Prova visual:** `ajuste-composer-teste-chromium-400-light.png` e `ajuste-composer-teste-chromium-400-dark.png` mostram o placeholder “Escreva uma mensagem de teste” quebrado em duas linhas; a segunda linha fica cortada na borda inferior do campo. Nas versões desktop, o mesmo composer fica alinhado e legível.

**Prova do estado avaliado:** no snapshot 53, `AgentTestPhone.vue:589-595` usa `rows="1"`, `h-11`, `min-h-11`, `py-2` e `leading-6`. A altura fixa de 44 px não comporta duas linhas de texto com esse espaçamento.

**Efeito:** em uma largura de 400 px, a pessoa não lê completamente a orientação do campo. O botão de envio continua com alvo de 44 px, mas a área de texto não oferece a mesma legibilidade do restante da jornada.

**Correção mínima:** manter os botões em 44 px e permitir ao textarea uma altura móvel de 64 px (`h-16` no mobile, `sm:h-11` no desktop), sem alterar o comportamento de envio.

## Verificações do Ligue e do Pronto

Não encontrei outro achado acionável nos quatro perfis.

- As quatro capturas de `criacao-06-ligue` mostram duas caixas selecionadas, `Caixas selecionadas (2)`, os dois nomes no resumo e o contador de ocupadas. O comportamento visual é consistente entre claro/escuro e desktop/mobile.
- As quatro capturas de `criacao-08-pronto` mostram “Bia revisada está atendendo em 2 caixas de entrada” e os dois nomes em cartões, sem perder a informação no mobile.
- A seleção vazia, a marcação de duas caixas, a desmarcação, o teclado e a publicação sem seleção estão cobertos pela suíte de `AgentBuildGoLivePage` (`app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentBuildGoLivePage.spec.js:48-111`) e pelo fluxo nativo registrado em `.codex/preview/check53/native53-verify.log`. O recibo final informa 45 testes nativos aprovados, três cenários F1 omitidos por projeto e quatro cenários de cópia de material aprovados.
- A projeção de ocupação mantém caixas ocupadas desabilitadas, informa o agente responsável sem expor nome de bot externo e filtra a conta atual (`spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb:37-82`). A captura mostra o grupo “Canais ocupados (3)” sem introduzir uma caixa selecionável.
- O caminho interno não associa caixa e continua permitido sem seleção (`spec/requests/api/v1/accounts/autonomia/agents/publisher_spec.rb:109-143,312-371`); o fluxo nativo também passou pelo cenário de ajudante sem canal.
- A publicação singular legada e a lista plural são aceitas com validação explícita, sem misturar os formatos (`spec/requests/api/v1/accounts/autonomia/agents/publisher_spec.rb:80-107,350-371`).
- A publicação múltipla é transacional: seleção com uma caixa ocupada ou bot externo não deixa vínculo parcial, estado ativo ou configuração alterada (`spec/requests/api/v1/accounts/autonomia/agents/publisher_spec.rb:213-225,246-308`). A seleção de caixa de outra conta também é recusada antes de qualquer alteração (`spec/requests/api/v1/accounts/autonomia/agents/publisher_spec.rb:213-225`).

## Conclusão

O ajuste de múltiplas caixas atende visualmente aos cenários avaliados e possui contrato de backend para seleção singular, plural, interna, ocupada, cross-account e rollback atômico. O único problema acionável desta R1 é o corte do placeholder do composer em 400 px. A mesma lente deve fazer uma R2 somente após a captura que comprovar a correção; este relatório não é aceite humano, CI, aprovação de release ou validação de produção.
