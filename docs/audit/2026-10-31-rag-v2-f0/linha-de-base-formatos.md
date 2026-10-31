# Linha de base do RAG por formato (#1431, F0) — 31/10/2026

O quanto o agente acha e responde certo, hoje, em cada formato de material que o dono sobe. É a régua contra a qual a
F1 e a F2 serão medidas. Tudo rodou no banco LOCAL de teste, pela pipeline real (processor, Chunker, classificador,
embedding, Retriever, Answerer em `prova: true`), no código da `main` (base 1696928724) com o placar do PR #2438.
Nada em produção.

## Bases e perguntas

- **Dois documentos reais e públicos** (a régua difícil):
  - PDF Suhai: Condição Geral do seguro auto, 74 páginas. Já era a base do placar.
  - PDF Mapfre (`pdf-real2`): Condições Contratuais do Seguro Residencial v3.0, 71 páginas. Fonte:
    https://www.mapfre.com.br/media/cg_residencial_3-0.pdf.
  - XLSX da Prefeitura de Curitiba (`xlsx-real`): Tabela de Custos Unitários da SMOP, abril/2022, com 7 abas e cerca
    de 2.900 linhas. Fonte: https://mid.curitiba.pr.gov.br/2024/00443250.xlsx.
- **Oito bases sintéticas**, de empresas fictícias e sem dado real: XLSX (provedor de internet), JSON (clínica),
  DOCX (academia), TXT (pousada), MD (app de delivery), site (oficina, uma página HTML), PDF escaneado (escola de
  idiomas, só imagem) e foto (5 fotos de celular de uma marmitaria).
- **Perguntas:** 30 a 40 por base (392 no total), escritas como cliente escreve no WhatsApp. São 7 a 8 de fora da
  base, e as respondíveis cobrem os tipos fato simples, valor, linha de tabela, paráfrase, seção longa, agregação e,
  nos reais, valor exato de tabela e pergunta que cruza seções. Gabaritos em `gabaritos/`.
- **Âncoras:** antes de medir, cada âncora foi conferida contra o texto-fonte, o texto extraído pelo processor real e
  os pedaços. Todas estão no texto-fonte. As que a extração perde são achados, não defeitos do gabarito (PDF Mapfre: 6
  das 32).
- **Tamanhos:** além do corte de hoje ("atual"), medi 250, 400 e 600 tokens (cerca de 4 caracteres cada) em todos os
  formatos. O Chunker de hoje fecha um pedaço por parágrafo, então só trocar o máximo não muda quase nada (no PDF, 250
  dá os mesmos 1.207 pedaços). Por isso a medida simula o desenho-alvo: o Chunker corta, e os pedaços seguidos da
  mesma seção são juntados até o tamanho. Só a busca foi medida nos tamanhos; resposta e juiz, só no corte de hoje.

## A tabela

Corte de hoje. **Acerto e recusa revisados à mão** (ver "O juiz" abaixo). Entre parênteses, o que o juiz do autoteste
deu.

| formato | hit@12 | acerto | recusa | de onde veio | custo da rodada |
|---|---|---|---|---|---|
| **PDF Suhai (real)** | **0,59** | **0,79** (0,69) | 1,00 (0,75) | 0,55 | US$ 0,18 |
| **PDF Mapfre (real)** | **0,56** | **0,75** (0,69¹) | 1,00 (1,00¹) | 0,50 | US$ 0,29 |
| **XLSX Curitiba (real)** | **0,89** | **0,85** (0,81¹) | 1,00 (0,71¹) | 0,85 | US$ 0,14 |
| XLSX | 0,89 | 0,89 (0,89) | 1,00 (1,00) | 0,89 | US$ 0,12 |
| JSON | 0,86 | 0,89 (0,71) | 1,00 (1,00) | 0,86 | US$ 0,15 |
| DOCX | 0,96 | 0,96 (0,93) | 1,00 (0,71) | 0,89 | US$ 0,30 |
| TXT | 1,00 | 1,00 (0,96) | 1,00 (1,00) | 1,00 | US$ 0,17 |
| MD | 0,94 | 0,81 (0,75) | 1,00 (0,43) | 0,91 | US$ 0,15 |
| site | 1,00 | 1,00 (1,00) | 1,00 (0,86) | 0,91 | US$ 0,20 |
| PDF escaneado | 0,96 | 0,96 (0,96) | 1,00 (0,50) | 0,92 | US$ 0,13 |
| foto | 0,96 | 0,96 (0,96) | 1,00 (1,00) | 0,96 | US$ 0,11 |

