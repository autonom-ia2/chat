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
| 5 | SQL de rollout do agente 24 + conferência | entregue, não executado | seção «Rollout» abaixo |
| 6 | Mutações: runtime lendo a coluna reprova; valores ausentes caindo no arquivo com placeholder reprova | fechado | M1 e M8 (coluna), M3 (arquivo cru), M4 (marcador sobrando), M6 (branco em silêncio) — tabela abaixo |

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

Passo 1 — só leitura: de onde os valores vão sair.

```sql
SELECT id, name, agent_type, md5(instruction) AS md5_da_coluna, length(instruction) AS tamanho,
       config ? 'agente_de_cotacao' AS ja_tem_escolhas,
       (regexp_match(instruction, 'Você é `?([^`,\n]+)`?, e atende pela corretora'))[1]            AS nome_agente,
       (regexp_match(instruction, 'e atende pela corretora `?([^`\n]+)`?\.'))[1]                   AS nome_corretora,
       COALESCE((regexp_match(instruction, '\*\*Dentro do horário de atendimento \(([^)\n]+)\):\*\*'))[1],
                (regexp_match(instruction, '\*\*Dentro de `?([^`\n]+)`?:\*\*'))[1])                AS horario,
       (regexp_match(instruction, '### 4\.1 O seu comportamento — `?(consultivo|objetivo)`?'))[1] AS comportamento
FROM autonomia_agents
WHERE id = 24 AND account_id = 16 AND agent_type = 'insurance_quote';
```

Esperado: 1 linha, `ja_tem_escolhas = f`, `nome_agente = Lia`, os outros três preenchidos e
`comportamento` em (`consultivo`, `objetivo`). Qualquer NULL: parar e ler a coluna à mão — não chutar.

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
