# Linha de base da busca — Suhai (#1431 F0, 31/10/2026)

Base: Condição Geral Suhai Automóvel (PDF público, 74 páginas). Perguntas: `perguntas-suhai.yml` (17 respondíveis, 5 de
fora). Banco local de teste, conta com a Fase 2 ligada (como a conta 1). Ingestão pelo `Ingestor` real: extração,
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
3. **A distância não separa "tem resposta" de "não tem".** As perguntas de fora da base ficam a 0,48–0,61, e as
   respondíveis a 0,27–0,50: as faixas se sobrepõem. O teto de 0,75 nunca corta nada, e toda pergunta de fora volta
   com 12 trechos. A recusa correta não pode vir de um limite de distância; tem de vir do modelo, que lê os trechos
   e diz que a base não responde. Isso se mede na etapa de resposta e juiz do placar (próxima, com IA paga).
4. A quarta âncora que não cabe ("prazo de até 7 (sete) dias da comunicação") foi cortada pela janela no meio da
   frase: defeito do corte por tamanho, que a F2 (seção inteira) resolve.

Com o #2431, os erros que sobram com a âncora inteira num pedaço são da busca: "bater no carro de outra pessoa" fica
fora do top 12; "parcelar", "cancelar", "200 km para 500 km" e "rastreador" chegam só entre a 5ª e a 12ª posição. Entram
na F1a (pergunta reescrita), na F2 (busca combinada e cabeçalho de contexto) e na F3 (reordenação).
