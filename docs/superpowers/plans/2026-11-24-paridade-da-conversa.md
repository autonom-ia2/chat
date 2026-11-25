# Paridade da conversa (PR 1 do #3211) — plano de implementação

> **Para agentes executores:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam caixas (`- [ ]`) para acompanhamento.

**Objetivo:** trazer para o agente nativo, como opções por agente desligadas por padrão, o ritmo de conversa dos fluxos externos (esperar a fala anterior, juntar a rajada, fila atrás do turno em curso, entrega que não se corta, pausa e "digitando" por canal, resposta em áudio sem link), e dar a data e a hora do fuso da conta a todo turno.

**Arquitetura:** quatro chaves novas no `config` do agente, lidas num módulo só (`Autonomia::Agents::ParidadeDaConversa`). Um marcador no Redis por conversa (`Operate::FalaEmCurso`) diz quem está falando e quando a fala anterior termina; o `ReplyJob` usa isso para calcular a espera (P1) e para pôr o turno novo na fila (P2). O `Responder` junta a rajada (P1), descarta a resposta superada (P2) e aplica o ritmo do canal (P5); o `ChunkedDeliveryJob` não corta a fala depois do 1º pedaço (P3). A data e hora (P6) entram no `PromptBuilder` para todos os agentes, menos a Lia, com chave de instalação para desligar. Nenhum `if agent_type` nas opções.

**Tech stack:** Rails 7.1, Sidekiq/ActiveJob, `Redis::Alfred`, RSpec (só na CI), RuboCop.

**Desenho (spec):** `docs/superpowers/specs/2026-11-24-agente-seguro-viagem-universal-design.md`, seções 8 e 11. Itens P1, P2, P3, P5, P6, P7 (P4 caiu: a quebra em pedaços da plataforma fica como está). Fatos de apoio: `FATOS-PIPELINE.md` da sessão (fora do repo).

**Issue:** autonom-ia2/chat#3211 (o PR usa `Refs #3211`; não fecha a Issue).

## Global Constraints

Regras da casa (copiadas do FATOS-PIPELINE, valem para toda tarefa):

- No local rspec: specs run only on CI. Write specs and do not run them locally. `pnpm eslint` and `pnpm test` (vitest) are allowed locally.
- No regex to interpret language. Avoid regex in general; use string methods and parsers.
- No native `<select>`: use `components-next/choice-select/ChoiceSelect.vue`.
- Tailwind only; no custom/scoped/inline CSS. Composition API `<script setup>`.
- i18n: only `en` and `pt_BR`, following `docs/i18n/fork-translations.md`; `pnpm i18n:fork:check`.
- Enterprise overlay: check `enterprise/` for counterparts.
- Guia: a new route/screen needs a block in `lib/operator_guide/porques.md` plus `pnpm guia:build`. Touching a controller or strong params needs `bundle exec rails autonomia:guia:formatos`.
- Commits in Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never chain test && commit.
- The repo is PUBLIC: no client names or account numbers in code, comments, specs, PR or plan.
- Do not touch the Lia's behaviour (`insurance_quote`).
- A new screen needs a mockup in screenshots approved by Rodrigo before implementation. The UI tasks in the plan come after a "mockup approved" gate.

Regras deste PR (do desenho, seções 8 e 11):

- Cada opção é uma chave do `config` do agente, **desligada por padrão**; sem a chave, o comportamento fica byte a byte o de hoje. Quem liga é o `Contratar` (PR seguinte).
- Com a opção ligada, ela vence o comportamento da Fase 2 para aquele agente. Sem `if agent_type` nas opções.
- A quebra em pedaços (`ReplyChunker`, 60/260/420, até 5) **não muda** (sem P4).
- Este PR não tem tela: nenhuma rota, nenhum texto de i18n, nenhum bloco do Guia. Não toca controller nem strong params.
- `enterprise/` não tem contraparte de `ReplyJob`, `Responder`, `ChunkedDeliveryJob`, `TypingIndicator` nem `PromptBuilder` (conferido). O que estende o `Responder` são os `prepend` do WAHA (`config/initializers/whatsapp_rich_native.rb`); o `AgentTurnGuard` sobrescreve `recent_messages` e `last_incoming_message`, e o código novo lê esses dois métodos, nunca a tabela direto.
- `responder.rb` já tem 1010 linhas: aqui só entram chamadas curtas para arquivos novos; extrair o `Responder` fica fora deste PR.

As chaves (nomes fixos; o PR do agente contratado usa exatamente estes):

| Item | Chave em `agent.config` | Padrão | Efeito ligado |
|---|---|---|---|
| P1 | `conversa_espera_a_fala` | ausente = desligada | espera = fim previsto da fala anterior − agora, mínimo 1 s, teto 180 s; a pergunta junta toda a rajada do cliente |
| P2 | `conversa_em_fila` | ausente = desligada | o turno novo espera o turno em curso (IA ou pedaços), de 2 em 2 s, até a espera + 150 s; a resposta superada antes do 1º pedaço é descartada, com ou sem Fase 2 |
| P3 | `conversa_entrega_inteira` | ausente = desligada | depois do 1º pedaço postado, mensagem nova não corta o resto. **Só vale com `conversa_em_fila`** (sem a fila, o turno novo falaria por cima) |
| P5 | `conversa_ritmo_do_canal` | ausente = desligada | pausa pós-envio 1–3 s; no WhatsApp oficial, espera cheia no 1º pedaço e a cada 25 s acumulados, 1/5 nos demais; "digitando" no WAHA |
| P6 | — (todos os agentes, menos a Lia) | ENV `AI_AGENT_DATA_DO_TURNO`, ausente = ligada | item `developer` "Agora: …" logo antes da pergunta |
| P7 | `voice_reply` (já existe) | já existe (ENV `AI_AGENT_VOICE_REPLY`, padrão desligada) | regra nova para toda resposta em voz: resposta com link sai em texto |

## Review Focus

1. **Marca do turno expira na espera nova.** Com `agente_so_informa`, `TurnoEmCurso.abrir` usa `teto_do_turno`, que conta só 30 s de debounce; P1 + P2 podem esperar 180 s + 150 s, e a marca some no meio, deixando a IA de Atribuição entregar a conversa durante a fila. Esperado: o teto cobre a espera nova. Teste na Tarefa 3.
2. **Fala presa no Redis.** Exceção no `Responder`, cadeia parada no meio, ou a opção desligada entre ocupar e soltar deixam a marca `fala_em_curso`; todo turno novo esperaria 150 s. Esperado: todo caminho solta (soltar não depende da opção). Testes nas Tarefas 4 e 6.
3. **Rajada com pedaços intercalados.** Com P3, a mensagem nova chega entre o 1º e o 2º pedaço; "incoming depois da última outgoing" fica vazio (a última outgoing é um pedaço posterior). Esperado: a pergunta é a mensagem nova, nunca vazia e nunca a já respondida. Teste na Tarefa 5.
4. **Fila + Fase 2.** Depois de esperar na fila, o `EsperaDoAssunto` mede o teto de 20 s da criação da mensagem e pode registrar `assunto_atrasou` falso, ou a posse do turno pode responder duas vezes. Esperado: com o marco do assunto já gravado, uma resposta e nenhum `assunto_atrasou`. Teste na Tarefa 4.
5. **Redis fora do ar.** `FalaEmCurso` levantando no settle mataria o turno calado. Esperado: sem Redis, "ninguém ocupando, sem fim previsto"; o agente responde com a espera mínima. Testes nas Tarefas 2 e 4.

---

## File Structure

Novos:

| Arquivo | Responsabilidade |
|---|---|
| `app/services/autonomia/agents/paridade_da_conversa.rb` | Lê as 4 chaves do `config` (nomes, cast booleano, dependência P3→P2) |
| `app/services/autonomia/agents/operate/fala_em_curso.rb` | Redis por conversa: quem está falando (P2) e quando a fala termina (P1) |
| `app/services/autonomia/agents/operate/espera_da_fala.rb` | Quanto o settle espera (P1) e se o turno vai para a fila (P2) |
| `app/services/autonomia/agents/operate/rajada_do_cliente.rb` | Mensagens do cliente desde a última fala e o texto juntado (P1) |
| `app/services/autonomia/agents/operate/ritmo_do_canal.rb` | Reescreve `delay_ms` dos pedaços: pausa pós-envio e regra de 25 s (P5) |
| `app/services/autonomia/agents/prompt_parts/agora.rb` | Texto "Agora: …" no fuso da conta (P6) |
| `docs/agentes/paridade-da-conversa.md` | Tabela das chaves, a ENV e o que cada uma muda |

