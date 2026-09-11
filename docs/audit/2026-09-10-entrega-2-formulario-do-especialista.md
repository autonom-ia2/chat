# Entrega 2 — o formulário do especialista passa de dez para noventa campos

Data: 10/09/2026 (noite) — 11/09/2026. Plano: entrega 2 do Agente de Cotação (10 termos de aceite).
Issue-mãe: #291. Repositórios: `autonomia-adapters` (fatia A) e `chat` (fatia B). Motivação
imediata: #378 — toda renovação pela Lia terminava em zero preço porque a ferramenta não tinha
onde escrever a seguradora anterior.

## O desenho, em uma frase

O formulário nasce do adapter. `quote/schema` de auto passa a carregar, por campo, a descrição em
português que ensina o modelo a extrair o valor da conversa e os valores aceitos (código →
rótulo), lidos do conhecimento capturado do portal. O chat2you guarda esse schema na conexão da
conta (na sincronização) e monta com ele os parâmetros do `cotar_seguro`, aninhados por grupo
(`vehicle: { plate }`), em strict mode. A montagem da entrada vira mecânica: o grupo vai como veio.
Nada de auto é digitado no chat2you — nem nome de campo, nem código, nem padrão.

## Fatia A — adapter (PR #51, mergeada em `65e39bf`; PR #52, mergeada em `41cba52`; Lambda no ar)

- `ramos/schema-auto.ts`: `DOMINIO_DE` (campo → domínio do portal em `value-domains.json`, com
  fallback na semente `field-contracts.json`), `valoresDe`, `descricaoDe`; `knowledge/descricoes-
  auto.json` (84 descrições escritas à mão em 10/09; nenhum código dentro delas — guarda por token);
  as 34 seguradoras anteriores de auto (`insurer-registry.json`, `apoliceAnterior`) no campo de
  renovação; tipo de veículo (`VEHICLE_TYPE_LABELS`, ao lado do enum) e pacotes (chaves de
  `PACKAGES` + rótulos do portal) de uma fonte só.
- `ramos/condicionais.ts`: seis travas na conferência gratuita, depois da checagem de domínio —
  renovação sem seguradora anterior (ERRO; número e vigência são AVISO: as medições de 05/09 não os
  isolam), empresa sem condutor pessoa física, empresa com vínculo "próprio", jovem sem idade e
  sexo, caminhão com uso de carro, moto sem associado e frequência. Padrões lidos do Zod; tabela
  uso × veículo é a mesma do `start`; dedupe só entre ausências.
- `vehicle/lookup` (consulta de placa, grátis, antes de cotar) e `quote/read` (a cotação como o
  portal gravou, nomes do portal, só escalares, sem dado da pessoa). CLI: `vehicle lookup`,
  `quote read`.
- PR #52: o tipo de campo com `transform`/`refine`/união saía como `objeto` (17 campos) —
  `innerType()` no desembrulho, `refine` no lugar de `pipe`, união lê o primeiro membro.
- Codex: PR #51 em 6 rodadas (REPROVADO ×5 → APROVADO em `40eb02d`); PR #52 APROVADO em 1.
  Achados reais: trava além da evidência; descrição que desligava as travas; valores à mão
  ("1 (Próprio)", "1 Prata", "use 0", "17 a 25", "100", "7 caracteres", `v/m/c` duplicado, 11/14);
  dedupe apagando diagnósticos de lista; objeto passando pela allowlist.
- Validação: `pnpm verify` verde (765 testes, cobertura 100%); 18 mutações; prova ao vivo
  read-only pela CLI (`vehicle lookup HIK9383` → Vectra 2008 tipo `v`; `quote read` da cotação da
  execução 7 → `renovacao: true, bonusAnterior: 9, seguradoraAnteriorId: null` — a causa do #378
  lida de volta do portal).

## Fatia B — chat2you (esta PR)

- `Native::Base#openai_schema(agent)` monta objetos aninhados em strict (todas as chaves em
  `required`, `additionalProperties: false`, opcional = `[tipo, 'null']`); `params_for(agent)`.
  `Bound#openai_schema` passa o agente.
- `Insurance::Parametros`: schema do adapter → um `object` por grupo (rótulo do grupo escrito aqui;
  grupo novo do adapter entra com rótulo genérico, nunca some; campo de raiz novo entra plano e a
  travessia reprova se a entrada não o levar) e a lista curta do que não se expõe:
  `commissionPercent` (é da conexão da corretora) e `insurerCodes` (decisão do PO: todas).
