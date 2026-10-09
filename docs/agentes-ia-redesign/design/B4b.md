# B4b — teste igual ao atendimento e campos de apresentação

**Estado:** IMPLEMENTAÇÃO LOCAL — contrato e specs RED foram preparados; a implementação deste lote
está salva na worktree e ainda aguarda a confirmação GREEN do coordenador. Nada foi aprovado para
release.

Este desenho cobre somente BE-12, BE-29 e BE-30. Ele transforma o Testar numa leitura real do
caminho de atendimento e dá efeito aos campos `name`, `greeting`, `fallback_message` e
`config.handoff_strategy` onde o PRD permite. Não cria rota, migration, provider pago, conversa,
ToolRun ou job de cotação para o Testar.

Fontes normativas: `docs/agentes-ia-redesign/PRD.md:525-543,567-618`, especialmente CA-TES-04,
CA-TES-08, CA-TES-09, D17-D19 e a matriz de variantes em §6.7. O código aberto que este desenho
reconfere é `app/services/autonomia/agents/playground.rb`, `answerer.rb`, `prompt_builder.rb`,
`copilot.rb`, `operate/responder.rb`, `tools/bound.rb`,
`services/crm/ai/interactive_operation_agent_test.rb` e os dois serializers em
`app/views/api/v1/accounts/autonomia/agents/playground/`.

## 1. Limites do lote

O lote entrega uma única política explícita de superfície. O serviço que já existe continua sendo
o executor; a política só informa ao motor qual chamada é válida:

| Superfície | Entrada | Handoff/prompt | Ferramentas |
|---|---|---|---|
| Atendimento externo | `Operate::Responder` | `trust_instruction: true`, delivery real; lê `always_ask`/`never` | catálogo e execução de produção |
| Testar externo | `Playground` | mesmo `trust_instruction`, `rodadas_do_turno(agent)`, `delivery: nil` | mesma lista; assíncrona nunca é aceita |
| Testar de quem só vê | `Playground` | resposta visível, sem validar E4 | HTTP diferente de GET é pulada |
| Copiloto/ajudante interno | `Agents::Copilot` e `ConversationChat` | resposta para o atendente, sem faixa de passagem e sem BE-30 | regra D17 conforme a permissão |
| Guia/sistema | `Guide::Chat` e agente com `system_key` | bytes atuais | bytes atuais |
| Lia/Cotação | `insurance_quote` | instrução e catálogo do deploy | teste recusa cotação |
| Manual | instrução escrita pela pessoa | texto manual continua autoridade; superfície externa aplica handoff/greeting/fallback | nome não é injetado pelo builder |
| `both` | perna externa ou interna | BE-29 nome nas duas pernas; BE-12/30 só na perna externa | política da superfície |

O chamador fornece `pode_editar`, derivado da permissão revalidada pelo servidor. O navegador não
manda `actor_permission`, `writes_external`, `skipped_tools`, prompt, instrução ou resultado.

## 2. Contrato do Playground

`Playground` deve construir o mesmo `Answerer` do atendimento externo com estas diferenças legítimas:

```ruby
Answerer.new(
  agent: agent,
  query: message,
  history: history,
  images: images,
  trust_instruction: true,
  audience: :customer,
  delivery: nil,
  test_mode: true,
  pode_editar: pode_editar,
  **Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(agent)
)
```

`pode_editar` vem do `AccountUser` no `InteractiveOperationAgentTest`; `true` equivale a
`autonomia_manage` e `false` a `autonomia_view`. A permissão não é inferida do nome, papel enviado
no JSON ou estado antigo do Redis. O mesmo valor vale para `test` e `suggest`.

O resultado de baixa confiança com `should_handoff: false` permanece sem handoff no Testar, como no
Responder; quando o modelo devolve `should_handoff: true`, ambos mantêm `true` e o código passa pela
mesma curadoria de `EventLogger`. Público e horário não são aplicados no Testar, mas a instrução e a
política de ferramenta são as mesmas do atendimento.

Para agente `internal`, o Testar usa a composição de entrada do `Agents::Copilot` para a mesma pergunta
e conversa de exemplo. Ele não usa o bloco de atendimento externo, não retorna faixa de passagem e não
fica sujeito aos campos de apresentação do BE-30. O teste só é válido quando a resposta não é o texto
fixo `ConversationChat::NO_ANSWER_TEXT`.

## 3. Prompt e variantes

`PromptBuilder` recebe uma etiqueta interna de superfície; ela não vai para o modelo como dado do
usuário e não aparece em nenhum serializer. Os blocos de passagem entram no atendimento externo e no
Testar externo, com `audience: :customer`, tanto para agente guiado quanto manual. Os blocos de
primeira mensagem e fallback seguem a mesma regra; o texto manual continua sendo a autoridade do
agente, e esses campos de apresentação só complementam a superfície externa.

### 3.1 Estratégia de passagem (BE-12)

Somente `always_ask` e `never` têm efeito. O texto deve ser determinístico e curto:

- `always_ask`: oferecer falar com uma pessoa quando a pessoa pedir e quando a regra de atendimento
  exigir passagem;
- `never`: não oferecer passagem por iniciativa própria; passar quando a pessoa pedir uma pessoa.

