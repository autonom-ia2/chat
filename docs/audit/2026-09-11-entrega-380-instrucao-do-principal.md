# #380 — a instrução da Lia passa a ser a do deploy

Data: 11/09/2026. Issue: chat#380 (mesma classe do defeito da entrega 3, agora no principal). Issue-mãe:
#291. Auditoria anterior: `docs/audit/2026-09-11-entrega-3-manual-do-especialista.md`.

## O defeito

`Builder#criar_agente` gravava `instrucoes/principal.md` em `autonomia_agents.instruction` com as quatro
variáveis substituídas (`$nomeAgente`, `$nomeCorretora`, `$horarioAtendimento`, `$comportamento`) e nada
relia o arquivo: `PromptBuilder#instructions` lia `@agent.instruction`. Toda edição de `principal.md` só
valia para agente criado depois — o agente 24 (Lia, conta 16) nasceu em 08/09 com a versão de
`13492bb594` e não recebeu nem a retirada das crases (#355) nem a retirada das frases de roteiro
(`79b1cdad70`).

## O desenho

Duas partes, porque o principal tem o que o especialista não tinha — valores que a corretora escolhe:

1. **As escolhas ficam guardadas.** `criar_agente` grava, em `agent.config['agente_de_cotacao']`
   (`Builder::ESCOLHAS_DA_CORRETORA`), as quatro: `nome_agente`, `nome_corretora`, `horario`,
   `comportamento` — sempre as quatro, chaves string como o jsonb devolve. A coluna `instruction`
   continua recebendo o texto do dia (retrato do nascimento), pela MESMA substituição do runtime.
2. **Quem roda lê o arquivo.** `Builder.instrucao_do_principal(agent)` lê `principal.md` do deploy a cada
   montagem (`texto_do_principal`, nunca fotografado no boot) e substitui com as escolhas guardadas.
   `Agent#instrucao_do_sistema` devolve isso para o agente `insurance_quote` que tem a chave, e a
   coluna para todos os outros — inclusive o de cotação criado antes de as escolhas serem guardadas.
   `PromptBuilder#instructions` passa a ler `instrucao_do_sistema`. É o espelho de
   `Specialist#instrucao_do_sistema` (entrega 3).

O que NÃO cai em silêncio: chave presente e incompleta (campo faltando, em branco, ou — rodada 6 — com um
marcador reservado dentro; e presente com `null`, `{}` ou `false`) para com
`Builder::EscolhasIncompletas`, cuja mensagem é só o nome do campo. Variável nunca chega ao modelo como
`$nomeAgente`, nem por arquivo cru nem por coluna escolhida às escondidas. Só um write fora do Builder
produz esse estado: a API do agente protege a chave (`PROTECTED_CONFIG_KEYS`, que já mesclava sem
sobrescrever as computadas).

O texto de `principal.md` NÃO muda nesta PR (md5 `c72ee21689378b084538eae552399cec`, 12.888 bytes).

## Auditabilidade (termo 4)

O que foi ao modelo é função de duas coisas só: o arquivo no SHA deployado e as escolhas em
`config['agente_de_cotacao']`. Para reconstruir o prompt de um turno: pegar o SHA da imagem que estava no
ar (registro de deploy / healthz), abrir `instrucoes/principal.md` nesse SHA, substituir as quatro
variáveis pelos valores do config do agente (`Builder.instrucao_do_principal` faz exatamente isso, e a
spec «o mesmo arquivo e as mesmas escolhas devolvem o mesmo texto, sem depender da coluna» prova que a
coluna não entra na conta). O restante do `instructions` (scaffold, tom, guardrails, formato) já era
reconstruível pelo agente + código. A coluna `instruction` vira retrato do nascimento: diz o que a Lia
leu ATÉ o deploy desta PR, não depois.

## Termos → guarda

| # | Termo | Estado | Guarda / evidência |
|---|---|---|---|
| 1 | Valores guardados na criação, chave própria e documentada | fechado | `builder_instrucao_do_principal_spec` «grava os quatro valores no config, na chave própria», «guarda o horário e o comportamento padrão», «guarda o que a corretora escreveu, sem interpretar»; chave documentada em `Builder::ESCOLHAS_DA_CORRETORA`; M2 |
| 2 | Quem monta o prompt lê o arquivo e substitui; agente sem os valores continua na coluna | fechado | «o agente já criado recebe o texto novo» (mede `PromptBuilder#instructions`), «lê o arquivo de novo a cada montagem», «criado antes … continua lendo a coluna, sem quebrar», «agente que não é de cotação continua lendo a própria instrução»; M1, M3, M5, M8 |
| 3 | Agente já criado recebe o texto novo sem ser recriado | fechado em código | spec: cria pelo Builder, envelhece a coluna (`update!(instruction: 'instrução velha…')`), o prompt efetivo é o do arquivo com os valores; em produção depende do rollout abaixo (pendente_producao) |
| 4 | Auditabilidade mantida e documentada | fechado | seção acima; spec «auditabilidade (termo 4)» |
| 5 | SQL de rollout do agente 24 + conferência | entregue, não executado (pendente_prova_real) | seção «Rollout» abaixo; passo 1 com o retrato completo (`mode`, andaime, BuildThreads) desde a rodada 3 |
| 6 | Mutações: runtime lendo a coluna reprova; valores ausentes caindo no arquivo com placeholder reprova | fechado | M1 e M8 (coluna), M3 (arquivo cru), M4 (marcador sobrando), M6 (branco em silêncio); rodada 4: R4A (chave presente e vazia não volta à coluna); rodada 3: VG/VG2 fecham o flip de tipo que reabria «runtime lendo a coluna», VD prova a leitura a cada montagem, VF/VI provam a mensagem e o locale; rodada 6: R6A/R6A2 (passada única e fronteira do marcador), R6B/R6C/R6D/R6F (marcador dentro de uma escolha recusado no runtime, na criação e na porta), R6E/R6E2 (chave presente com `null` não volta à coluna) — tabelas abaixo |

## Mutações (`~/ops/agente-cotacao/issue-380/mutacoes_i380.rb`, 11/09/2026)

Cada uma: edita o arquivo, roda a spec alvo (`builder_instrucao_do_principal_spec` +
`external_agent_lifecycle_spec`), restaura, confere o md5 do original e, no fim, roda de novo verde.

| Mutação | Reprova? | Exemplos que caem |
|---|---|---|
| M1 `PromptBuilder` lê `@agent.instruction` | sim | «o agente já criado recebe o texto novo sem ser recriado» |
| M2 Builder não grava `agente_de_cotacao` | sim | 6 (os três do termo 1, «já criado recebe o texto novo», «lê o arquivo de novo», auditabilidade) |
| M3 escolhas ausentes → arquivo cru (placeholder ao modelo) | sim | «criado antes … continua lendo a coluna», «variável nunca chega — no agente criado antes» |
| M4 `VARIAVEIS` sem `$horarioAtendimento` | sim | 5 («nasce com o mesmo texto», «no agente criado pelo Builder», …) |
| M5 tipo do agente ignorado | sim | «agente que não é de cotação continua lendo a própria instrução» |
| M6 escolha em branco vira `''` em silêncio | sim | «escolha faltando para com o nome do campo», «escolha em branco também para», «o erro nomeia o campo…» |
| M7 chave fora de `PROTECTED_CONFIG_KEYS` | sim | «preserves the quote agent choices when updating config via API» |
| M8 `Agent#instrucao_do_sistema` devolve só a coluna | sim | 5 («já criado recebe o texto novo», «lê o arquivo de novo», os três de escolha incompleta) |

Restauração conferida por md5 nas oito; suíte alvo verde depois (`verde depois de restaurar: true`).

## Rollout em produção — agente 24 (conta 16) — o ORQUESTRADOR executa

A ordem não importa: antes do deploy a chave é inerte (o código de hoje não a lê); depois do deploy e
antes do SQL, a Lia segue lendo a coluna (comportamento de hoje). Do momento em que AS DUAS coisas
existem, a Lia passa a ler `principal.md` do deploy — isto é o efeito de #380, e é uma mudança de
comportamento em produção: se o agente 24 nasceu com o texto de 08/09, ele passa ao texto atual
(sem crases, sem frases de roteiro).

Os valores são lidos DO TEXTO GRAVADO (o nome é Lia; corretora, horário e comportamento estão lá). As
expressões aceitam as duas formas que o arquivo já teve: com crases (`13492bb594`, 08/09) e sem; horário
como «Dentro de X:» (08/09) ou «Dentro do horário de atendimento (X):» (atual). `psql` na conexão de
produção, um passo por vez.

Passo 1 — só leitura: de onde os valores vão sair, e o RETRATO COMPLETO do estado (rodada 3). Se alguém
usou «Ajustar com IA» na Lia entre 08/09 e o deploy, `apply_builder_config!` gravou `scaffold` e
reescreveu `instruction`/`config`: as expressões abaixo podem devolver NULL (aí para) ou casar por acaso.
Por isso o passo 1 também mostra `mode` (0 = guided), se há andaime, e quantas BuildThreads apontam para o
agente.

```sql
SELECT a.id, a.name, a.agent_type, a.mode, a.scaffold IS NULL AS sem_andaime,
       (SELECT count(*) FROM autonomia_agent_build_threads t WHERE t.autonomia_agent_id = a.id) AS build_threads,
       md5(a.instruction) AS md5_da_coluna, length(a.instruction) AS tamanho,
       a.config ? 'agente_de_cotacao' AS ja_tem_escolhas,
       (regexp_match(a.instruction, 'Você é `?([^`,\n]+)`?, e atende pela corretora'))[1]            AS nome_agente,
       (regexp_match(a.instruction, 'e atende pela corretora `?([^`\n]+)`?\.'))[1]                   AS nome_corretora,
       COALESCE((regexp_match(a.instruction, '\*\*Dentro do horário de atendimento \(([^)\n]+)\):\*\*'))[1],
                (regexp_match(a.instruction, '\*\*Dentro de `?([^`\n]+)`?:\*\*'))[1])                AS horario,
       (regexp_match(a.instruction, '### 4\.1 O seu comportamento — `?(consultivo|objetivo)`?'))[1] AS comportamento
FROM autonomia_agents a
WHERE a.id = 24 AND a.account_id = 16 AND a.agent_type = 'insurance_quote';
```

Esperado: 1 linha, `mode = 0`, `sem_andaime = t`, `build_threads = 0`, `ja_tem_escolhas = f`,
`nome_agente = Lia`, os outros três preenchidos e `comportamento` em (`consultivo`, `objetivo`).
Qualquer coisa diferente disso — `mode` ≠ 0, andaime presente, uma BuildThread que seja, um NULL —:
PARAR e ler a coluna (e a thread) à mão antes do passo 2 — não chutar. O passo 2 repete `mode = 0` e
`scaffold IS NULL` como precondição (falha fechada); a contagem de threads é só do passo 1, porque uma
thread por si não muda o texto de onde os valores saem — o andaime e o modo mudam.

Passo 2 — a escrita (mesma extração, com as precondições dentro do comando; `RETURNING` mostra o gravado):

```sql
BEGIN;
WITH lidas AS (
  SELECT id,
         (regexp_match(instruction, 'Você é `?([^`,\n]+)`?, e atende pela corretora'))[1]            AS nome_agente,
         (regexp_match(instruction, 'e atende pela corretora `?([^`\n]+)`?\.'))[1]                   AS nome_corretora,
         COALESCE((regexp_match(instruction, '\*\*Dentro do horário de atendimento \(([^)\n]+)\):\*\*'))[1],
                  (regexp_match(instruction, '\*\*Dentro de `?([^`\n]+)`?:\*\*'))[1])                AS horario,
         (regexp_match(instruction, '### 4\.1 O seu comportamento — `?(consultivo|objetivo)`?'))[1] AS comportamento
  FROM autonomia_agents
  WHERE id = 24 AND account_id = 16 AND agent_type = 'insurance_quote'
    AND NOT (config ? 'agente_de_cotacao')
    AND mode = 0 AND scaffold IS NULL
)
UPDATE autonomia_agents a
SET config = COALESCE(a.config, '{}'::jsonb) || jsonb_build_object(
      'agente_de_cotacao', jsonb_build_object(
        'nome_agente', l.nome_agente, 'nome_corretora', l.nome_corretora,
        'horario', l.horario, 'comportamento', l.comportamento)),
    updated_at = now()
FROM lidas l
WHERE a.id = l.id
  AND l.nome_agente IS NOT NULL AND l.nome_corretora IS NOT NULL AND l.horario IS NOT NULL
  AND l.comportamento IN ('consultivo', 'objetivo')
RETURNING a.id, a.config -> 'agente_de_cotacao' AS escolhas;
-- Esperado: UPDATE 1 e as quatro chaves iguais ao passo 1. Qualquer outra coisa: ROLLBACK.
COMMIT;
```

Passo 3 — conferência (só leitura): as quatro preenchidas, o comportamento válido, e cada valor está
de fato no texto de onde saiu.

```sql
SELECT id,
       config -> 'agente_de_cotacao' AS escolhas,
       (SELECT count(*) FROM jsonb_each_text(config -> 'agente_de_cotacao') WHERE value <> '') = 4 AS quatro_preenchidas,
       config -> 'agente_de_cotacao' ->> 'comportamento' IN ('consultivo', 'objetivo')           AS comportamento_valido,
       position((config -> 'agente_de_cotacao' ->> 'nome_agente') IN instruction) > 0             AS nome_no_texto,
       position((config -> 'agente_de_cotacao' ->> 'nome_corretora') IN instruction) > 0          AS corretora_no_texto,
       position((config -> 'agente_de_cotacao' ->> 'horario') IN instruction) > 0                 AS horario_no_texto,
       name = config -> 'agente_de_cotacao' ->> 'nome_agente'                                     AS nome_bate_com_a_tela
FROM autonomia_agents
WHERE id = 24 AND account_id = 16;
```

Esperado: tudo `t` (`nome_bate_com_a_tela` pode ser `f` se alguém renomeou o agente no painel — o
que vale para a instrução é o nome do texto, como o termo 5 pede; anotar). Depois, a prova real: uma
conversa com a Lia em que ela diga o nome e não use crase nem frase do roteiro de 08/09.

Rollback (volta ao comportamento de hoje — a coluna — sem tocar no texto):

```sql
UPDATE autonomia_agents SET config = config - 'agente_de_cotacao', updated_at = now()
WHERE id = 24 AND account_id = 16 AND agent_type = 'insurance_quote';
```

Backup antes do passo 2: `SELECT id, config FROM autonomia_agents WHERE id = 24;` guardado em
`/tmp/chat2you_config_agente24_<ts>.txt` (o `config` inteiro; o rollback acima não precisa dele, mas o
padrão da casa é backup antes de PATCH).

## Rodada de correção (P2 do verificador) — a coluna ainda tinha escritores

**O achado.** A primeira versão desta auditoria dizia que "o agente de cotação não passa" pelo painel
nem pelo construtor conversacional. Estava errado: o hub abre a Lia na mesma tela dos outros agentes
(`InsuranceAgentTab` manda para `autonomia_agents_index`; `PanelTune` não tem trava por tipo) e a API
também não tinha. O admin ligava o modo avançado, escrevia a instrução dele, salvava → 200, o jbuilder
devolvia o texto dele, `instruction_versions` gravava `manual_edit`, o scaffold virava o manual — e o
prompt continuava sendo `principal.md` com as escolhas. Antes de #380 o texto dele valia; depois, a
edição era aceita, exibida e ignorada em silêncio: o cartão mentia. O mesmo valia para o rollback G2
(`Agent#restore_instruction!`), para o refresh de KB (`InstructionRefresher`) e para o "Ajustar com IA"
(BuildThread → `apply_builder_config!`).

**A varredura (classe, não caso).** Quem escreve `autonomia_agents.instruction` depois do nascimento:

| Escritor | Caminho | Antes | Agora |
|---|---|---|---|
| Edição manual pelo hub | `AgentsController#update` com `mode: 'manual'` e/ou `instruction` | 200, gravava, o prompt ignorava | 422 com a mensagem, nada gravado |
| Rollback G2 | `InstructionVersionsController#restore` → `Agent#restore_instruction!` | 200, gravava + snapshot `rollback` | 422, coluna e histórico intactos |
| Refresh de KB | `RefreshInstructionJob` → `InstructionRefresher` → `Agent#refresh_instruction!` | chamava o modelo e gravava | sai antes do modelo (`status=skipped_instrucao_mantida`) |
| "Ajustar com IA" | `BuildThreadsController#create` com `autonomia_agent_id` → `SubmitJob` → `apply_builder_config!` | abria a thread, gastava modelo, gravava instruction/scaffold/config | 422 na porta, thread não nasce |
| Nascimento pela API genérica | `AgentsController#create` com `agent_type: 'insurance_quote'` | nascia uma Lia sem escolhas, lendo uma coluna que ninguém mantém | 422; o agente de cotação nasce só pela aba Cotação |

**O desenho.** A regra tem UM nome no model, `Agent#instrucao_mantida?` (`agent_type == 'insurance_quote'`),
e cada escritor a consulta — nunca o tipo direto:

- `Agent#recusar_se_instrucao_mantida!` levanta `Agent::InstrucaoMantida`; é a primeira linha de
  `apply_builder_config!`, `refresh_instruction!` e `restore_instruction!` (um escritor novo chama isto).
- `validate :instrucao_mantida_fica_guiada`: o agente de instrução mantida nunca entra em modo manual,
  por qualquer caminho de escrita — é o modo manual que expõe a coluna no jbuilder e a aceita na API.
- `Autonomia::BaseController` tem `rescue_from InstrucaoMantida` → 422 `{ error: I18n.t('autonomia.agents.instrucao_mantida') }`.
  Uma resposta para a regra, onde quer que ela levante (model ou porta).
- `AgentsController#update` recusa ANTES de qualquer assign quando o request traz `instruction` ou um
  `mode` que não seja `guided`. O `mode: 'guided'` que o PanelTune carimba em TODO save passa — senão
  salvar saudação/tom/handoff da Lia quebraria (spec «still accepts the ordinary PanelTune save»).
- `AgentsController#create` recusa `agent_type: 'insurance_quote'`; `BuildThreadsController#thread_params`
  recusa abrir thread para o agente; `InstructionRefresher` sai com telemetria própria antes do modelo.

A mensagem (pt_BR/en, `autonomia.agents.instrucao_mantida`) diz o que é verdade hoje: a instrução é mantida
pela Autonom.ia e nome/horário/comportamento foram escolhidos na aba Cotação ao criar o agente. NÃO diz
"mudam pela aba Cotação", porque não existe endpoint para mudar as escolhas depois da criação
(`Insurance::QuoteAgentController` só tem `show` e `create`) — isso fica como pendência de produto.

**O que NÃO mudou.** O front (PanelTune) continua mostrando o modo avançado para a Lia; a API é que
recusa, com a mensagem que o painel já exibe no `catch` do save. Esconder o toggle por tipo é trabalho
de front, fora desta PR. `record_instruction_version!` (o snapshot) continua permitido: é auditoria, não
escrita da coluna.

### Mutações da rodada 2 (`~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada2.rb`, 11/09/2026)

Alvo: `agent_spec` (model), `instruction_versions_spec`, `builder_thread_spec`,
`external_agent_lifecycle_spec`, `instruction_refresher_spec`. Cada uma: edita, roda, restaura, confere o md5.

| Mutação | Reprova? | Exemplos que caem |
|---|---|---|
| M9 `update` sem `rejeitar_edicao_da_instrucao_mantida` | sim | «refuses the advanced-mode edit with a clear message», «refuses an instruction sent without switching mode» |
| M10 `create` genérico aceita `insurance_quote` | sim | «refuses to create a quote agent through the generic agents API» |
| M11 model aceita modo manual | sim | «não aceita o modo manual» |
| M12 `refresh_instruction!` sem guarda | sim | «não é reescrita pelo refresh de conhecimento» |
| M13 `restore_instruction!` sem guarda | sim | «não volta por rollback», «refuses to roll back the quote agent instruction» |
| M14 `apply_builder_config!` sem guarda | sim | «não recebe a config do Construtor conversacional» |
| M15 refresher chama o modelo para o agente de cotação | sim | «keeps the column intact and never calls the LLM» |
| M16 porta do BuildThread aberta | sim | «refuses to open a builder thread for the quote agent» |
| M17 `instrucao_mantida?` sempre falso | sim | 11 (todos os exemplos da rodada) |
| M18 `recusar_se_instrucao_mantida!` vazia | sim | 4 (refresh, rollback no model e na API, Construtor) |

As oito da rodada 1 (M1–M8) foram rodadas de novo depois da correção: 8/8 reprovam. `verde depois de
restaurar: true` nas duas rodadas.

### Comandos da rodada 2

- Specs novas antes da implementação: 44 exemplos, 11 falhas (RED: 10 reproduzem o achado — 200 aceito,
  thread criada, LLM chamado — e 1 é o método ausente).
- Alvo depois: `bundle exec rspec spec/models/autonomia/agents/agent_spec.rb spec/requests/api/v1/accounts/autonomia/agents/instruction_versions_spec.rb spec/requests/api/v1/accounts/autonomia/journeys/builder_thread_spec.rb spec/requests/api/v1/accounts/autonomia/journeys/external_agent_lifecycle_spec.rb spec/services/autonomia/agents/knowledge/instruction_refresher_spec.rb spec/services/autonomia/insurance/quote_agent spec/requests/api/v1/accounts/autonomia/insurance/quote_agent_spec.rb spec/services/autonomia/agents/prompt_builder_spec.rb spec/requests/api/v1/accounts/autonomia/agent_config_exposure_spec.rb spec/models/autonomia --format json` → 209 exemplos, 0 falhas, 0 erros fora, exit 0.
- Ampla, com o diretório inteiro de requests da área (o `rescue_from` novo é do BaseController de toda
  ela): `bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia spec/requests/api/v1/accounts/autonomia --format json` → 1.038 exemplos, 0 falhas, 3 pendentes pré-existentes, 0 erros fora, exit 0.
- `bundle exec rubocop` nos dez arquivos Ruby tocados → 0 ofensas (a guarda repetida em três escritores
  estourou ABC/ciclomática de `apply_builder_config!`; virou `recusar_se_instrucao_mantida!`, um método só).
- `ruby ~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada2.rb` → 10/10; `mutacoes_i380.rb` → 8/8.

## Rodada 3 (achados do verificador cego sobre 02d785a9a1)

Sete achados; nenhum deferido. Cada um: o achado → o que mudou → a guarda → a mutação que a prova.

### P2 — a chave nova morria no `en.yml` (dois blocos `autonomia:`)

**Achado.** `config/locales/en.yml` tinha DOIS blocos top-level `autonomia:` (L446 e L730). O YAML não
avisa: a última chave vence e a primeira some inteira. O segundo bloco entrou em 05ad7fe9d7 (03/09, #300)
com `insurance.errors.encryption_unavailable`, e desde então `en.autonomia.build_thread.*`, `faq.*`,
`source.*`, `image_*` respondiam "Translation missing" em inglês — e a chave nova de #380,
`agents.instrucao_mantida`, foi posta no bloco morto. As cinco request specs que "provavam" a mensagem
faziam `eq(I18n.t(...))`: os dois lados viravam o marcador e passavam vazias.

**Correção (causa raiz).** Um bloco só: `insurance:` mudou para dentro do primeiro `autonomia:`; o segundo
foi apagado. As chaves mortas desde 03/09 voltam a resolver em inglês — é o mesmo defeito, entra aqui.

**Guarda.** `spec/config/locales_sem_chave_duplicada_spec.rb`: percorre os NÓS de cada YAML de
`config/locales` (`Psych.parse_stream`; o hash carregado já perdeu a duplicata) e reprova chave repetida no
mesmo nível — um exemplo por arquivo (116). O detector é provado contra uma amostra com duplicata (para ele
mesmo não ficar cego), e um exemplo confere que as chaves de `autonomia` resolvem com `raise: true` em en
e pt_BR. Nas request specs, a mensagem agora vem de `I18n.t(..., raise: true)`: a chave sumindo derruba.

### P2 — o tipo era editável pelo mesmo PATCH que a guarda protegia

**Achado.** `instrucao_mantida?` é o tipo, e `agent_type` estava em `agent_params`. Dois requests de
admin desmontavam a regra: `PATCH {agent_type:'custom'}` → 200, a Lia deixa de ser mantida, o prompt volta
à coluna velha; depois `PATCH {mode:'manual', instruction:'minha'}` → 200. Efeitos colaterais do mesmo
flip: o especialista volta ao manual gravado (`Builder.mantido` olha o tipo), `QuoteAgentController#show`
deixa de achar a Lia, `JaExiste` deixa nascer um segundo agente de cotação.

**Correção.** No MODEL (`validate :tipo_do_agente_de_cotacao_e_fixo`): agente persistido não entra nem sai
de `insurance_quote` — por PATCH, Construtor ou `update!` de qualquer caminho. O nascimento fica livre (é
o Builder quem cria; a API genérica já recusava na porta). E na PORTA (`rejeitar_edicao_da_instrucao_mantida`):
`agent_type` diferente no PATCH da Lia levanta `InstrucaoMantida` (a resposta é a mesma mensagem, não
`RecordInvalid`); e um agente comum pedindo `insurance_quote` também é recusado.

**Guarda.** `agent_spec` «o tipo do agente de cotação é fixo» (3 exemplos); `external_agent_lifecycle_spec`
«refuses to change the quote agent type, and the second request of the bypass fails too» (a sonda inteira:
os dois PATCHes, coluna intacta, prompt segue o arquivo) e «refuses to turn an ordinary agent into the
quote agent».

### P3 — `messages`/`retry` de uma thread já vinculada gastavam modelo

**Achado.** A guarda do Construtor só existia em `thread_params` (`create`). Uma thread vinculada à Lia
ANTES do deploy seguia aceitando `POST .../messages` e `POST .../retry` (202, job enfileirado); o modelo
rodava e só `apply_builder_config!` levantava → `build_error` genérico, sem a mensagem.

**Correção.** `fetch_thread` (usado por `show`, `messages`, `retry_build`) levanta `InstrucaoMantida`
quando `@thread.agent&.instrucao_mantida?`. Mesma resposta 422, antes de gastar modelo.

**Guarda.** `builder_thread_spec` «a builder thread already bound to the quote agent»: `messages` em
thread `ready` e `retry` em thread `failed` → 422, `not_to have_enqueued_job(SubmitJob)`, thread intacta.

### P3 — o ramo `mode` da guarda da porta não tinha spec

**Correção.** Nenhuma no código. **Guarda.** `external_agent_lifecycle_spec` «refuses switching the quote
agent to manual mode even without an instruction»: `PATCH {mode:'manual'}` sozinho → 422 com `error` = a
mensagem (sem o ramo, o model ainda recusaria, mas via `RecordInvalid`, corpo `message`), modo segue guided.

### P3 — "lido a cada montagem" era afirmação sem prova

**Achado.** A spec dublava o próprio `texto_do_principal`, então um `||=` na leitura passava.

**Correção.** Nenhuma no código (a leitura já não memoizava). **Guarda.** A spec «lê o arquivo de novo a
cada montagem» agora dubla a LEITURA DO ARQUIVO (`File.read` com o caminho de `principal.md` —
`Pathname#read` passa por ali com a string do caminho) devolvendo dois textos em chamadas sucessivas, e
mede duas montagens do MESMO agente: cada uma tem de refletir a sua leitura.

### P3 — rollout: passo 1 sem `scaffold`/`mode`/BuildThreads

**Correção.** Passo 1 mostra `mode`, `scaffold IS NULL AS sem_andaime` e a contagem de
`autonomia_agent_build_threads` do agente 24; qualquer coisa diferente de 0/t/0 → parar e ler à mão. Passo 2
repete `mode = 0 AND scaffold IS NULL` como precondição (falha fechada). Não executado.

### P3 — `EscolhasIncompletas` emudecia a Lia só com `warn` no log

**Achado.** Chave `agente_de_cotacao` presente e incompleta (só por escrita fora do Builder) → `Answerer`
levanta `Builder::EscolhasIncompletas` na montagem do prompt → `Responder#perform` resgatava no
`rescue StandardError`: turno mudo para TODO cliente, e a causa só num `warn`.

**Correção.** Resgate específico ANTES do largo: registra `skipped_escolhas_incompletas` no EventLogger
(tipo novo em `AgentEvent`, motivo `escolhas_incompletas` na allowlist — NÃO entra em `HANDOFF_TYPES`: a
conversa não é passada a humanos), uma vez por conversa, com `warn` que nomeia o campo (a mensagem do erro
é só o nome do campo, nunca um valor); depois segue pelo MESMO caminho de falha de sempre
(`falha_no_turno`: warn + descarte do assíncrono + silêncio). Nada novo é engolido.

**Guarda.** `responder_escolhas_incompletas_spec` (Answerer real, credencial dublada, cliente de IA nunca
chamado): evento com conversa/agente/motivo; uma vez por conversa; outra conversa ganha o seu; não conta
como handoff.

### Mutações da rodada 3 (`~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada3.rb`, 11/09/2026)

Alvo: `locales_sem_chave_duplicada_spec`, `agent_spec`, `instruction_versions_spec`, `builder_thread_spec`,
`external_agent_lifecycle_spec`, `builder_instrucao_do_principal_spec`, `responder_escolhas_incompletas_spec`.
Cada uma: edita, roda, restaura, confere o md5. 11/11 reprovam; `verde depois de restaurar: true`.

| Mutação | Reprova? | Exemplos que caem |
|---|---|---|
| VF chave `instrucao_mantida` renomeada no `en.yml` | sim | 11: os dez exemplos de request que exibem a mensagem (`raise: true`) + «as chaves de autonomia resolvem» |
| VI segundo bloco top-level `autonomia:` de volta no `en.yml` | sim | 12: «config/locales/en.yml não tem chave duplicada», «as chaves de autonomia resolvem» + os dez da mensagem |
| VG model: `tipo_do_agente_de_cotacao_e_fixo` apagada | sim | «o agente de cotação não vira outro tipo», «um agente comum não vira o agente de cotação» |
| VG2 porta: `troca_o_tipo?` sempre falso | sim | «refuses to change the quote agent type, and the second request of the bypass fails too» (o model ainda recusa, mas via `RecordInvalid`, corpo `message`) |
| VG3 porta: `pede_o_tipo_mantido?` sempre falso | sim | «refuses to turn an ordinary agent into the quote agent» |
| VC porta: ramo `mode` apagado | sim | «refuses switching the quote agent to manual mode even without an instruction» |
| VH `fetch_thread` sem guarda | sim | «refuses a new message before spending the model», «refuses the retry of a failed build before spending the model» |
| VD `texto_do_principal` com `||=` | sim | «lê o arquivo de novo a cada montagem, com as escolhas guardadas» |
| VE Responder sem o resgate específico | sim | 3: «records skipped_escolhas_incompletas with the field name», «once per conversation», «in another conversation» |
| VE2 sem o «uma vez por conversa» | sim | «records the event once per conversation, not once per message» |
| VJ `escolhas_incompletas` fora de `ALLOWED_REASONS` | sim | «records skipped_escolhas_incompletas with the field name» (motivo colapsa em `other`) |

### Comandos da rodada 3

- Banco próprio: `POSTGRES_DATABASE=chatwoot_test_i380r3` (`db:create db:schema:load`).
- RED antes da implementação: 183 exemplos, 10 falhas (8 reproduzem os achados — 200 aceito no flip de
  tipo, job enfileirado em `messages`/`retry`, tipo livre no model, evento inexistente —; 2 eram defeitos
  das specs novas: `Pathname#read` chama `File.read` com a STRING do caminho, e `ResponsesClient.new` é
  avaliado antes dos argumentos onde o erro nasce — corrigidas para dublar o que é real).
- Alvo depois: as sete specs acima + `responder_spec`, `responder_async_spec`, `event_logger_spec`,
  `analytics_spec`, `insurance/quote_agent_spec`, `services/autonomia/insurance/quote_agent` →
  285 exemplos, 0 falhas, 0 erros fora, exit 0.
- `bundle exec rubocop` nos 13 arquivos tocados → 0 ofensas.
- `ruby ~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada3.rb` → 11/11.
- Suíte ampla (`spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia` + a spec de locales) → 1.169 exemplos, 0 falhas, 3 pendentes
  pré-existentes, 0 erros fora, exit 0.
- As mutações das rodadas 1 e 2 rodadas DE NOVO sobre o código desta rodada (`mutacoes_i380_r3.rb`,
  `mutacoes_i380_rodada2_r3.rb`: os mesmos scripts, banco por env): 8/8 e 10/10 seguem reprovando; M9
  (porta sem a guarda) agora derruba 5 exemplos e M17 (predicado apagado) 16. `verde depois de restaurar:
  true` nas duas.

## Rodada 4 (três P3 do verificador cego sobre dcc2cc769a)

Veredito anterior: APROVADO. Os três achados são da mesma classe — a recusa por `EscolhasIncompletas`
estava certa no Responder, mas as bordas ao redor dela (a guarda da chave vazia, o número da aba
Desempenho, os outros chamadores do `Answerer`) não tinham spec ou não tinham a mesma recusa explícita.

### P3 — `builder.rb`: a chave presente e VAZIA não tinha spec

**Achado.** `instrucao_do_principal` faz `return nil if escolhas.nil?`. Com a chave `agente_de_cotacao`
presente e vazia (`{}`, `false`, escrita fora do Builder) o código já levantava `EscolhasIncompletas`
(`escolha` recebe algo que não tem `nome_agente`), mas nenhum exemplo cobria essa borda: a mutação
`.nil?` → `.blank?` passava 38/38, e com ela o agente voltaria em silêncio à coluna de nascimento — o
texto velho, com crases — em vez de parar com o nome do campo (o default calado que o termo 6 proíbe).

**Correção.** Nenhuma no código (a guarda já era `nil?`); comentário no método dizendo POR QUE é `nil?`
e não `blank?`. A guarda que faltava era a spec.

**Guarda.** `builder_instrucao_do_principal_spec` «chave presente e vazia também para, em vez de voltar à
coluna em silêncio» (`chave => {}`, coluna envelhecida de propósito → `EscolhasIncompletas('nome_agente')`)
e «chave presente com um valor que não é hash (false) também para». Mutação R4A (`.nil?` → `.blank?`)
derruba os dois.

### P3 — `analytics.rb`: a Lia MUDA contava como "conversa atendida"

**Achado.** `conversations_handled` e `handled_ids` (o universo de `outcome_scope('handled')`) contavam
qualquer evento com `conversation_id`; o tipo novo `skipped_escolhas_incompletas` entrava. A aba
Desempenho mostrava "Conversas atendidas: N" para conversas em que a Lia não respondeu nem passou a
humanos, e a lista do clique as abria. O número mentia para o corretor.

**Correção.** Em `AgentEvent`: `NAO_ATENDIMENTO_TYPES = %w[skipped_escolhas_incompletas]` e
`scope :atendimentos` (`where.not(event_type: NAO_ATENDIMENTO_TYPES)`) — o universo de "atendidas" tem
UM nome, ao lado de `handoffs`. `Analytics` passa por ele nos DOIS sítios de "atendidas":
`conversations_handled` e `handled_ids` (cartão e lista do clique contam as mesmas conversas). Nesta
rodada o scope foi aplicado também a `all_time_handled_ids` (o universo sem janela que liga reports e
handoffs do core à conversa do agente) sem spec que decidisse o comportamento — a rodada 5 desfez essa
escolha extra (ver abaixo): um report sobre mensagem que o bot de fato postou é um report real. Timeline,
`handoff_count` e `top_handoff_reasons` já não somavam o tipo (só `replied`/`handoffs`).

**Guarda.** `analytics_spec` «does not count a conversation where the agent stayed silent for incomplete
choices as handled»: o evento sozinho (com um `conversation_resolved` do core, para provar que ele também
não vira "resolvida sem humano") → `conversations_handled` 0, `outcomes` todos 0, `outcome_scope('handled')`
vazio, timeline zerada; e «counts the conversation once when the agent stayed silent and later replied in
it» (a conversa que depois foi atendida conta uma vez). Mutações R4B (cartão sem o scope), R4B2 (lista
sem o scope) e R4B3 (scope sem o `where.not`) derrubam o primeiro exemplo.

### P3 — `playground_controller.rb`: Testar e Copilot respondiam 500

**Achado.** `PlaygroundController` → `Answerer` → `PromptBuilder#instructions` → `Agent#instrucao_do_sistema`
é o mesmo caminho do Responder; com a chave incompleta, `EscolhasIncompletas` subia até o Rails: 500
genérico, sem o nome do campo e sem registro além do erro. O Responder ganhou o tratamento na rodada 3; o
outro chamador (e o Copilot, `suggest`, que passa pelo mesmo `Answerer`) não.

**Correção.** `Autonomia::BaseController` ganha `rescue_from Builder::EscolhasIncompletas` ao lado do de
`InstrucaoMantida` — uma resposta para a regra em toda a API de agentes: 422 com
`{ error: <mensagem pt_BR/en>, code: 'escolhas_incompletas', campo: <nome do campo> }` e `warn` com o
campo (a mensagem do erro é só o nome do campo, `Builder.escolha`, nunca um valor). Chave nova
`autonomia.agents.escolhas_incompletas` em `en.yml` e `pt_BR.yml`, com `%{campo}`; a spec de locales passa
a exigi-la nos dois. Detalhe de implementação: o handler usa `current_account` (ivar memoizado), não
`Current.account` — o `ensure` de `handle_with_exception` (around_action do core) já fez `Current.reset`
quando o `rescue_from` roda.

**Guarda.** `playground_escolhas_incompletas_spec` (Answerer real, credencial dublada): `test` e `suggest`
→ 422 com `code`/`campo`/mensagem resolvida, cliente de IA nunca chamado, `warn` com o campo; a resposta
nunca ecoa o valor de outra escolha; com as quatro escolhas a porta não recusa e o modelo é chamado.
Mutação R4C (rescue apagado) derruba os dois de 422 e o «never echoes».

### Mutações da rodada 4 (`~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada4.rb`, 11/09/2026)

Alvo: `builder_instrucao_do_principal_spec`, `analytics_spec`, `playground_escolhas_incompletas_spec`,
`responder_escolhas_incompletas_spec`. Cada uma: edita, roda, restaura, confere o md5. 5/5 reprovam;
`verde depois de restaurar: true`.

| Mutação | Reprova? | Exemplos que caem |
|---|---|---|
| R4A builder `.nil?` → `.blank?` | sim | 2: «chave presente e vazia também para», «chave presente com um valor que não é hash (false)» |
| R4B `conversations_handled` sem `atendimentos` | sim | 1: «does not count a conversation where the agent stayed silent…» |
| R4B2 `handled_ids` sem `atendimentos` | sim | 1: o mesmo (via `outcomes.handled` e `outcome_scope('handled')`) |
| R4B3 scope `atendimentos` = `all` | sim | 1: o mesmo |
| R4C `rescue_from EscolhasIncompletas` apagado | sim | 3: «answers 422 … on test», «… on suggest», «never echoes another choice in the body» |

### Comandos da rodada 4

- Banco próprio: `POSTGRES_DATABASE=chatwoot_test_i380r4` (`db:create db:schema:load`).
- RED: a primeira versão do handler lia `Current.account` e respondia 500 (`NoMethodError` sobre nil,
  causa `EscolhasIncompletas`) nos quatro exemplos do Playground — foi assim que apareceu o `Current.reset`
  do around_action; o RED "sem o rescue" é a mutação R4C. Os dois exemplos do Builder passam desde o
  primeiro run — a guarda já existia; a prova de que valem é a mutação R4A. A spec de analytics caiu no
  primeiro run só na mutação R4B (o código já vinha corrigido junto).
- `bundle exec rubocop` nos 8 arquivos tocados → 0 ofensas (depois de um `RSpec/IncludeExamples`).
- Alvo: as quatro specs acima + `locales_sem_chave_duplicada_spec`, `analytics_spec` (request),
  `spec/models/autonomia`, `event_logger_spec` → 247 exemplos, 0 falhas, 0 erros fora, exit 0.
- `ruby ~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada4.rb` → 5/5.
- Suíte ampla (`spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia` + a spec de locales) → 1.177 exemplos, 0 falhas, 3 pendentes
  pré-existentes (`RegistrationCheckout::Provisioner`, `Sso::Provisioner`), 0 erros fora, exit 0.

## Rodada 5 (um P3 do verificador cego sobre 3603d3e811 — última passada)

Veredito anterior: APROVADO. O achado é da classe «regra sem guarda»: dos três sítios que a rodada 4
passou por `atendimentos`, só dois tinham mutação; o terceiro era observável e nenhuma spec decidia o que
ele devia fazer.

### P3 — `analytics.rb`: `all_time_handled_ids` apagava um report real em silêncio

**Achado.** `all_time_handled_ids` é o universo sem janela que liga `Captain::MessageReport` (respostas
marcadas como erradas) à conversa do agente. Com `.atendimentos` ali, uma conversa cujo ÚNICO evento é
`skipped_escolhas_incompletas` saía do universo — mas o bot pode ter postado nela: a entrega assíncrona
num turno mudo (`silence_with_async` despacha a cotação; o `AsyncRunJob` posta como o espelho) não grava
`replied` (só o Responder chama `EventLogger.replied`). Um atendente reportando essa mensagem via
`Captain::MessageReport` era um report real sobre uma mensagem real, e `outcomes[:wrong_replies]` caía
de 1 para 0 sem nenhuma spec reprovar: a mutação «remover `.atendimentos` só de `all_time_handled_ids`»
passava 49/49. A auditoria dizia que os três sítios eram «o mesmo universo», mas só dois tinham guarda.

**Decisão (orquestrador, opção a).** `all_time_handled_ids` volta ao que era em dcc2cc769a (sem
`.atendimentos`). O universo de "atendidas" (cartão e lista do clique) segue excluindo a conversa muda; o
universo de "o bot tocou esta conversa" (reports e handoffs do core) não exclui, porque o bot pode ter
postado sem `replied`.

**Correção.** `analytics.rb`: `.atendimentos` removido de `all_time_handled_ids`, com o porquê no
comentário (a entrega assíncrona no turno mudo posta sem `replied`; filtrar ali apagaria o report); o
comentário de `handled_conversations` passa a dizer que SÓ os dois sítios de "atendidas" filtram.
`agent_event.rb` não muda: o scope continua tendo um nome e dois chamadores.

**Guarda.** `analytics_spec` «counts a report on a mirror message as a wrong reply even when the agent
only stayed silent there»: evento `skipped_escolhas_incompletas` sozinho + mensagem outgoing do
AgentBot-espelho na mesma conversa + `Captain::MessageReport` → `outcomes` inclui `handled: 0,
wrong_replies: 1`, `outcome_scope('wrong_replies')` é exatamente a conversa, `conversations_handled` 0 e
`outcome_scope('handled')` vazio (os dois sítios de "atendidas" seguem excluindo). Mutação R5A (pôr
`.atendimentos` de volta em `all_time_handled_ids`, o código da rodada 4) derruba o exemplo com
`wrong_replies => 0`.

### Mutações da rodada 5 (`~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada5.rb`, 11/09/2026)

Alvo: `analytics_spec` (service) e `analytics_spec` (request). Cada uma: edita, roda, restaura, confere o
md5. 4/4 reprovam; `verde depois de restaurar: true`. As três da rodada 4 sobre analytics rodam de novo
para provar que os dois sítios de "atendidas" seguem guardados depois da mudança.

| Mutação | Reprova? | Exemplos que caem |
|---|---|---|
| R5A `all_time_handled_ids` COM `atendimentos` (código da rodada 4) | sim | 1: «counts a report on a mirror message as a wrong reply even when the agent only stayed silent there» (`wrong_replies => 0`) |
| R4B `conversations_handled` sem `atendimentos` | sim | 2: «does not count a conversation where the agent stayed silent…», «counts a report on a mirror message…» (`handled` 1) |
| R4B2 `handled_ids` sem `atendimentos` | sim | 2: os mesmos |
| R4B3 scope `atendimentos` = `all` | sim | 2: os mesmos |

### Comandos da rodada 5

- Banco próprio: `POSTGRES_DATABASE=chatwoot_test_i380r5` (`db:create db:schema:load`).
- RED: é a mutação R5A — o exemplo novo contra o código da rodada 4 cai com `wrong_replies => 0`.
- `bundle exec rubocop` nos 2 arquivos tocados → 0 ofensas.
- Alvo: `analytics_spec` (service) → 8 exemplos, 0 falhas, 0 erros fora, exit 0; com a request spec no
  script de mutação → 14 exemplos.
- `ruby ~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada5.rb` → 4/4.
- Suíte ampla (`spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia` + a spec de locales) → 1.178 exemplos, 0 falhas, 3 pendentes
  pré-existentes (`RegistrationCheckout::Provisioner`, `Sso::Provisioner`), 0 erros fora, exit 0.

## Rodada 6 (dois P2 do Codex sobre 573a344b8e)

Veredito anterior: APROVADO. Os dois achados são da mesma classe: a substituição e a guarda da chave
tratavam a FORMA NORMAL das escolhas (quatro valores sem `$`; chave ausente ou hash) e deixavam passar as
bordas — um valor de escolha que carrega um marcador, e a chave presente com `null`.

### P2 — `substituir` relia o valor inserido (uma passada por marcador)

**Achado.** `substituir` era um `reduce` sobre `VARIAVEIS`: um `gsub` por marcador, cada um sobre o texto
que o anterior devolveu. Um valor de escolha que contivesse OUTRO marcador era relido pela passada seguinte
— `nome_corretora: '$horarioAtendimento'` fazia a corretora virar o horário. E um valor com o PRÓPRIO
marcador, ou com um já passado, chegava ao modelo literal: `nome_corretora: '$nomeAgente'` → «atende pela
corretora $nomeAgente» (termo 6 violado). No runtime só escrita fora do Builder produz esse estado; mas a
criação também aceitava — `POST` com `broker_name: '$nomeAgente'` nascia e gravava.

**Decisão (orquestrador).** (a) substituição em UMA passada — uma regex de união dos marcadores, o bloco
consulta a escolha, o valor inserido nunca é relido; (b) escolha que CONTENHA marcador reservado é recusada:
no runtime com `EscolhasIncompletas` (nome do campo); na criação com a classe de erro já coerente.

**Correção.**

- `builder.rb`: `MARCADOR = /(?:#{Regexp.union(VARIAVEIS.keys).source})\b/` — os quatro marcadores numa
  regex só, derivada de `VARIAVEIS` (uma lista, não duas); a fronteira de palavra fecha o nome
  (`$nomeAgente,` casa; `$nomeAgentes` não é marcador). `substituir` é
  `texto.gsub(MARCADOR) { |m| escolhas.fetch(VARIAVEIS.fetch(m)).to_s }`: uma passada, e `fetch` em vez
  de `[]` para uma chave ausente falhar alto em vez de virar `''`.
- `conferir_escolhas!(escolhas)` substitui o `escolha` por campo: as quatro presentes, nenhuma em branco,
  nenhuma com `MARCADOR` dentro → `EscolhasIncompletas(campo)`; devolve as escolhas quando passam. Só o
  nome do campo na mensagem (o Responder e o `BaseController` já a mandam para o log e para a API).
- `validar_escolhas!` (era `validar_nomes!`): além de vazio/longo, `NomeInvalido «<campo> contém um
  marcador reservado»` para o nome do agente e o da corretora, e `HorarioInvalido` para o horário.
  `comportamento` é um de dois valores fixos (`COMPORTAMENTOS`), conferido em `call` antes — não pode
  carregar marcador. **Escolha registrada:** `HorarioInvalido` é classe NOVA, ao lado de `NomeInvalido` e
  `ComportamentoInvalido`, em vez de uma `EscolhaInvalida` genérica — a porta responde por classe
  (`error: e.class.name.demodulize.underscore`) e a tela traduz por código; um código por campo mantém o
  contrato que já existia. A mensagem nomeia o campo e o motivo, nunca o valor digitado.
- Porta (`Insurance::QuoteAgentController#create`): `HorarioInvalido` entra no mesmo `rescue` → 422
  `{ error: 'horario_invalido', detail: <motivo> }`. Sem a recusa na criação, o `EscolhasIncompletas`
  nasceria em `texto(ARQUIVO_DO_PRINCIPAL)` dentro da transação, e este controller não herda o
  `rescue_from` da área de agentes: 500 sem o nome do campo.
- Tela (`InsuranceAgentTab.vue` + `en/insurance.json`): `horario_invalido` → `ERRORS.HORARIO_INVALIDO`
  («Confira o horário de atendimento: escreva só os dias e as horas, sem marcador de variável»). Sem a
  linha, o código novo caía em `GENERIC` — «tente de novo em instantes» para um erro que tentar de novo
  não resolve.
- Comentários que apontavam para `Builder.escolha` (`responder.rb`, `base_controller.rb`) passam a apontar
  para `conferir_escolhas!`.

**Guarda.** `builder_instrucao_do_principal_spec`: «escolha com um marcador dentro para com o nome do
campo, em vez de virar a outra escolha», «escolha com o próprio marcador dentro para, em vez de mandar o
marcador ao modelo», «horário com marcador dentro também para» (runtime, via `instrucao_do_sistema`); e o
describe «a substituição é numa passada só»: «o valor inserido nunca é relido» mede `substituir` DIRETO,
com um valor que a conferência recusaria — a regra da passada única é independente da recusa, são duas
guardas —, e «um marcador só casa inteiro». `builder_spec` «o que a corretora escreve»: recusa nos três
campos de texto livre, mensagem sem o valor, nada gravado. `quote_agent_spec` (request): 422
`nome_invalido` / `horario_invalido`, `detail` com o campo, `body` sem o valor, `Agent.count` 0.
`InsuranceAgentTab.spec.js`: «mostra a mensagem do produto quando o backend recusa o horario» (não cai em
`GENERIC`, não ecoa o `detail`).

### P2 — a chave presente com `null` voltava à coluna em silêncio

**Achado.** `instrucao_do_principal` fazia `escolhas = config[chave]; return nil if escolhas.nil?`. O jsonb
guarda `{"agente_de_cotacao": null}` COM a chave; o `nil?` não distingue «chave ausente» de «chave presente
com null» e devolvia `nil` — `Agent#instrucao_do_sistema` caía na coluna de nascimento em silêncio (o texto
velho, com crases): o default calado que o termo 6 proíbe. A rodada 4 tinha fechado `{}` e `false`; `null`
passava.

**Correção.** `config = agent.config.to_h; return nil unless config.key?(ESCOLHAS_DA_CORRETORA)`: só a chave
AUSENTE é o agente de antes de #380. Chave presente com qualquer valor (`null`, `{}`, `false`, hash
incompleto) passa por `conferir_escolhas!` e para com `EscolhasIncompletas('nome_agente')`.

**Guarda.** «chave presente com null também para, em vez de voltar à coluna em silêncio» — confere
`have_key(chave)` depois do `reload` (o jsonb guardou o `null` com a chave) e o erro com o primeiro campo.

O rollout SQL do agente 24 (seção «Rollout») NÃO muda: as escolhas reais (Lia / Sena Negócios / «de segunda
à sexta, de 09h as 18h» / consultivo) não contêm marcador, e o passo 2 grava as quatro preenchidas.

### Mutações da rodada 6 (`~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada6.rb`, 11/09/2026)

Alvo: `builder_instrucao_do_principal_spec`, `builder_spec`, `insurance/quote_agent_spec` (request). Cada
uma: edita, roda, restaura, confere o md5. 8/8 reprovam; `verde depois de restaurar: true`.

| Mutação | Reprova? | Exemplos que caem |
|---|---|---|
| R6A `substituir` volta ao `reduce` (uma passada por marcador) | sim | 2: «o valor inserido nunca é relido», «um marcador só casa inteiro» |
| R6A2 `MARCADOR` sem `\b` | sim | 1: «um marcador só casa inteiro: `$nomeAgentes` não é `$nomeAgente`» |
| R6B runtime sem a recusa de marcador (`conferir_escolhas!` só confere branco) | sim | 3: os três de «marcador dentro» via `instrucao_do_sistema` |
| R6C criação sem a recusa de marcador nos nomes | sim | 3: «recusa nome de corretora…», «recusa nome de agente…», request «recusa nome com marcador…» |
| R6D criação sem a recusa de marcador no horário | sim | 2: «recusa horário com marcador reservado», request «recusa horario com marcador…» |
| R6E `key?` volta a `nil?` | sim | 1: «chave presente com null também para» |
| R6E2 `key?` vira `present?` | sim | 3: «…null…», «chave presente e vazia…», «…não é hash (false)…» |
| R6F porta sem `HorarioInvalido` no `rescue` | sim | 1: request «recusa horario com marcador reservado» (500 em vez de 422) |

Front (mutação manual, `mutacao_front_r6.rb` no scratchpad da sessão): apagar a linha
`if (code === 'horario_invalido') return 'HORARIO_INVALIDO'` do `InsuranceAgentTab.vue` derruba «mostra a
mensagem do produto quando o backend recusa o horario» (cai em `GENERIC`); restaurado, md5 conferido.

### Comandos da rodada 6

- Estado herdado: a tentativa anterior desta rodada caiu no meio (limite de cota) e deixou edições não
  commitadas em 6 arquivos (`builder.rb`, `responder.rb`, `quote_agent_controller.rb` e três specs). Foram
  lidas linha a linha contra as decisões e aproveitadas — batiam com (a) e (b) e com o `key?`. O que
  faltava entrou por cima: comentário do `BaseController`, código e tradução na tela, spec do front, o
  script de mutação e esta seção.
- Banco: `POSTGRES_DATABASE=chatwoot_test_i380r5` (o da rodada 5).
- `bundle exec rubocop` nos 7 arquivos Ruby tocados → 0 ofensas.
- Alvo: `builder_instrucao_do_principal_spec`, `builder_spec`, `insurance/quote_agent_spec`,
  `responder_escolhas_incompletas_spec`, `external_agent_lifecycle_spec`, `agent_spec` → 101 exemplos,
  0 falhas, 0 erros fora, exit 0.
- `ruby ~/ops/agente-cotacao/issue-380/mutacoes_i380_rodada6.rb` → 8/8.
- Front: `vitest` em `InsuranceAgentTab.spec.js` → 10/10. O `node_modules` deste worktree é symlink para
  outro worktree e o Vite recusa arquivo cuja realpath fica fora da raiz («Failed to load url …
  fake-indexeddb/auto/index.mjs. Does the file exist?» — o arquivo existe); rodado com uma config local
  temporária que só acrescenta `server.fs.allow` à `vitest.config.ts`, movida para fora do worktree depois,
  não commitada. `eslint` nos dois arquivos → 0 erros (os avisos `@intlify/vue-i18n/*` são pré-existentes,
  no arquivo inteiro); `prettier --check` OK.
- Suíte ampla (`spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia` + a spec de locales) → 1.189 exemplos, 0 falhas, 3 pendentes
  pré-existentes (`RegistrationCheckout::Provisioner`, `Sso::Provisioner`), 0 erros fora, exit 0.

## Fora desta PR (da mesma classe ou vizinhos)

- **Lacuna do `EventLogger` (registrada na rodada 5, não corrigida aqui):** a entrega assíncrona num
  turno mudo (`silence_with_async` → `AsyncRunJob` → `deliveries`) posta mensagens como o AgentBot-espelho
  SEM gravar `replied` — os únicos chamadores de `EventLogger.replied` são `responder.rb` (215/244). Para
  a aba Desempenho, essa conversa não conta como atendida nem como resposta enviada, embora o bot tenha
  postado; a rodada 5 só garante que um report sobre essa mensagem não some. O conserto (o job gravar o
  evento de resposta ao entregar) é de outra PR.

- Não existe endpoint para a corretora MUDAR nome/horário/comportamento depois de criar o agente
  (`Insurance::QuoteAgentController` só tem `show` e `create`). Com as escolhas no `config`, o endpoint
  é pequeno; sem ele, a única saída é recriar o agente. Decisão de produto.
- O front (PanelTune) mostra o modo avançado, o histórico e o "Ajustar com IA" para a Lia; a API recusa
  os três com a mesma mensagem. Esconder por tipo é trabalho de front.
- Especialista e principal têm cada um o seu `instrucao_do_sistema`; um `Instrucoes::Mantidas` comum
  seria o próximo passo se um terceiro leitor aparecer (hoje são dois).
- As views do Testar/Copilot (`playground/test.json.jbuilder`, `suggest.json.jbuilder`) chamam
  `json.should`, que no ambiente de teste colide com o `should` do RSpec (`undefined method 'matches?'
  for true`): nenhuma request spec consegue medir o 200 dessas views — por isso o exemplo positivo de
  `playground_escolhas_incompletas_spec` mede "não recusa e chama o modelo", não o 200. Pré-existente
  (vem de antes de #380); o conserto é renomear a chave ou usar `json.set!('should', …)` na view e
  confirmar que o front lê `handoff.should` do mesmo jeito.

## Comandos rodados

- `RAILS_ENV=test bundle exec rails db:create db:schema:load` (`POSTGRES_DATABASE=chatwoot_test_i380`).
- Spec nova antes da implementação: 14 exemplos, 12 falhas (RED: constante e métodos ausentes).
- Alvo: `bundle exec rspec spec/services/autonomia/insurance/quote_agent spec/requests/api/v1/accounts/autonomia/journeys/external_agent_lifecycle_spec.rb spec/services/autonomia/agents/prompt_builder_spec.rb spec/services/autonomia/agents/prompt_builder_documents_spec.rb spec/requests/api/v1/accounts/autonomia/agent_config_exposure_spec.rb spec/models/autonomia --format json` → 177 exemplos, 0 falhas, 0 erros fora.
- Ampla: `bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia --format json` → 896 exemplos, 0 falhas, 3 pendentes (pré-existentes: `RegistrationCheckout::Provisioner`, `Sso::Provisioner`), 0 erros fora, exit 0.
- `bundle exec rubocop` nos seis arquivos tocados → 0 ofensas (depois de um `Style/HashSyntax` na spec).
- `ruby ~/ops/agente-cotacao/issue-380/mutacoes_i380.rb` → 8/8 reprovam, restauração conferida por md5.
- Ensaio do rollout (regra da casa: migration/UPDATE que muda estado se ensaia antes): as expressões dos
  passos 1–3 rodadas no `chatwoot_test_i380` contra as TRÊS versões que `principal.md` já teve
  (`13492bb594` com crases, `504083ae30`, `79b1cdad70`) com valores de amostra → as quatro extraídas
  iguais nas três; passo 2 + passo 3 + rollback numa tabela temporária com a versão de 08/09 →
  `UPDATE 1`, conferência toda `t`, `with_knowledge` preservado, rollback deixa `ainda_tem = f`.