- `Connection#quote_schema(product)` + `Connections::Sync#scan!` guardando `quote_schemas.auto` na
  sincronização — DENTRO do lock, com a linha recarregada, mesclado por produto (adapter mudo num
  produto não apaga o outro, e a varredura não apaga o que o polling gravou enquanto ela esperava
  o adapter). Conexão sincronizada antes desta versão: a ferramenta busca e guarda na primeira
  montagem; sem schema mesmo assim, a ferramenta recusa auto por `formulario_indisponivel` (turno
  e envio) — indisponibilidade nossa não vira "peça a placa ao cliente". Exceção transitória: schema
  ausente na montagem e presente na conferência (recuperado entre as duas) → `sem_veiculo` uma vez,
  porque os argumentos vieram sem o bloco; a montagem seguinte já o tem.
- `QuoteInput#de_auto`: os sete grupos vão como vieram (`nil`/vazio saem; `false`/`0` ficam);
  `cpf`/`nome`/`cep`/`numero` continuam como atalho, e o bloco vence quando os dois vêm.
  `AutoRenewal` lê `quotation` (só para o aviso de renovação sem bônus).
- `InsuranceQuote`: a entrada leva o que o portal sabe do veículo SEMPRE que há placa
  (`Veiculo#com_veiculo`): tipo e ano da consulta vencem o que o modelo escreveu — por construção,
  não por obediência. No turno (conferência, `delivery` presente) a consulta só corre com a sessão
  que já está viva (`Session#with_live_session`): login tem o teto de 60 s do conector e o turno não
  espera; no job do envio, com a sessão fresca. Falha ou ausência da consulta não barra. Sem placa,
  chassi nem FIPE → recusa `sem_veiculo` no turno (texto ao modelo) e no envio (texto ao cliente);
  a conferência fala ao modelo pelo campo e pelo motivo do adapter.
- `Native::VehicleLookup` (`consultar_placa`) para o especialista: modelo, ano e tipo com o rótulo
  do schema; só com sessão viva (nunca abre login no turno); recusas `placa_invalida` e
  `consulta_de_placa_indisponivel` registradas (entrega 6). A descrição diz QUANDO: placa em mãos e
  ainda faltando dado — com tudo em mãos, `cotar_seguro` direto, porque a rodada de ferramentas do
  especialista é uma só (`ResponsesClient#create_with_tool_executor`) e a cotação consulta sozinha.
  `Builder::TOOLS_DO_ESPECIALISTA = %w[consultar_placa cotar_seguro]`.
- Conector: `Http#vehicle_lookup`/`quote_read`; `Mock` com o schema de auto gerado pela CLI do
  adapter (`mock/schema_auto.json`, 84 campos; regenerar com `npx tsx src/cli/main.ts agger quote
  schema auto`) e as leituras (`Mock::Leituras`).

### Termos (10)

| # | Termo | Estado |
|---|---|---|
| 1 | Campos gerados do adapter, nada à mão, nenhum valor em dois lugares | Código + guardas (adapter: descrição ↔ Zod; chat2you: `parametros_spec`) |
| 2 | Verificação quebra se o adapter ganhar campo sem o formulário | O formulário É o schema guardado na sincronização; `parametros_spec` amarra o snapshot ↔ formulário; raiz nova reprova a travessia |
| 3 | Descrição em português por campo, com sinônimos | 84 em `descricoes-auto.json`, chegam no schema e na ferramenta |
| 4 | Todo campo declarado é enviado | `quote_input_travessia_spec` (cada folha do formulário chega ao envio) |
| 5 | Consulta de placa obrigatória antes de cotar | `com_veiculo` na própria cotação, sempre que há placa, e o portal vence (por construção; spec + mutações M20/M21); `consultar_placa` para o especialista confirmar o veículo antes de pedir o resto |
| 6 | Seguradoras anteriores na descrição do campo | 34 de auto, `657=HDI…` |
| 7 | Cinco condicionais viram trava com mutação | Seis no adapter (M5–M9), cada uma com par viola/cumpre |
| 8 | Cotação real com campo hoje impossível, lido de volta | **Pendente: rodada real (fatia D)** — `quote/read` pronto |
| 9 | Conversa real de moto e de caminhão | **Pendente: fatia D** (harness + rodada) |
| 10 | Sem placa e sem chassi não cota, encaminha | `sem_veiculo` no turno e no envio (spec + mutações M11/M12) |