Alterados: `app/jobs/autonomia/agents/operate/reply_job.rb`, `app/jobs/autonomia/agents/operate/chunked_delivery_job.rb`, `app/services/autonomia/agents/operate/responder.rb`, `app/services/autonomia/agents/operate/typing_indicator.rb`, `app/services/autonomia/agents/operate/turno_em_curso.rb`, `app/services/autonomia/agents/prompt_builder.rb`, `app/services/autonomia/agents/config.rb`, e specs existentes que fixam o `input` inteiro do `PromptBuilder` (Tarefa 9).

---

### Tarefa 0: Worktree e branch

- [ ] **Passo 1: criar a worktree a partir da `main`**

```sh
git -C <repo> fetch origin --prune
git -C <repo> worktree add \
    <worktree> -b feat/3211-paridade-da-conversa origin/main
```

`<repo>` é o clone principal do chat2you e `<worktree>`, a pasta da worktree desta entrega (fora do clone, na pasta de
worktrees da máquina). Esperado: worktree criada, `git -C <worktree> status` limpo. Todos os caminhos abaixo são relativos a ela.

---

### Tarefa 1: As chaves (`ParidadeDaConversa`)

**Arquivos:**
- Criar: `app/services/autonomia/agents/paridade_da_conversa.rb`
- Criar: `docs/agentes/paridade-da-conversa.md`
- Teste: `spec/services/autonomia/agents/paridade_da_conversa_spec.rb`

**Interfaces:**
- Consome: `agent.config` (Hash jsonb, chaves string).
- Produz (módulo `Autonomia::Agents::ParidadeDaConversa`, `module_function`, molde de `fase2.rb`):
  - `ESPERA_A_FALA = 'conversa_espera_a_fala'`, `EM_FILA = 'conversa_em_fila'`, `ENTREGA_INTEIRA = 'conversa_entrega_inteira'`, `RITMO_DO_CANAL = 'conversa_ritmo_do_canal'`, `CHAVES = [as 4].freeze`
  - `espera_a_fala?(agent) -> Boolean`, `em_fila?(agent) -> Boolean`, `entrega_inteira?(agent) -> Boolean` (= chave ligada **e** `em_fila?`), `ritmo_do_canal?(agent) -> Boolean`
  - `nil`, objeto sem `config` ou `config` que não é Hash → `false`. Valor lido com `ActiveModel::Type::Boolean` (`'false'` → `false`).

- [ ] **Passo 1: escrever o spec que falha**

```ruby
RSpec.describe Autonomia::Agents::ParidadeDaConversa do
  def agente(config) = Autonomia::Agents::Agent.new(config: config)

  it 'sem as chaves, tudo desligado' do
    vazio = agente({})
    expect(%i[espera_a_fala? em_fila? entrega_inteira? ritmo_do_canal?].map { |p| described_class.public_send(p, vazio) })
      .to all(be(false))
  end
  it { expect(described_class.espera_a_fala?(agente('conversa_espera_a_fala' => true))).to be(true) }
  it { expect(described_class.em_fila?(agente('conversa_em_fila' => 'false'))).to be(false) }
  it { expect(described_class.ritmo_do_canal?(agente('conversa_ritmo_do_canal' => 'true'))).to be(true) }
  it 'entrega inteira só com a fila' do
    expect(described_class.entrega_inteira?(agente('conversa_entrega_inteira' => true))).to be(false)
    expect(described_class.entrega_inteira?(agente('conversa_entrega_inteira' => true, 'conversa_em_fila' => true))).to be(true)
  end
  it 'agente nil ou sem config' do
    expect(described_class.em_fila?(nil)).to be(false)
    expect(described_class.em_fila?(Struct.new(:agent_bot).new(nil))).to be(false)
  end
end
```

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. Localmente só: `eval "$(rbenv init -)" && bundle exec rubocop spec/services/autonomia/agents/paridade_da_conversa_spec.rb`.

- [ ] **Passo 3: implementar** o módulo com as constantes e os quatro predicados acima, mais `ligada?(agent, chave)` privado (`private_class_method`). Comentário de topo em pt-BR: o que cada chave faz, que todas nascem desligadas, que o `Contratar` liga, e a dependência P3→P2.

- [ ] **Passo 4: doc** — `docs/agentes/paridade-da-conversa.md` com a tabela das chaves da seção "Global Constraints" (sem a linha P6 por enquanto; a Tarefa 9 acrescenta), um parágrafo "como ligar num agente" (`config` do agente, sem tela) e "como desligar" (tirar a chave).

- [ ] **Passo 5: verificar** — `bundle exec rubocop app/services/autonomia/agents/paridade_da_conversa.rb spec/services/autonomia/agents/paridade_da_conversa_spec.rb` → `no offenses detected`.

- [ ] **Passo 6: commit**

```bash
git add app/services/autonomia/agents/paridade_da_conversa.rb spec/services/autonomia/agents/paridade_da_conversa_spec.rb docs/agentes/paridade-da-conversa.md
git commit -m "feat(agentes): chaves da paridade da conversa, desligadas por padrão" -m "Refs #3211" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 2: Quem fala e quando termina (`FalaEmCurso`)

**Arquivos:**
- Criar: `app/services/autonomia/agents/operate/fala_em_curso.rb`
- Teste: `spec/services/autonomia/agents/operate/fala_em_curso_spec.rb`

**Interfaces:**
- Consome: `Redis::Alfred` (`set(ex:)`, `get`, `with`/`watch`/`multi`, `delete_if_equals`), `TurnoEmCurso.teto_do_turno`, `TurnoEmCurso::TTL_DA_CADEIA` (molde de `turno_em_curso.rb`).
- Produz (módulo `Autonomia::Agents::Operate::FalaEmCurso`, `module_function`):
  - `CHAVE_OCUPADA = 'autonomia:fala_em_curso:%<conversa>d'`, `CHAVE_DO_FIM = 'autonomia:fim_da_fala:%<conversa>d'`
  - `MS_POR_CARACTERE = 160`, `VARIACAO = 0.2`, `TETO_DO_FIM_MS = 150_000`, `TTL_DO_FIM = 9000` (segundos; valores do fluxo externo)
  - `chave_ocupada(conversation_id) -> String`, `chave_do_fim(conversation_id) -> String`
  - `ocupar(conversation_id, message_id) -> nil` — SET com TTL `TurnoEmCurso.teto_do_turno`
  - `renovar(conversation_id, message_id) -> Boolean` — compare-and-expire com `TTL_DA_CADEIA`, igual ao `TurnoEmCurso.renovar`
  - `soltar(conversation_id, message_id) -> nil` — compare-and-delete; `message_id` vazio não faz nada
  - `ocupada_por_outro?(conversation_id, message_id) -> Boolean` — valor presente e diferente de `message_id.to_s`
  - `duracao_estimada_ms(texto) -> Integer` — `texto.length × taxa`, com a taxa sorteada uma vez em `128..192` (160 ± 20%), teto `TETO_DO_FIM_MS`
  - `prever_fim!(conversation_id, texto, agora: Time.current) -> Time | nil` — grava `agora + duracao_estimada_ms` em ms epoch, TTL `TTL_DO_FIM`
  - `fim_previsto(conversation_id) -> Time | nil`
  - **Nunca levanta:** todo método com `rescue StandardError` → `nil` / `false`.

- [ ] **Passo 1: escrever o spec que falha** (com `freeze_time`; `before` apaga as duas chaves da conversa 42)

```ruby
it 'ocupar e perguntar por outro turno' do
  fala.ocupar(42, 7)
  expect(fala.ocupada_por_outro?(42, 8)).to be(true)
  expect(fala.ocupada_por_outro?(42, 7)).to be(false)
  expect(Redis::Alfred.ttl(fala.chave_ocupada(42))).to be > 0
end
it 'soltar só apaga a marca do próprio turno' do
  fala.ocupar(42, 7)
  fala.soltar(42, 8)
  expect(Redis::Alfred.get(fala.chave_ocupada(42))).to eq('7')
  fala.soltar(42, 7)
  expect(Redis::Alfred.get(fala.chave_ocupada(42))).to be_nil
