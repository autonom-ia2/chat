# Entrega 3 — o manual do especialista alinhado ao que passou a existir

Data: 11/09/2026. Plano: entrega 3 do Agente de Cotação (6 termos de aceite). Issue-mãe: #291.
Depende da entrega 2 (fatia B, chat#379): o texto descreve a consulta de placa e o formulário de
noventa campos.

## O achado que muda o desenho

A instrução do especialista `cotacao_auto` do agente 24 em produção tinha md5 `c5d6711f…` (10.208
caracteres, gravada em 08/09 17:40Z). O arquivo do repositório (`instrucoes/especialista_auto.md`)
tinha md5 `60f3e219…` (11.352). A diferença é a mudança de #362 (10/09: "entregue todas as ofertas",
sem o teto de três) — que **nunca chegou ao agente já criado**. É exatamente o que o plano descreve:
"o manual é gravado dentro do agente no momento em que ele nasce; corrigir o modelo não corrige quem
já existe". Reaplicar por UPDATE consertaria este caso e deixaria a classe: a próxima edição do
arquivo desatualizaria de novo.

## O desenho

- **O manual que vale é o do deploy.** `Builder.instrucao_mantida(specialist)` devolve o texto do
  arquivo para os especialistas que a Autonom.ia mantém (agente `insurance_quote`, slug em
  `ESPECIALISTAS`); `Specialist#effective_instruction` passa a ler daí (`instrucao_do_sistema`), e a
  coluna `instruction` fica como retrato do nascimento. Especialista que a corretora criou com
  instrução própria (agente `custom`) continua lendo a coluna. O arquivo é lido cru: a spec garante
  que não há variável nele.
- **O texto aprovado (v6)** entra em `especialista_auto.md`, com TRÊS ajustes que o Codex e o código
  impuseram depois da aprovação — para decisão do Rodrigo, listados abaixo.
- **A guarda** (`builder_instrucao_do_especialista_spec`): cada promessa do texto, pela FRASE EXATA,
  amarrada ao que a sustenta no código ou no schema do adapter (snapshot do mock) — 24 promessas; o
  texto não cita slug de ferramenta que não é do especialista; não escreve `R$` nem nome de pacote
  (lidos do schema); não tem variável; agente já criado lê o texto novo sem ser recriado; agente
  criado do zero nasce com o mesmo; o acréscimo da corretora entra depois.

### Ajustes ao texto aprovado (v6)

1. §4 "Assim que receber a placa, consulte-a" ganhou a condição "se ainda faltar algum dos quatro"
   e o parágrafo "Se os quatro já vieram, cote direto: a cotação consulta a placa sozinha, e você
   tem uma rodada de ferramentas por resposta — consultar e cotar não cabem na mesma". Motivo: a
   rodada de ferramentas do especialista é UMA (`ResponsesClient#create_with_tool_executor`); com o
   texto original, cliente que manda tudo de uma vez faria o especialista consultar e não cotar
   (achado 4 do Codex na entrega 2).
2. §4 exemplo "Se a apólice diz R$ 200 mil … e o cliente pede R$ 500 mil" virou "Se a apólice traz
   um valor de danos a terceiros e o cliente pede outro, vai o do cliente". Motivo: termo 3 —
   nenhum valor de cobertura no texto; a guarda é `R$` ausente.
3. §11 item 1 "as cinco da §4" → "os quatro da §4" (a §4 lista quatro).

Observação, sem edição: §8 "Comissão pode ser obrigatória … Se a ferramenta pedir, é isso" — a
ferramenta nunca pede: `commissionPercent` não é exposto ao modelo (`Parametros::NAO_EXPOSTOS`), a
comissão vem da conexão da corretora. A frase não promete nada ao cliente; fica como está até o
Rodrigo decidir.

### Termos (6)

| # | Termo | Estado |
|---|---|---|
| 1 | Texto aprovado aplicado | `especialista_auto.md` = v6 + 3 ajustes acima (md5 no fim desta auditoria) |
| 2 | Verificação cruza toda ferramenta citada com as que existem | 24 promessas ancoradas por frase + "não cita ferramenta que não é dele" |
| 3 | Nenhum valor de cobertura no texto | guardas `R$` e nome de pacote (lido do schema) |
| 4 | Promessa falsa reintroduzida quebra a verificação | mutações M3–M9 (`mutacoes_e3.py`) |
| 5 | Agentes já criados recebem o texto novo; produção lida e idêntica | runtime lê o arquivo (spec + M1/M2); coluna do agente 24 atualizada no rollout; md5 conferido em produção — **pendente até o deploy** |
| 6 | Agente criado do zero nasce com o mesmo texto | spec (Builder → coluna = arquivo = runtime) |

## Rollout (depois do deploy)

1. Conferir a coluna em produção (read-only): `md5(instruction)` do especialista 1.
2. UPDATE da coluna para o texto do deploy (backup antes; rollback = texto anterior guardado no
   backup). Não é o que faz o runtime ler o texto novo — isso o deploy já faz —; é o que faz a
   leitura do banco ser idêntica ao aprovado (termo 5, "comparação exata").
3. `md5(instruction)` em produção == md5 do arquivo do repositório no SHA deployado.

## Da mesma classe, fora desta entrega

`principal.md` (a instrução da Lia) tem o mesmo defeito — copiada no nascimento, com variáveis
substituídas (`$nomeAgente`, `$nomeCorretora`, …). Não entra aqui: o plano da entrega 3 é o manual
do especialista, e o principal tem variáveis, que exigem outro desenho (substituir na leitura, com
os valores gravados). Issue a abrir.
