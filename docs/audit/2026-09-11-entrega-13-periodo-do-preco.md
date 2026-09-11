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

Os campos de TEXTO e de VIGÊNCIA do bruto (rodada 3, a pedido do verificador — são os que um
leitor perguntaria se foram olhados), lidos do mesmo `cotacao/versoes` salvo fora do repo:

| Campo | Nível | Bp Assinatura (351,59) | Justos res 0 (134,50) / res 1 (1.539,24) | Tokio (1.901,97) | Porto moto 430,75 / 671,73 | Distingue período? |
|---|---|---|---|---|---|---|
| `observacoes` (lista de strings) | resultado | 1 string com dois ajustes de limite: "O valor da cobertura Danos Corporais foi ajustado para o limite mínimo permitido. (R$ 100.000,00)" + o mesmo para Danos Materiais | o MESMO texto nos dois resultados: "9% desconto pagando à vista: R$ 1.398,12 e 5% desconto parcelando em 2 a 4x: R$ 1.469,04" (fala da apólice anual e aparece igual no 134,50) | `null` | `null` / "Cobertura de custos de defesa contratada automaticamente no valor de R$20 mil…" | não |
| `alertas` (lista de strings) | resultado | os mesmos dois ajustes, um por item | o mesmo texto de desconto, 1 item, nos dois | `[]` | `[]` / o mesmo texto dos custos de defesa | não |
| `coberturas.tipo` | resultado | "Compreensiva" | "Compreensiva" nos DOIS | "Compreensiva" | "Incêndio, Roubo/Furto" / "Compreensiva" | não — distingue PACOTE de cobertura, não período |
| `vigenciaIni` / `vigenciaFim` | versão (não há por resultado nem por cálculo) | 2026-09-11 → 2027-09-11 (a versão inteira, anual; a assinatura da Justos e a Bp estão dentro dela) | idem | idem | 2026-09-11 → 2027-09-11 | não |
| `calc.alertas` | cálculo | `[]` | `[]` | `[]` | `[]` | não |

Nenhuma chave de resultado ou de `coberturas` contém "vig", "period" ou "mens" além de `premioMensal`
(que é `premio/12`, conclusão 1). Inspecionados; não distinguem período.

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
- `toOffer` → `escolherPremium(premios, premioDoCalculo)`: entre resultados selecionados da mesma
  seguradora, o de período conhecido mais barato vence. Sem NENHUM conhecido, o número não decide
  (rodada de correção, abaixo): sai o que o portal escolheu — `premio` do cálculo casa com um dos
  resultados, com tolerância de um centavo (Hdi: 2.581,007156 no resultado, 2.581,01 no cálculo) —
  ou, se nada casar, o primeiro na ordem do portal; o motivo diz qual dos dois foi
  (`escolhido pelo portal (premio do calculo=351.59)` / `primeiro na ordem do portal (…)`). Em
  qualquer ramo, o que ficou de lado vai para o motivo: `posto de lado: premio=134.5
  (parcelamentos=[] …)`.
- Fixture `test/fixtures/agger/parcelamentos-reais-2026-09-11.sanitized.json` (só números de preço e
  parcelamento; nenhum dado pessoal). Desde a rodada de correção carrega também DUAS seguradoras
  recusadas no formato bruto (Darwin na renovação, 15 chaves com `premioMensal: null`; Usebens na
  moto, 6 chaves sem `selected`). Guardas: toda oferta real com plano de pagamento sai `total`; toda
  seguradora real da fixture passa por `result()` (recusada → `declined`, cotada → `quoted`).
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
| 5 | Períodos diferentes nunca ordenados pelo número cru | adapter: `escolherPremium` (M3 da rodada 1; rodada de correção R-M2/R-M3/R-M4/R-M5: sem período conhecido, escolha do portal ou ordem dele, nunca o menor número, e os demais sempre no motivo); chat2you: `QuoteOffers#quoted` particiona (MC1; `ramo_auto_spec` "no lote, o preço sem período vem depois") | fechado |

## Rodada de correção (verificador cego, 11/09/2026)

Dois achados na PR autonomia-adapters#54, os dois corrigidos na causa raiz, na mesma branch.