end
it 'renovar só renova o próprio turno' do
  fala.ocupar(42, 7)
  expect(fala.renovar(42, 8)).to be(false)
  expect(fala.renovar(42, 7)).to be(true)
  expect(Redis::Alfred.ttl(fala.chave_ocupada(42))).to be <= Autonomia::Agents::Operate::TurnoEmCurso::TTL_DA_CADEIA.to_i
end
it 'sem marca, ninguém ocupa' do
  expect(fala.ocupada_por_outro?(42, 8)).to be(false)
end
it 'fim previsto: 160 ms ± 20% por caractere' do
  fim = fala.prever_fim!(42, 'a' * 100)
  expect(fim).to be_between(Time.current + 12.8.seconds, Time.current + 19.2.seconds)
  expect(fala.fim_previsto(42)).to be_within(0.001.seconds).of(fim)
end
it 'fim previsto tem teto de 150 s' do
  expect(fala.duracao_estimada_ms('a' * 2000)).to eq(150_000)
end
it 'Redis fora do ar: não levanta, ninguém ocupa, sem fim' do # Review Focus 5
  allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)
  allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)
  expect { fala.ocupar(42, 7) }.not_to raise_error
  expect(fala.ocupada_por_outro?(42, 8)).to be(false)
  expect(fala.fim_previsto(42)).to be_nil
  expect(fala.prever_fim!(42, 'oi')).to be_nil
end
```

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` no spec.
- [ ] **Passo 3: implementar** o módulo com a interface acima. Comentário de topo: por que existe (o par "fim previsto da fala" + "agente ocupado" do fluxo externo), por que não reaproveita `TurnoEmCurso` (aquela marca é aberta a cada mensagem do cliente e a mais nova toma; esta é do turno que está falando).
- [ ] **Passo 4: verificar** — `bundle exec rubocop app/services/autonomia/agents/operate/fala_em_curso.rb spec/services/autonomia/agents/operate/fala_em_curso_spec.rb` → sem ofensas.
- [ ] **Passo 5: commit** — `feat(agentes): marca da fala em curso e fim previsto no Redis`.

---

### Tarefa 3: Quanto esperar e quando entrar na fila (`EsperaDaFala`)

**Arquivos:**
- Criar: `app/services/autonomia/agents/operate/espera_da_fala.rb`
- Alterar: `app/services/autonomia/agents/operate/turno_em_curso.rb:41-48` (`teto_do_turno`)
- Teste: `spec/services/autonomia/agents/operate/espera_da_fala_spec.rb`; acrescentar em `spec/services/autonomia/agents/operate/turno_em_curso_spec.rb`

**Interfaces:**
- Consome: `ParidadeDaConversa.espera_a_fala?/em_fila?`, `FalaEmCurso.fim_previsto/ocupada_por_outro?`, `Config.debounce_seconds_for(agent)`, a marca do debounce `conversation.additional_attributes['autonomia_debounce']` com `'at'` (float epoch) e `'espera_ms'` (Integer, gravado na Tarefa 4).
- Produz (módulo `Autonomia::Agents::Operate::EsperaDaFala`, `module_function`):
  - `ESPERA_MINIMA = 1.second`, `ESPERA_MAXIMA = 180.seconds`, `INTERVALO_DA_FILA = 2.seconds`, `TETO_DA_FILA = 150.seconds`
  - `da_rajada(agent:, conversation_id:, agora: Time.current) -> ActiveSupport::Duration` — opção P1 desligada: `Config.debounce_seconds_for(agent)` (hoje, 6 s). Ligada: `(fim_previsto − agora)` preso entre `ESPERA_MINIMA` e `ESPERA_MAXIMA`; sem fim previsto, `ESPERA_MINIMA`.
  - `na_fila?(agent:, conversation:, message_id:, agora: Time.current) -> Boolean` — `true` só com `em_fila?(agent)`, `ocupada_por_outro?(conversation.id, message_id)` **e** `agora < at + espera_ms + TETO_DA_FILA`. Sem a marca do debounce ou sem `'at'`: `false` (nunca fila sem prazo).
  - `TurnoEmCurso.teto_do_turno`: o termo `OPERATE_DEBOUNCE_MAX_SECONDS` passa a ser `[OPERATE_DEBOUNCE_MAX_SECONDS, EsperaDaFala::ESPERA_MAXIMA + EsperaDaFala::TETO_DA_FILA].max`.

- [ ] **Passo 1: escrever o spec que falha** (`freeze_time`; `agent` = `criar_principal(conta_da_fase2(ligada: false))`; `liga!(*chaves)` grava `true` nas chaves)

```ruby
describe '.da_rajada' do
  it 'opção desligada: o debounce de sempre' do
    expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(6.seconds)
  end
  it 'ligada e sem fala anterior: 1 s' do
    liga!('conversa_espera_a_fala')
    expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(1.second)
  end
  it 'ligada: espera a fala anterior acabar' do
    liga!('conversa_espera_a_fala')
    allow(Autonomia::Agents::Operate::FalaEmCurso).to receive(:fim_previsto).with(1).and_return(25.seconds.from_now)
    expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(25.seconds)
  end
  it 'ligada: teto de 180 s' do
    liga!('conversa_espera_a_fala')
    allow(Autonomia::Agents::Operate::FalaEmCurso).to receive(:fim_previsto).and_return(500.seconds.from_now)
    expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(180.seconds)
  end
end

describe '.na_fila?' do
  # conversa com a marca { 'pending_message_id' => 9, 'at' => Time.current.to_f, 'espera_ms' => 1000 }
  it 'outro turno falando: fila' do
    liga!('conversa_em_fila')
    Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, 8)
    expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(true)
  end
  it 'opção desligada: nunca fila' do
    Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, 8)
    expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(false)
  end
  it 'passado espera + 150 s, segue mesmo ocupada' do
    liga!('conversa_em_fila')
    Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, 8)
    expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9, agora: 152.seconds.from_now)).to be(false)
    expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9, agora: 150.seconds.from_now)).to be(true)
  end
  it 'sem marca do debounce: não fila' do
    liga!('conversa_em_fila')
    Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, 8)
    conversation.update!(additional_attributes: {})
    expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(false)
  end
end
```

Em `turno_em_curso_spec.rb` (Review Focus 1):

```ruby
it 'o teto do turno cobre a espera da fala e a fila' do
  espera = Autonomia::Agents::Operate::EsperaDaFala
  expect(described_class.teto_do_turno).to be >= espera::ESPERA_MAXIMA + espera::TETO_DA_FILA
end
```

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` nos specs.
- [ ] **Passo 3: implementar** `EsperaDaFala` e a troca no `teto_do_turno` (atualizar o comentário dele: a maior janela agora é a da fala). O TTL maior é só rede de segurança; o caminho normal sempre solta.
- [ ] **Passo 4: verificar** — `bundle exec rubocop` nos 4 arquivos → sem ofensas.
- [ ] **Passo 5: commit** — `feat(agentes): espera pela fala anterior e fila atrás do turno em curso`.

---

### Tarefa 4: `ReplyJob` com a espera (P1) e a fila (P2); resposta superada descartada

**Arquivos:**
- Alterar: `app/jobs/autonomia/agents/operate/reply_job.rb:66-71` (trigger), `:76-82` (settle), `:102-112` (responder/ensure), `:144-153` (`stamp_debounce`)
- Alterar: `app/services/autonomia/agents/operate/responder.rb:106-110` (público) e `:596-602` (`turno_superado?`)
- Teste: `spec/jobs/autonomia/agents/operate/reply_job_fila_da_fala_spec.rb`

**Interfaces:**
- Consome: `EsperaDaFala.da_rajada/na_fila?/INTERVALO_DA_FILA`, `FalaEmCurso.ocupar/soltar`, `ParidadeDaConversa.em_fila?`.
- Produz:
  - `ReplyJob#stamp_debounce(conversation, message_id, espera)` grava `{ 'pending_message_id', 'at', 'espera_ms' => (espera.to_f * 1000).round }` (mesmo `jsonb_set`).
  - `trigger`: `espera = EsperaDaFala.da_rajada(agent: agent_inbox.agent, conversation_id: conversation.id)`; grava a marca com ela; `set(wait: espera)`.
  - `settle`: logo depois de `current_token?` e **antes** de `esperar_o_assunto?`: `na_fila?` → reagenda `settle` com `wait: INTERVALO_DA_FILA` e o mesmo `posse`, sem responder.
  - `responder`: com `em_fila?(agent_inbox.agent)`, `FalaEmCurso.ocupar(conversation.id, message_id)` antes de `responder.perform`; no `ensure`, `FalaEmCurso.soltar(conversation.id, message_id)` **sem checar a opção**, salvo quando `responder&.cadeia_agendada?`.
  - `Responder#cadeia_agendada? -> Boolean` (público, `@cadeia_agendada == true`).
  - `Responder#turno_superado?`: o gate vira `Fase2.ligada?(account) || ParidadeDaConversa.em_fila?(@agent)`; o resto igual.

