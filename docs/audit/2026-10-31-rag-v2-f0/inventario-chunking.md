# Inventário do corte da base por formato (#1431, 31/10/2026)

Pedido do Rodrigo, pelo gestor: o corte do material precisa estar ótimo para a leitura do agente antes de subirmos. O
que está construído, formato por formato, o que mede e o que falta.

Fontes: código da `main` (500a644ec5) e do PR #2431 (`fix/1426-corte-pdf`, 272b641b1c), medida local e produção só
leitura (contagens por tipo, sem conteúdo). Sem gasto: nenhuma chamada de IA. Amostras: o PDF público da Condição Geral
Suhai Automóvel (74 páginas) e arquivos sintéticos criados para a medida.

## O caminho do material

1. **Extração (processor)**: cada formato vira texto puro. `Processors::Dispatcher` mapeia o tipo para a classe.
2. **Perfil (ChunkProfile)**: as 60 primeiras linhas do documento escolhem um perfil para o documento INTEIRO
   (`tabular` 300/60, `faq` 700/120, `list` 300/60, `prose` 900/140: teto/sobreposição em caracteres).
3. **Corte (Chunker)**: linha em branco fecha parágrafo; título é adivinhado por padrão de texto (linha curta numerada,
   linha em maiúsculas, `#`); o título corrente é repetido no início de cada pedaço da seção. Um pedaço FECHA assim que
   passa do piso (80 caracteres na prosa): **cada parágrafo vira um pedaço, nunca se juntam parágrafos até o teto**.
   Parágrafo maior que o teto cai numa janela deslizante.
4. **Metadado por pedaço**: título da seção, perfil, palavras-chave, tamanho. Página só no material com mais de 50
   páginas, e por bloco de 25 páginas (`paginas: [26, 50]`), e só na Fase 2.
5. **Embedding** (text-embedding-3-small) e gravação.

O defeito comum: **o processor joga fora a estrutura** (título, tabela, lista, página) **e o Chunker tenta adivinhá-la de
volta pelo texto**. Onde a adivinhação falha, o pedaço perde o contexto.

## Tabela-resumo

| Formato | Aceito (tela/API) | Em produção (fontes) | Extração | Título/seção | Tabela | Página | Nota | Para chegar a 10 | Esforço | Fase |
|---|---|---|---|---|---|---|---|---|---|---|
| PDF digitado | sim | 11 (5 hub2you, 6 autonomia) | pdf-reader; #2431 remonta parágrafos pela geometria | errado com frequência | 1 linha por pedaço, sem cabeçalho | só bloco de 25 p. | **3 → 5 com #2431** | título pela letra da página; tabela com cabeçalho; sem sumário; página por pedaço | G | F1+F2 |
| PDF escaneado / com imagem | sim | (contado acima) | tesseract, só se o PDF inteiro tem < 20 letras; 30 p.; só Fase 2 | bom quando a página é limpa | linhas soltas | não | **4** | OCR por página (PDF misto); página por pedaço; teto de páginas visível | M | F1 |
| XLSX | sim | 0 | roo, linha = "a \| b \| c" | nome da aba só no 1º pedaço | cabeçalho vira pedaço à parte; linhas sem nome de coluna | — | **3** | "Coluna: valor" em cada linha + aba; juntar linhas pequenas | P | F1 |
| CSV / XLS | **não** | — | — | — | — | — | — | aceitar CSV pelo mesmo caminho do XLSX | P | F1 |
| DOCX | sim | 3 | XML, parágrafo e tabela | estilos de título ignorados | linhas juntam no parágrafo | — | **4** | estilo Título → seção; parágrafo separado; tabela com cabeçalho | P | F1 |
| DOC (antigo) | **não** | — | — | — | — | — | — | fora (pedir DOCX/PDF) | — | — |
| JSON | sim | 0 | 1 objeto = 1 linha | — | objeto filho perde o pai | — | **6** | levar o nome do pai ao objeto filho | P | F1 |
| MD | sim | 12 (9+3), corte antigo | tira `#`, `*`, `_`, links | **apagados** | cabeçalho à parte | — | **2** | manter `#` como seção; não apagar `_`; tabela com cabeçalho; recortar as 12 bases | P | F1 |
| TXT | sim | 0 | bytes | só se numerado/maiúsculo | — | — | **6** | juntar parágrafos da seção | P | F2 |
| Foto / imagem | sim (só na criação do agente) | 0 | tesseract | se a foto tem texto | linhas soltas | — | **4** | imagem sem texto (foto de produto) não vira nada; descrição pelo modelo | M | F3 |
| Site / URL | sim | 8 (3+5) | 1 página, Nokogiri `text` | **perdidos** | **células coladas** | — | **2** | bloco por bloco; h1–h6 como seção; tabela; acento; página JS | M | F1 |
| Áudio / vídeo | **não** | — | — | — | — | — | — | fora deste tema | — | — |
| PPTX, ODT, RTF, HTML arquivo, EPUB | **não** | — | — | — | — | — | — | fora deste tema | — | — |

