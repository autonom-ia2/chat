# Desenho-alvo do corte por formato (#1431, 31/10/2026)

Pedido do Rodrigo: como cada formato DEVE ser lido e cortado para o agente acertar em 95% ou mais. O estado de hoje
está em `inventario-chunking.md`; as medidas, em `linha-de-base-suhai.md`. Escrito sem gasto de IA.

## Resumo

| Formato | Hoje | Alvo | O que muda | Esforço | Ordem |
|---|---|---|---|---|---|
| PDF digitado | 3 (hit@12 0,59; 0,88 com o #2431) | ≥ 95% com F2+F3 | título e tabela pela geometria, página por pedaço, sumário fora, junção por seção | G | 1 |
| MD | 2 | ≥ 95% | ler pela árvore do Markdown (commonmarker, já no projeto), sem apagar nada | P | 2 |
| Site / URL | 2 | ≥ 95% em página estática; não lê página feita em JavaScript | blocos do DOM, h1–h6 como seção, tabela, charset certo | M | 3 |
| DOCX | 4 | ≥ 95% | estilos de título, listas e tabelas do próprio Word | P | 4 |
| PDF escaneado / misto | 4 | 90–95% em digitalização limpa; 80–90% em foto de celular | OCR por página, com a posição das linhas; mesmas regras do PDF digitado | M | 5 |
| XLSX / CSV | 3 (CSV não aceito) | ≥ 95% em "quanto custa X"; conta sobre a tabela (o mais barato, quantos) só com F3 | 1 linha = 1 pedaço com o nome das colunas; CSV pelo mesmo caminho | P | 6 |
| JSON | 6 | ≥ 95% | objeto com o caminho do pai | P | 7 |
| TXT | 6 | 90–95% (texto sem estrutura) | junção por parágrafos até o teto | P | 8 |
| Foto | 4 | 85–90% (cardápio, tabela de preço); foto sem texto só com IA de visão (F3) | OCR com posição; descrição pelo modelo de visão | M | 9 |
| PPTX (novo) | não aceito | ≥ 95% | 1 slide = 1 seção, com o título do slide e as notas | M | 10, se houver pedido |

"Hoje" é a nota do inventário (0 a 10), salvo onde há medida. A ordem segue o uso em produção (pdf 11 fontes, md 12,
site 8, docx 3) e o tamanho do ganho. Áudio, vídeo, DOC antigo, ODT, RTF e EPUB ficam fora: DOC e ODT pedem "salve como
DOCX ou PDF"; áudio e vídeo são transcrição, outro tema.

**Honestidade sobre os 95%.** O corte sozinho não chega a 95% em nenhum formato rico. Ele leva o PDF do Suhai de 0,59
para 0,88 (hit@12) e garante que a resposta exista inteira num pedaço (17 de 17 âncoras). O que falta para 95% é da
busca: pergunta curta que depende da conversa (F1a), termo exato e sinônimo (busca combinada, F2), trecho certo fora do
topo (reordenação, F3) e base pequena inteira no prompt (F3). Conta sobre tabela ("o mais barato", "quantos") não se
resolve com pedaço nenhum: precisa da tabela inteira no prompt (F3) ou de uma ferramenta de consulta.

## A peça comum a todos os formatos

Hoje cada processor devolve texto puro, e o Chunker adivinha título e tabela por padrão de texto. O alvo inverte isso:

1. **O processor devolve blocos**, lidos da estrutura que o próprio formato já tem (nenhuma regra de idioma, nenhuma
   regex sobre o que a pessoa escreveu):
   - `titulo` (com o nível: 1, 2, 3…);
   - `paragrafo`;
   - `lista` (os itens juntos);
   - `tabela` (cabeçalho e linhas, separados);
   - `pagina` (a página de início e de fim de cada bloco, quando o formato tem página).
2. **O Chunker junta blocos por seção.** Uma seção é tudo o que vem sob um título, até o próximo título do mesmo nível ou
   acima.
3. **Cada pedaço começa com o caminho**: `Documento › Seção › Subseção`. O caminho vai no texto do embedding (é ele que
   faz "franquia" achar o pedaço da seção FRANQUIA) e vai ao modelo, que cita de onde tirou.
4. **O metadado do pedaço** guarda: o caminho, a página (de–até), a linha da planilha ou o endereço da página, o id da
   seção e o tipo do bloco. Página, linha e endereço vão ao modelo para o "de onde veio"; não vão ao embedding (número
   de página só atrapalha a busca).

### Tamanho e sobreposição

- **Alvo: seção inteira até ~400 tokens (~1.600 caracteres em português).** Seção maior se divide por parágrafo, nunca
  no meio da frase, em pedaços de ~400 tokens. Seção menor que ~60 tokens se junta à irmã seguinte (mesmo pai).
- **Sobreposição: 1 parágrafo** (o último do pedaço anterior abre o seguinte), não um número fixo de caracteres. Assim
  uma resposta que cruza a divisa cabe inteira em um dos dois.
- **Por que 400.** No Suhai, com pedaços de mediana 232 caracteres (~60 tokens), as 17 respostas já cabem inteiras, mas
  a pergunta "bater no carro de outra pessoa" não acha a RCF-V, porque a definição e a cobertura estão em pedaços
  separados. Pedaço de 400 tokens junta a seção, e 12 pedaços de 400 tokens são ~5 mil tokens no prompt: cabe com folga.
  O número é ponto de partida: a F2 mede 250, 400 e 600 no placar (só busca, cerca de US$ 0,01 por medida) e fica o
  melhor.
- **Seção inteira na resposta (F2, lado da busca):** quando um pedaço de uma seção pequena acerta, o modelo recebe a
  seção inteira (até ~1.200 tokens). Isso precisa do id da seção gravado no corte.

### Tabela (vale para PDF, DOCX, MD, site e planilha)

- **Tabela pequena** (até ~400 tokens): um pedaço só, em Markdown, com o caminho e o título da tabela.
- **Tabela grande:** grupos de linhas até ~400 tokens, com o cabeçalho repetido em cada grupo e o título da tabela no
  caminho. Cada linha vira "Coluna: valor · Coluna: valor", para que "Ectrópio bilateral 06" chegue como
  "Tabela de invalidez › Lesão: Ectrópio bilateral · Percentual: 06" (os nomes das colunas saem do cabeçalho da própria
  tabela).
- **Tabela de consulta** (planilha, catálogo): 1 linha = 1 pedaço (abaixo, em XLSX).

## Por formato

### PDF digitado

1. **Unidade:** seção inteira até ~400 tokens; tabela pela regra das tabelas.
2. **Estrutura, pela geometria do PDF** (o PdfParagrafos do #2431 já lê linha a linha, com o tamanho da letra):
   - **título** = linha cuja letra é maior que a do corpo da página, ou negrito curto seguido de corpo. O nível sai do
     tamanho da letra (maior = nível 1). Isso substitui o `Chunker#heading?` por padrão de texto, que o gestor pediu para trocar;
   - **parágrafo** = linhas na mesma letra com espaço normal entre elas (já feito no #2431);
   - **sumário** = página em que a maioria das linhas termina num número alinhado à direita: sai inteira. Hoje são 39
     pedaços de ruído no Suhai;
   - **tabela** = linhas consecutivas cujos trechos começam nas mesmas posições horizontais (colunas alinhadas). O
     cabeçalho é a primeira linha do grupo;
   - **duas colunas** = trechos da página agrupados pela posição horizontal; lê a coluna da esquerda inteira, depois a
     da direita;
   - **cabeçalho e rodapé corridos** saem (já feito no #2431);
   - **página** de cada linha vai junto com o bloco.
3. **No pedaço:** `Nome do arquivo › Seção › Subseção`, página de–até.
4. **Tabela:** regra das tabelas. Tabela de invalidez do Suhai = tabela grande, grupos de linhas com cabeçalho.
5. **Tamanho:** 400 tokens, sobreposição de 1 parágrafo.
6. **Casos difíceis:**
   - título no meio do parágrafo (Suhai, "9 – TABELA…"): resolvido pela letra, não pelo texto;
   - tabela sem linhas de grade: pela coluna alinhada; tabela desenhada como imagem: cai no OCR da página;
   - PDF com letras sem espaço (Suhai): resolvido no #2431 (c7cf171d83: 0% de palavra colada);
   - texto girado: sai na ordem do pdf-reader (raro em material de atendimento);
   - PDF protegido sem texto extraível: vira PDF escaneado.
7. **Medida:** Suhai (público, 22 perguntas hoje, ampliar para 40) + uma segunda condição geral pública com tabela e
   duas colunas, 40 perguntas. Alvo: hit@12 ≥ 0,95, acerto ≥ 0,95 (revisado por pessoa nos erros do juiz), recusa 5 de 5,
   de onde veio ≥ 0,90. Hoje: hit@12 0,59 (main), 0,88 (#2431); acerto 10/17 (main), 14/17 (#2431).
8. **Fora do corte:** sinônimo e termo exato (F2), pergunta que depende da conversa (F1a), reordenação (F3). A distância
   não separa "tem" de "não tem" (medido): a recusa fica com o modelo.

### PDF escaneado ou misto

1. **Unidade:** a do PDF digitado.
2. **Estrutura:** OCR **por página** (não só quando o PDF inteiro não tem texto): página com pouco texto extraível vai
   ao tesseract, que devolve as linhas com a posição e a altura da letra (saída TSV/hOCR, já disponível no tesseract da
   imagem). A partir daí, as mesmas regras de título, parágrafo e tabela do PDF digitado.
3. **No pedaço:** o mesmo, com a página.
4. **Tabela:** pela coluna alinhada no OCR; a qualidade cai com digitalização torta.
5. **Tamanho:** o mesmo.
6. **Casos difíceis:**
   - PDF misto (texto + páginas digitalizadas): hoje as páginas de imagem somem sem aviso; com OCR por página, entram;
   - foto de documento tirada com celular (perspectiva, sombra): o OCR erra palavras; o placar mostra quanto;
   - mais de 30 páginas para OCR: hoje o resto fica de fora. O alvo processa todas em segundo plano, com o tempo por
     página como proteção contra defeito, sem limite de quantidade (regra: nenhum teto no uso do cliente);
   - página com figura sem texto: só com IA de visão (F3, paga).
7. **Medida:** o Suhai rasterizado (100% imagem) e um misto (metade das páginas como imagem), feitos a partir do PDF
   público, com as mesmas 40 perguntas. Alvo: hit@12 ≥ 0,90 em digitalização limpa. Hoje: 0 nas páginas de imagem de um
   PDF misto (não são lidas).
8. **Fora do corte:** o erro do OCR em si. Acima de ~95% de palavras certas, a busca combinada (F2) compensa parte.

### XLSX e CSV

1. **Unidade:** 1 linha = 1 pedaço, com o nome das colunas: `Arquivo › Aba Preços › linha 12: Produto: Mouse Sem Fio ·
   Preço: 99 · Garantia: 6 meses · Estoque: 40`. E 1 pedaço por aba com o "retrato" dela (colunas e número de linhas),
   para "quais produtos vocês têm".
2. **Estrutura:** as células da própria planilha (roo). O cabeçalho é a primeira linha não vazia da aba. CSV pela
   biblioteca CSV do Ruby, testando `,`, `;` e tab e ficando com o separador que dá o mesmo número de colunas em todas
   as linhas.
3. **No pedaço:** aba, número da linha, cabeçalho. O número da linha vai ao modelo ("linha 12 da aba Preços").
4. **Tabela:** é a própria planilha.
5. **Tamanho:** uma linha (normalmente 20–80 tokens). Linha com texto longo numa célula segue a regra de tamanho.
6. **Casos difíceis:**
   - várias tabelas numa aba, separadas por linha vazia: cada bloco com o seu cabeçalho;
   - célula mesclada: o valor vale para as linhas que ela cobre;
   - número, data e moeda: o valor formatado como aparece na planilha, não o número cru (hoje sai o cru);
   - fórmula: o valor calculado.
7. **Medida:** catálogo sintético de 300 linhas, 8 colunas, 3 abas; 40 perguntas de consulta ("quanto custa", "tem
   garantia de quanto", "tem em estoque"). Alvo: hit@12 ≥ 0,95. Hoje: 3 no inventário (a linha chega sem o nome das
   colunas); CSV não é aceito.
8. **Fora do corte:** conta sobre a tabela ("o mais barato", "quantos têm garantia de 12 meses", "some"). Pedaço nenhum
   responde: precisa da planilha inteira no prompt (F3, quando é pequena) ou de uma ferramenta de consulta à planilha
   (nova). Sem isso, essas perguntas não chegam a 95%.

### DOCX

1. **Unidade:** seção inteira até ~400 tokens.
2. **Estrutura:** os estilos do próprio Word (Título 1, 2, 3 e o nível de tópico `w:outlineLvl`), listas numeradas e com
   marcador (`w:numPr`), tabelas (`w:tbl`, primeira linha como cabeçalho), caixas de texto. Cabeçalho e rodapé da página
   saem; alterações controladas valem como aceitas; nota de rodapé entra no fim da seção.
3. **No pedaço:** `Arquivo › Seção › Subseção`. DOCX não tem página (quem pagina é o Word): fica sem.
4. **Tabela:** regra das tabelas.
5. **Tamanho:** o padrão.
6. **Casos difíceis:** documento sem estilo de título (tudo "Normal" em negrito): usa negrito curto seguido de corpo,
   como no PDF; imagem com texto dentro: fica fora (o texto alternativo entra).
7. **Medida:** documento sintético de política de atendimento, 15 páginas, com títulos, listas e 3 tabelas; 30
   perguntas. Alvo: hit@12 ≥ 0,95. Hoje: 4 (um documento com 2 títulos e uma tabela vira 1 pedaço).
8. **Fora do corte:** o mesmo do PDF (F1a, F2, F3).

### MD

1. **Unidade:** seção inteira até ~400 tokens.
2. **Estrutura:** a árvore do Markdown (commonmarker, já no Gemfile): títulos `#`, listas, tabelas, blocos de código,
   citações e links. **Nada é apagado**: hoje os `#` somem antes do corte, `_` some dentro de palavras (e-mail
   corrompido) e o endereço dos links some (derruba o botão de link da #1479).
3. **No pedaço:** o caminho dos títulos. O link vira "texto (endereço)".
4. **Tabela:** regra das tabelas.
5. **Tamanho:** o padrão.
6. **Casos difíceis:** cabeçalho de metadados no topo (front matter): sai; HTML dentro do MD: lido como texto; título
   pulando nível (`#` e depois `###`): o caminho segue o nível real.
7. **Medida:** manual sintético de 20 seções com links, listas e 2 tabelas; 30 perguntas, 5 delas sobre o endereço de um
   link. Alvo: hit@12 ≥ 0,95 e o link certo nas 5. Hoje: 2 (0 de 9 pedaços com título na amostra).
8. **Fora do corte:** o de sempre. As 12 bases MD de produção só melhoram depois do reprocessamento (aprovado pelo
   Rodrigo para depois dos passos 1 e 2).

### TXT

1. **Unidade:** grupo de parágrafos até ~400 tokens.
2. **Estrutura:** só a linha em branco (parágrafo). Sem título no formato, não há seção: o caminho é só o nome do
   arquivo.
3. **No pedaço:** o nome do arquivo e o número do parágrafo inicial.
4. **Tabela:** não existe no formato.
5. **Tamanho:** o padrão, sobreposição de 1 parágrafo.
6. **Casos difíceis:** FAQ em texto ("P:" e "R:"): pergunta e resposta ficam juntas por estarem no mesmo parágrafo;
   texto colado sem nenhuma linha em branco: divisão por frase até o teto.
7. **Medida:** FAQ sintético de 40 pares e um texto corrido de 20 páginas; 30 perguntas. Alvo: hit@12 ≥ 0,95 no FAQ,
   ≥ 0,90 no texto corrido. Hoje: 6.
8. **Fora do corte:** sem título, o caminho não ajuda a busca; a busca combinada (F2) compensa.

### Foto

1. **Unidade:** a foto inteira, se couber em ~400 tokens; senão, blocos do OCR.
2. **Estrutura:** OCR com a posição das linhas (como no PDF escaneado). Foto sem texto (produto, ambiente): descrição
   pelo modelo de visão (F3, IA paga, por foto).
3. **No pedaço:** o nome do arquivo.
4. **Tabela:** cardápio e tabela de preço pela coluna alinhada do OCR.
5. **Tamanho:** o padrão.
6. **Casos difíceis:** foto torta, reflexo, letra pequena; texto à mão.
7. **Medida:** 10 fotos sintéticas (cardápio e tabela de preço impressos e fotografados), 30 perguntas. Alvo: hit@12 ≥
   0,85. Hoje: 4.
8. **Fora do corte:** a qualidade da foto. 95% não é realista em foto de celular; o placar diz quanto chega.

### Site / URL

1. **Unidade:** seção inteira até ~400 tokens.
2. **Estrutura:** o DOM da página (Nokogiri, já no projeto):
   - h1–h6 → seção;
   - p, li, td, blockquote → blocos, **com quebra entre eles** (hoje "Plano Fibra 300" + "300 megas" vira "300300 megas");
   - table → regra das tabelas;
   - conteúdo principal: `main` ou `article` quando existem; menu, cabeçalho, rodapé, aside e aviso de cookies saem;
   - charset: o do cabeçalho HTTP, depois o `<meta>`; hoje sem `<meta>` o acento quebra.
3. **No pedaço:** `Título da página › Seção`, e o endereço da página (vai ao modelo; é o que o botão de link da #1479
   usa).
4. **Tabela:** regra das tabelas.
5. **Tamanho:** o padrão.
6. **Casos difíceis:**
   - página feita em JavaScript (o texto só aparece no navegador): a imagem não tem navegador. O alvo DETECTA (página
     com quase nenhum texto) e diz ao dono "não consegui ler esta página, mande o conteúdo em PDF". Ler de verdade exige
     navegador no servidor: decisão de infra;
   - várias páginas do site: hoje só a página dada. Ler o site inteiro (mesmo domínio, pelo mapa do site) é recurso novo,
     decisão do Rodrigo.
7. **Medida:** 5 páginas HTML sintéticas e estáticas (planos, FAQ, tabela de preços, contato), uma delas sem `<meta
   charset>` e uma minificada; 30 perguntas. Alvo: hit@12 ≥ 0,95. Hoje: 2.
8. **Fora do corte:** página em JavaScript (não lê); o resto é o de sempre.

### PPTX (novo, se houver pedido)

1. **Unidade:** 1 slide = 1 seção, com o título do slide e as notas do apresentador.
2. **Estrutura:** o XML do próprio PPTX (zip, como o DOCX): título do slide, caixas de texto, tabelas, notas.
3. **No pedaço:** `Arquivo › Slide 7: título`.
4. **Tabela:** regra das tabelas.
5. **Tamanho:** o slide; slides curtos seguidos se juntam até ~400 tokens.
6. **Casos difíceis:** slide só com imagem: IA de visão (F3).
7. **Medida:** apresentação sintética de 30 slides, 30 perguntas. Alvo: hit@12 ≥ 0,95.
8. **Fora do corte:** o de sempre.

## Como medir 95% sem se enganar

- **Base de teste:** pública ou sintética, nunca de cliente. As sintéticas são escritas para o teste e ficam no repo, com
  as perguntas.
- **Perguntas:** 30 a 40 por formato, não 20. Com 20 perguntas, uma errada derruba 5 pontos, e 95% vira "no máximo 1
  erro"; com 40, cada erro vale 2,5 pontos. Cerca de 15% das perguntas de fora da base.
- **Métricas-alvo por formato:**
  - hit@12 ≥ 0,95 (a resposta chega ao agente);
  - acerto ≥ 0,95, com os "errados" do juiz revistos por uma pessoa. O juiz de hoje é severo com detalhe: no Suhai, 2 dos
    7 erros da main eram resposta certa julgada errada. Sem revisão, o alvo honesto do juiz sozinho é ≥ 0,90;
  - recusa correta = 100% nas de fora;
  - de onde veio ≥ 0,90.
- **Custo:** só busca, cerca de US$ 0,01 por base e rodada; com resposta e juiz, cerca de US$ 0,007 por pergunta, ou seja
  US$ 0,28 por formato com 40 perguntas. Medir todos os formatos uma vez: cerca de US$ 2,50.
- **Régua por PR:** cada PR de corte roda o placar do formato que toca e mostra o antes e o depois; nenhum PR piora
  outro formato (o placar de todos roda no fim de cada fase).

## Ordem proposta

1. **F1, consertos que corrompem ou apagam (P cada):** MD pela árvore, site pelos blocos e charset, DOCX pelos estilos,
   CSV aceito, XLSX com o nome das colunas, JSON com o pai.
2. **F2, blocos e junção por seção (G):** o Chunker novo, comum a todos; o PDF depois do merge do #2431 (título pela
   letra, tabela pela coluna, sumário fora, página); OCR por página. Junto, do lado da busca: busca combinada,
   cabeçalho de contexto e seção inteira na resposta.
3. **Reprocessar as 34 bases de produção** (aprovado pelo Rodrigo para depois dos passos 1 e 2).
4. **F3:** reordenação, base pequena inteira no prompt, planilha inteira para contas, IA de visão para foto sem texto.
5. **Medir todos os formatos** contra os alvos acima; o que não chegar fica escrito com o número.

O primeiro passo antes de qualquer código: montar as bases sintéticas e as perguntas de cada formato (sem gasto) e medir a
linha de base de todas (só busca: cerca de US$ 0,10; com resposta e juiz: cerca de US$ 2,50, que pede OK).