- [ ] **Passo 1: escrever o spec que falha** — `RSpec.describe Autonomia::Agents::Operate::ReplyJob, :um_turno`, `include_context 'with crm responsible agent'`, `around` com `AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false'`, `before { contrato!; ia_responde!; clear_enqueued_jobs; freeze_time }`, apaga as chaves da `FalaEmCurso` da conversa. Ajudantes: `fala = Autonomia::Agents::Operate::FalaEmCurso`; `liga!(*chaves)` faz `agente_da_porta.update!(config: agente_da_porta.config.to_h.merge(chaves.index_with(true)))`.

```ruby
it 'P1: settle marcado para quando a fala anterior acaba' do
  liga!('conversa_espera_a_fala')
  allow(fala).to receive(:fim_previsto).and_return(25.seconds.from_now)
  gatilho(cliente_escreve('oi'))
  expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(25.seconds.from_now)
  expect(conversation.reload.additional_attributes.dig('autonomia_debounce', 'espera_ms')).to eq(25_000)
end

it 'sem opção: 6 s, como hoje' do
  gatilho(cliente_escreve('oi'))
  expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(6.seconds.from_now)
end

it 'P2: outro turno falando, o settle volta em 2 s e não responde' do
  liga!('conversa_em_fila')
  fala.ocupar(conversation.id, 999_999)
  m = cliente_escreve('oi'); gatilho(m)
  rodar_rodada!
  expect(respostas).to be_empty
  expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(2.seconds.from_now)
  fala.soltar(conversation.id, 999_999)
  rodar_turno!
  expect(respostas.count).to eq(1)
end

it 'P2: passado o teto da fila, responde mesmo com a marca de outro' do
  liga!('conversa_em_fila')
  fala.ocupar(conversation.id, 999_999)
  m = cliente_escreve('oi'); gatilho(m)
  travel 6.seconds + 151.seconds
  settle(m)
  expect(respostas.count).to eq(1)
end

it 'P2 sem Fase 2: mensagem nova durante a IA descarta a resposta velha; uma resposta só' do
  Autonomia::Agents::Fase2.desligar!(account)
  liga!('conversa_em_fila')
  primeira = cliente_escreve('oi'); gatilho(primeira)
  ia_responde!(durante: ->(_) { @segunda ||= cliente_escreve('quero cotar').tap { |m| gatilho(m) } })
  rodar_turno!
  expect(respostas.count).to eq(1)
  expect(respostas.sole.content_attributes['autonomia_reply_to_message_id']).to eq(@segunda.id)
end

it 'sem opção e sem Fase 2: posta as duas, como hoje' do
  Autonomia::Agents::Fase2.desligar!(account)
  primeira = cliente_escreve('oi'); gatilho(primeira)
  ia_responde!(durante: ->(_) { @segunda ||= cliente_escreve('quero cotar').tap { |m| gatilho(m) } })
  rodar_turno!
  expect(respostas.count).to eq(2)
end

it 'durante a IA a fala é deste turno; depois, solta' do # Review Focus 2
  liga!('conversa_em_fila')
  m = cliente_escreve('oi')
  ia_responde!(durante: ->(_) { @durante = Redis::Alfred.get(fala.chave_ocupada(conversation.id)) })
  gatilho(m); rodar_turno!
  expect(@durante).to eq(m.id.to_s)
  expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to be_nil
end

it 'a IA falhou: solta a fala' do # Review Focus 2
  liga!('conversa_em_fila')
  allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(StandardError, 'caiu')
  gatilho(cliente_escreve('oi')); rodar_turno!
  expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to be_nil
end

it 'opção desligada no meio do turno: ainda solta' do # Review Focus 2
  liga!('conversa_em_fila')
  ia_responde!(durante: ->(agent) { agent.update!(config: agent.config.except('conversa_em_fila')) })
  gatilho(cliente_escreve('oi')); rodar_turno!
  expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to be_nil
end

it 'com pedaços: a cadeia fica com a fala' do
  with_modified_env(AI_HUMANIZE_DELIVERY: 'true') do
    liga!('conversa_em_fila')
    m = cliente_escreve('oi'); gatilho(m); rodar_turno!
    expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to eq(m.id.to_s)
  end
end

it 'Fase 2: depois da fila, com o assunto decidido, uma resposta e nenhum assunto_atrasou' do # Review Focus 4
  liga!('conversa_em_fila')
  contrato!(ordem: true)
  fala.ocupar(conversation.id, 999_999)
  m = cliente_escreve('oi'); gatilho(m)
  allow(contrato).to receive(:decidido_ate).with(conversation.id).and_return(m.id)
  travel 30.seconds
  fala.soltar(conversation.id, 999_999)
  settle(m)
  expect(respostas.count).to eq(1)
  expect(Autonomia::Agents::AgentEvent.skipped_assunto_atrasou.where(conversation_id: conversation.id)).to be_empty
end

it 'Redis fora do ar: responde' do # Review Focus 5
  liga!('conversa_em_fila', 'conversa_espera_a_fala')
  allow(Redis::Alfred).to receive(:get).and_call_original
  allow(Redis::Alfred).to receive(:get).with(fala.chave_ocupada(conversation.id)).and_raise(Redis::CannotConnectError)
  gatilho(cliente_escreve('oi')); rodar_turno!
  expect(respostas.count).to eq(1)
end
```

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` no spec.
- [ ] **Passo 3: implementar** as mudanças da seção Interfaces. O reagendamento da fila é um método privado `esperar_na_fila(conversation, message_id, posse)` no molde de `esperar_o_assunto`. Ordem no `settle`: `current_token?` → fila → assunto → posse → responder (a fila antes do assunto: o assunto costuma ser decidido enquanto espera, e o `EsperaDoAssunto` só lê o marco uma vez).
- [ ] **Passo 4: verificar** — `bundle exec rubocop app/jobs/autonomia/agents/operate/reply_job.rb app/services/autonomia/agents/operate/responder.rb spec/jobs/autonomia/agents/operate/reply_job_fila_da_fala_spec.rb` → sem ofensas.
- [ ] **Passo 5: commit** — `feat(agentes): turno novo espera a fala anterior e entra na fila (opções por agente)`.

---

### Tarefa 5: A pergunta é a rajada inteira; o fim previsto é gravado (P1)

**Arquivos:**
- Criar: `app/services/autonomia/agents/operate/rajada_do_cliente.rb`
- Alterar: `app/services/autonomia/agents/operate/responder.rb:765-775` (`query`), `:849-854` (`current_turn_incoming`), `:636-642` (`depois_da_entrega`)
- Teste: `spec/services/autonomia/agents/operate/rajada_do_cliente_spec.rb`, `spec/services/autonomia/agents/operate/responder_rajada_spec.rb`

**Interfaces:**
- Consome: `Responder#recent_messages` (ordem cronológica; o `AgentTurnGuard` do WAHA pode sobrescrever), `email_autoria.texto(message)`, `FalaEmCurso.prever_fim!`, `ParidadeDaConversa.espera_a_fala?`.
- Produz (módulo `Autonomia::Agents::Operate::RajadaDoCliente`, `module_function`):
  - `CHAVE_DO_PEDACO = 'autonomia_chunk_index'`
  - `mensagens(recent_messages) -> Array<Message>` — anda do fim para o começo: incoming entra; outgoing com `content_attributes[CHAVE_DO_PEDACO].to_i.positive?` (continuação de uma cadeia) é pulada; qualquer outra mensagem para. Devolve em ordem cronológica.
  - `texto(mensagens) { |m| String } -> String` — o bloco dá o texto de cada uma; `strip`, tira vazias, tira repetida **seguida** (mensagem igual à anterior), junta com `"\n"`.
