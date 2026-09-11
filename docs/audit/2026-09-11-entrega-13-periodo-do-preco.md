# Entrega 13 — dizer se o preço é mensal ou anual

Data: 11/09/2026. Plano: entrega 13 do Agente de Cotação (5 termos de aceite). Issue-mãe: #291.
Repositórios: `autonomia-adapters` (PR #54, fatia A) e `chat` (esta PR, fatia B). Ponto de partida:
na renovação real de 11/09 (`b0220871-…:1`, 11 seguradoras cotaram) o cliente leu a ressalva "a
seguradora não informou se é o total ou uma parcela" em Bp Assinatura (351,59), Justos (134,50) e
Tokio (1.901,97). Duas delas tinham a informação no payload.

## O achado que decide o desenho (termo 3) — lido do payload bruto, não do papel

Payload cru de `GET /calculo/cotacao/versoes/{id}` das três cotações reais (renovação, moto
`91bef437-…:1`, caminhão `4c278fcf-…:1`), lido pelo `HttpClient` com a conta de teste (script
read-only no scratchpad; nenhum `quote start`). O que cada `resultado` selecionado traz:

| Seguradora | `premio` | `premioMensal` | `parcelamentos` | `packageType` | `identificacao` |
|---|---|---|---|---|---|
| Suhai | 1818,48 | 151,54 (= premio/12) | 24 planos `{parcelas, premioPrimeiraParc, premioDemaisParc, tipoPag, valorIof}`; 1x = 1818,48; 2x 909,24; 3x 606,16; de 4x em diante juros | 0 | Compreensiva |
| Tokio | 1901,97 | 158,4975 (= premio/12) | 34 planos; 1x = 1901,97 exato; 2x 950,93 (−0,11); 12x 158,39 (−1,29) | 0 | Auto |
| Porto | 1321,25 | 110,10 (= premio/12) | 44 planos; à vista com desconto (1255,13 / 1192,35); 2x..10x fecham; 11x, 12x com juros | 0 | Tradicional |
| Justos, res 0 | **134,50** | 11,208333 (= premio/12) | **`[]`** | 1 | Principal |
| Justos, res 1 | 1539,24 | 128,27 (= premio/12) | 10 planos; 1x 1398,12 (9% desconto); 5x 307,848 e 10x 153,924 fecham | 0 | Principal |
| Bp Assinatura | **351,59** | **29,299166…** (= premio/12) | **`[]`** | 1 | Principal |
| Ituran | 2736,48 | 228,04 (= premio/12) | 2 planos, só 12x 228,04 (fecha) | 0 | Connect… |
| Usebens, Pier, Mapfre, HDI, Allianz | … | = premio/12 | planos que fecham | 0 | … |

Conclusões, com os campos reais:

1. **`premioMensal` não distingue nada.** É `premio/12` em TODAS as seguradoras, inclusive nas duas
   assinaturas mensais, com centavos fracionários (29,299166…) — derivado pelo portal, não cotado
   pela seguradora. O portal trata todo `premio` como anual mecanicamente.
2. **O que Bp Assinatura e a assinatura da Justos trazem que as outras não trazem: nada.** O que
   NÃO trazem: `parcelamentos` vem `[]` (lista vazia, e não `false`, que é o "ainda não respondeu").
   `identificacao` é "Principal" como nas outras; `packageType: 1` é índice do resultado dentro da
   resposta da seguradora (a Suhai tem 0..3 para os quatro pacotes), não marcador de periodicidade.
   Não há campo de periodicidade, tipo de plano, vigência por resultado, nem observação de texto.
3. **A Justos devolve DOIS resultados selecionados no mesmo cálculo**: a assinatura (134,50, sem
   parcelamento) e a apólice anual (1.539,24 em até 10x). `calc.premio` do portal é 1.539,24 — o
   próprio portal escolhe a anual. O adapter escolhia o menor número cru (134,50) e descartava a
   oferta que tinha período derivável.
4. **A Tokio tinha a informação e o adapter dizia `unknown`**: a regra "uma parcela não prova nada"
   (escrita quando o nome dos campos era desconhecido, para não casar qualquer valor monetário do
   objeto) recusava o plano 1x = 1.901,97, e os planos de 2x a 12x desviam mais de um centavo por
   parcela (−0,11 em 2x; −1,29 em 12x), acima da tolerância de 1 centavo/parcela.

**Decisão (termo 3): NÃO existe detector de mensalidade.** `parcelamentos: []` em duas amostras não é
contrato — e assumir "vazio = mensal" seria inventar o detector sem evidência. O honesto é `unknown`
com o motivo nomeando o campo, por oferta, para a próxima cotação real confirmar ou desmentir.

## O desenho

### Adapter (PR autonomia-adapters#54)

- `derivePremium(amount, parcelamentos, premioMensal?)` lê cada plano pelo contrato observado
  (`Parcelamento = { parcelas, premioPrimeiraParc, premioDemaisParc }`, passthrough). Um plano prova
  o total quando `premioPrimeiraParc + (parcelas−1) × premioDemaisParc` fecha com o prêmio dentro de
  `max(0,01 × parcelas + 0,01, 0,5% do prêmio)`: o maior desvio de arredondamento medido foi 0,07%
  (Tokio 12x), o menor desconto real foi 5% (Porto à vista) — a régua fica duas ordens de grandeza
  longe dos dois. `parcelas: 1` no campo nomeado É prova (o portal diz "pague o prêmio de uma vez").
  O parcelamento anunciado ao cliente é o MAIOR sem juros (Suhai: 3x 606,16, não o 2x que fechava
  primeiro). Sem nada fechando: `unknown`, e `basisEvidence` diz `parcelamentos=[] (vazio)`,
  `N parcelamento(s) fora do contrato (sem parcelas/premioPrimeiraParc/premioDemaisParc)`, o plano
  mais próximo (`parcelas=1 soma=1398.12`), e se `premioMensal` é premio/12 (derivado, não distingue)
  ou veio diferente disso (sinal novo, nomeado, sem virar detector).
- `toOffer` → `escolherPremium`: entre resultados selecionados da mesma seguradora, o de período
  conhecido mais barato vence; só sem nenhum conhecido sai o menor desconhecido. O que ficou de lado
  vai para o motivo: `posto de lado: premio=134.5 (parcelamentos=[] …)`.
- Fixture `test/fixtures/agger/parcelamentos-reais-2026-09-11.sanitized.json` (só números de preço e
  parcelamento; nenhum dado pessoal). Guarda: toda oferta real com plano de pagamento sai `total`.
- `pnpm verify` verde (765 unitários + 12 integração; cobertura 100/100/100/100). Nove mutações,
  todas reprovam o alvo (arquivo restaurado, md5 conferido): M1 `parcelas: 1` volta a não provar;
  M2 tolerância relativa desligada; M3 escolha pelo menor número cru; M4 plano posto de lado some
  do motivo; M5 primeiro plano em vez do maior; M6 `premioMensal` some do motivo; M7 tolerância
  vira 10% (desconto à vista viraria total); M8 plano fora do contrato lido como parcela; M9 lista
  vazia vira total.

### chat2you (esta PR)

- `PremiumText#resumo`: "no total" SÓ quando `basis == 'total'` — o parcelamento sozinho deixou de
  ser uma segunda derivação por cima da do adapter. `#indefinido?` = `!total?`. `#motivo` = o
  `basis_evidence` do adapter (já em snake_case pelo `Http`); sem ele, descreve o que veio
  (`basis=nil sem basis_evidence`) em vez de uma frase nossa.
- `QuoteOffers#quoted`: as com período ordenadas por valor, as sem período DEPOIS, na ordem do
  portal. `#sem_periodo` → `{ código => motivo }`.
- `InsuranceQuote#precos` → `registrar_sem_periodo`: grava `preco_sem_periodo` no handle da
  execução, acumulando entre lotes, só quando há o que registrar. Consulta:
  `autonomia_agent_tool_runs.handle->'preco_sem_periodo'`.
- `Connector::Mock`: prêmios com `basis` e `basis_evidence` (antes o mock saía sem base e toda oferta
  levava a ressalva); a terceira oferta passa a ser a Bp Assinatura real (351,59, `unknown`, motivo
  real), para o caminho da ressalva e da ordenação ficar visível em desenvolvimento.
- Texto ao cliente: NÃO mudou a frase da ressalva (`SEM_BASE`). Ela continua saindo — agora só
  onde a informação NÃO está no payload (Bp Assinatura).

### Termos (5)

| # | Termo | Guarda / evidência | Estado |
|---|---|---|---|
| 1 | Motivo registrado e consultável por oferta (campo que faltou/veio ambíguo) | adapter: `basisEvidence` nomeia `parcelamentos=[]`, `premioMensal` derivado, plano fora do contrato, plano posto de lado (`premio-com-significado.test.ts`, M6/M8/M4); chat2you: `QuoteOffers#sem_periodo` + handle `preco_sem_periodo` (`quote_offers_spec`, `ramo_auto_spec` "registra no handle", MC3/MC4/MC5/MC6); consulta por `quote result <id>` na CLI ou pelo handle da execução | fechado em código; **pendente_prova_real**: ler o handle de uma execução em produção |
| 2 | Cliente para de ouvir a ressalva quando a informação estava no payload | Tokio → `total` (M1, M2); Justos → 1.539,24 `total` em 10x (M3); guarda "toda oferta real com plano de pagamento sai total" sobre a fixture | fechado em código; **pendente_prova_real**: cotação nova em produção depois do deploy da Lambda |
| 3 | Decisão de detecção com cotação real com plano mensal na mão | tabela acima, com os campos reais; decisão: sem detector (`describe 'não há detector de mensalidade'`, M9) | fechado |
| 4 | Período desconhecido → preço sem afirmar período | `PremiumText#resumo` só com `total` (`premium_text_spec`, MC2/MC7); `ramo_auto_spec` "NÃO inventa período" | fechado |
| 5 | Períodos diferentes nunca ordenados pelo número cru | adapter: `escolherPremium` (M3); chat2you: `QuoteOffers#quoted` particiona (MC1; `ramo_auto_spec` "no lote, o preço sem período vem depois") | fechado |

### Mutações do chat2you (8/8 reprovam o alvo; restaurado com md5 conferido)

MC1 `quoted` ordena pelo número cru · MC2 `resumo` volta a deduzir total do parcelamento · MC3
`sem_periodo` devolve vazio · MC4 registro no handle desligado · MC5 registro sobrescreve em vez de
acumular · MC6 `motivo` ignora o `basis_evidence` · MC7 `indefinido?` volta a aceitar parcelamento
como base · MC8 mock: oferta sem período vira total.

## O que fica para prova real / produção

- A Lambda precisa ser publicada com o #54 antes desta PR fazer diferença ao cliente (o chat2you
  só traduz o que o adapter manda). Ordem: adapter → Lambda → chat2you.