Notas de 0 a 10, para "o pedaço chega ao agente com o contexto de que ele precisa para responder certo e dizer de onde
veio". Formatos fora da lista: a tela filtra pela extensão (`useFileDrop`: pdf, docx, xlsx, txt, md, json; foto só no
compositor da criação) e a API recusa o tipo (`Source::SOURCE_TYPES`). **Não existe formato aceito sem processor.**

## Produção (só leitura, 31/10, as duas stacks)

| Tipo | Fontes | Pedaços | Média (caracteres) | Pedaços < 120 | Com título |
|---|---|---|---|---|---|
| md | 12 | 2.952 | 1.702 | 0% | 0% |
| pdf | 11 | 5.017 | 150 | 41% (hub2you), 68% (autonomia) | 98% / 31% |
| link | 8 | 153 | 310 | 0–2% | 0–16% |
| docx | 3 | 576 | 254–811 | 0–1% | 0% |

- Os 12 MD (média 1.702, sem perfil, sem título) foram cortados por uma versão antiga do Chunker e **nunca reprocessados**:
  nenhuma melhoria do corte chega a eles sem reprocessar. Reprocessar é escrita em produção (decisão do Rodrigo).
- 315 pedaços de PDF e 17 de link na stack autonomia também não têm perfil: corte antigo.
- xlsx, json, txt e foto: nenhuma fonte em produção.

## Por formato

**PDF digitado — 3 hoje, 5 com o #2431.** Extração pelo `pdf-reader`; na `main` o `page.text` põe linha em branco falsa
no meio do parágrafo e o Suhai vira 1.206 pedaços (mediana 186, mínimo 27). O #2431 remonta os parágrafos pela posição
das linhas e tira o rodapé corrido: 762 pedaços (mediana 232, máximo 932), e das 18 âncoras do placar, 14 cabem inteiras
num pedaço (13 na main). Defeitos que continuam, medidos no Suhai com o #2431:
- **Título errado**: o título "9 – TABELA PARA CÁLCULO… INVALIDEZ" fica no meio de um parágrafo e não é reconhecido; os
  pedaços da tabela herdam "4 – PERDA DE DIREITOS" (96 pedaços com esse título). Com o #2431, os títulos distintos caem de
  116 para 58, porque mais títulos ficam colados no texto ao lado.
- **Tabela**: cada linha vira um pedaço ("- Ectrópio bilateral 06", 45 a 65 caracteres), sem o título nem as colunas.
  A busca acha a linha e o agente não sabe de que tabela ela é.
- **Sumário**: 39 pedaços são linhas de sumário com pontilhado ("3. DEFINIÇÕES......5"), ruído que compete na busca.
- **Página**: não há página por pedaço; "de onde veio" só aponta um bloco de 25 páginas, e só em material grande.
- Colunas e texto girado seguem a ordem do `page.text`.

Para 10: o processor já sabe o tamanho da letra de cada linha (é como o #2431 separa parágrafo de título). Ele pode
marcar a linha de título como seção, em vez de o Chunker adivinhar pelo texto. Também falta: tabela com o cabeçalho
repetido em cada grupo de linhas, sumário fora, e a página de cada pedaço. G, F1 (página) e F2 (seção e tabela). O
processor é área da #1426: só depois do merge do #2431 e com aviso a ela.

**PDF escaneado / com imagem — 4.** O OCR (tesseract, português, 60 s por página, 30 páginas, prazo de 300 s) só roda
quando o PDF INTEIRO tem menos de 20 letras, e só na Fase 2. Medido numa página do Suhai rasterizada: 17 pedaços,
títulos reconhecidos, texto limpo. Defeitos: um **PDF misto** (texto e páginas digitalizadas, ou tabela como imagem) não
lê as páginas de imagem, e elas somem sem aviso; acima de 30 páginas, o resto fica de fora (o material registra quantas
ficaram). Para 10: OCR por página quando a página não tem texto, e página por pedaço. M, F1.

**XLSX — 3.** Cada linha da planilha vira um pedaço de cerca de 35 caracteres. A linha de cabeçalho vira um pedaço à
parte: "Mouse Sem Fio | 99 | 6 meses | 40" chega ao agente sem saber que 40 é o estoque. O nome da aba só aparece no
primeiro pedaço. Para 10: cada linha como "Produto: Mouse Sem Fio · Preço: 99 · Garantia: 6 meses · Estoque: 40 (aba
Preços)", juntando linhas curtas até o teto. **CSV e XLS não são aceitos**; CSV entra pelo mesmo caminho. P, F1.

**DOCX — 4.** Extrai parágrafos e tabelas na ordem. Os estilos de título do Word (Título 1, 2…) são ignorados, e os
parágrafos são unidos por uma quebra simples, que o Chunker lê como o mesmo parágrafo. Medido: um documento com dois
títulos, dois parágrafos e uma tabela virou **1 pedaço**, com a tabela achatada ("Plano | Preço Básico | R$ 99…"). Para
10: estilo de título vira seção, parágrafo separado, tabela com cabeçalho por linha, e listas. P, F1.

