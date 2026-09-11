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
  coluna `instruction` fica como retrato do nascimento. O mesmo para a DESCRIÇÃO que o principal lê
  na função (`descricao_do_sistema` ← `Builder.descricao_mantida`): a gravada dizia "para pessoa
  física" e o manual passou a cotar empresa. Especialista que a corretora criou com instrução própria
  (agente `custom`) continua lendo as colunas. O arquivo é lido cru: a spec garante que não há
  variável nele.
- **Zero-quilômetro ambíguo é conferência no código.** O ajuste "com os quatro em mãos, cote direto"
  deixaria um modelo do ano (ano atual ou seguinte, pela consulta de placa) ser cotado como usado — o
  schema documenta que `isZeroKm` omitido é usado. `Veiculo#problema_de_zero_km` compara o ano do
  modelo com o calendário e entra na conferência como um problema a mais, no formato do adapter
  (`vehicle.isZeroKm — motivo`, `faltam_dados`): no turno o modelo lê e pergunta com o nome do carro;
  no envio o cliente lê "se o veículo é zero-quilômetro" (`ROTULOS`). Código compara dados; quem
  pergunta é o modelo. Sem motivo novo, sem gatilho novo.
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
| 4 | Promessa falsa reintroduzida quebra a verificação | md5 do texto assinado na spec (mudou uma letra, reprova, e quem assina revisa `PROMESSAS`) + campo só conta se EXPOSTO ao modelo + mutações M3–M16 (`mutacoes_e3.py`) |
| 5 | Agentes já criados recebem o texto novo; produção lida e idêntica | runtime lê o arquivo (spec + M1/M2); coluna do especialista 1 atualizada às 01:17Z; **produção lida: md5 `3eba319bca1e6159e950def73a2f91ab` = md5 do arquivo em `7260e4e317`** |
| 6 | Agente criado do zero nasce com o mesmo texto | spec (Builder → coluna = arquivo = runtime) |

## Rollout (depois do deploy) — `~/ops/agente-cotacao/entrega-3/rollout-instrucao.sh`

1. `backup`: texto (base64, `-At`, uma linha) + descrição + leitura, em `/tmp/chat2you_instrucao_especialista_<ts>.txt`.
2. `aplicar <arquivo.md> "<descricao>"`: o texto sobe em pedaços de base64 (teto do parâmetro do SSM),
   vira arquivo no container e entra como variável do psql num UPDATE PLANO (dentro de `DO $$` a
   variável não é interpolada — achado do Codex), com precondição `md5(left(:'texto',-1)) = md5 do
   arquivo` e abort se não houver `UPDATE 1`; `description` junto. Não é o que faz o runtime ler o
   texto novo — isso o deploy já faz —; é o que faz a leitura do banco ser idêntica (termo 5).
3. `conferir <arquivo.md>`: `md5(instruction)` em produção == `md5 -q` do arquivo no SHA deployado.
4. `rollback <backup>`: o mesmo caminho, com o texto e a descrição do backup.

## Codex — rodada 1 (`57f8353848`, REPROVADO: 1 P1, 4 P2)

1. **P1 rollout:** `:'texto'` dentro de `DO $$…$$` não é interpolado pelo psql; `; rm -f` mascarava o
   exit; `sleep` fixo em vez de estado terminal do SSM. Reescrito (acima).
2. **P2 guarda:** promessa nova em prosa passava ("emita a apólice"); campo escondido em
   `NAO_EXPOSTOS` continuava "cumprido". Agora: md5 do texto assinado na spec (toda mudança exige
   revisão de `PROMESSAS`) e `campo()` só aceita o que o formulário expõe (M11, M12).
3. **P2 zero-km:** "cote direto" cotaria modelo do ano como usado → problema local na conferência
   (`vehicle.isZeroKm`, M15, M16). A primeira forma (recusa nomeada em `start`/`precheck`) estourou a
   complexidade do rubocop — e era a forma errada: é dado faltando, não motivo novo.
4. **P2 descrição:** `ESPECIALISTAS[:descricao]` dizia "pessoa física" e é o que o principal lê →
   alinhada e lida do deploy (`descricao_do_sistema`, M14); o rollout atualiza a coluna também.
5. **P2 rollback:** `tr -d ' +\n'` apagava `+` do base64 → backup em `-At`, uma linha, sem `tr` de `+`.
6. P3 comissão: fica como texto aprovado, anotado acima. (i) M13: Builder gravando outro texto reprova.

## Da mesma classe, fora desta entrega

`principal.md` (a instrução da Lia) tem o mesmo defeito — copiada no nascimento, com variáveis
substituídas (`$nomeAgente`, `$nomeCorretora`, …). Não entra aqui: o plano da entrega 3 é o manual
do especialista, e o principal tem variáveis, que exigem outro desenho (substituir na leitura, com
os valores gravados). Issue a abrir.

Rodada 2 (`eddff00a66`): código aprovado nos achados anteriores; REPROVADO pelo script de rollout —
P1 `for i` em `ssm()` clobberava o `i` de `subir()` (escopo dinâmico do zsh; o upload em pedaços nunca
terminava) → índice local; P2 `ssm | tee` sem `pipefail` escondia falha remota → saída capturada,
status do `ssm` exigido E `UPDATE 1`, `set -o pipefail`. P3: a spec do zero-km usava a instância do
job na conferência → `tool_no_turno`. E o motivo pedia "o nome do carro" que a consulta interna não
entregava → `@modelo_lido` entra no texto ao modelo ("o veículo (Onix 1.0)").

Rodada 3 (`ccde424d21`): código APROVADO; P2 no backup do script (`psql | tr` remoto mascarava falha do
psql — backup vazio passaria por válido) → status do psql remoto preservado, texto vazio aborta, rollback
exige bytes > 0 e descrição. Rodada 4: **APROVADO**.

## Produção (11/09/2026)

- chat#381 squash `7260e4e317`; deploy concluído nas duas stacks às 01:16Z (Autonomia: alvo
  `i-03e542d5c66949213`, imagem `7260e4e317`, healthz 200).
- Rollout às 01:17Z (`rollout-instrucao.sh aplicar` com o arquivo extraído do blob de `7260e4e317`,
  md5 `3eba319bca1e6159e950def73a2f91ab`, 17.511 bytes / 16.823 caracteres): `UPDATE 1`, `COMMIT`;
  `conferir`: `md5(instruction) = 3eba319bca1e6159e950def73a2f91ab`, `description` = a do `Builder`. Backup
  anterior `/tmp/chat2you_instrucao_especialista_20260911T00*.txt` (md5 `c5d6711f…`, 10.627 bytes) — rollback
  = `rollout-instrucao.sh rollback <backup>`. Healthz 200 depois.
- Termo 5 fechado pela comparação exata. Os 3 ajustes ao texto aprovado seguem para decisão do Rodrigo.
