# Desenho da F1 do RAG v2 (#1431) — 08/11/2026

Objetivo do Rodrigo: "um modelo mais assertivo de resposta para qualquer tipo de mídia que o usuário subir como KB".
Qualquer material que o dono subir tem de virar resposta certa, que diga de onde veio e que recuse quando a base não sabe.

A F1 é a parte **sem IA paga**: ler cada formato pela estrutura que ele já tem e cortar por seção. Ela prepara a F2
(contexto por trecho e reescrita da pergunta) e a F3 (reordenação), que são pagas e vêm depois, com teto próprio.

Base do desenho:
- linha de base por formato (`../2026-10-31-rag-v2-f0/linha-de-base-formatos.md`);
- desenho-alvo (`../2026-10-31-rag-v2-f0/desenho-alvo-por-formato.md`);
- o conceito do RAG que a sessão "Agentes externos" montou no n8n (abaixo);
- medidas só de leitura na produção, feitas hoje.

## O que vem do n8n, e o que não vem

O RAG do n8n atende 2 agentes de seguro. Ele foi medido só em PDF digitado e Markdown: o trecho certo saiu em 1º lugar
em 31 de 40 perguntas, contra 9 de 40 antes da troca.

| ideia do n8n | entra? | fase | por quê |
|---|---|---|---|
| corte por estrutura (cláusula, item, título), 350 a 2.000 caracteres, sem sobreposição fixa | sim | F1 | ataca o "corte no meio", 8 das 17 falhas do PDF Suhai |
| seção, cláusula e página guardadas com o trecho | sim | F1 | é o que permite dizer de onde veio |
| sumário, menu e rodapé fora | sim | F1 | sem IA: sai pela geometria do PDF e pelo DOM do site |
| índice HNSW por cosseno | só com prova | F1 | o ivfflat sai; o HNSW, aproximado, só entra se igualar a busca exata (ver "Banco") |
| resumo, perguntas de leigo e termos do dia a dia por trecho, no vetor | sim | F2 | ataca o vocabulário, 5 das 17 falhas; custa 1 chamada por trecho |
| reescrita da pergunta, somando os dois vetores | sim | F2 | mesma causa; custa 1 chamada por pergunta |
| text-embedding-3-large com 1.536 dimensões, na mesma coluna | medir | F2 | troca o modelo sem migration; só fica se o placar mostrar ganho |
| reordenação por IA pequena, 30 candidatos | sim | F3 | sobe o hit@1 |
| sem OCR, DOCX recusado | não | — | nós já lemos escaneado, foto e DOCX |
| recusa só por instrução, sem juiz | não | — | a nossa recusa está em 1,00 com juiz; não troco o que funciona |
| busca só por vetor, sem texto | não | — | perde termo exato (código de tabela, nome de plano); a busca por texto entra na F2 |

## O placar

O placar mede, em todas as fases e em todos os formatos:
- **hit@12** e **hit@1**: a busca acha o trecho certo entre os 12 primeiros e em 1º lugar;
- **acerto**: a resposta certa nas perguntas que a base responde, pelo JuizDoPlacar v2, com os erros revistos à mão;
- **recusa**: nas perguntas de fora, o agente não inventa;
- **de onde veio**: a resposta diz ter usado um trecho que contém a âncora.

Regras:
- **Recusa abaixo de 1,00 barra a fase.**
- Diferença de acerto menor que 5 pontos não decide nada (margem do juiz).
- Cada PR se mede contra a main, nas mesmas bases e nas mesmas perguntas.

## Por formato

"Hoje" é a linha de base de 31/10 (hit@12 · hit@1 · acerto · recusa · de onde veio). "Meta F1" é o que a F1 sozinha
deve dar; o resto até 95% depende da F2 e da F3.

