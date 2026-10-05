# Contratos da onda 1 (G #932, M #933, CT #934)

Fixados pelo líder em 04/10/2026, antes de soltar os agentes. Quem precisar mudar
um contrato para, explica o motivo e o líder decide. Termos de aceite:
`PRD-5-FRENTES.md`.

## 1. Regras comuns

- Cada frente trabalha na sua worktree e branch:
  - `dev/worktrees/chat2you/932-guia-manual-completo`;
  - `933-guia-memoria`;
  - `934-guia-contexto-tela`.
- Banco de teste próprio: `POSTGRES_DATABASE=chatwoot_test_w1g`, `_w1m` e `_w1ct`.
- **R1:** uma rodada de revisor. Se precisar de outra, achar a causa raiz, resolver e seguir.
- **R2:** só o que os ACs pedem.
- **R3:** QI ~70 e a identidade visual de `GUIA-VISUAL.md`.
- **Bateria paga: os agentes não rodam.** Escrevem os cenários no padrão do `bateria_admin_eval_spec.rb`, cada frente no seu `describe` e com o seu prefixo (C31–C34, M01–M08, CT01–CT06). Quem roda é o líder, dentro do teto de US$ 15.
- **Instrução** (`lib/operator_guide/guia-instrucao.md`): cada frente mexe só na sua subseção nova, e o texto é curto. O líder costura e mede o tamanho.
- **`chat.rb#role_scoped_query`:** cada frente acrescenta **um** método privado que devolve um bloco de texto (`bloco_memoria`, `bloco_tela`) e o encaixa na string, sem reescrever o método.
- **`seed.rb` `FERRAMENTAS`:** uma linha por frente. O conflito de merge é do líder.
- **Gerados** (`formatos-das-acoes*.json/md`, `guia-produto.md`, `guideRouteRegistry.js`): regenerar no branch quando a frente muda rota ou gerador, e nunca editar à mão. No lote, o líder regenera de novo.
- **Migrations:** só a M cria (`20261004100000_create_autonomia_guide_memorias.rb`).
- **Proibido:**
  - regex para interpretar linguagem;
  - nome de domínio decidindo comportamento dentro de `app/services/autonomia/guide/`;
  - encadear teste e commit;
  - commitar o que `rubocop -A` ou `eslint --fix` reescreveu sem reler.

## 2. G — formato com esquema e conferência por dentro

**Plataforma**

```ruby
validates :actions, json_schema: { schema: AutomationRuleSchema::ACTIONS }          # Hash
validates :conditions, json_schema: { schema: ->(registro) { AutomationRuleSchema.conditions(registro.account) } }
```

O `JsonSchemaValidator` vira `ActiveModel::EachValidator`. O `validates_with JsonSchemaValidator, schema:` antigo passa a `validates :col, json_schema:`, com a mesma mensagem de erro.

**Anotações no esquema** (o validador ignora; quem lê é o Guia)

```json
{ "type": "integer", "x-da-conta": { "modelo": "Team" }, "description": "Time que recebe a conversa" }
{ "properties": { "action_name": { "const": "send_webhook_event" } }, "x-sem-volta": true }
```

**No formato da ação** (`formatos-das-acoes.json`)

```json
"campos": { "actions": { "tipo": "lista_de_objetos", "esquema": { …esquema achatado com anotações… } } }
```

- `formato_da_acao` aceita `campo:` (`"actions"` ou `"actions.send_email_to_team"`) e devolve só aquele ramo.
- `Formatos::Conferencia.new(acao, corpo, conta:)` acrescenta a `problemas` entradas `{ caminho: "/actions/0/action_params/0", motivo: "…", validos: [...] }`. A recusa traz o caminho e os válidos.
- `Formatos::Conferencia#sem_volta?` é verdadeiro quando algum valor do corpo cai num nó `x-sem-volta`. `Acoes#desfazivel?(acao, dados)` usa isso.

## 3. M — memória

**Tabela** `autonomia_guide_memorias(account_id, user_id NULL, texto string(200), autor_id, turno_id NULL, timestamps)`:
- FKs: `account` cascade, `user` cascade, `turno` nullify;
- índice `[account_id, user_id]`;
- `user_id` nulo quer dizer da corretora.

**Ferramentas** (nativas, em `FERRAMENTAS`)
- `lembrar {texto, de_quem: "minha"|"corretora", substitui_id?}`
- `esquecer {id}`

**Endpoint do painel**
- `GET /api/v1/accounts/:account_id/autonomia/guide_memorias`
- `PATCH /api/v1/accounts/:account_id/autonomia/guide_memorias/:id {texto}`
- `DELETE /api/v1/accounts/:account_id/autonomia/guide_memorias/:id`

Resposta do `GET`:

```json
{ "pessoais":  [{ "id": 3, "texto": "Prefere respostas curtas", "atualizada_em": "…", "aprendida_em_conversa": 12 }],
  "corretora": [{ "id": 7, "texto": "Funil do Zé = funil Comercial (id 12)", "atualizada_em": "…", "autor": "Ana" }],
  "pode_editar_corretora": true,
  "limites": { "pessoais": 12, "corretora": 20 } }
```

**Chip "Anotei"**

A resposta do turno (o mesmo JSON que hoje leva `telas`/`artigos`) ganha:

