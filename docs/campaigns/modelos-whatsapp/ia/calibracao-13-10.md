# Calibração do prompt `whatsapp_modelo` (13/10/2026, #1333)

Esta é a segunda calibração. A primeira, de 12/10, está em `calibracao-12-10.md`.

**Bateria.** 60 casos, 20 por perfil:
- dona_maria (leiga);
- pequeno_negocio;
- agencia.

Cada caso vem em "criar" ou "melhorar", com armadilhas: promoção pedida como serviço, dado pessoal, urgência falsa,
fato do pedido trocado por campo e link no fim.

**Como rodou.** As saídas foram reais, no `gpt-6-luna` low, com a chave de IA da conta 16 (lida em produção só para
leitura). O caminho foi o da tela: redator, conferência do código e, a partir da rodada 3, o job de 25 s.

**Como foi julgado.** Um juiz cego, com rubrica de 7 eixos (a–g), atribuiu nota de 0 a 100 por caso e eliminação por
risco com a Meta. Foi julgado só o que a pessoa vê. Caso "ok" sem nenhuma opção aceita conta como falha.

Os arquivos de trabalho ficaram fora do git: bateria, saídas, julgamentos, rubrica e variantes.

## As 4 rodadas

| Rodada | Variantes (cegas) | Vencedora | Nota média | Pior perfil | Eliminados | Falhas para a pessoa | p95 |
|---|---|---|---|---|---|---|---|
| 1 | A v2, B v1, C v0, D v3 | D (v3-enxuta) | 71,2 | 64,9 | 1 | 3 | 10,0 s |
| 2 | K v3, M v5, T v4 | T (v4-enxuta-corrigida) | 70,9 | 67,8 | 1 | 3 | 10,2 s |
| 3 | P v6, W v4 | W (v4) | 75,0 | 73,1 | 0 | 1 | 11,6 s |
| 4 | X v7-final (+ 24 repetições) | **X (v7-final)** | 73,5 | 69,2 | **0 (e 0 em 24 repetições)** | 3 | 10,4 s |

**Achados que viraram código, não prompt:**

| Rodada | Caso | Correção |
|---|---|---|
| 1 | AG11 | Em "manter como serviço" e "corrigir recusa", a opção pode tirar campo da base |
| 1 | PN12 | A comparação com a base usa só o corpo (`Canais::Base`, com OK do Agendamento) |
| 1 | AG15 | O nome sugerido é normalizado, não descarta |
| 2 | AG15 | Campo que vai do corpo para um botão de link conta como presente |
| 2 | — | "Mais curto" medido no código, com mínimo de 30% (25% com 4 campos ou mais), e a tela mostra o corte medido |
| 2 | — | Timeout: a escrita passou para o job (25 s, 1 nova tentativa) |
| final | AG15 | No "mais curto", acrescentar `{{minha_empresa.nome}}` (quem fala) não descarta |

## Veredito do juiz (rodada 4)

**SIM para piloto em produção**, restrito à conta 16, atrás da flag `whatsapp_templates_ai` e com a pessoa revisando
cada modelo antes de enviar. **NÃO para todas as contas** antes de medir os riscos de piloto (lista em
`docs/audit/modelos-whatsapp-ia-1333.md`). O Rodrigo decidiu: "Piloto só na conta 16". Refs #1450.

Em 84 saídas não houve eliminação nem pedido de dado sensível, ameaça, urgência falsa ou promoção marcada como
serviço (g = 4,98).

## Custo

| Variante | Chamadas | US$ |
|---|---|---|
| v0-atual | 97 | 0,0352 |
| v1-conversao | 60 | 0,0211 |
| v2-aprovacao | 60 | 0,0216 |
| v3-enxuta | 120 | 0,0459 |
| v4-enxuta-corrigida | 120 | 0,0519 |
| v5-enxuta-categoria | 60 | 0,0305 |
| v6-final | 62 | 0,0265 |
| v7-final | 84 | 0,0336 |
| Timeouts sem usage (estimativa) | 6 | 0,0060 |
| Campanha (#1335, mesmo orçamento) | 21 | 0,0080 |
| **Total** | **684** | **0,2802** |

O teto do épico é de US$ 2.
