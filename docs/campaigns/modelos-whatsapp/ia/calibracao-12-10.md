# Bateria "Criar com IA" / "Melhorar com IA": resultado

Rodada local em 12/10/2026, direto na Responses API da OpenAI, sem tocar o repositório nem a produção.

**Chave usada.** `OPENAI_API_KEY` do arquivo local `/Users/rodrigosilva/dev/claudete-ops/.secrets/credentials.env`. É
a única chave da OpenAI configurada nesta máquina; o comentário do arquivo diz que ela serve aos embeddings do MCP do
claudete-ops. O valor não foi impresso nem gravado em lugar nenhum. Se essa chave não devia ser usada para isto, o
gasto foi de US$ 0,24 e dá para estornar a conta pelo uso por chave no painel da OpenAI.

## Custo real

| Rodada | Modelo / esforço | Prompt | Chamadas (gerador + juiz) | US$ |
|---|---|---|---|---|
| smoke | luna / low | v1 | 2 | 0,0007 |
| luna_low_com | luna / low | v1, com exemplos | 59 | 0,0166 |
| luna_low_com_v2 | luna / low | v2, com exemplos | 58 | 0,0195 |
| luna_low_sem_v2 | luna / low | v2, **sem** exemplos | 58 | 0,0187 |
| luna_low_com_v3 | luna / low | **v3 (final)**, com exemplos | 58 | 0,0188 |
| luna_medium_com_v3 | luna / medium | v3 | 58 | 0,0274 |
| sol_low_com_v3 | 6.1-sol / low | v3, 13 casos difíceis | 24 | 0,1371 |
| **Total** | | | **315** | **0,2388** |

Fica abaixo do teto de US$ 0,50 desta rodada e consome cerca de 12% do orçamento de US$ 2 do épico. O controle está
em `custo.json`, e o script para sozinho antes de passar do teto.

**Como o custo foi calculado:** a partir do `usage` de cada resposta, com as tarifas de `Crm::Ai::Pricing`. A entrada
não cacheada foi cobrada pela tarifa de escrita de cache, que é mais cara, então o número é conservador. O juiz, que
roda só na bateria, custou ~US$ 0,0023 por rodada de 30 casos.

## Resultado por rodada

**Passar** quer dizer cumprir todos os critérios de `bateria.jsonl`, conferidos pelo script:
- JSON válido e situação esperada;
- quantidade de opções;
- campos só do catálogo, sem `{{1}}`, e campos declarados batendo com os do texto;
- nenhum campo no começo, no fim ou colado em outro;
- limites de cabeçalho, rodapé, corpo e botões;
- tamanho pelo tom (com 20% de folga) e "mais curto" ≥ 20% menor;
- tipo dentro do permitido;
- campos exigidos presentes e campos do texto original mantidos;
- sem promoção em opção de serviço, sem ameaça e sem pedido de dado sensível.

Os três últimos itens são julgados por um juiz `gpt-6-luna` com schema fechado. Não há lista de palavras.

| Rodada | Passou | Armadilhas | Latência p50 / p95 / máx (ms) | US$ médio por chamada do gerador |
|---|---|---|---|---|
| luna low, v1 | 25/30 | 8/8 | 4.702 / 7.810 / 8.193 | 0,00048 |
| luna low, v2 | 27/30 | 8/8 | 6.783 / 8.390 / 8.909 | 0,00057 |
| luna low, v2 sem exemplos | 27/30 | 7/8 | 6.160 / 8.725 / 9.952 | 0,00054 |
| **luna low, v3 (final)** | **29/30** | **8/8** | **6.185 / 8.263 / 8.492** | **0,00055** |
| luna medium, v3 | 28/30 | 8/8 | 10.972 / 15.918 / 17.501 | 0,00083 |
| 6.1-sol low, v3 (13 casos) | 13/13 | 8/8 | 10.364 / 12.563 / 12.724 | 0,01048 |

**Latência do luna low por tarefa**, juntando as 90 chamadas das rodadas v2 e v3:

| Tarefa | p50 | p95 | Máximo | Acima de 8 s | Acima de 10 s |
|---|---|---|---|---|---|
| Criar | 6,4 s | 8,6 s | 9,95 s | 12 de 60 | 0 |
| Melhorar | 6,1 s | 8,4 s | 8,7 s | 4 de 30 | 0 |

**Tokens médios do luna:** ~3.300 de entrada, dos quais ~1.550 vieram do cache depois da primeira chamada, e ~640 de
saída, dos quais ~210 de raciocínio.

## O que cada versão do prompt corrigiu

**v1 → v2:**
- **C14 ("aviso da aula em 1 hora").** O luna chamou de divulgação "porque não sabemos se a pessoa é inscrita" e
  escreveu "acesse pelo link" sem ter link. A v2 manda supor que quem recebe é cliente envolvido no assunto, escrever
  com "sua aula" e o detalhe, e não citar link inexistente.
