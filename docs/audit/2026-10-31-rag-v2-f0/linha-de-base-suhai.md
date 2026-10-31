# Linha de base da busca — Suhai (#1431 F0, 31/10/2026)

Base: Condição Geral Suhai Automóvel (PDF público, 74 páginas). Perguntas: `perguntas-suhai.yml` (17 respondíveis, 5 de
fora). Banco local de teste, conta com a Fase 2 ligada (como nas contas piloto). Ingestão pelo `Ingestor` real: extração,
Chunker, classificador da fonte e embedding text-embedding-3-small. Busca pelo `Retriever` real, top 12.

## Placar

| | main (500a644ec5) | PR #2431 (272b641b1c) |
|---|---|---|
| Pedaços (mediana de caracteres) | 1.207 (184) | 762 (232) |
| hit@1 | 0,29 | **0,47** |
| hit@5 | 0,41 | **0,59** |
| hit@12 | 0,59 | **0,76** |
| MRR | 0,36 | **0,53** |
| Âncora inteira dentro de algum pedaço | 13 de 17 | 14 de 17 |
| Fora da base que voltou sem trecho | 0 de 5 | 0 de 5 |
| Distância, respondíveis (mediana / p90) | 0,42 / 0,48 | 0,42 / 0,47 |
| Distância, fora da base (mínimo / mediana) | 0,49 / 0,52 | 0,48 / 0,50 |
| Busca (média) | 523 ms | 503 ms |
| Custo real | US$ 0,0080 | US$ 0,0084 |

Custo: classificador da fonte pelo evento `crm.ai_usage` (US$ 0,0065 e 0,0069) e embedding pelos tokens devolvidos pela
API (77 mil e 74 mil tokens, US$ 0,0015 cada). **Total da rodada: US$ 0,0164**, de US$ 2 autorizados.

## O que a linha de base mostra

1. **O #2431 melhora a busca de verdade**: hit@12 de 0,59 para 0,76 e MRR de 0,36 para 0,53, só pelo corte em
   parágrafos.
