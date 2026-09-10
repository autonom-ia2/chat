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
  sincronização (adapter mudo mantém o anterior). Conexão sincronizada antes desta versão: a
  ferramenta busca uma vez e guarda.
- `QuoteInput#de_auto`: os sete grupos vão como vieram (`nil`/vazio saem; `false`/`0` ficam);
  `cpf`/`nome`/`cep`/`numero` continuam como atalho, e o bloco vence quando os dois vêm.
  `AutoRenewal` lê `quotation` (só para o aviso de renovação sem bônus).
- `InsuranceQuote`: a entrada leva o tipo do veículo da consulta de placa antes da conferência
  (`Veiculo#com_veiculo`; falha não barra); sem placa, chassi nem FIPE → recusa `sem_veiculo` no
  turno (texto ao modelo: peça a placa; zero-km sem placa → chassi; sem os dois, encaminhe) e no
  envio (texto ao cliente); a conferência fala ao modelo pelo campo e pelo motivo do adapter.
- `Native::VehicleLookup` (`consultar_placa`) para o especialista: modelo, ano e tipo com o rótulo
  do schema; recusas `placa_invalida` e `consulta_de_placa_indisponivel` registradas (entrega 6).
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
| 5 | Consulta de placa obrigatória antes de cotar | `consultar_placa` (especialista) + `com_veiculo` na própria cotação (vale por construção) |
| 6 | Seguradoras anteriores na descrição do campo | 34 de auto, `657=HDI…` |
| 7 | Cinco condicionais viram trava com mutação | Seis no adapter (M5–M9), cada uma com par viola/cumpre |
| 8 | Cotação real com campo hoje impossível, lido de volta | **Pendente: rodada real (fatia D)** — `quote/read` pronto |
| 9 | Conversa real de moto e de caminhão | **Pendente: fatia D** (harness + rodada) |
| 10 | Sem placa e sem chassi não cota, encaminha | `sem_veiculo` no turno e no envio (spec + mutações M11/M12) |

### O que fica de fora desta PR, de propósito

- A instrução v6 do especialista (entrega 3): "não aplicar antes das entregas 1 e 2" — próxima PR.
- Em produção, o especialista do agente 24 precisa de `consultar_placa` em `tool_slugs` e a
  conexão precisa sincronizar uma vez (ou a ferramenta busca o schema no primeiro turno).
- `pctAjuste`/`tipoFranquia`: o domínio publicado é mais estreito que o Zod; os valores entram só
  na descrição, nunca como `enum` (observação do Codex, rodada 2 do adapter).
