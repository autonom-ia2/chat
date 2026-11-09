# #2810 — busca híbrida da base do agente (Refs #1431)

## Resultado em uma frase

Com a flag `rag_busca_hibrida`, o trecho certo entra mais vezes nos 12 que vão ao modelo: o **acerto@12 da busca passou
de 0,75 para 0,875** nas duas bases. Na resposta, o **acerto do auto subiu de 0,375 para 0,50**, e o do residencial
ficou em 0,625. A **recusa ficou em 1,00**. Dois casos do #2807 ficaram certos: o telefone de aviso de sinistro e o
carro na garagem.

## O diagnóstico que levou ao desenho

Posição do trecho certo em cada etapa da busca de hoje, nas 16 perguntas de resposta (a tabela completa está na
#2810):

- **O bônus por metadado derrubava o certo** quando as distâncias estavam próximas: a garagem caiu de 5º para 28º, e os 45 dias de 12º para 15º.
- **A troca do item pela seção ajudava**: o aviso de sinistro subiu de 26º para 13º, mas ficou a 1 posição do corte.
- **2 trechos não entravam nem nos 48 candidatos do vetor** (o reparo antes de avisar e o airbnb).

## O que a flag faz

- Os candidatos do vetor (48) e os da busca por palavra (48, texto em português, `ts_rank_cd`, índice GIN de expressão) entram juntos.
- A ordem sai da fusão por posição (RRF, k = 60), no lugar do bônus por metadado e do reforço lexical.
- Todo candidato leva a distância real do vetor. O teto de distância (0,75) continua cortando o que só casa a palavra e está longe no sentido.
- Seguem como estão: as seções dos itens, o dedup por fonte, o material reprovado fora e o isolamento por agente.
- A troca do item pela seção saiu do `Retriever` para `SecoesDosItens`, sem mudar o comportamento. Os specs de antes passam.

## Placar

Medido nos dois documentos públicos de condições gerais (auto e residencial), com o segmento `seguros/corretora` e as
flags do #2801 e do #2807 ligadas nas duas rodadas. Cada base teve 14 perguntas: 8 de resposta e 6 de recusa.

O gabarito é o do #2807, com uma diferença: a âncora do "Bati o carro" passou a ser a do item do aviso, porque a de antes
também aparecia no item do rastreador. A troca foi feita antes de qualquer medida.

**Busca** (sem resposta; só o embedding das perguntas):

| | hit@1 auto | hit@12 auto | MRR auto | hit@1 resid. | hit@12 resid. | MRR resid. |
|---|---|---|---|---|---|---|
| ANTES | 0,25 | 0,75 | 0,48 | 0,25 | 0,75 | 0,37 |
| DEPOIS | 0,125 | **0,875** | 0,40 | 0,375 | **0,875** | **0,55** |

Entraram nos 12:

| caso | antes | depois |
|---|---|---|
| aviso de sinistro | fora | 3º |
| garagem | fora | 1º |
| 45 dias | 7º | 2º |
| venda do imóvel | 11º | 6º |
| SAC | 4º | 1º |

No auto, alguns trechos que já estavam no topo desceram poucas posições (Argentina de 2º para 5º, embriaguez de 3º para
7º). Nenhum saiu dos 12.

**Resposta:**

| | acerto auto | acerto resid. | recusa auto | recusa resid. | fonte auto | fonte resid. |
|---|---|---|---|---|---|---|
| ANTES | 0,375 | 0,625 | 1,00 | 1,00 | 0,50 | 0,75 |
| DEPOIS | **0,50** | 0,625 | 1,00 | 1,00 | **0,625** | **0,875** |

Mudanças de veredito:

| pergunta | antes | depois |
|---|---|---|
| aviso de sinistro | errado | **certo** |
| garagem | errado | **certo** |
| venda do imóvel | certo | errado |

A venda do imóvel já tinha errado em rodadas anteriores com o mesmo código: com 8 perguntas por base, 1 pergunta a mais
ou a menos é ruído. As respostas por pergunta e as posições de antes e depois estão em `respostas.json`.

## Riscos e custo por turno

- **hit@1 do auto caiu de 0,25 para 0,125** e o MRR de 0,48 para 0,40: o certo entra mais vezes nos 12, mas nem sempre
  em 1º. O modelo lê os 12, por isso o acerto da resposta subiu mesmo assim. Fica na conta de quem ligar a flag.
- **Tempo da busca por palavra** (banco de medida, agente com 1.051 trechos, 30 rodadas): p50 1,9 ms, p95 28,7 ms,
  máx. 66 ms. A busca do vetor no mesmo agente: p50 2,0 ms, p95 9,0 ms. O plano usa o índice GIN novo junto com o do
  agente (BitmapAnd). Se um agente muito maior pesar, o passo seguinte é guardar o texto já processado numa coluna.
- **Sem custo de IA por turno**: a busca por palavra é só SQL. O embedding da pergunta é o mesmo de hoje.
- **Erro de SQL** na busca por palavra sobe como o erro da busca de hoje (`RetrievalError`): mesma recuperação, sem caminho novo.
- **Termos com `&`** (um endereço na pergunta): o OU é montado termo a termo, para o `&` de dentro do termo continuar
  parte dele. O placar da busca foi medido de novo depois dessa troca e deu o mesmo número.
- **Pergunta colada longa** (6 mil caracteres repetindo as mesmas palavras, 2 mil trechos): o termo repetido entra uma
  vez no OU. Com o OU da primeira versão, que repetia o termo, levava 6 s; com o de agora, cerca de 0,2 s (tester).
- **Byte nulo na pergunta** (o Guia e o Ajudante passam texto que não foi gravado antes): vira espaço antes da busca.
  Na primeira versão, derrubava a busca com a flag ligada (tester).

- **Pergunta longa com palavras diferentes** (6 mil caracteres, 2 mil trechos, tester): 110 a 130 ms com a flag, 17 a
  22 ms sem. Não foi medida numa tabela do tamanho da de produção.
- **Pedaço de palavra deixa de casar**: com a flag, o reforço lexical antigo (`ILIKE '%termo%'`, que só rodava quando o
  vetor vinha fraco) não roda. "dermato" casava "dermatologista" por ele; a busca por palavra casa pelo radical da palavra
  inteira. Aceito: o placar subiu sem ele.
- **Outros usos do Retriever na mesma conta**: a extração de FAQ, o diagnóstico do Guia e o Ajudante pedem 3 trechos.
  Com a fusão, o 1º do vetor que não repete as palavras pode cair para fora dos 3 (soma 1/61; quem está nas duas listas
  soma mais). Na extração de FAQ, isso pode sugerir uma pergunta que a base já responde. Só a resposta foi medida.
- **Ligar em todas as contas (regra C)**: por esses números (hit@1 do auto caiu, amostra de 8 perguntas por base, os
  usos com 3 trechos sem medida), ligar em todas é decisão do Rodrigo, não automática.

## O que ficou de fora

- O reparo antes de avisar e o âmbito territorial (Uruguai) continuam fora dos 12. A pergunta do cliente não se parece com o trecho nem no sentido nem na palavra.
- O próximo passo seria reescrever a pergunta ou reordenar com um modelo. Os dois custam IA por turno e ficam para o Rodrigo decidir.

## Custo

US$ 0,78 nas duas medidas da resposta, mais ~US$ 0,001 nos embeddings da busca e do diagnóstico. A frente RAG v2 acumula
≈ US$ 2,61 de 3,00.