| formato | aceito hoje | hoje | o que a F1 muda | meta F1 (hit@12 · acerto) | PR |
|---|---|---|---|---|---|
| PDF digitado (Suhai, Mapfre) | sim | 0,56–0,59 · 0,25–0,28 · 0,75–0,79 · 1,00 · 0,50–0,55 | título, tabela e sumário pela geometria; seção inteira até ~400 tokens; página no trecho | ≥ 0,85 · ≥ 0,88 | 1 |
| PDF escaneado | sim | 0,96 · 0,69 · 0,96 · 1,00 · 0,92 (sintético, 4 páginas) | OCR com a posição das linhas (TSV do tesseract), mesmas regras do digitado; página misturada passa a ser lida | sem regressão; misto ≥ 0,85 | 1 |
| foto | sim | 0,96 · 0,71 · 0,96 · 1,00 · 0,96 | OCR com posição, como o escaneado; tabela de preço por coluna alinhada | sem regressão | 2 |
| XLSX | sim | real 0,89 · 0,52 · 0,85 · 1,00 · 0,85 | grupos de linhas com o cabeçalho repetido e cada linha como "Coluna: valor" (ver "Planilha" abaixo); valor como aparece na planilha (hoje sai `406.21000000000004`) | ≥ 0,92 · ≥ 0,90 | 2 |
| CSV | **não** | — | entra pelo mesmo caminho do XLSX (biblioteca CSV do Ruby) | ≥ 0,92 | 2 |
| DOCX | sim | 0,96 · 0,46 · 0,96 · 1,00 · 0,89 | título pelo estilo do Word, listas e tabelas do próprio documento | sem regressão; hit@1 ≥ 0,60 | 2 |
| MD | sim | 0,94 · 0,69 · 0,81 · 1,00 · 0,91 | árvore do Markdown (commonmarker, já no projeto): título, lista e tabela | acerto ≥ 0,90 | 2 |
| site | sim | 1,00 · 0,84 · 1,00 · 1,00 · 0,91 | blocos do DOM, h1–h6 como seção, menu e rodapé fora, tabela | sem regressão | 2 |
| JSON | sim | 0,86 · 0,79 · 0,89 · 1,00 · 0,86 | cada objeto com o caminho do pai ("clínica › convênios › Previna") | ≥ 0,92 | 2 |
| TXT | sim | 1,00 · 0,71 · 1,00 · 1,00 · 1,00 | só junta parágrafos até o teto; não adivinha título | sem regressão | 2 |
| PPTX | **não** | — | não entra na F1: ninguém pediu. Quando entrar, 1 slide = 1 seção | — | — |
| áudio e vídeo | **não** | — | não entra na F1: é transcrição, outra peça. Proponho Issue própria (transcrever, depois cortar como TXT com o minuto no lugar da página) | — | Issue |

Nenhum formato aceito fica sem linha no placar. CSV ganha base e perguntas próprias no PR 2.

### Por que as metas da F1 param em ~0,85–0,90 nos PDFs reais