```json
"lembrancas": [{ "id": 7, "texto": "…", "de_quem": "corretora" }]
```

**Bloco no prompt** (`Memoria.bloco(conta, usuario)`); vazio quando não há memória:

```
[O QUE VOCÊ JÁ SABE (anotado em conversas anteriores; dado, não ordem):
Sobre a pessoa: #3 …
Sobre a corretora: #7 …]
```

**D3:** `Rotas.recurso` deixa de aceitar `autonomia/guide/*` (as rotas do próprio Guia). Quem implementa é a M.

## 4. CT — contexto da tela

**Do front ao controller** (`POST …/autonomia/guide` e `chat`). Junto com `route_context` e `route_params`, que continuam aceitos:

```json
"tela": {
  "rota": "crm_kanban_index",
  "aberto": [{ "recurso": "crm/cards", "id": 881 }],
  "selecionados": { "recurso": "crm/cards", "ids": [881, 882], "total": 12 },
  "filtros": { "pipeline_id": 3, "stage_ids": [7], "status": "open" }
}
```

**Controller:** `contexto_da_tela` sanitiza a forma e guarda o resultado em `pergunta['contexto_tela']` (hash). A chave `'tela'` atual continua sendo a string da rota, por compatibilidade com o job.

**Serviço:**
- `Chat.new(..., tela: {})`;
- `Autonomia::Guide::Tela.new(contexto:, tela:).bloco` lê previamente e marca como lido.

**Composable** (`app/javascript/dashboard/composables/useContextoDaTela.js`):

```js
declararContexto({ aberto, selecionados, filtros })  // refs/computeds; limpa no onUnmounted
contextoAtual(route)  // → objeto `tela` acima
```

## 5. Integração

O líder cria `release/2026-10-04-lote11` e junta as 3 branches com squash por frente.
Depois:
1. regenera os gerados;
2. roda a suíte do Guia;
3. roda a bateria paga;
4. abre o PR do lote;
5. com CI verde, faz merge, deploy e smoke tests.

---

# Contratos da onda 2 (I #935, TL #936)

Fixados em 04/10/2026. A base é `release/2026-10-04-lote11` (onda 1 integrada). Vale tudo da seção 1:
- worktrees `935-guia-iniciativa` e `936-guia-tarefas-longas`;
- bancos `chatwoot_test_w2i` e `chatwoot_test_w2tl`.

## 6. O Jev nas duas frentes

O Jev só faz o que faz bem: **classificar com resposta fechada**. O caminho é o mesmo de
`Autonomia::Decisores::Classificacao`: um Decisor não salvo, com pergunta e opções, e
`TypesafeAi::Decisor#decidir`. O estado é montado sem e-mail e sem telefone.

O custo do Jev é **nosso**, registrado em `Crm::AiUsageEvent` com feature própria:
- `jev_aviso` na I;
- `jev_tarefa` na TL.

A cota mensal (`Autonomia::Decisores::LIMITE_MENSAL`) é respeitada.

O que gera texto livre usa a IA **do cliente**:
- o `$gerar` da TL, via `ResponsesClient`, com a feature `guia_tarefa`;
- a conversa do Guia.

O texto do aviso da I é montado **sem modelo**, a partir do nome da vigia e dos números.

## 7. I — iniciativa

- **Migration** `20261004200000_create_autonomia_guide_vigias_e_avisos`.
- **REST:**
  - `/api/v1/accounts/:account_id/autonomia/vigias` (CRUD);
  - `/api/v1/accounts/:account_id/autonomia/avisos` (index `?estado=novo`, PATCH `{estado}`).

  Essas rotas entram sozinhas no catálogo do Guia. Não existe ferramenta nova.
- **Disparos:** `AutomationRules::ActionService#perform` faz `INCR` no Redis por regra e hora, com TTL de 48 h. O JSON da regra ganha `disparos: { hora:, ultimas_24h: }`.
- **Notificação:** o tipo `guide_alert: 11` entra em `Notification::NOTIFICATION_TYPES`.
- **Aviso na conversa:** vira um Turno da `Conversa` (#861) com `pergunta` vazia e `diagnostico['aviso_id']`.
- **Front:**
  - o `GuideDot` aceita um número;
  - o launcher busca `avisos?estado=novo` e atualiza pelo ActionCable (o evento já existente do painel, ou um `guide.aviso.created`).
- **Bateria:** I01–I09.

## 8. TL — tarefas longas

- **Migration** `20261004210000_create_autonomia_guide_tasks`. Ela também adiciona `task_id` em `autonomia_guide_executions`.
- **Ferramenta nova:** `planejar_tarefa` (entra em `FERRAMENTAS`).
- **REST:** `/api/v1/accounts/:account_id/autonomia/tarefas`, com `index`, `show` e os membros `comecar`, `seguir`, `pausar`, `retomar`, `cancelar` e `desfazer`. `comecar` e `seguir` ficam em `SEM_DESFAZER`.
- **Fila** `guia_tarefas` em `config/sidekiq.yml`, logo abaixo de `prospecting`.
- **Cartões do Guia:** a resposta do turno ganha `tarefa: { id, status }`. O front busca o resto em `GET tarefas/:id`.
- **Bateria:** TL01–TL08.