`nil`, `low_confidence`, `none` e qualquer valor desconhecido não acrescentam bytes às instruções.
Para cada um, a spec compara a string inteira com a instrução do agente sem o campo. A estratégia não
entra no Copiloto, Guia, sistema, Lia ou lado interno de `both`.

### 3.2 Nome (BE-29)

Uma instrução gerada precisa guardar, no `metadata` da versão guiada correspondente, o nome que foi
usado na geração. A leitura considera somente a versão guiada mais recente do próprio agente e da
própria conta. Registros legados sem esse metadado não autorizam inferência: preservam bytes antigos.

Se o agente guiado mudou de nome depois dessa versão, a superfície elegível recebe exatamente a
identidade de dados `Seu nome é {nome}.`. Isso vale no atendimento externo, no ajudante interno e
nas duas pernas de `both`. A edição manual e o Guia/sistema ficam byte a byte iguais; a Lia segue o
fluxo próprio do BE-17 e não recebe uma injeção genérica deste builder. Sem mudança, cada variante é
comparada com seu próprio baseline. A edição manual não reescreve a instrução da pessoa.

### 3.3 Primeira mensagem e fallback (BE-30)

`greeting` e `fallback_message` não são balões fixos do front. No caminho externo, valores não vazios
entram como regras de apresentação do modelo, tanto no guiado quanto no manual: o greeting só se
aplica ao primeiro turno vazio de histórico; o fallback é a frase a ser usada quando o agente
precisar não responder ou passar. O resultado continua tipado e não expõe o prompt.

Com ambos vazios, as instruções são iguais às do baseline. Em `internal`, Copiloto, Lia, Guia/sistema
e na perna interna de `both`, os campos não ganham interpretação nova; o bloco genérico de fallback já
existente permanece igual e a comparação antes/depois usa os mesmos valores preenchidos.

## 4. Ferramentas e envelope do resultado

`AnswerResult` ganha dois campos seguros, com defaults compatíveis:

```ruby
skipped_tools: []
writes_external: false
```

Uma linha de `skipped_tools` contém somente `{ slug, name, code }`. Os únicos códigos deste lote são
`not_in_test` (ferramenta assíncrona/Lia) e `viewer_not_allowed` (HTTP diferente de GET para quem só
vê). Argumentos, URL, cabeçalhos, corpo, tokens e retorno do provedor nunca entram no resultado, no
Redis, no log ou no JSON.

`writes_external` é `true` quando o agente tem ferramenta HTTP ligada com método diferente de GET e a
pessoa que testa pode editar; para quem só vê é sempre `false`. Ele representa o risco do catálogo
ligado, não uma tentativa feita pelo modelo. A tela decide mostrar o aviso somente desse booleano.

No Testar:

1. uma ferramenta assíncrona não instancia o adapter, não chama `start`/`poll`, não cria `ToolRun` e
   não enfileira job; a função é devolvida ao modelo como recusa nomeada e entra em `skipped_tools`;
2. uma ferramenta HTTP `POST`/outro método não executa para `pode_editar: false`, não faz request e
   entra em `viewer_not_allowed`;
3. `GET` continua elegível para quem só vê;
4. para `pode_editar: true`, a ferramenta percorre o executor oficial, usando apenas um provider local
   nomeado no teste; nenhum teste chama provedor pago ou endpoint de cliente.

Os dois serializers (`test` e `suggest`) expõem `skipped_tools` e `writes_external` como dados tipados.
Eles continuam sem `raw_reply`, prompt, instrução ou `AnswerResult` interno. O state store reaproveita
a sanitização já existente para persistir as linhas permitidas.

## 5. Specs antes do produto

As specs novas deste bloco são:

- `spec/services/autonomia/agents/b4b_playground_contract_spec.rb`: forwarding de trust, rodadas,
  delivery nulo, permissão e paridade do sinal de handoff;
- `spec/services/autonomia/agents/b4b_prompt_contract_spec.rb`: bytes para valores neutros,
  `always_ask`/`never` em guiado/manual, nome pós-geração nas superfícies guiada/interna/`both`,
  greeting/fallback no externo e matriz de variantes;
- `spec/services/autonomia/agents/b4b_tools_contract_spec.rb`: viewer GET/non-GET, editor,
  assíncrona e ausência de ToolRun/job;
- `spec/services/autonomia/agents/b4b_result_contract_spec.rb`: shape seguro de `AnswerResult` e
  serialização de `skipped_tools`/`writes_external`.

Os testes de modelo simulam somente a resposta estruturada do modelo e usam provider HTTP local
nomeado para verificar a política; não fabricam resultado de negócio em controller, não pulam a
permissão e não usam uma API paga. O RED deve ser executado pelo coordenador no snapshot combinado.

## 6. Gate de implementação

Antes do código, o snapshot deve mostrar os casos carregados e falhando por contrato, sem falhas de
harness. Depois de uma correção única, a confirmação limitada deve cobrir a mesma matriz. Qualquer
resíduo concreto nessa confirmação para o lote e é devolvido ao Rodrigo; este documento não autoriza
merge, fila, deploy, produção ou banco.

Não há migration prevista. A confirmação final de migration só será declarada depois do diff e do CI do
PR, conforme a regra do usuário.