O corte resolve o "corte no meio" (8 falhas no Suhai) e a "palavra colada" (3, já resolvidas pelo #2431). Não resolve:
- o vocabulário (5): a pergunta usa outras palavras. É da F2;
- a tabela embaralhada que ganha a busca (2): a F1 resolve se a tabela vira tabela.

Medida já feita no Suhai com o #2431: hit@12 de 0,59 para 0,79–0,94, conforme o conjunto de perguntas. A F1 completa esse
caminho no PDF e leva o mesmo desenho aos outros formatos.

## O que muda no código

1. **O processor devolve blocos, não texto.** Cada bloco tem o tipo (título com nível, parágrafo, lista, tabela), o texto
   e a página (ou a aba e a linha, ou o endereço da página do site). A estrutura vem do próprio formato: geometria do PDF,
   estilo do Word, árvore do Markdown, DOM do site, células da planilha, chaves do JSON. Nenhuma regex sobre o texto.
2. **O Chunker junta blocos por seção.**
   - Seção até ~400 tokens (~1.600 caracteres) vira um trecho só.
   - Seção maior se divide por parágrafo, nunca no meio da frase.
   - Seção menor que ~60 tokens se junta à irmã seguinte.
   - Sobreposição de 1 parágrafo.
   - Tabela grande sai em grupos de linhas com o cabeçalho repetido; cada linha como "Coluna: valor · Coluna: valor".
3. **Cada trecho começa com o caminho** (`Documento › Seção › Subseção`), que vai ao embedding. Página, linha e endereço
   vão ao metadado e ao modelo, não ao embedding.
4. **O título de 2 linhas** (Suhai, "9 – TABELA PARA CÁLCULO DA INDENIZAÇÃO EM CASO DE INVALIDEZ PERMANENTE"): duas linhas
   seguidas na letra de título, com o espaço de linha normal entre elas, são um título só. Hoje a 2ª linha vira corpo e
   a tabela herda um título partido. Sai pela fonte e pela posição que o PdfTrechos já entrega, sem regex e sem o
   `HEADING_MAX`. Os casos "tabela 9" e "braço inteiro" entram no gabarito do Suhai.
5. **Regex de título sai do Chunker** nos formatos que passam a dar blocos (`NUMBERED_HEADING`, `shouted_line?`, a
   divisão de FAQ por pergunta). Com o bloco vindo do formato, o Chunker não precisa adivinhar.
6. **O metadado do trecho** ganha `caminho`, `paginas` (de–até) ou `linha`/`aba`/`endereco`, e `secao_id`. A F3 usa o
   `secao_id` para mandar a seção inteira ao modelo.

### Planilha (XLSX e CSV): linhas em grupo, não 1 linha = 1 trecho

1 linha = 1 trecho deixa uma planilha grande com milhares de trechos. Isso custa embedding na ingestão e, na F2, 1
chamada paga por trecho na chave do cliente. A planilha real da régua (Curitiba, 7 abas, ~2.900 linhas) daria ~2.900
trechos.

- **A regra:** linhas seguidas da mesma aba e da mesma tabela se juntam até ~400 tokens, como a tabela grande do PDF.
  Cada grupo começa com o caminho (`Arquivo › Aba`) e o cabeçalho, e cada linha vai como "Coluna: valor · Coluna: valor".
- **O teto de linhas por trecho sai da medida:** 1, 5, 10 e 20 linhas por grupo. Mede-se hit@12, hit@1 e acerto na
  planilha real e na sintética, e fica o maior grupo que não perde busca. A F0 já mostrou o risco: juntar linhas sem
  cabeçalho piorou a planilha real (0,89 para 0,78–0,85).
- **Custo da F2 da maior planilha real:** com o grupo escolhido, conto os trechos da Curitiba e meço uma chamada de
  contexto por trecho numa amostra. O valor vai junto com a medida, dentro do teto da F2.
- O "retrato" de cada aba (colunas e número de linhas) continua sendo um trecho próprio, para "quais produtos vocês têm".

O que **não** muda na F1: a busca (Retriever), o Answerer e a recusa. A F1 só muda o que é gravado.

## Banco: índice

Medido hoje na produção, só leitura (Postgres 18.3, pgvector 0.8.1):

| | hub2you | autonomia |
|---|---|---|
| trechos ativos | 7.402 | 1.352 |
| com `embedding_large` | **0** | **0** |
| tabela (com índices) | 167 MB | 41 MB |
| índice ivfflat em `embedding` | 77 MB, **0 usos** | 21 MB, **0 usos** |
| `unaccent` | disponível, não instalado | disponível, não instalado |
| `maintenance_work_mem` | 64 MB | — |

- **ivfflat sem uso.** O índice foi criado com a operação padrão (distância L2), e a busca pede cosseno. O Postgres
  nunca o usa. Toda busca é **exata**: filtra pelo agente e ordena pela distância (108 ms hoje).
- **Migration do PR 1**, versão `20261108820000`, reservada pela Orquestração Deploy (vez 6 na fila de migrations):
  - `DROP INDEX CONCURRENTLY` do ivfflat sem uso;
  - `SET statement_timeout = 0` antes e o valor anterior de volta no fim. Os 14 s do `config/database.yml` matariam
    o comando no meio, como a `20261108310000_add_convite_uid_index_to_messages.rb` já trata;
  - o OK da migration é do Rodrigo, no próprio PR, com o rollback escrito; o parecer da Funções vem antes da fila.
- **HNSW só com prova.** O HNSW é busca aproximada. Com o filtro por agente (uma base pequena no meio de milhares de
  trechos de outras contas), ele pode devolver menos de 12 candidatos ou candidatos diferentes. O padrão do pgvector é
  `ef_search = 40`, com a busca iterativa desligada. O índice vale para todas as contas, com ou sem a flag: se piorar
  a busca, piora para todo mundo no deploy.
  - **A medida:** no banco local, uma carga que imita a produção, com várias contas e agentes e cerca de 9 mil trechos
    (as bases da régua mais contas de enchimento). Comparo o hit@12 e a lista dos 12 candidatos com o índice e na busca
    exata, com `hnsw.iterative_scan = relaxed_order` e `hnsw.ef_search` setados na própria consulta (`SET LOCAL`).
  - **Só entra se** o hit@12 for igual ao da busca exata em todas as bases. Aí o HNSW volta à migration, com a
    limpeza de índice INVALID que tenha sobrado (`DROP INDEX CONCURRENTLY IF EXISTS` antes de criar) e o tempo de
    criação: medido localmente em 51 s a 3 min 50 s com 8.800 vetores e 64 MB.
  - **Se não for igual**, o HNSW espera a busca exata ficar lenta. O PR traz os 108 ms de hoje e o resultado da medida.
- **`unaccent` sai do PR 1.** Ninguém o usa antes da F2. Entra na migration da F2, junto com a busca por texto, e a
  permissão de criar extensão se confere nessa hora.
- **`embedding_large` (0 trechos nas duas stacks).** A coluna e o índice HNSW dela ficaram de um teste anterior com
  text-embedding-3-large. Ninguém grava nela, porque `AUTONOMIA_EMBEDDING_MODEL` segue no small. A F1 não mexe nela. A
  F2 mede o 3-large com 1.536 dimensões na coluna `embedding`, como o n8n faz. Se ganhar, a coluna `embedding_large` e o
  índice dela podem sair, em PR próprio e com OK.

## Base já existente em produção: reprocessar

Sem reprocessar, os clientes de hoje não ganham nada: a F1 vale só para o que for ingerido depois do deploy. O objetivo
do Rodrigo é resposta melhor para quem já usa, então o reprocessamento faz parte da entrega.

- **Reprocessar** = rodar de novo a ingestão de cada fonte. Hoje são 20 fontes com trechos na hub2you e 14 na
  autonomia, com 6,1 milhões de caracteres.
- **O pacote que vai ao Rodrigo** traz, por conta:
  - o custo real de reprocessar: embedding, classificação, resumo por seção e revisão (pelo menos 3 chamadas pagas
    por fonte, que a ingestão já faz hoje), medido na régua com material do mesmo tamanho;
  - o ganho medido no placar, no formato daquela conta (o PDF, o MD, o site).
- **Reprocessar é decisão do Rodrigo.** A F1 não reprocessa sozinha. Com o OK, o reprocessamento roda fonte a fonte,
  com o conhecimento antigo mantido até o novo estar gravado (a ingestão já troca numa transação, e a extração vazia
  não apaga nada).
- **A F2 cobra 1 chamada por trecho na chave do cliente.** Depois da F1 os trechos ficam maiores e em menor número
  (cerca de 1.600 caracteres cada, contra 634 de média hoje). Na maior base de hoje, com ~650 mil caracteres, seriam
  cerca de 400 trechos e ~550 mil tokens de entrada. O valor em US$ por conta sai da medida da F2 no Suhai.

## Flag

- Uma flag por conta, `rag_corte_por_estrutura`. Ela decide se a ingestão usa os blocos novos ou o caminho antigo.
- Liga em todas as contas das duas stacks, pela regra nova.
- Posição 30 em `feature_flags_ext_2`, que é o bit 29 (bit = posição − 1; a posição é a ordem no `features.yml`).
  Reservada pela Orquestração. A posição 29 (bit 28) é da `prospeccao_nova` (#2712).
  - No `features.yml`, a flag vem logo depois da `prospeccao_nova`.
  - Se este PR entrar antes da #2712, a posição não sobe: fica um comentário no yml reservando a 29.
- Depois do NO AR, a Orquestração liga a flag em todas as contas ativas das 2 stacks, com backup.
- Desligar a flag volta a ingestão antiga para o próximo material; o que já foi ingerido fica como está.

## Os 2 PRs

**PR 1 — PDF**
- blocos do PDF digitado (título pela letra, título de 2 linhas, tabela por coluna alinhada, sumário fora, página);
- OCR com posição para o escaneado e para a página de imagem no PDF misto;
- Chunker por seção, para quem entrega blocos;
- metadado do trecho;
- migration: o ivfflat sem uso sai; o HNSW só entra com a prova da seção "Banco";
- flag.

**PR 2 — os outros formatos**
- XLSX e CSV, DOCX, MD, site, JSON, TXT e foto passam a entregar blocos;
- CSV passa a ser aceito.

Cada PR segue o processo: teste antes do código, agentes-ia-refactor-reviewer, caveman:cavecrew-reviewer fresco,
agentes-ia-refactor-tester com 18+ cenários, parecer da Funções, CI, pacote ao coordenador, "ok merge" do Rodrigo.

Não tem tela. Se um dia o dono for ver o que a base sabe, entra protótipo antes.

## A régua local

A worktree antiga foi apagada, e com ela os scripts locais da régua (`tmp/placar`, fora do git) e os 8 arquivos das bases
sintéticas.
- **O que ficou no git:** as perguntas e os gabaritos de todas as bases, a rake `autonomia:rag:placar`, o placar e o juiz.
- **O que eu refaço:**
  - as bases sintéticas, a partir dos gabaritos (todas as âncoras precisam estar no texto);
  - os scripts de ingestão por formato.
  - Desta vez os scripts entram no git, em `script/rag_placar/`, sem chave e sem dado de cliente.
- **Os três documentos reais** voltam pelas URLs públicas (Mapfre e Curitiba estão na linha de base; Suhai, a localizar
  de novo).
- **Comparação:** as bases sintéticas refeitas não são as mesmas de 31/10. A linha de base delas roda de novo na main
  antes da F1, dentro do teto de US$ 2. Os reais continuam comparáveis com 31/10.

## Custos

| etapa | teto | status |
|---|---|---|
| código da F1 | US$ 0 | — |
| medidas da F1 (main e PR 1 e 2, todas as bases, com resposta e juiz) | US$ 2 | espera OK |
| F2 + F3 (medidas, contexto por trecho, reordenação) | US$ 5 | espera OK |
| reprocessar bases de clientes | por conta, medido | decisão do Rodrigo, com custo e ganho por conta |