**JSON — 6.** O melhor hoje: cada objeto vira um registro com todos os campos ("nome Notebook Pro 15 | sku NB-15 | preco
4999"). Defeito: o objeto filho sai separado do pai ("produtos.specs: ram 16GB | ssd 512GB", sem dizer de qual
produto). Para 10: o filho leva o nome do pai. P, F1.

**MD — 2.** O processor apaga os `#` dos títulos ANTES do corte, e o Chunker deixa de reconhecê-los: 0 de 9 pedaços com
título na amostra. Ele também apaga `_` e `*` dentro das palavras: o e-mail `contato_loja@exemplo.com.br` virou
`contatoloja@exemplo.com.br` (**dado corrompido**). Itens de lista viram pedaços de 20 caracteres; a tabela fica com o
cabeçalho num pedaço à parte. Em produção, as 12 bases MD estão no corte antigo: média de 1.702
caracteres e nenhum título. Para 10: manter os títulos como seção, não apagar caracteres dentro de palavras, lista e
tabela juntas na seção, e reprocessar as 12. P, F1.

**TXT — 6.** Texto puro, parágrafo por pedaço. Funciona em texto simples; título só quando numerado ou em maiúsculas,
o que é o esperado num TXT. Falta juntar parágrafos curtos da mesma seção (comum a todos). P, F2.

**Foto / imagem — 4.** Só na criação do agente (o compositor do assistente), com OCR. Foto com texto (cardápio, tabela
de preço) lê; o layout de colunas se perde. Foto sem texto (produto, ambiente) não gera nada. Para 10: descrição da
imagem pelo modelo (é IA paga). M, F3.

**Site / URL — 2.** Baixa uma página só (sem rastrear o site), tira menu, cabeçalho e rodapé, e usa o texto do
Nokogiri, que cola os blocos sem espaço. Medido:
- "Plano Fibra 300" + "300 megas" virou **"Plano Fibra 300300 megas"**: o número sai errado;
- as células da tabela colam: "PlanoFidelidadeFibra 30012 meses";
- sem `<meta charset>` na página, o acento sai trocado ("trÃªs", "mÃªs"): o charset que vem no cabeçalho HTTP é ignorado;
- h1/h2 não viram seção;
- página montada por JavaScript volta vazia.
Para 10: extrair bloco a bloco, com quebra entre blocos, h1–h6 como seção, tabela com cabeçalho, e o charset da
resposta. M, F1. Rastrear mais páginas do site é recurso novo, não conserto.

## O que é do corte (ingestão) e o que é da busca

| Problema | Resolve no corte | Resolve na busca |
|---|---|---|
| Título errado ou perdido, tabela sem cabeçalho, página, sumário, pedaço pequeno demais | sim | não |
| Texto corrompido (site colado, `_` do MD, acento) | sim | não |
| Pergunta curta que depende da conversa ("e pra moto?") | não | sim (F1a) |
| Termo exato (código, número, nome) | ajuda (cabeçalho) | sim (busca combinada, F2) |
| Trecho certo fora do top 12 | ajuda | sim (reordenação, F3) |
| Resposta espalhada em vários pedaços da seção | sim (seção inteira gravada) | sim (trazer a seção, F2) |
| Base pequena | não | sim (inteira no prompt, F3) |

## A proposta: o processor entrega estrutura, o Chunker não adivinha

Em vez de cada processor devolver texto puro, ele devolve **blocos**: título (com nível), parágrafo, linha de tabela
(com o cabeçalho), item de lista, página. Os dados para isso já existem em cada formato: tamanho da letra no PDF,
estilo no DOCX, `#` no MD, `h1`–`h6` no site, cabeçalho e aba no XLSX. O Chunker então:
- junta blocos da mesma seção até o teto (fim do pedaço de 80 caracteres);
- começa cada pedaço com o caminho "Documento › Seção › Subseção";
- repete o cabeçalho da tabela em cada grupo de linhas;
- grava a página de início e fim;
- deixa o sumário de fora.

Isso tira a adivinhação por padrão de texto do Chunker e vale para todos os formatos de uma vez. Ordem proposta:
1. **F1 (P cada)**: consertos de extração que corrompem ou apagam (site colado e acento, MD, DOCX, XLSX com cabeçalho,
   CSV, JSON pai) e OCR por página.
2. **F2 (G)**: blocos estruturados + Chunker por seção (o defeito do título no meio do parágrafo e a tabela do Suhai
   entram aqui), com o PDF depois do merge do #2431.
3. **Reprocessar as bases de produção**: sem isso, nada muda para os agentes que já existem (12 MD e os PDF antigos).
   O embedding custa pouco (cerca de 8,7 mil pedaços, menos de US$ 0,05); o classificador da fonte é IA paga (cerca de
   US$ 0,05 por fonte, umas 34 fontes). É escrita em produção: decisão do Rodrigo.

Cada passo provado no placar (hit@k, âncora inteira num pedaço, fidelidade) contra a linha de base.