¹ Os dois reais novos rodaram já com o juiz do placar (régua v1), não com o do autoteste.

- **acerto:** respondíveis com resposta certa.
- **recusa:** perguntas de fora em que o agente não inventou.
- **de onde veio:** a resposta diz ter usado um trecho que contém a âncora.
- **custo:** ingestão + busca + resposta + juiz.

**Leitura:**
- **As sintéticas são fáceis.** As bases pequenas têm de 45 a 190 pedaços, o hit@12 delas fica em 0,86–1,00 e a
  resposta em 0,81–1,00. Elas servem para pegar regressão por formato, não para provar 95%.
- **Os reais mostram o problema.** Nos dois PDFs reais a busca acha a âncora em 56–59% das perguntas, e "de onde
  veio" fica em 50–55%. O acerto passa da busca porque o modelo responde com outro trecho que também traz o fato.
- **Recusa:** nenhuma resposta de fora da base inventou o fato pedido (revisado, 100% em todos os formatos). Os
  "inventou" do juiz eram recusas certas que citavam outro fato do material.

## Busca por tamanho

Com empacotamento por seção. Em base pequena, 12 pedaços são quase a base inteira e o hit@12 satura; compare hit@5 e
MRR.

| formato | tamanho | pedaços | hit@1 | hit@5 | hit@12 | MRR |
|---|---|---|---|---|---|---|
| PDF Suhai | atual | 1.207 | 0,28 | 0,45 | 0,59 | 0,36 |
| | 250 | 296 | 0,38 | 0,55 | 0,66 | 0,45 |
| | 400 | 205 | 0,34 | 0,59 | **0,72** | 0,43 |
| | 600 | 167 | 0,38 | 0,55 | 0,66 | 0,47 |
| PDF Mapfre | atual | 839 | 0,25 | 0,44 | 0,56 | 0,34 |
| | 250 | 330 | 0,22 | 0,44 | 0,69 | 0,34 |
| | 400 | 184 | 0,22 | 0,53 | 0,62 | 0,34 |
| | 600 | 120 | 0,38 | 0,62 | **0,72** | 0,49 |
| XLSX Curitiba | atual | 1.811 | 0,52 | 0,81 | **0,89** | 0,64 |
| | 250 | 130 | 0,44 | 0,74 | 0,81 | 0,55 |
| | 400 | 80 | 0,52 | 0,74 | 0,78 | 0,62 |
| | 600 | 53 | 0,48 | 0,78 | 0,85 | 0,62 |
| XLSX | atual / 250 / 400 / 600 | 190 / 15 / 9 / 6 | 0,67 / 0,63 / 0,44 / 0,52 | 0,89 / 0,96 / 0,96 / 1,00 | 0,89 / 1,00 / 1,00 / 1,00 | 0,76 / 0,74 / 0,65 / 0,70 |
| JSON | atual / 250 / 400 / 600 | 122 / 31 / 20 / 13 | 0,79 / 0,68 / 0,54 / 0,57 | 0,82 / 0,86 / 0,79 / 0,86 | 0,86 / 0,93 / 0,93 / 0,96 | 0,81 / 0,76 / 0,65 / 0,68 |
| DOCX | atual / 250 / 400 / 600 | 46 / 41 / 25 / 17 | 0,46 / 0,57 / 0,57 / 0,68 | 0,82 / 0,82 / 0,82 / 0,93 | 0,96 / 0,93 / 0,96 / 0,96 | 0,64 / 0,69 / 0,69 / 0,78 |
| TXT | atual / 250 / 400 / 600 | 77 / 32 / 21 / 17 | 0,71 / 0,68 / 0,79 / 0,89 | 0,93 / 1,00 / 1,00 / 1,00 | 1,00 / 1,00 / 1,00 / 1,00 | 0,82 / 0,82 / 0,88 / 0,95 |
| MD | atual / 250 / 400 / 600 | 147 / 29 / 17 / 11 | 0,69 / 0,62 / 0,72 / 0,66 | 0,88 / 0,97 / 1,00 / 0,94 | 0,94 / 1,00 / 1,00 / 1,00 | 0,77 / 0,77 / 0,82 / 0,77 |
| site | atual / 250 / 400 / 600 | 72 / 23 / 14 / 9 | 0,84 / 0,78 / 0,62 / 0,62 | 1,00 / 1,00 / 0,97 / 0,94 | 1,00 / 1,00 / 1,00 / 1,00 | 0,90 / 0,88 / 0,76 / 0,77 |
| PDF escaneado | atual / 250 / 400 / 600 | 77 / 16 / 13 / 10 | 0,69 / 0,65 / 0,62 / 0,81 | 0,88 / 0,92 / 0,92 / 0,96 | 0,96 / 1,00 / 1,00 / 1,00 | 0,78 / 0,78 / 0,77 / 0,87 |
| foto | atual / 250 / 400 / 600 | 45 / 5 / 5 / 5 | 0,71 / 0,75 / 0,79 / 0,75 | 0,83 / 1,00 / 1,00 / 1,00 | 0,96 / 1,00 / 1,00 / 1,00 | 0,77 / 0,86 / 0,89 / 0,86 |