2. **Palavras coladas na extração do PDF, nas duas versões.** Cerca de 10% dos pedaços têm palavras sem espaço entre
   elas: "ASeguradorateráoprazomáximode30(trinta) diasparapagar aindenização", "NÃOFAZERNENHUMACORDOCOMOSDEMAIS…".
   Três das quatro âncoras que não cabem em nenhum pedaço caem nesse defeito: o texto existe, mas colado, e nem o
   embedding nem a busca por palavra o acham. O `pdftotext` (poppler) lê o mesmo PDF com os espaços certos, e o
   `poppler-utils` já está na imagem de produção (`docker/Dockerfile`). É defeito da extração (`Processors::Pdf`, área da
   #1426); provável causa: o PDF justifica o texto pelo espaçamento entre caracteres, e o `pdf-reader` não transforma
   esse espaçamento em espaço.
3. **A distância não separa "tem resposta" de "não tem".** Medida só pela busca vetorial, na main as perguntas de fora
   da base ficam a 0,49–0,55 e as respondíveis a 0,27–0,49 (as faixas se encostam); no c7cf171d83, fora a 0,45–0,55 e
   respondíveis a 0,26–0,47 (se sobrepõem). O teto de 0,75 nunca corta nada, e toda pergunta de fora volta com 12
   trechos; por isso `fora_sem_trecho` dá 0 por construção, não por medida. A recusa correta não pode vir de um limite de distância; tem de vir do modelo, que lê os trechos
   e diz que a base não responde (medido na etapa de resposta e juiz, abaixo).
4. A quarta âncora que não cabe ("prazo de até 7 (sete) dias da comunicação") foi cortada pela janela no meio da
   frase: defeito do corte por tamanho, que a F2 (seção inteira) resolve.

Com o #2431, os erros que sobram com a âncora inteira num pedaço são da busca: "bater no carro de outra pessoa" fica
fora do top 12; "parcelar", "cancelar", "200 km para 500 km" e "rastreador" chegam só entre a 5ª e a 12ª posição. Entram
na F1a (pergunta reescrita), na F2 (busca combinada e cabeçalho de contexto) e na F3 (reordenação).

## Etapa da resposta e do juiz (main, 31/10)

Cada pergunta passa pelo `Answerer` como no atendimento (`trust_instruction: true`), e o juiz do autoteste
(`JuizDoAutoteste`, gpt-6-luna) dá o veredito pelo sentido, comparando com a resposta esperada escrita no YAML
(`PlacarDaResposta`).

| | main |
|---|---|
| Acerto nas respondíveis | 10 de 17 (0,59) |
| Recusa correta nas de fora da base | 5 de 5 (1,00), todas passando para a equipe |
| "De onde veio": a resposta diz ter usado um trecho com a âncora | 9 de 17 (0,53) |
| Custo real da rodada (ingestão + 22 respostas + juiz) | US$ 0,1437 |

Leitura:
- **A recusa funciona pelo modelo**: as 5 perguntas de fora voltaram com "vou confirmar com a equipe", mesmo com 12
  trechos entregues. Isso confirma o achado 3: a recusa vem do modelo, não de limiar.
- Das 7 erradas, 3 são de busca (a resposta não chegou: "200 km para 500 km", "pátio", "bater no carro de outra
  pessoa"), e o agente passou para a equipe ou ficou vago. Elas devem melhorar com o #2431 e com a F1a e a F2.
- Algumas "certas" aparecem com "de onde veio" falso: o agente usou o trecho certo, mas o trecho está com as palavras
  coladas, e a âncora não casa. O "de onde veio" desta rodada subestima; o conserto das palavras coladas corrige a
  medida junto.
- O juiz é severo com resposta parcial (o "15 dias" e o "táxi" foram julgados errados por um detalhe a mais ou a menos
  que o esperado). Para comparar versões, vale a diferença entre rodadas com o mesmo juiz e o mesmo YAML.

## Proposta: a recalibração dos limites 0,75 e 0,45 sai do escopo

Pelos números acima (busca vetorial, c7cf171d83): as perguntas de fora da base ficam a 0,45–0,55 e as respondíveis a
0,26–0,47; as faixas se sobrepõem e nenhum limite de distância separa as duas. São só 5 perguntas de fora: a linha de
base por formato (30 a 40 perguntas cada) traz a amostra para confirmar ou desmentir. O teto de 0,75 nunca corta nada, e a recusa correta (5 de 5) já
vem do modelo. Mudar os limites não melhoraria nada que o placar mede. A frente propôs tirar o item da F2; o gestor levou
ao Rodrigo junto com o plano (31/10).

A distância foi medida de novo só pelos trechos da busca vetorial (o trecho que entra pelo reforço por palavra tem
distância fixa de 0,45 no Retriever e passou a ficar de fora). No Suhai, os números não mudaram, na main e no
c7cf171d83: o reforço por palavra não entrou em nenhuma pergunta.

## Produção (só leitura, 31/10)

- Modelo de embedding ativo: `text-embedding-3-small` (`AUTONOMIA_EMBEDDING_MODEL` não definido; a coluna do 3-large
  está vazia em todas as linhas).
- PostgreSQL 18.3, pgvector 0.8.1, pg_trgm 1.6; `unaccent` disponível e não instalado (a busca combinada da F2 precisa
  de migration).
- EXPLAIN da busca de um agente com cerca de 2,1 mil pedaços: varredura pelo índice do agente e ordenação exata,
  108 ms. O índice ivfflat foi criado sem classe de operador (distância L2) e a busca usa cosseno: o índice nunca é
  usado. O HNSW do 3-large é da tabela inteira; se o 3-large for ligado, o planejador pode filtrar o agente depois e
  perder trechos.

## O que da F0 fica para depois

- Fidelidade estrita (cada afirmação da resposta apoiada nos trechos usados): o juiz de hoje confere o fato esperado, não
  frase a frase. Entra com a conferência em modo sombra (F4).
- Bases de cliente: esperam decisão do Rodrigo sobre onde guardar o gabarito.

As medidas do "#2431" (272b641b1c e c7cf171d83) são commits do PR #2431 (`fix/1426-corte-pdf`), medidos num checkout à
parte com o placar deste PR; não estão no histórico deste PR.

## Régua do #2431 no head c7cf171d83 (palavras coladas e títulos)

| | main | 272b641b1c | **c7cf171d83** |
|---|---|---|---|
| Pedaços | 1.207 | 762 | 799 |
| hit@1 | 0,29 | 0,47 | 0,47 |
| hit@5 | 0,41 | 0,59 | **0,76** |
| hit@12 | 0,59 | 0,76 | **0,88** |
| MRR | 0,36 | 0,53 | **0,62** |
| Pedaços com palavra colada | 10,3% | 10,0% | **0,0%** |
| Títulos distintos | 117 | 58 | 157 |
| Pedaços que herdam "4 – PERDA DE DIREITOS" | 58 | 96 | 22 |
| Âncora inteira num pedaço | 13/17 | 14/17 | **17/17** |
| Acerto (juiz) | 10/17 | — | **14/17** |
| Recusa correta | 5/5 | — | 5/5 |
| De onde veio | 9/17 | — | **14/17** |
| Custo da rodada | US$ 0,1437 | US$ 0,0084 (só busca) | US$ 0,1643 |

Gasto total do D3 até aqui: US$ 0,324 de US$ 2.

As 3 erradas no c7cf171d83: "cancelar" (resposta certa, mas passou para a equipe), "bater no carro de outra pessoa"
(a busca não traz a RCF-V: assunto da F1a e da F2) e "táxi" (o juiz cobra o táxi; o agente respondeu com outro
serviço da assistência). Os 22 pedaços que ainda herdam "4 – PERDA DE DIREITOS" ficam para o PR de seção e cabeçalho.