- No `Responder`, com `espera_a_fala?(@agent)`:
  - `current_turn_incoming` = `RajadaDoCliente.mensagens(recent_messages)` (sem a opção, o cálculo de hoje);
  - em `query`, `base` = `RajadaDoCliente.texto(current_turn_incoming) { |m| email_autoria.texto(m) }`; `quoted_context` e `email_autoria.aviso` continuam lendo `last_incoming_message`;
  - em `depois_da_entrega`, quando `@cadeia_agendada || outcome.message.present?`: `FalaEmCurso.prever_fim!(@conversation.id, result.reply)` (método privado `prever_o_fim_da_fala(result, outcome)`).

- [ ] **Passo 1: escrever os specs que falham**

`rajada_do_cliente_spec.rb` (dublês, sem banco):

```ruby
def recebida(texto) = instance_double(Message, incoming?: true, content: texto, content_attributes: {})
def pedaco(indice) = instance_double(Message, incoming?: false, content_attributes: { 'autonomia_chunk_index' => indice })
def fala_de_gente = instance_double(Message, incoming?: false, content_attributes: {})

it 'tudo desde a última fala' do
  m1, m2 = recebida('quero cotar'), recebida('pra Portugal')
  expect(described_class.mensagens([recebida('antiga'), fala_de_gente, m1, m2])).to eq([m1, m2])
end
it 'pedaços intercalados não fecham a rajada' do # Review Focus 3
  m2 = recebida('e pra 2 pessoas?')
  expect(described_class.mensagens([recebida('oi'), pedaco(0), m2, pedaco(1), pedaco(2)])).to eq([m2])
end
it 'sem nenhuma fala, todas as recebidas' do
  expect(described_class.mensagens([recebida('a'), recebida('b')]).size).to eq(2)
end
it 'junta com quebra de linha, sem vazias nem repetidas seguidas' do
  msgs = [recebida('oi'), recebida('oi'), recebida('  '), recebida('tudo bem?'), recebida('oi')]
  expect(described_class.texto(msgs, &:content)).to eq("oi\ntudo bem?\noi")
end
```

`responder_rajada_spec.rb` (`:um_turno`, `include_context 'with crm responsible agent'`, `AI_HUMANIZE_DELIVERY: 'false'`, `freeze_time`; captura a pergunta com `allow(Autonomia::Agents::Answerer).to receive(:new) { |query:, **| perguntas << query; dublê que responde 'Claro, te ajudo.' }`):

```ruby
it 'com a opção, a pergunta é a rajada inteira' do
  liga!('conversa_espera_a_fala')
  cliente_escreve('quero cotar'); cliente_escreve('pra Portugal'); ultima = cliente_escreve('saio dia 02/02')
  settle_direto(ultima) # Responder.new(conversation:, agent_inbox: vinculo_da_porta, reply_to_message_id: ultima.id).perform
  expect(perguntas.sole).to eq("quero cotar\npra Portugal\nsaio dia 02/02")
end
it 'sem a opção, só a última' do
  cliente_escreve('quero cotar'); ultima = cliente_escreve('pra Portugal')
  settle_direto(ultima)
  expect(perguntas.sole).to eq('pra Portugal')
end
it 'grava o fim previsto da fala ao responder' do
  liga!('conversa_espera_a_fala')
  settle_direto(cliente_escreve('oi'))
  fim = Autonomia::Agents::Operate::FalaEmCurso.fim_previsto(conversation.id)
  expect(fim).to be_between(Time.current + (16 * 0.128).seconds, Time.current + (16 * 0.192).seconds) # 'Claro, te ajudo.' = 16
end
it 'silêncio não grava fim previsto' do
  liga!('conversa_espera_a_fala')
  responde_com('conversation_closed_for_now')
  settle_direto(cliente_escreve('ok'))
  expect(Autonomia::Agents::Operate::FalaEmCurso.fim_previsto(conversation.id)).to be_nil
end
it 'sem a opção, não grava' do
  settle_direto(cliente_escreve('oi'))
  expect(Autonomia::Agents::Operate::FalaEmCurso.fim_previsto(conversation.id)).to be_nil
end
```

(Se a moldura da equipe da Fase 2 mudar o texto da pergunta no contexto compartilhado, desligar a Fase 2 neste spec com `Autonomia::Agents::Fase2.desligar!(account)`; a rajada não depende dela.)

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` nos specs.
- [ ] **Passo 3: implementar** `RajadaDoCliente` e as três trocas no `Responder`. Sem regex: comparação de string e `to_i`.
- [ ] **Passo 4: verificar** — `bundle exec rubocop` nos 4 arquivos → sem ofensas.
- [ ] **Passo 5: commit** — `feat(agentes): a pergunta junta a rajada do cliente e o fim da fala fica previsto`.

---

### Tarefa 6: A fala não se corta depois do 1º pedaço (P3)

**Arquivos:**
- Alterar: `app/jobs/autonomia/agents/operate/chunked_delivery_job.rb:30-33` (`perform`), `:93-99` (`motivo_da_parada`), `:139-152` (`schedule_next`)
- Teste: `spec/jobs/autonomia/agents/operate/chunked_delivery_job_entrega_inteira_spec.rb`

**Interfaces:**
- Consome: `ParidadeDaConversa.entrega_inteira?/em_fila?`, `FalaEmCurso.renovar/soltar`.
- Produz:
  - `motivo_da_parada`: a primeira linha vira `return :turno_mudou unless turno_vale?(conversation, agent_inbox, reply_to_message_id, index)`.
  - privado `turno_vale?(conversation, agent_inbox, reply_to_message_id, index) -> Boolean` = `(index.positive? && ParidadeDaConversa.entrega_inteira?(agent_inbox.agent)) || current_turn?(conversation, reply_to_message_id)`. Elegibilidade, `ja_postado` e `pessoa_respondeu` seguem conferidos em todo pedaço.
  - `schedule_next`: depois de `renovar_o_turno`, `FalaEmCurso.renovar(conversation.id, reply_to_message_id) if ParidadeDaConversa.em_fila?(agent_inbox.agent)`.
  - `perform`: junto de `soltar_o_turno(...) unless @turno_segue`, `FalaEmCurso.soltar(conversation.id, reply_to_message_id)` (sem checar a opção).

- [ ] **Passo 1: escrever o spec que falha** (`:um_turno`, `include_context 'with crm responsible agent'`, `allow(Rails.configuration.dispatcher).to receive(:dispatch)`; `pedacos = [{ 'text' => 'Primeira parte da resposta.', 'type' => 'text', 'delay_ms' => 900 }, { 'text' => 'Segunda parte da resposta.', 'type' => 'text', 'delay_ms' => 900 }]`; `m1` respondida; `m2` nova grava a marca do debounce `pending_message_id = m2.id`)

```ruby
def pedaco!(indice) = described_class.perform_now(conversation.id, vinculo_da_porta.id, m1.id, pedacos, indice, {})

it 'com entrega inteira e fila: o 2º pedaço sai mesmo com mensagem nova' do
  liga!('conversa_entrega_inteira', 'conversa_em_fila')
  pedaco!(1)
  expect(respostas.pluck(:content)).to eq(['Segunda parte da resposta.'])
end
it 'sem a opção: para no 2º pedaço, como hoje' do
  pedaco!(1)
  expect(respostas).to be_empty
end
it 'entrega inteira sem a fila: para (a dependência)' do
  liga!('conversa_entrega_inteira')
  pedaco!(1)
  expect(respostas).to be_empty
end
it 'o 1º pedaço ainda confere o turno' do
  liga!('conversa_entrega_inteira', 'conversa_em_fila')
  pedaco!(0)
  expect(respostas).to be_empty
end
it 'pessoa assumiu: para mesmo com a opção' do
  liga!('conversa_entrega_inteira', 'conversa_em_fila')
  conversation.update!(assignee: admin)
  pedaco!(1)
  expect(respostas).to be_empty
end
it 'cadeia que para solta a fala' do # Review Focus 2
  Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, m1.id)
  pedaco!(1) # para por turno_mudou (sem opção)
  expect(Redis::Alfred.get(Autonomia::Agents::Operate::FalaEmCurso.chave_ocupada(conversation.id))).to be_nil