### O que fica de fora desta PR, de propósito

- A instrução v6 do especialista (entrega 3): "não aplicar antes das entregas 1 e 2" — próxima PR.
- Em produção, `consultar_placa` precisa entrar em DOIS lugares, na mesma transação, e nesta ordem:
  `specialists.tool_slugs` do especialista do agente 24 (reserva: sem ela a ferramenta apareceria
  no PRINCIPAL) e `agents.config->native_tool_slugs` do agente 24 (catálogo: `Registry.for_agent`
  só liga o que está lá; só a reserva deixa a ferramenta em lugar nenhum). O `Builder` grava os
  dois só na criação. A conexão da conta 16 precisa sincronizar uma vez (ou a ferramenta busca o
  schema na primeira montagem e guarda).
- `pctAjuste`/`tipoFranquia`: o domínio publicado é mais estreito que o Zod; os valores entram só
  na descrição, nunca como `enum` (observação do Codex, rodada 2 do adapter).

## Codex — rodada 1 (`7ac1ac69`, REPROVADO, 4 P2) e o que mudou

1. **`scan!` apagava escrita concorrente de `metadata`** — o `update!` gravava o jsonb inteiro do
   retrato em memória, depois de segundos de HTTP. Agora: capacidades e schema buscados fora, a
   escrita dentro de `with_lock` (linha recarregada), `quote_schemas` mesclado por produto. Spec de
   corrida (outro escritor grava durante o `quote_schema`) + M19 (tirar o lock reprova).
2. **A conferência podia esperar login de 60 s** — `with_fresh_session` na consulta de placa dentro
   do turno. Agora: `Session#with_live_session` (só a sessão viva, nunca abre, nunca renova) no
   turno; `with_fresh_session` só no job. Vale para `consultar_placa` também — mesma classe. Specs
   "não abre login" nos dois + M21/M23/M24.
3. **Schema indisponível virava "peça a placa"** — a ferramenta saía só com o comum e recusava por
   `sem_veiculo`. Agora: `formulario_indisponivel` (motivo novo, registrado), antes de `sem_veiculo`,
   no turno (texto ao modelo: encaminhe) e no envio (`FALHOU`); antes de recusar, tenta buscar o
   schema e guardar. Spec + M22. Corrida "ausente na montagem, presente na chamada" fica: `sem_veiculo`
   uma vez, e a montagem seguinte já tem o bloco.
4. **Consultar e cotar não cabem na mesma rodada** — a descrição mandava consultar ANTES de cotar, e
   `create_with_tool_executor` faz a segunda chamada sem ferramentas. Decisão: não abrir segunda
   rodada (é o núcleo do turno, do principal também); a cotação consulta SEMPRE que há placa e o
   portal vence (M20), e a descrição de `consultar_placa` passa a dizer quando usá-la (placa em mãos,
   dado faltando) e quando não (tudo em mãos → cotar direto). A observação do Codex de que "tipo
   já informado não consultava" era verdadeira — e caía junto.
5. **Rollout**: a auditoria previa só `tool_slugs`; `Registry.for_agent` exige o slug também em
   `native_tool_slugs` do agente. Seção "O que fica de fora" corrigida (dois lugares, uma transação,
   reserva primeiro).

Rodada 2 (`f0746414f2`): **APROVADO**, 2 P3 incorporados aqui e nos comentários — o teto de 10 s é
de leitura POR TENTATIVA (até duas por atendimento sem schema), não do turno; e a exceção
transitória acima. Frase de `consultar_placa` reescrita na forma que o Codex sugeriu (placa, CPF e
CEP em mãos → cotar direto).

## Produção (11/09/2026)

- chat#379 squash `b25abe4424`; deploy blue-green concluído nas duas stacks às 00:46Z (Autonomia: alvo
  `i-025e227311cbd56b3`, imagem `b25abe4424`, healthz 200).
- Rollout de `consultar_placa` às 00:47Z (`~/ops/agente-cotacao/entrega-2/rollout-consultar-placa.sh`,
  uma transação, abort por contagem; backup `/tmp/chat2you_tool_slugs_20260911T002637Z.txt`): especialista 1
  `["consultar_placa","cotar_seguro"]`; agente 24 `["consultar_produtos_cotacao","consultar_condicoes_gerais",
  "cotar_seguro","consultar_placa"]`. Healthz 200 depois.