Custo da busca: US$ 0,007 a 0,012 por rodada.

**O que o tamanho diz:**
- Não existe um tamanho bom para todos os formatos.
- Nos dois PDFs reais, juntar ajuda: o hit@12 sobe de 0,56–0,59 para 0,72. Mas o melhor tamanho muda entre os dois
  (400 no Suhai, 600 no Mapfre), e nenhum passa de 0,72.
- Na planilha real, juntar **piora** (0,89 → 0,78–0,85). Ali cada linha é uma resposta, e juntar linhas dilui.
- Nas bases sintéticas, juntar tira precisão do primeiro lugar (hit@1 e MRR caem em JSON, site e XLSX) e ajuda em
  TXT, DOCX e escaneado.
- O tamanho sozinho não leva a 95%. Isso confirma o desenho-alvo: um corte por formato e por estrutura, não um
  número só.

## Por que o PDF erra (Suhai)

São as 29 perguntas respondíveis do Suhai. A causa de cada pergunta que falhou foi classificada lendo os pedaços do
agente no banco local; 31 buscas reais foram refeitas para conferir.

| causa | corte de hoje | 400 tokens |
|---|---|---|
| corte no meio (a resposta foi partida entre pedaços) | 8 | 0 |
| vocabulário (pedaço certo e inteiro, mas a pergunta usa outras palavras e outro pedaço ganha) | 5 | 3 |
| extração (palavras coladas: "ASeguradoraterá…") | 3 | 4 |
| tabela embaralhada que ganha a busca (tabela de planos da assistência) | 0 | 2 |
| diluição (pedaço de 1,5 mil caracteres onde a frase certa se perde) | 0 | 2 |
| título errado (glossário inteiro herdou "2.2 RCF-V") | 0 (junto com corte) | 1 |
| busca achou e a resposta errou | 1 (o juiz errou) | — |
| **falhas** | **17** | **12** |

Na variante de 400 só a busca foi medida, então a causa ali vale só para a posição.

Das 17 falhas de hoje, 8 têm resposta certa (a falha é só de posição) e 2 são erro do juiz. Erros reais de resposta:
7.

**O que a F1/F2 leva disso:**
1. **Extração do PDF.** A #2431 já troca a extração, e na medida do c7cf171d83 os pedaços colados foram a 0%. Resolve
   3 falhas de hoje e 4 do 400. Vale também para o PDF Mapfre, onde a extração de hoje perde 6 âncoras.
2. **Corte por item numerado e por frase**, com teto bem abaixo de 1,5 mil caracteres. Resolve o corte no meio (8)
   sem diluir.
