# Automação livre · valor calculado no corpo da ação (G16a)

- **Épico:** #2414 · lacuna G16 do fechamento dos 20 exemplos (F9.6).
- **Destrava:** o G16 sai das listas dos exemplos 3, 5, 6, 11, 13, 16 e 17. Nenhum roda inteiro só com ele: todos
  dependem também de G1, G4, G6 ou G18.
- **G16a:** motor, salvar, Guia, ensaio e o editor de **texto**.
- **G16b:** a peça "data" no editor, para o atributo do tipo data (conversa, contato, empresa).

## O que a receita escreve

Uma folha do corpo da ação (também dentro de `custom_attributes`) pode ser uma de três formas fechadas. Não há fórmula
nem eval.

| Forma | Exemplo | Grava |
|---|---|---|
| `{"$valor": "<caminho>"}` | `{"$valor": "card.responsavel_id"}` | o valor do alvo, da lista fechada do `Valores` |
| `{"$texto": [...]}` | `{"$texto": ["indicado por ", {"$valor": "contato.nome"}]}` | "indicado por Maria" (os pedaços do texto da mensagem) |
| `{"$data": {"de": ..., "mais": ...}}` | `{"$data": {"de": "hoje", "mais": {"valor": 6, "unidade": "meses"}}}` | "2027-05-04" |

Passo 3 do exemplo 5 ("card ganho → revisão daqui a 6 meses"):

```json
{ "id": "revisao", "tipo": "acao", "acao": "PATCH crm/cards/:id", "descricao": "Marcar a revisão",
  "caminho": { "id": { "$valor": "card.id" } },
  "corpo": { "card": { "custom_attributes": {
    "revisao": { "$data": { "de": "hoje", "mais": { "valor": 6, "unidade": "meses" } } } } } } }
```

## A data

- **Formato:** "AAAA-MM-DD", o mesmo que a tela grava num atributo do tipo data (`attributeDate`, que corta a hora) e no
  campo de data do card (`expected_close_at` sai do `<input type="date">`). O spec grava pela automação e pelo mesmo
  endpoint da tela, lê os dois pelo endpoint que a tela lê e compara (conversa e card).
- **"Hoje"** é o dia da execução no fuso da conta (`Crm::Timezone::Resolver`, o mesmo do extrair e do Guia), nunca o do
  salvar. Às 22h30 do dia 4 em São Paulo (01h30 do dia 5 em UTC), "hoje" é o dia 4. Conta sem fuso gravado usa o
  padrão da plataforma, como o resto do produto.
- **De um atributo:** `"de": {"$valor": "card.atributos.entrega"}` só aceita atributo do tipo data (frase
  `data_sem_data` no salvar). Os campos fixos (`CAMPOS`) não têm data hoje. O valor guardado com hora
  ("2026-03-31T00:00:00Z" ou "2026-03-31 08:00") vale pelo dia escrito, como na tela.
- **Soma pelo calendário:** dias, semanas, meses ou anos; N inteiro, pode ser negativo. 31/01 + 1 mês = 28/02. Teto
  de 3650 de cada unidade no esquema, contra erro de digitação (igual à duração).

## Quando a ação pula

O motor nunca grava valor pela metade ou inválido. A ação pula, segue para o próximo passo e o histórico diz o motivo:

| Motivo | Quando |
|---|---|
| `faltou_valor` | um valor lido está vazio (nunca grava "indicado por ") |
| `data_invalida` | o atributo de data lido não é uma data |
| `valor_fora_do_formato` | o valor calculado não cabe no campo: fora das opções de um enum (`priority`) ou de outro tipo (texto no campo de data do card) |

`false` é valor (um atributo sim/não desmarcado), não vazio. Dentro de um `$texto`, o pedaço segue a regra do texto da
mensagem: `false` conta como vazio, e a ação pula.

O tipo de cada campo vem do formato da ação no Guia (`CampoDaAcao`). Só o campo do primeiro nível tem tipo conhecido;
dentro de um campo JSON (`custom_attributes`) qualquer valor cabe, como na tela.

## Salvar

- Cada caminho lido no corpo passa pela mesma conferência do caminho da ação (desconhecido, fora do alvo do gatilho,
  atributo que a conta não tem, mensagem e resposta fora do lugar delas).
- O formato da ação confere o corpo com um **exemplo** no lugar de cada valor calculado: a primeira opção de um campo
  com lista; senão, um valor do tipo do campo. Chave fora do formato e literal fora da lista continuam recusados. O
  valor de verdade só existe ao executar, e o `PassoDeAcao` confere o formato de novo com ele.
- Texto montado ou data calculada num campo que nunca os aceitaria (opções, número, sim/não) é recusado
  (`forma_nao_cabe`). O `$valor` só se sabe ao executar e é conferido lá.
- Chave com "$" que não é uma das três formas (`$soma`) é recusada (`forma_desconhecida`): gravar o texto literal
  seria falhar em silêncio.

## Ensaio

A ação com valor calculado mostra o que gravaria agora, com os dados da conversa e o "hoje" de agora: "Gravaria:
revisao: 04/05/2027." Pula como o motor pularia, com o aviso de cada motivo, inclusive valor vazio no caminho da ação.
O histórico guarda, no motivo `valor_fora_do_formato`, o problema com o valor lido, para quem opera a conta ver o que
não coube. A ação de corpo literal continua só
mostrada.

## Editor

- O campo de texto de uma ação (nome, descrição) e o atributo personalizado de texto usam a mesma caixa da mensagem
  (`LivreTexto`), com "Pôr um dado". Só texto grava string; com dado, grava `{"$texto": [...]}`.
- O atributo do tipo data usa a peça `LivreData` (G16b), uma pergunta por vez, só com `ChoiceSelect`:
  1. "Que data gravar?": um dia certo, uma data a partir de hoje ou a partir de um campo de data (o próprio campo vale).
  2. Dia certo: o mesmo campo de data da tela da conversa (`<input type="date">`), grava "AAAA-MM-DD".
  3. A partir de um campo: só os atributos do tipo data da conta. Sem nenhum, a peça diz isso.
  4. "Quanto tempo?" só depois de saber de onde a data parte: o número, a unidade (dias, semanas, meses, anos) e
     depois ou antes. Zero grava a data de partida, sem soma.
  5. Embaixo, "Grava: hoje + 6 meses" (ou o dia certo, no formato da tela).
- Data calculada pela metade (sem o campo de partida, número vazio, quebrado ou negativo) segura o "Salvar".
- Outro valor calculado que só o Guia monta (`$valor` sozinho numa escolha ou num atributo, `$data` num campo de
  texto) aparece em frase ("Data calculada na hora: hoje + 6 meses") e passa intacto.

## Fora daqui

- Atributo de data do **card** no editor: o catálogo ainda não tem a ação "Mudar campos do card" (#2594). O motor e o
  Guia já gravam (exemplo 5 no card).
- Nome amigável do campo no ensaio: hoje mostra a chave ("revisao").
- Cálculo com número (somar, multiplicar) e texto com formatação (maiúsculas, data por extenso): fora do G16.