- Termos 1 e 2 em produção: uma cotação nova (ou `quote result` da `b0220871-…:1` pela Lambda nova)
  mostrando Tokio e Justos com "no total" e o handle da execução com `preco_sem_periodo` só para a
  Bp Assinatura.
- Decisão para o Rodrigo: a assinatura da Justos (134,50/mês, provavelmente) hoje fica só no
  motivo e no PDF comparativo (que imprime todos os resultados selecionados). Mostrar também ao
  cliente como segunda linha exigiria dizer o período, que o portal não dá.
- Cotação futura com `premioMensal ≠ premio/12` ou `parcelamentos` fora do contrato sai nomeada no
  motivo ("sinal novo, investigar"): é o gatilho para revisitar o detector.

## Comandos rodados

- Leitura do bruto: `npx tsx <scratchpad>/ler-bruto.ts` (login + `GET negocio/versoes/calculos` das três
  cotações; salvo no scratchpad, fora do repo — contém dado do segurado).
- Adapter: `pnpm verify` (exit 0; `tools/py` reaproveitado por symlink do checkout principal, porque o
  venv é gitignored e o CI o recria); `test/unit/destino-seguro.test.ts:32` presume que a pasta do
  checkout se chama `autonomia-adapters` — reprova em qualquer worktree; medido com symlink temporário
  de nome, removido depois. Mutações: `mutacoes_adapter.py` (scratchpad).
- chat2you: `POSTGRES_DATABASE=chatwoot_test_e13 bundle exec rspec <4 specs> --format json` (72
  exemplos, 0 falhas, 0 erros fora); `rubocop` nos 8 arquivos tocados (0 ofensas); mutações
  `mutacoes_chat.py`; suíte ampla `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia`
  (resultado no fim desta auditoria).

Suíte ampla: **899 exemplos, 0 falhas, 0 erros fora de exemplos** (3 pendentes pré-existentes, não
desta entrega), lido do JSON do rspec, exit 0.
