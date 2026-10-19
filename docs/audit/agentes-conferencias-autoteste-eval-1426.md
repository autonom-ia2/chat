# Eval pago: conferências e autoteste do material (#1426, PR 2, tema 4b)

Data: 19/10/2026. Autorização do Rodrigo, frase exata: "Pode, teto US$ 2 (Recomendado)". Teto TOTAL de US$ 2 para
o eval dos 10 cenários; estimativa prévia de US$ 0,80 a 1,00.

## O que se avalia

As conferências do material (o modelo decide pelo sentido, com "não se aplica" explícito; nunca regex nem lista de
palavras) e o autoteste (até 10 perguntas, 8 do material e 2 de fora).

| Cena | O que entra | O que tem de sair |
|---|---|---|
| C1 foto legível | `cardapio-legivel.png`, lida pelo OCR de verdade (tesseract local) | leitura legível, sem problema |
| C2 foto borrada | `cardapio-borrado.png`, mesmo OCR | leitura ruim, problema `ocr` |
| C3 planilha sem títulos | linhas `101 \| 24 \| 3` | tabela sem cabeçalho, amostra da 1ª linha |
| C4 planilha com títulos | `Produto \| Preço (R$) \| Estoque` | com cabeçalho, sem problema |
| C5 PDF de texto corrido | três frases sobre a casa | tabela "não se aplica", sem problema |
| C6 sábado diverge | site 9h–13h, folheto 9h–12h | 1 contradição |
| C7 complementares | horário num, entrega no outro | nenhuma |
| C8 mesmo fato | "9h às 13h" e "9 da manhã até 1 da tarde" | nenhuma |
| A1 autoteste, base limpa | lanchonete com cardápio, horário e entrega | ≤ 8 do material todas certas, as 2 de fora recusadas, nenhum cartão |
| A2 autoteste, material reprovado no meio | igual; o material da 1ª pergunta é reprovado depois de gerar as perguntas | as perguntas dele erradas e cada uma vira cartão; as de fora recusadas |

O teto é somado pelo consumo gravado (`Crm::AiUsageEvent`). Cena que não cabe no que sobra nem começa, e o autoteste
recebe como teto só o que sobrou (o `MedidorDeCusto` da própria rodada).

## Como rodar

Spec: `spec/services/autonomia/agents/material/conferencias_e_autoteste_eval_spec.rb` (desligado por padrão).

```
AUTONOMIA_EVAL_PAGO=1 CONFERENCIAS_EVAL=1 OPENAI_API_KEY=<da conta de eval> CONFERENCIAS_EVAL_SAIDA=<arquivo> \
POSTGRES_DATABASE=chatwoot_test_1426b bundle exec rspec spec/services/autonomia/agents/material/conferencias_e_autoteste_eval_spec.rb
```

Banco próprio `chatwoot_test_1426b`, no M4. Precisa do `tesseract` no PATH (C1 e C2).

## Rodadas e custo

| Rodada | Resultado | Custo |
|---|---|---|
| 0 | só C3, para conferir o encanamento | US$ 0,0001 |
| 1 | 6 de 10. C6, C7 e C8 reprovadas por erro do próprio eval (lia o retorno de `conferir!` como lista; o produto acertou as três). C1 reprovada de verdade (abaixo) | US$ 0,0554 |
| 2 | 10 de 10, depois do ajuste da instrução e do eval | US$ 0,0547 |
| 3 | 10 de 10, depois da refatoração do spec (rubocop) | US$ 0,0558 |

**Total gasto: US$ 0,166 de US$ 2.** O custo dos embeddings dos materiais (text-embedding-3-small, poucas centenas
de tokens) não entra no `Crm::AiUsageEvent` e é desprezível.

O autoteste custou US$ 0,02 a 0,03 por rodada (10 perguntas, respostas e juiz), bem abaixo da estimativa de US$ 0,80.
O `gasto_usd` gravado na rodada bateu com o consumo registrado (A1: 0,0293 nos dois).

## Achado da rodada 1 (corrigido)

C1: a foto legível do cardápio foi reprovada como "tabela sem cabeçalho". O OCR separa a coluna dos nomes da coluna
dos preços, e o modelo leu isso como tabela cujas colunas não dizem o que são. Seria um falso positivo grave: o
material bom ficaria fora do agente. Correção na instrução de `ConferenciaDoMaterial` (pelo sentido, sem lista de
palavras): "com_cabecalho" também quando o próprio conteúdo deixa claro o que cada coluna é, por exemplo nomes de
produto ao lado de valores com R$, mesmo sem título e mesmo que a leitura tenha separado as colunas. Nas rodadas 2 e
3: C1 legível e com cabeçalho; C3 (números sem sentido) continua sem cabeçalho.

## Resultado final (rodada 3)

| Cena | Saída do modelo | Problema | Aprovada |
|---|---|---|---|
| C1 | legível, com cabeçalho | nenhum | sim |
| C2 | ruim, não se aplica | `ocr` | sim |
| C3 | não se aplica, sem cabeçalho, amostra `101 · 24 · 3` | `sem_cabecalho` | sim |
| C4 | não se aplica, com cabeçalho | nenhum | sim |
| C5 | não se aplica, não se aplica | nenhum | sim |
| C6 | 1 contradição, "horário de sábado": 9h às 13h × 9h às 12h | cartão | sim |
| C7 | nenhuma | nenhum | sim |
| C8 | nenhuma | nenhum | sim |
| A1 | 10 perguntas: 8 certas, 2 de fora recusadas (passou para a equipe) | nenhum cartão | sim |
| A2 | 10 perguntas: as 3 do cardápio reprovado erradas, 5 certas, 2 de fora recusadas | 3 cartões `autoteste` | sim |

Placar: 10 de 10.

Observação sobre C2: o OCR da foto borrada devolveu 2 caracteres. No caminho real da ingestão isso não chega à
conferência: a extração vazia vira o problema "vazio" (`empty_extraction`). A cena prova que a conferência também
reprova leitura ruim quando há texto.