end
it 'último pedaço postado solta a fala' do
  liga!('conversa_entrega_inteira', 'conversa_em_fila')
  Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, m1.id)
  pedaco!(1)
  expect(Redis::Alfred.get(Autonomia::Agents::Operate::FalaEmCurso.chave_ocupada(conversation.id))).to be_nil
end
it 'pedaço intermediário renova a fala' do
  liga!('conversa_em_fila')
  conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
  Autonomia::Agents::Operate::FalaEmCurso.ocupar(conversation.id, m1.id)
  pedaco!(0)
  expect(Redis::Alfred.ttl(Autonomia::Agents::Operate::FalaEmCurso.chave_ocupada(conversation.id)))
    .to be <= Autonomia::Agents::Operate::TurnoEmCurso::TTL_DA_CADEIA.to_i
end
```

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` no spec.
- [ ] **Passo 3: implementar** as três trocas. Atualizar o comentário de topo do job (guarda TURN-TOKEN): "com `conversa_entrega_inteira`, só o 1º pedaço confere o turno".
- [ ] **Passo 4: verificar** — `bundle exec rubocop` nos 2 arquivos → sem ofensas.
- [ ] **Passo 5: commit** — `feat(agentes): fala em pedaços não se corta depois do primeiro (opção por agente)`.

---

### Tarefa 7: Pausa pós-envio e regra dos 25 s do WhatsApp oficial (P5, ritmo)

**Arquivos:**
- Criar: `app/services/autonomia/agents/operate/ritmo_do_canal.rb`
- Alterar: `app/services/autonomia/agents/operate/responder.rb:452` (`deliver_humanized`)
- Teste: `spec/services/autonomia/agents/operate/ritmo_do_canal_spec.rb`, `spec/services/autonomia/agents/operate/responder_ritmo_do_canal_spec.rb`

**Interfaces:**
- Consome: pedaços `Array<Hash>` do `ReplyChunker`/`Interacao.nos_pedacos` (`'delay_ms'` = espera **antes** de postar o pedaço), `ParidadeDaConversa.ritmo_do_canal?`.
- Produz (módulo `Autonomia::Agents::Operate::RitmoDoCanal`, `module_function`):
  - `JANELA_DO_DIGITANDO_MS = 25_000`, `FRACAO_DA_ESPERA = 5`
  - `pausa_depois_do_envio(espera_ms) -> Integer` — `≤ 3_000` → `1_000`; `≤ 15_000` → `2_000`; acima → `3_000` (do fluxo externo, `Wait1`)
  - `aplicar(chunks, whatsapp_oficial:) -> Array<Hash>` — `w[i]` = `delay_ms` original, `acum[i] = Σ w[0..i]`. Espera do pedaço `i`: oficial e `i > 0` e `acum[i] / 25_000 == (acum[i] − w[i]) / 25_000` (divisão inteira) → `(w[i] / 5.0).round`; senão `w[i]`. Novo `delay_ms[i]` = espera + (`i > 0` ? `pausa_depois_do_envio(w[i − 1])` : 0). Devolve hashes novos (`merge`); demais chaves intactas; não muta a entrada.
  - `whatsapp_oficial?(conversation) -> Boolean` — `Channel::Whatsapp` com `provider == 'whatsapp_cloud'`
  - `para(chunks, agent:, conversation:) -> Array<Hash>` — sem `ritmo_do_canal?(agent)`, devolve `chunks` como vieram; com, `aplicar(chunks, whatsapp_oficial: whatsapp_oficial?(conversation))`.
- `Responder#deliver_humanized`: `chunks = RitmoDoCanal.para(com_os_cartoes_no_ultimo(chunks), agent: @agent, conversation: @conversation)`.

- [ ] **Passo 1: escrever os specs que falham**

```ruby
let(:pedacos) { [5000, 4000, 9000, 10_000].map { |ms| { 'text' => 'x', 'type' => 'text', 'delay_ms' => ms } } }

it 'WhatsApp oficial: cheia no 1º e ao cruzar 25 s; 1/5 nos demais; mais a pausa' do
  expect(described_class.aplicar(pedacos, whatsapp_oficial: true).pluck('delay_ms')).to eq([5000, 2800, 3800, 12_000])
end
it 'outros canais: espera cheia mais a pausa' do
  expect(described_class.aplicar(pedacos, whatsapp_oficial: false).pluck('delay_ms')).to eq([5000, 6000, 11_000, 12_000])
end
it 'pausa pós-envio' do
  expect([2500, 3000, 3001, 15_000, 15_001].map { |ms| described_class.pausa_depois_do_envio(ms) })
    .to eq([1000, 1000, 2000, 2000, 3000])
end
it 'não muta e mantém as outras chaves' do
  com_marca = [pedacos.first.merge('marca' => { 'k' => 1 })] + pedacos.drop(1)
  saida = described_class.aplicar(com_marca, whatsapp_oficial: false)
  expect(com_marca.pluck('delay_ms')).to eq([5000, 4000, 9000, 10_000])
  expect(saida.first['marca']).to eq('k' => 1)
end
it 'sem a opção, os pedaços voltam iguais' do
  expect(described_class.para(pedacos, agent: Autonomia::Agents::Agent.new(config: {}), conversation: nil)).to equal(pedacos)
end
```

`responder_ritmo_do_canal_spec.rb` (`:um_turno`, contexto compartilhado, `AI_HUMANIZE_DELIVERY: 'true'`; `allow(Autonomia::Agents::Operate::ReplyChunker).to receive(:call).and_return([{ 'text' => 'A' * 70, 'type' => 'text', 'delay_ms' => 5000 }, { 'text' => 'B' * 70, 'type' => 'text', 'delay_ms' => 4000 }])`):

```ruby
def pedacos_agendados = ActiveJob::Arguments.deserialize(jobs_de(UmTurnoHelper::CHUNK_JOB).sole[:args])[3]

it 'com a opção, o 2º pedaço espera a pausa a mais (caixa que não é WhatsApp oficial)' do
  liga!('conversa_ritmo_do_canal')
  gatilho(m = cliente_escreve('oi')); rodar_turno!
  expect(pedacos_agendados.pluck('delay_ms')).to eq([5000, 6000])
end
it 'sem a opção, como hoje' do
  gatilho(cliente_escreve('oi')); rodar_turno!
  expect(pedacos_agendados.pluck('delay_ms')).to eq([5000, 4000])
end
```

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` nos specs.
- [ ] **Passo 3: implementar** `RitmoDoCanal` e a linha do `Responder`. O `ChunkedDeliveryJob` não muda: ele já lê `delay_ms` de cada pedaço e prende em 0,1–30 s.
- [ ] **Passo 4: verificar** — `bundle exec rubocop` nos 4 arquivos → sem ofensas.
- [ ] **Passo 5: commit** — `feat(agentes): pausa depois de cada pedaço e ritmo do digitando no WhatsApp oficial`.

---

### Tarefa 8: "Digitando" no WAHA (P5, canal)

**Arquivos:**
- Alterar: `app/services/autonomia/agents/operate/typing_indicator.rb:36-42` (`dispatch`) e o comentário de topo (linhas 9-16)
- Teste: `spec/services/autonomia/agents/operate/typing_indicator_spec.rb` (contexto WAHA, linhas 53-74)

**Interfaces:**
- Consome: `ParidadeDaConversa.ritmo_do_canal?`, `Conversations::ChannelTyping::Deliverer` (já cobre WAHA: `supports?` exige `waha_provider?`, `Waha::Config.enabled?` e `AI_HUMANIZE_CHANNEL_TYPING`; `on` → `start_typing`, `off` → `stop_typing`; nunca levanta).
- Produz: em `dispatch`, `Channel::Api` passa a fazer `web_widget_typing(typing_on)` e, quando `ParidadeDaConversa.ritmo_do_canal?(@agent_inbox.try(:agent))`, também `channel_typing(typing_on)`. `Channel::WebWidget` fica como está. (`try`: o spec existente usa um `Struct` só com `agent_bot`.)

- [ ] **Passo 1: escrever o spec que falha** (no contexto WAHA existente)

```ruby
it 'com conversa_ritmo_do_canal, liga e desliga o digitando no WAHA e mantém o evento do painel' do
  agente = instance_double(Autonomia::Agents::Agent, config: { 'conversa_ritmo_do_canal' => true })
  vinculo = Struct.new(:agent_bot, :agent).new(agent_bot, agente)
  waha = instance_double(Waha::Client, start_typing: {}, stop_typing: {})
  allow(Waha::Client).to receive(:new).and_return(waha)
  allow(Rails.configuration.dispatcher).to receive(:dispatch)

  with_modified_env WAHA_API_URL: 'https://waha.example', WAHA_API_KEY: 'waha-key' do
    described_class.new(conversation: conversation, agent_inbox: vinculo).on
    described_class.new(conversation: conversation, agent_inbox: vinculo).off
  end

  expect(waha).to have_received(:start_typing).with(session: '5511888880000', chat_id: '5511999990000@c.us')
  expect(waha).to have_received(:stop_typing).with(session: '5511888880000', chat_id: '5511999990000@c.us')
  expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(Conversation::CONVERSATION_TYPING_ON, any_args).once