3. **Título pela geometria** (ver `desenho-alvo-por-formato.md`): o "3. DEFINIÇÕES" não é reconhecido hoje.
4. **Tabela como tabela:** a de planos da assistência sai embaralhada e ganha as perguntas de km e guincho.
5. **Vocabulário** ("oficina do cunhado", "esconder", "carro de outra pessoa"). Nenhum corte resolve. Precisa de
   reescrita da pergunta (F1a) ou de busca combinada (F2). As duas são IA paga e entram medidas.

## O juiz

### O juiz do autoteste erra para o lado estrito

Revisei à mão os 318 vereditos das 9 bases que rodaram com o juiz do autoteste (`Material::JuizDoAutoteste`).

| formato | erros do juiz |
|---|---|
| PDF Suhai | 5/37 (13,5%) |
| JSON | 5/35 (14,3%) |
| MD | 6/39 (15,4%) |
| PDF escaneado | 4/34 (11,8%) |
| DOCX | 3/35 (8,6%) |
| TXT | 1/35 (2,9%) |
| site | 1/39 (2,6%) |
| XLSX | 0/34 |
| foto | 0/30 |
| **total** | **25/318 (7,9%)** |

Os 25 erros vão todos para o mesmo lado, reprovando resposta boa:
- "errado" porque faltou um detalhe secundário (a validade de um pacote quando a pergunta era o preço) ou porque
  sobrou um fato verdadeiro do material (o CEP junto com o endereço);
- "inventou" numa recusa certa que citava outro fato do material.

Ele também é incoerente: dá "certo" a omissões parecidas. A causa está na instrução dele ("sem ser generoso" junto
com "errado se falta o fato"). O mesmo defeito atinge o autoteste que o dono vê, e foi registrado na #2444 para a
#1426. Nada muda em produção sem OK.

### O juiz do placar

