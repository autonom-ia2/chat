# B4b — desenho e contrato antes do produto

**Data:** 2026-10-08  
**Escopo:** BE-12, BE-29 e BE-30  
**Estado:** RED observado e implementação local concluída; confirmação GREEN ainda pendente

## Decisão registrada

O lote B4b seguirá com uma única política de superfície sobre o executor existente. O Testar externo
repassa `trust_instruction`, as rodadas de cotação e a permissão recalculada pelo servidor; o ajudante
interno usa a composição do Copilot e não devolve faixa de passagem. Estratégias neutras de handoff
preservam bytes. `always_ask` e `never` entram apenas no caminho externo, inclusive manual. Nome
gerado entra no externo guiado, no ajudante interno guiado e nas duas pernas de `both`; manual e Guia
ficam fora, e Lia segue o BE-17. Saudação e fallback entram somente na perna externa, guiada ou
manual. Ferramentas assíncronas e HTTP não-GET para quem só vê são recusadas com motivo tipado; o
resultado expõe somente `skipped_tools` sanitizado e `writes_external`.

## Fontes conferidas

- `docs/agentes-ia-redesign/PRD.md:525-543` (BE-12, BE-29 e BE-30);
- `docs/agentes-ia-redesign/PRD.md:567-618` (casos obrigatórios e matriz de variantes);
- `app/services/autonomia/agents/playground.rb`;
- `app/services/autonomia/agents/answerer.rb`;
- `app/services/autonomia/agents/prompt_builder.rb`;
- `app/services/autonomia/agents/copilot.rb`;
- `app/services/autonomia/agents/operate/responder.rb`;
- `app/services/autonomia/agents/tools/bound.rb`;
- `app/services/crm/ai/interactive_operation_agent_test.rb`;
- serializers `app/views/api/v1/accounts/autonomia/agents/playground/{test,suggest}.json.jbuilder`.

## Artefatos TDD

- `docs/agentes-ia-redesign/design/B4b.md` descreve o contrato e os limites do lote;
- `spec/services/autonomia/agents/b4b_playground_contract_spec.rb` cobre forwarding do Playground,
  rodadas, permissão e rota interna do Copilot;
- `spec/services/autonomia/agents/b4b_prompt_contract_spec.rb` cobre bytes neutros, regras de handoff,
  nome por variante e greeting/fallback;
- `spec/services/autonomia/agents/b4b_tools_contract_spec.rb` cobre viewer GET/non-GET, editor,
  provider local nomeado e ferramenta assíncrona;
- `spec/services/autonomia/agents/b4b_result_contract_spec.rb` cobre envelope sanitizado e serializers.

Os testes dublam somente a resposta estruturada do modelo. O executor HTTP permanece o código oficial;
o provider usado no contrato é um fixture local nomeado, sem rede e sem provedor pago. Nenhum teste,
serviço, banco, job ou produção foi executado nesta etapa. Não há migration prevista.

## Implementação local e validação estática

Após o RED36 (47 exemplos, 43 falhas, 0 falhas fora do contrato), foram implementados os campos e
políticas em `AnswerResult`, `Answerer`, `Playground`, `Copilot`, `PromptBuilder`, `Tools::Bound`, no
executor de operações interativas e nos dois serializers do Playground. A permissão continua sendo
recalculada no servidor; o resultado só carrega `slug`, `name` e `code` permitidos, além de
`writes_external`. A ferramenta HTTP oficial permanece o executor do caso permitido; o provider
usado pela spec é apenas um fixture local nomeado.

Validação estática executada na worktree:

- `ruby -c` nos sete arquivos Ruby alterados e nas quatro specs B4b: todos `Syntax OK`;
- `git diff --check`: sem erro;
- nenhuma spec, serviço, banco, job, navegador, provider pago ou produção foi executado nesta etapa.

Integração ainda pendente: o metadata `agent_name` das versões guiadas depende do owner do modelo, e o
coordenador deve decidir se `writes_external` também será projetado no estado persistido do teste além
do resultado Redis imediato. Não há migration prevista.

## Próximo gate

O coordenador deve capturar o snapshot combinado e executar o RED uma vez. Depois disso, a implementação
fica limitada aos contratos acima; qualquer resíduo concreto na confirmação limitada encerra o lote para
retorno ao Rodrigo. Este registro não autoriza merge, fila, deploy, produção ou banco.