end

it 'com a opção e AI_HUMANIZE_CHANNEL_TYPING=false, não chama o WAHA' do
  # mesmo arranjo, com_modified_env AI_HUMANIZE_CHANNEL_TYPING: 'false' => expect(Waha::Client).not_to have_received(:new)
end
```

O teste existente "keeps using the panel event and never calls the WAHA engine" continua passando sem mudança (sem a opção).

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` no spec.
- [ ] **Passo 3: implementar** a troca no `dispatch` e a linha do comentário de topo ("WhatsApp API (WAHA): o evento do painel e, com `conversa_ritmo_do_canal`, o digitando no WAHA").
- [ ] **Passo 4: verificar** — `bundle exec rubocop` nos 2 arquivos → sem ofensas.
- [ ] **Passo 5: commit** — `feat(agentes): digitando no WAHA para o agente com ritmo do canal`.

---

### Tarefa 9: Data e hora no fuso da conta em todo turno (P6)

**Decisão (o desenho não fixou):** **sem opção por agente**, ligada para todos, com chave de instalação para desligar sem deploy (`AI_AGENT_DATA_DO_TURNO`, ausente = ligada, padrão dos outros kill-switches do `Config`). Justificativa: é uma lacuna real (o modelo não sabe que dia é e erra "amanhã", "sexta", datas sem ano), o item vai depois do histórico e não quebra o cache do prompt (instruções + histórico continuam o prefixo), e não mexe em fluxo de entrega. **Fora a Lia** (`insurance_quote`): regra da casa de não tocar o comportamento dela; segue o mesmo corte que o `segmento_message` já faz no `PromptBuilder`. O `$dataDeHoje` da instrução do agente contratado é do PR seguinte.

**Formato exato** — item `developer`, imediatamente antes da pergunta do cliente (depois da memória; o lembrete do fim, quando existe, continua depois da pergunta):

```text
Agora: terça-feira, 24/11/2026 14:35 (fuso da conta: America/Sao_Paulo).
```

Dia da semana em pt-BR por tabela (`DIAS_DA_SEMANA[agora.wday]`, sem `strftime('%A')`, que sai em inglês); data `%d/%m/%Y %H:%M`; fuso de `Crm::Timezone::Resolver.new(account: account).name_or_default` (o mesmo da memória do turno).

**Arquivos:**
- Criar: `app/services/autonomia/agents/prompt_parts/agora.rb`
- Alterar: `app/services/autonomia/agents/config.rb` (depois de `prompt_v2_enabled?`, ~linha 256), `app/services/autonomia/agents/prompt_builder.rb:337-340` (`fim_da_entrada`), `docs/agentes/paridade-da-conversa.md` (linha P6)
- Teste: `spec/services/autonomia/agents/prompt_parts/agora_spec.rb`, `spec/services/autonomia/agents/prompt_builder_agora_spec.rb`
- Atualizar specs que fixam o `input` inteiro (lista no Passo 4)

**Interfaces:**
- Produz:
  - `Autonomia::Agents::PromptParts::Agora` (`module_function`): `DIAS_DA_SEMANA = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze`, `FORMATO = '%d/%m/%Y %H:%M'`, `texto(account, agora: Time.current) -> String`.
  - `Autonomia::Agents::Config.data_do_turno_enabled? -> Boolean` (`ENV.fetch('AI_AGENT_DATA_DO_TURNO', true)`).
  - `PromptBuilder#fim_da_entrada` → `[agora_message, user_message(@query), lembrete].compact`; privado `agora_message -> Hash | nil` (nil com a ENV desligada ou `@agent.agent_type == 'insurance_quote'`).

- [ ] **Passo 1: escrever os specs que falham**

```ruby
# agora_spec.rb
it 'no fuso da conta' do
  travel_to Time.utc(2026, 11, 24, 17, 35) do
    conta = create(:account, custom_attributes: { 'timezone' => 'America/Sao_Paulo' })
    expect(described_class.texto(conta)).to eq('Agora: terça-feira, 24/11/2026 14:35 (fuso da conta: America/Sao_Paulo).')
  end
end
it 'outro fuso' do
  travel_to Time.utc(2026, 11, 24, 17, 35) do
    conta = create(:account, custom_attributes: { 'timezone' => 'Europe/Lisbon' })
    expect(described_class.texto(conta)).to eq('Agora: terça-feira, 24/11/2026 17:35 (fuso da conta: Europe/Lisbon).')
  end
end
it 'domingo e virada de dia pelo fuso' do
  travel_to Time.utc(2026, 11, 30, 2, 10) do
    conta = create(:account, custom_attributes: { 'timezone' => 'America/Sao_Paulo' })
    expect(described_class.texto(conta)).to eq('Agora: domingo, 29/11/2026 23:10 (fuso da conta: America/Sao_Paulo).')
  end
end
it 'sem conta: o fuso padrão' do
  expect(described_class.texto(nil)).to include("(fuso da conta: #{Crm::Timezone::Resolver.default_timezone}).")
end

# prompt_builder_agora_spec.rb (freeze_time)
it 'o item Agora vem logo antes da pergunta' do
  input = described_class.new(agent: agente, query: 'Tudo bem?').input
  expect(input[-2]).to eq(role: 'developer', content: [{ type: 'input_text', text: Autonomia::Agents::PromptParts::Agora.texto(agente.account) }])
  expect(input.last[:content].first[:text]).to eq('Tudo bem?')
end
it 'a Lia não recebe' do
  lia = Autonomia::Agents::Agent.new(account: agente.account, agent_type: 'insurance_quote', name: 'Lia')
  expect(textos_de(described_class.new(agent: lia, query: 'oi').input)).not_to include(a_string_starting_with('Agora:'))
end
it 'com AI_AGENT_DATA_DO_TURNO=false, não entra' do
  with_modified_env(AI_AGENT_DATA_DO_TURNO: 'false') do
    expect(textos_de(described_class.new(agent: agente, query: 'oi').input)).not_to include(a_string_starting_with('Agora:'))
  end
end
```