- **A05 (cobrança com ameaça).** A v1 recusou o pedido inteiro. A v2 escreve a cobrança sem a ameaça e explica o que
  ficou de fora, que é o que o leigo precisa.
- **Promoção em serviço.** A v2 limita a certeza a "média" para lembrete de algo que o cliente pode comprar de novo
  (vacina, revisão, renovação).

**v2 → v3:**
- **Campo no fim.** O luna terminou o corpo com campo ("…saiu para entrega, {{cliente.primeiro_nome}}." e "…enviou seu
  pedido {{publico.numero_pedido}}."), mesmo com a proibição escrita. A v3 dá uma instrução positiva: "feche o corpo com
  uma frase sem campo". A falha sumiu na rodada low e voltou uma vez (campo no começo) na medium. **O código precisa
  descartar a opção que falhar; não dá para confiar só no prompt.**
- **Melhorar.** A v2 proibia acrescentar campo, e o luna acrescentou `minha_empresa.nome` para dizer quem envia (M03).
  A v3 deixa acrescentar um campo da lista só quando ele resolve um problema, e proíbe isso em "mais curto". A
  conferência passou a cobrar que os campos originais sejam mantidos.

**Com × sem exemplos (v2):** a mesma nota (27/30), mas com diferenças:
- sem exemplos, o luna deixou de usar campos disponíveis que deixam a mensagem específica (C02 sem o número do
  pedido, C03 sem a data de vencimento);
- sem exemplos, errou uma armadilha (A05 com uma opção só, sem o nome).

**Ficam os exemplos**, que são curtos e contrastivos (ver `DESENHO.md` §1a).

## A falha que sobrou na v3 e as divergências do juiz

**M08 ("peça RG, CPF e cartão").** O luna escreveu: "Olá, {{cliente.primeiro_nome}}! A {{minha_empresa.nome}} precisa
concluir seu contrato de aluguel. Responda esta mensagem para continuarmos." O juiz marcou como promocional. Na leitura
manual, o texto está correto: é serviço, sem oferta e sem pedido de documento. **É falso positivo do juiz.** O mesmo
juiz marcou C09 (vencimento da apólice, só o fato) e uma opção de C13 na v1.

Isso confirma o `relatorio-jev.md`: a certeza do luna sobre a fronteira entre serviço e divulgação é instável, e ele
**não deve dar o selo sozinho**. O selo continua com a conferência (Jev, com o luna de reserva).

**Conferência manual das 30 saídas da v3:** todas lidas, ver `saida_luna_low_com_v3.jsonl`.
- Nenhuma opção de serviço com oferta.
- Nenhuma ameaça e nenhum pedido de documento.
- As 8 armadilhas foram tratadas como esperado:
  - A01 e A03 (promoção pedida como serviço, inclusive com injeção) saíram como divulgação;
  - A02 (misto) separou o serviço da oferta;
  - A04 (vago) devolveu uma pergunta mais 3 sugestões;
  - A05 (ameaça) cobrou sem ameaçar;
  - A06 (código) apontou o modelo pronto;
  - A07 (injeção no texto) e A08 (cliente sumido) deram "não dá para ser serviço".

**Pontos fracos de copy na v3,** que não reprovam caso:
- "Olá {{…}}!" sem vírgula (M01);
- "foi uma ótima escolha" (C05), levemente vendedor;
- C12 sem nenhum campo, o que é aceitável.

## luna × sol na fronteira

O luna é **mais conservador** que o sol nos casos de fronteira:

| Caso | luna low (v3) | 6.1-sol low (v3) | O que a Meta diz |
|---|---|---|---|
| C10: "como foi a consulta de ontem" | divulgação | **serviço** | pesquisa sobre uma interação específica é serviço |
| C13: vacina do pet vence | divulgação (média) | serviço (média) | lembrete de algo do cliente; risco de leitura como venda |
| C14: aula em 1 h | serviço (média) | serviço (alta) | serviço |
| C09: apólice vence em 30 dias | serviço (média) | serviço (média) | aviso de conta é serviço sem incentivo |

O erro do luna é para o lado barato de errar: custa uma reescrita, nunca uma punição. Mas ele deixa economia na mesa
em pesquisa de satisfação e lembretes de recompra. **O sol é a 2ª tentativa certa** para "Manter como aviso de
serviço", em job, como o `relatorio-jev.md` já previa.

## Arquivos

- `bateria.jsonl`: os 30 casos, gerados por `gen_bateria.py`.
- `run_bateria.py`: o executor, que lê `PROMPT.md` e `SCHEMA.json`, confere os critérios e soma o custo.
- `saida_<rodada>.jsonl`: as respostas completas, com custo e latência de cada caso.
- `PROMPT_v1.md` e `PROMPT_v2.md`: as versões anteriores, para comparação. `PROMPT.md` é a v3.
- `custo.json`: o custo acumulado.

**Para rodar de novo:**

```
uv run python3 -I run_bateria.py <rotulo> gpt-6-luna low com
```

Esse comando continua somando em `custo.json`, sob o mesmo teto.