| # | Achado | Causa raiz | Correção | Guarda |
|---|---|---|---|---|
| P1 | `premioMensal: null` (toda seguradora recusada: Darwin, Sancor, Zurich, Bradesco, Liberty, Bp…) reprovava o schema; `result()`, `read()` e `proposal()` lançavam `protocol` e o cliente ficava sem preço NENHUM. Reproduzido: `quote result b0220871…:1` → exit 76 no c7c9165 | a fixture saneada filtrava `selected && premio numérico` e apagou a forma que não é preço; nenhum teste tinha seguradora recusada no bruto | `premioMensal: z.union([z.number(), notYet, z.null()])`; fixture ganha Darwin (15 chaves) e Usebens (6 chaves) no bruto | `agger-quote-fluxo`: "seguradora recusada com premioMensal: null ao lado de uma que cotou: declined + quoted, sem protocolo" e "toda seguradora real da fixture passa por result()" (R-M1) |
| P2 | `escolherPremium` sem período conhecido escolhia o menor número cru e os demais sumiam do motivo — a mesma classe do defeito da Justos, com guarda invertida (`not.toContain('posto de lado')`) | a regra "período desconhecido não se compara pelo número" tinha exceção no próprio ramo em que ela mais importa | escolha do PORTAL (`calc.premio` casa com um resultado, ±0,01) ou o primeiro na ordem dele; `posto de lado` SEMPRE anexado | `agger-quote-fluxo`: três testes novos (portal escolhe 400 sobre 351,59; Hdi com tolerância; sem escolha → primeiro, ausente e não-casa) (R-M2…R-M5); `quote-guardas` "a mais barata" reescrito com planos de período conhecido |

Mutações da rodada (arquivo restaurado, md5 conferido igual ao original no fim; `mutacoes_r2.cjs`):

| Mutação | Reprova o alvo |
|---|---|
| R-M1 schema volta a recusar `premioMensal: null` | sim (2 testes) |
| R-M2 sem período conhecido volta a `maisBarato` | sim (3 testes) |
| R-M3 sem período conhecido, os demais não vão ao motivo | sim (3 testes) |
| R-M4 sem escolha do portal, sai o último em vez do primeiro | sim (1 teste) |
| R-M5 escolha do portal exige igualdade exata (sem o centavo) | sim (1 teste) |

Prova ao vivo (leitura, `quote result` nas três cotações reais, conta de teste): exit 76 no
c7c9165 → exit 0 com a correção, 17 ofertas em cada; renovação: Tokio 1.901,97 total 12x, Justos
1.539,24 total 10x com `posto de lado: premio=134.5`, Bp Assinatura 351,59 `unknown` com
`escolhido pelo portal (premio do calculo=351.59)`, Hdi 2.581,007156 total 12x; moto: Suhai e Porto
total; caminhão: Suhai total, Pier `auth_required`, o resto `declined`.

Também nesta rodada: `test/unit/destino-seguro.test.ts` presumia que a pasta do checkout se chama
`autonomia-adapters` (reprovava em qualquer worktree; a rodada 1 contornou com symlink de nome).
Corrigido na premissa do teste (`basename(RAIZ)`), uma linha — sem isso `pnpm verify` não é um
portão em worktree.

`pnpm verify` verde: 769 unitários + 12 integração, cobertura 100/100/100/100.

### Mutações do chat2you (8/8 reprovam o alvo; restaurado com md5 conferido)

MC1 `quoted` ordena pelo número cru · MC2 `resumo` volta a deduzir total do parcelamento · MC3
`sem_periodo` devolve vazio · MC4 registro no handle desligado · MC5 registro sobrescreve em vez de
acumular · MC6 `motivo` ignora o `basis_evidence` · MC7 `indefinido?` volta a aceitar parcelamento
como base · MC8 mock: oferta sem período vira total.

## Rodada de correção 3 (verificador cego, veredito anterior APROVADO, 4 achados P3)

| # | Achado | Causa raiz | Correção | Guarda | Mutação |
|---|---|---|---|---|---|
| A1 | adapter `quote.ts` `escolherPremium`, ramo com período conhecido: só os planos NÃO-`total` iam ao motivo; outro `total` posto de lado sumia do `basisEvidence`. Porto moto real: sai 430,75 ("Incêndio, Roubo/Furto") e o 671,73 ("Compreensiva", a escolha do portal em `calc.premio`) não aparecia em lugar nenhum — o comentário prometia "em qualquer caso, o que ficou de lado vai ao motivo" e o código não cumpria; a guarda `not.toContain('posto de lado')` FIXAVA o defeito | o filtro do ramo conhecido era `basis !== 'total'` (o que ficou de fora do critério) em vez de "todo plano que não foi o escolhido" | `premios.filter((p) => p !== escolhido)`; comentário reescrito com o caso da Porto e a decisão de produto pendente | `agger-quote-fluxo` "com todos os planos de período conhecido, sai o mais barato e o outro total vai ao motivo": `toContain('posto de lado: premio=671.73')` (números reais da Porto moto) | R3-M1: filtro volta a `basis !== 'total'` → 1 teste reprova (`Tests 1 failed / 27 passed`); restaurado, md5 conferido igual |
| A2 | esta auditoria dizia que o payload não tem "observação de texto"; tem `observacoes`, `alertas`, `coberturas.tipo` (por resultado) e `vigenciaIni/vigenciaFim` (por versão) | a tabela do termo 3 só listava os campos numéricos | tabela dos campos de texto/vigência acima, com o conteúdo observado na Bp Assinatura, na Justos, na Tokio e na Porto moto; nenhum distingue período — a decisão "sem detector" se sustenta | só documentação | — |
| A3 | chat2you `PremiumText#detalhe` devolvia a linha de parcelamento ANTES de checar `indefinido?`: premium `{351.59, unknown, installments 2x 175,80}` → "R$ 351,59 / ou 2x de R$ 175,80" SEM a ressalva, com o handle dizendo "sem período" para uma frase que o cliente não ouviu. Hoje inalcançável (o adapter só manda `installments` junto de `total`), mas a spec que cobria o caso exigia "não diz no total" e não exigia a ressalva | a ordem das duas linhas em `detalhe` tratava o parcelamento como mais forte que a falta de período | `return SEM_BASE if indefinido?` antes da linha de parcelamento (sem período, o parcelamento não tem o que parcelar; o motivo no handle é que explica o que ficou de fora) | `premium_text_spec` "sem periodo, a ressalva vem antes do parcelamento" (`detalhe == SEM_BASE`); `quote_offers_spec` "nem com parcelamento no payload" passa a exigir `include(SEM_BASE)` e `not_to include('2x de')` | R3-MC1: ordem original restaurada → 2 testes reprovam (24 exemplos, 2 falhas); restaurado, md5 conferido igual |
| A4 | `especialista_auto.md:191` diz "da mais barata para a mais cara" e nada diz ao especialista que preço sem período não se compara pelo número (termo 5 na camada conversacional, "qual a mais barata?") | — | **DEFERIDO pelo orquestrador**: o arquivo de instrução não é tocado nesta rodada (md5 assinado no builder spec). A frase "as sem período vêm no fim e não se comparam pelo número; se perguntarem a mais barata, compare só as que dizem no total" fica como **prova real pendente do termo 5** na conversa | — | — |