(Se `Agent.new(agent_type: 'insurance_quote')` sem escolhas fizer `instrucao_do_sistema` levantar ao montar só o `input`, dublar `instrucao_do_sistema`; o `input` não a lê.)

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` nos specs.
- [ ] **Passo 3: implementar** `Agora`, `Config.data_do_turno_enabled?` (comentário no padrão dos kill-switches vizinhos) e `fim_da_entrada`/`agora_message`. Atualizar o comentário de `input` ("… + pergunta") para citar o item Agora.
- [ ] **Passo 4: atualizar os specs existentes que fixam o `input` inteiro.** O item novo é parte do contrato: a expectativa muda, a ENV não é desligada para esconder. Com `freeze_time` onde se compara texto exato ou dois `input` montados:
  - `spec/services/autonomia/agents/prompt_builder_spec.rb:62,75` — `input[0..-2]` ("tudo menos a query") vira `input[0..-3]`.
  - `spec/services/autonomia/agents/prompt_builder_memoria_spec.rb:27-31` — `['developer', <Agora>]` antes de `['user', 'E a placa?']`; `:53` — `last(2)` vira `last(3)` com o item no meio.
  - `spec/services/autonomia/agents/operate/responder_regra_do_turno_spec.rb:64` — `input[-2]` vira `input[-3]`; `:134-150` — `esperado_de_antes` ganha o item antes de `'Tudo bem?'` e o `insert(2, …)` continua antes dele.
  - `spec/services/autonomia/agents/prompt_builder_usa_o_trecho_spec.rb:127` — envolver em `freeze_time`.
  - Depois, varrer o resto: `rg -n "input(\)|\b)(\.last\(|\[-|\[0\.\.-|\)\.to eq)" spec/services/autonomia spec/jobs/autonomia spec/enterprise` e ler cada acerto; ajustar só os que fixam posição a partir do fim ou o `input` inteiro.
- [ ] **Passo 5: doc** — linha P6 na tabela de `docs/agentes/paridade-da-conversa.md` (ENV, padrão, formato do texto, fora a Lia).
- [ ] **Passo 6: verificar** — `bundle exec rubocop` em todos os arquivos tocados → sem ofensas.
- [ ] **Passo 7: commit** — `feat(agentes): data e hora no fuso da conta em todo turno do agente`.

---

### Tarefa 10: Resposta em voz não leva link (P7)

**Decisão:** a regra vale para **toda** resposta em voz (não só para quem tem a chave nova): link lido em voz não serve ao cliente, e o caminho de fuga é o texto de hoje. "Voz ligada neste agente" é a chave que já existe, `voice_reply: true`, gravada pelo `Contratar` no PR seguinte.

**Arquivos:**
- Alterar: `app/services/autonomia/agents/operate/responder.rb:249-254` (`deliver`) e um privado novo
- Teste: `spec/services/autonomia/agents/operate/responder_voz_sem_link_spec.rb`

**Interfaces:**
- Produz: `deliver` → `return deliver_voice(result) if voice_reply_applies? && !resposta_com_link?(result)`; privado `resposta_com_link?(result) -> Boolean` = texto de `result.reply` em minúsculas inclui `'http://'` ou `'https://'` (método de string, sem regex). A interação de link (`result.interacao`) não conta: ela já sai numa mensagem própria depois do áudio.

- [ ] **Passo 1: escrever o spec que falha** (molde de `responder_interacao_na_voz_spec.rb`: `AI_HUMANIZE_DELIVERY: 'false'`, `allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(true)` e `receive(:synthesize_audio).and_return('OggS-bytes')`)

```ruby
it 'resposta com link sai em texto' do
  responde('Seu link de pagamento: https://pagamento.exemplo.com/?IdCarrinho=123')
  perform
  expect(enviadas.sole.content).to include('https://pagamento.exemplo.com/?IdCarrinho=123')
  expect(enviadas.sole.content_attributes).not_to have_key('autonomia_voice')
end
it 'HTTPS maiúsculo também é link' do
  responde('Acesse HTTPS://exemplo.com')
  perform
  expect(enviadas.sole.content_attributes).not_to have_key('autonomia_voice')
end
it 'sem link segue em áudio' do
  responde('Seu seguro está pronto.')
  perform
  expect(enviadas.sole.content_attributes['autonomia_voice']).to be(true)
end
```

- [ ] **Passo 2: rodar** — não rodar localmente; roda na CI. `bundle exec rubocop` no spec.
- [ ] **Passo 3: implementar** a condição e o privado (comentário: por que a regra existe e que vale para toda voz).
- [ ] **Passo 4: verificar** — `bundle exec rubocop` nos 2 arquivos → sem ofensas.
- [ ] **Passo 5: commit** — `fix(agentes): resposta com link não vira áudio`.

---

### Tarefa 11: Fechamento do PR

- [ ] **Passo 1: lint geral** — `bundle exec rubocop $(git diff --name-only origin/main...HEAD -- '*.rb')` → sem ofensas. Se usar `-a`, ler o `git diff` inteiro do que a ferramenta mudou antes de commitar.
- [ ] **Passo 2: conferir o diff inteiro** — `git diff origin/main...HEAD`: nenhuma chave ligada por padrão, nenhum `agent_type` nas opções, nenhum nome de cliente ou número de conta.
- [ ] **Passo 3: PR** — `gh pr create --repo autonom-ia2/chat --base main`, título `feat(agentes): paridade da conversa (opções por agente)`, corpo no formato do repo (parágrafo de produto, `Refs #3211`, "What changed" curto com a tabela das chaves, o que ficou de fora: P4, o `Contratar` que liga as chaves, o `$dataDeHoje` da instrução). Rodapé de atribuição do PR.
- [ ] **Passo 4: CI** — ler a saída inteira da CI; contagem de exemplos não é resultado.
- [ ] **Passo 5: revisão** — `agentes-ia-refactor-reviewer` no diff (obrigatória: > 30 linhas e mexe no turno). Tratar CRITICAL/HIGH.
- [ ] **Passo 6: Project** — atualizar o card do #3211 no Project Autonom.ia Dev (Status, Próxima ação "pedido de merge pela gestora da fila"). Merge e deploy só pela gestora da fila, com OK do Rodrigo; o testador entra depois do deploy, quando o PR do agente ligar as chaves.

---

## Auto-revisão

**1. Cobertura do desenho (seção 8 e 11):**
- Quem vence a rajada (igual) — sem tarefa, de propósito.
- Quanto espera — P1, Tarefas 3 e 4. Juntar a rajada — P1, Tarefa 5.
- Agente ocupado / fila — P2, Tarefas 2, 3 e 4. Resposta superada descartada sem Fase 2 — Tarefa 4.
- Corte da entrega — P3, Tarefa 6.
- Quebra em balões — mantida (sem P4); nenhuma tarefa mexe no `ReplyChunker`.
- Pausa pós-envio e "digitando" oficial — P5, Tarefa 7. "Digitando" WAHA — P5, Tarefa 8.
- Data e hora — P6, Tarefa 9 (o `$dataDeHoje` da instrução fica no PR do agente, que pode reaproveitar `PromptParts::Agora`).
- Responder em áudio — P7, Tarefa 10 (ligar `voice_reply` é do `Contratar`).
- "Opção ligada vence a Fase 2": `turno_superado?` (Tarefa 4) e o corte do pedaço (Tarefa 6, que nem era da Fase 2). "Sem a opção, nada muda": cada tarefa tem o teste "sem a opção, como hoje".
- "PR próprio, antes do PR do agente" (seção 11): Tarefa 0 abre branch própria a partir da `main`.

**2. Varredura dos passos:** cada passo de código diz arquivo, assinatura e valores (1 s, 180 s, 2 s, 150 s, 160 ms ± 20%, 150 s de teto, 9000 s, 25 s, 1/5, pausas 1/2/3 s, formato do "Agora"). Corpos só onde o algoritmo não se deduz (regra dos 25 s, rajada com pedaços). Sem "tratar casos de borda" solto.

**3. Consistência de nomes:** `ParidadeDaConversa.espera_a_fala?/em_fila?/entrega_inteira?/ritmo_do_canal?`; `FalaEmCurso.ocupar/renovar/soltar/ocupada_por_outro?/prever_fim!/fim_previsto/chave_ocupada/duracao_estimada_ms`; `EsperaDaFala.da_rajada/na_fila?` e constantes `ESPERA_MINIMA/ESPERA_MAXIMA/INTERVALO_DA_FILA/TETO_DA_FILA`; `RajadaDoCliente.mensagens/texto`; `RitmoDoCanal.aplicar/para/pausa_depois_do_envio/whatsapp_oficial?`; `PromptParts::Agora.texto`; `Config.data_do_turno_enabled?`; `Responder#cadeia_agendada?`. Conferidos entre as Tarefas 1–10. A marca do debounce ganha `'espera_ms'` na Tarefa 4 e é lida na Tarefa 3 (a Tarefa 3 monta a marca à mão no spec, então não depende da ordem).

**4. Review Focus:** os cinco têm teste na tarefa dona (1 → Tarefa 3; 2 → Tarefas 4 e 6; 3 → Tarefa 5; 4 → Tarefa 4; 5 → Tarefas 2 e 4). Fora da lista, de propósito: a resposta do evento assíncrono (`EventoJob`/`ResponderAoEvento`) e a da passagem não entram na fila — o agente contratado usa ferramentas síncronas.

**5. Proporção:** o plano descreve 6 arquivos novos pequenos e ~40 linhas em arquivos existentes; o volume está nos testes (assinaturas e asserções), não em corpos de método.