O `JuizDoPlacar` roda só em dev e test, pela rake. Tem a mesma saída do juiz do autoteste (um veredito por índice,
válido para a origem) e recebe os trechos que o agente usou. Ele é a base proposta para corrigir o juiz do autoteste
(#2444).

**v2, a que vale (decisão do Rodrigo, 31/10):** o juiz julga como uma pessoa sensata, não por lista de regras. A
instrução dá o objetivo ("a resposta atende o que o cliente perguntou, com o que o material diz, sem inventar?") e oito
exemplos inventados (lava-rápido, oficina, assinatura, caixa), nenhum tirado das bases medidas. Detalhe secundário que
falta ou fato verdadeiro a mais ficam a critério dele. Texto em `app/services/autonomia/agents/juiz_do_placar.rb`,
sha256 `cb705c0614f6012c…`.

A v1 (régua escrita, item por item, sha256 `83582093fe0ac2f4…`) foi medida antes e fica registrada abaixo para
comparação.

Protocolo contra régua circular:
- **Sorteio fixo:** os 318 itens rotulados à mão foram divididos em duas metades de 159 (`random.Random(1431)` sobre
  a lista ordenada de pares (formato, índice)).
- **Metade A, para ajuste:** a v2 discordou de 4/159 na primeira medida. Uma rodada de ajuste acrescentou três
  exemplos inventados (conselho prudente a mais, condição secundária que faltou, pergunta para ajudar numa recusa):
  3/159 (1,9%). Aí a instrução foi congelada.
- **Metade B, para teste:** medida uma vez com a v2 congelada: **3/159 (1,9%)**.
- **Reserva:** os dois documentos reais novos, fora do sorteio (74 itens), medidos uma vez: **2/74 (2,7%)**.
- **Ressalva:** a metade B e a reserva já tinham sido medidas uma vez com a v1, e eu vi aquelas discordâncias. Os
  exemplos da v2 não vêm delas, mas a metade B deixou de ser inteiramente inédita para quem escreveu a instrução.
- **Rotulador cego:** um subagente novo, que não viu nenhum rótulo nem a instrução do juiz, rotulou 40 itens da
  metade B (21 do PDF, 15 do JSON, 3 da foto e 1 do DOCX) só com o objetivo, sem régua.
  - **cego × eu:** 40/40 concordam.
  - **cego × juiz v2:** 38/40 (PDF #29, gabarito ambíguo; JSON #25).
  - **cego × juiz do autoteste:** 37/40.

| juiz | metade A | metade B | reserva | cego × juiz |
|---|---|---|---|---|
| autoteste (produção hoje) | — | 8/159 (5,0%) | — | 37/40 |
| placar v1 (régua escrita) | 1/159 (0,6%) | 4/159 (2,5%) | 4/74 (5,4%) | 37/40 (cego com régua) |
| **placar v2 (objetivo + exemplos)** | 3/159 (1,9%) | **3/159 (1,9%)** | **2/74 (2,7%)** | **38/40** |

As discordâncias da v2 se dividem: na metade B, dois "errado" onde o rótulo é "certo" (PDF #29, cuja pergunta tem duas
respostas certas no material; JSON #25) e um "inventou" onde o rótulo é "recusou" (escaneado #32). Na reserva, dois
"errado" onde o rótulo é "certo" (PDF real #30; XLSX real #0, de gabarito ambíguo). Não houve caso de aprovar
resposta ruim.

- **Variação entre rodadas:** o mesmo juiz já deu "certo" e depois "errado" para uma pergunta do PDF Mapfre (#28). A
  margem de ±5% vale também para isso.

**Conclusão:** a v2 fica dentro da meta na metade de teste (1,9%) e nos documentos reais (2,7%), melhor que a v1
neles. Ela serve para comparar F1/F2 com a linha de base desde que:
- uma diferença menor que 5 pontos de acerto não decida nada;
- em decisão perto de um limite, os "errados" sejam revistos à mão (são poucos e baratos de ler).

Os rótulos, o sorteio e as rodadas de calibração ficaram fora do git: os rótulos dizem respeito a respostas que
citam os textos das bases, e o protocolo cabe neste documento.

## Custo

| etapa | gasto |
|---|---|
| Linha de base do Suhai (antes desta rodada) | US$ 0,34 |
| Busca nos 11 formatos e 4 tamanhos (42 rodadas, com repetições) | US$ 0,38 |
| Resposta + juiz nos 11 formatos (11 rodadas, com a ingestão) | US$ 1,95 |
| Calibração do juiz v1 (A, B, reserva) | US$ 0,06 |
| Calibração do juiz v2 (A duas vezes, B, reserva) | US$ 0,09 |
| Rodadas que caíram (paralelas sem chave, log do Faraday) | cerca de US$ 0,03 |
| **total da frente** | **cerca de US$ 2,85 de US$ 5** |

## Achados à parte

- **Log do Faraday (só local).** Em `test` (e `development`) o `log_level` é debug, e o RubyLLM loga o corpo do pedido.
  Com um PDF grande, o `gsub` do formatador do Faraday estourou o `Regexp.timeout` (`Regexp::TimeoutError`) e
  derrubou a rodada. Em produção o nível é `info`. As rodadas de medida passaram a usar `LOG_LEVEL=info`.
- **XLSX:** o Roo devolve número de ponto flutuante cru (`406.21000000000004`) no texto do pedaço. A âncora bate, mas
  o texto que o agente lê sai feio. Entra no desenho do XLSX.
- **Gabarito ambíguo:** duas perguntas tinham mais de uma resposta certa no próprio material (perda total do Suhai;
  container com e sem sanitário na planilha). Foram contadas como certas quando a resposta dava uma delas.

## Como refazer

1. Rake: `RESPOSTA=1 TETO_USD=… AGENTES=… PERGUNTAS=gabaritos/<formato>.yml SAIDA=<fora do git> rails
   autonomia:rag:placar` (só dev e test), com a base ingerida num agente local.
2. Os scripts que ingerem cada formato, simulam o tamanho e calibram o juiz são cola local (`tmp/placar/`, fora do
   git): eles leem a chave do arquivo de segredos sem imprimir, gravam a chave só no banco de teste e a apagam no fim
   da fila.