Decisão de produto para o Rodrigo (fora desta rodada; registrada aqui e no comentário de
`escolherPremium`): no ramo com período conhecido, a régua hoje é "o mais barato entre os `total`";
a alternativa é a régua única "escolha do portal (`calc.premio`) quando casa; senão o mais barato de
período conhecido". O caso real é a Porto na moto: 430,75 "Incêndio, Roubo/Furto" (sem DM/DC) contra
671,73 "Compreensiva" (a escolha do portal) — 56% abaixo, o lado que fecha venda, e é PACOTE de
cobertura, não período. Com A1, o 671,73 ao menos fica no motivo; qual dos dois o cliente deve ler
primeiro é decisão de negócio, não de código. Issue própria a abrir.

Comandos da rodada 3 (worktrees `~/dev/worktrees/{adapters,chat2you}/entrega-13-periodo-do-preco`):
- Bruto: `uv run python3 <scratchpad>/e13/inspecionar_r3.py` sobre `renovacao-versoes.json` e
  `moto-versoes.json` salvos na rodada 2 (fora do repo; nenhum `quote start`).
- Adapter: `npx prettier --write` nos 2 tocados; `pnpm verify` exit 0 — **769 unitários + 12
  integração (781), cobertura 100/100/100/100**; mutação R3-M1 por `npx vitest run
  test/unit/agger-quote-fluxo.test.ts` (exit 1, 1 falha), arquivo restaurado e md5 conferido.
- chat2you: `POSTGRES_DATABASE=chatwoot_test_e13 bundle exec rspec` nos 4 specs alvo (`premium_text`,
  `quote_offers`, `insurance_quote_ramo_auto`, `connector/quote`) `--format json` — **73 exemplos, 0
  falhas, 0 erros fora de exemplos**, exit 0; `rubocop --format json` nos 3 arquivos Ruby tocados — 0
  ofensas; mutação R3-MC1 (exit 1, 2 falhas em 24), restaurado e md5 conferido; suíte ampla
  `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia` — **1.029 exemplos, 0 falhas, 0 erros fora de exemplos** (3 pendentes pré-existentes), exit 0, lido do JSON do rspec. O total subiu de 899 para 1.029 porque a rodada 3 inclui `spec/requests/api/v1/accounts/autonomia`, que as rodadas anteriores não rodavam.

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

Rodada de correção (só o adapter mudou de código; no chat2you esta auditoria):
- Bruto das três cotações: `npx tsx <scratchpad>/e13/bruto-versoes.mts` (login + `GET
  cotacao/versoes`, salvo fora do repo). Reprodução do P1: `npx tsx src/cli/main.ts agger quote result
  b0220871-…:1` → exit 76 antes, exit 0 depois (idem moto e caminhão).
- `pnpm verify` (exit 0) no worktree, sem symlink de nome. Mutações: `node <scratchpad>/e13/mutacoes_r2.cjs`
  (5/5 reprovam, md5 restaurado).
- chat2you: specs alvo repetidos por sanidade com `POSTGRES_DATABASE=chatwoot_test_e13` (código Ruby
  idêntico ao da rodada 1; resultado abaixo).

Specs alvo na rodada de correção: **72 exemplos, 0 falhas, 0 erros fora de exemplos**, exit 0 (lido do
JSON do rspec). Adapter da rodada: `a6309b9`.