- Conexão 10 (conta 16): sem `quote_schemas` até a primeira montagem do formulário (a ferramenta busca e
  guarda); conferir por psql depois do primeiro turno do especialista.
- **Pendente (fatia D, autorização por rodada):** termo 8 (renovação com a apólice HDI, lida de volta por
  `quote/read` — resolve #378) e termo 9 (moto NCD3080, caminhão IDX3056). Plano das rodadas em
  `~/ops/agente-cotacao/entrega-2/rodadas-reais.md`. Nenhum turno de teste na conversa 5045 sem
  autorização: o histórico tem CPF e CEP, e o manual manda cotar sem pedir licença.

## Rodadas reais (11/09/2026, autorizadas pelo Rodrigo: "Tem meu ok em tudo")

**Rodada A — renovação com a apólice do William: VERDE.** PDF + pedido numa mensagem (06:47Z).
Execução 8, cotação `b0220871-…:1`. O especialista escreveu `quotation.isRenewal=true`,
`previousInsurerCode="657"` (HDI, código de apólice anterior), `bonusClass=9`, `previousClaimsCount=1`,
número e fim de vigência da apólice, chassi, FIPE, FLEX, coberturas lidas do PDF. Schema guardado na
conexão 10 na primeira montagem (84 campos). **11 seguradoras cotaram** (Usebens, Mapfre, Suhai,
Tokio, Justos, Porto, HDI, Pier, Allianz, Bp Assinatura, Ituran), 6 recusaram — na execução 7 eram 17
recusas. `quote read`: `renovacao=true, seguradoraAnteriorId="657", bonusAnterior=9,
sinistrosAnterior=1`. Prazo estourou de verdade (19 consultas, 7,5 min): PDF + fecho parcial saíram
(entrega 4, termo 1). **Fecha #378 e os termos 6 e 8.** Prova: `~/ops/agente-cotacao/entrega-2/rodada-A.md`.

**Rodada B — moto NCD3080: VERDE, com defeito real encontrado e corrigido no caminho.** Primeira
mensagem (06:58Z): a conferência recusou por `vehicle.isAssociate, vehicle.usagePeriod` sem gastar e a
Lia perguntou. Na resposta, a conferência recusou de novo só por `usagePeriod` e o especialista
ESCALOU: o schema publicava o campo **sem `valores`** (o Zod aceitava 0/1/2, o modelo não sabia que
"todos os dias" é 0) — furo do termo 3 neste campo, e o mesmo no caminhão (`predominantPeriod`, que
ainda ia "3" em silêncio e cujo domínio do cálculo é 1/2/3, não o 0/1/2 da lista da tela).
Correção: autonomia-adapters#53 (listas curtas de `Auto/Data` capturadas inteiras em
`listas-auto.json`; `usagePeriod` lê `PeriodoUso`; caminhão com rótulos ao lado do Zod e trava
`caminhaoSemPeriodo`; guarda: todo campo restrito a literais publica valores). Codex 2 rodadas →
APROVADO. Lambda versão 21 publicada por CLI (o GitHub Actions ficou ~30 min sem criar runs; os dois
jobs do CI foram reproduzidos localmente; a branch precisou de rebase por ter nascido do commit
pré-squash do #52). `quote_schemas` da conexão 10 apagado (backup) e rebuscado com os valores. Retomada
(07:56Z): execução 9, `vehicleType=m`, `isAssociate=false`, `usagePeriod=0`; 2 preços (Suhai R$ 291,35,
Porto R$ 430,75), 15 recusas; `quote read`: `tipo=m, associado=false, periodoUso="0"`. **Termo 9
(moto) fechado.** Issue chat#383: o schema guardado nunca se renova sozinho. Prova: `rodada-B.md`.

**Rodada C — caminhão IDX3056: PENDENTE por indisponibilidade da OpenAI.** Três tentativas
(08:05Z, 08:14Z, 08:24Z) morreram em `503 server_is_overloaded` antes de qualquer resposta — quatro
503 em 18 min, "Partial System Degradation" no status da OpenAI. Nenhuma cotação gasta. Issue
chat#384: o turno morre em silêncio, sem retry/backoff nem aviso ao cliente. Prova: `rodada-C.md`.
