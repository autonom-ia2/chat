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

O que NÃO cai em silêncio: chave presente e incompleta (campo faltando ou em branco) para com
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
| 6 | Mutações: runtime lendo a coluna reprova; valores ausentes caindo no arquivo com placeholder reprova | fechado | M1 e M8 (coluna), M3 (arquivo cru), M4 (marcador sobrando), M6 (branco em silêncio); rodada 3: VG/VG2 fecham o flip de tipo que reabria «runtime lendo a coluna», VD prova a leitura a cada montagem, VF/VI provam a mensagem e o locale — tabelas abaixo |

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

## Fora desta PR (da mesma classe ou vizinhos)

- Não existe endpoint para a corretora MUDAR nome/horário/comportamento depois de criar o agente
  (`Insurance::QuoteAgentController` só tem `show` e `create`). Com as escolhas no `config`, o endpoint
  é pequeno; sem ele, a única saída é recriar o agente. Decisão de produto.
- O front (PanelTune) mostra o modo avançado, o histórico e o "Ajustar com IA" para a Lia; a API recusa
  os três com a mesma mensagem. Esconder por tipo é trabalho de front.
- Especialista e principal têm cada um o seu `instrucao_do_sistema`; um `Instrucoes::Mantidas` comum
  seria o próximo passo se um terceiro leitor aparecer (hoje são dois).

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
