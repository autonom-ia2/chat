# B1 — checagem limitada das correções: runtime, erros e prazo

Issue #1120. Checagem independente e limitada aos três achados da revisão normal
`B1-codigo-runtime-permissoes.md`: B1-RUN-01 (concorrência Agent → BuildThread),
B1-RUN-02 (erros estáveis e localização) e B1-RUN-03 (prazo compartilhado).
Não revisei os serviços BE-19/BE-31 sob minha autoria, nem reabri as outras
lentes do B1.

## Base e método

- Worktree: `docs/agentes-ia-prd`.
- Baseline documental: `6242e31695fd1c6b8b088f2fcb819c027fc5083c`; ele continua
  sendo um snapshot fixo, sem afirmar que é o `origin/main` atual.
- O inventário da checagem contém 53 arquivos e tem fingerprint
  `04baa47e5200089e89a17e322769890cc9263aab44f1870bd762c4b35f298738`.
  A conferência local encontrou 53/53 arquivos presentes e 0 divergências de
  SHA-256 antes desta checagem.
- Li o relatório normal, a causa raiz registrada em
  `docs/audit/2026-10-07-agentes-b1-codigo-causa-raiz.md`, o desenho B1, as
  portas de escrita/leitura e os specs correspondentes.
- Não executei RSpec, Vitest, build, serviço, banco, navegador, M2/M4 ou
  produção. Os resultados focados informados no registro de causa raiz
  (180 exemplos Ruby/0 falhas e 43 exemplos JS/0 falhas) são evidência
  anterior fornecida pelo bloco de implementação, não uma execução desta
  checagem.

## B1-RUN-01 — PASS limitado — domínio de lock Agent → BuildThread

O caminho de mensagem de usuário ligado a um agente agora entra em
`BuildThread#append_user_message_with_agent_lock!`
(`app/models/autonomia/agents/build_thread.rb:192-234`). Ele resolve o agente,
adquire `linked_agent.with_lock`, revalida `deleted?` dentro do lock e só então
faz o append atômico no JSONB da thread. O caminho legado de thread ainda sem
agente preserva o append atômico sem lock de agente, como autorizado pela
correção: não existe agente para travar nesse caso.

O reaper usa o mesmo domínio em
`app/jobs/autonomia/agents/reap_stale_drafts_job.rb:33-40`: seleciona candidatos,
adquire `agent.with_lock`, reexecuta `stale_drafts(cutoff).exists?(agent.id)`
dentro do lock e só então chama o soft delete. A proteção de resposta do dono
permanece no predicado em `:70-74`, com filtro de `autonomia_agent_id` não nulo.
Assim, quando o append do dono adquire o agente primeiro, o reaper espera o
commit antes de sua checagem final; quando o reaper vence primeiro, o append
revalida o agente arquivado e não grava mensagem órfã.

O escritor do Builder para agente já existente usa a ordem correta em
`app/models/autonomia/agents/agent.rb:217-246`: `Agent#with_lock` vem antes de
`build_threads...lock.first`. O guard de `processing`, token ativo e thread mais
nova continua dentro da mesma transação, preservando supersede e impedindo que
uma geração antiga aplique config.

`Builder#ensure_agent` (`app/services/autonomia/agents/builder.rb:1390-1412`)
mantém `@thread.with_lock` somente no caso de criação/linkagem em que a thread
ainda não tem agente. Ele revalida token e estado antes de criar o rascunho;
quando o agente já existe, libera esse lock e o fechamento passa por
`Agent#apply_builder_config!`, na ordem Agent → Thread. Não há lock aninhado
Thread → Agent nesse caminho existente. A exceção de criação sem agente está
documentada no desenho e não abre uma inversão entre dois registros existentes.

O spec concorrente dedicado (`spec/jobs/autonomia/agents/reap_stale_drafts_job_concurrency_spec.rb:41-169`)
tem os três casos correspondentes: append antes da checagem final do reaper,
Builder com Agent antes de Thread e thread legada sem agente. O fluxo conserva
token, supersede, histórico e a rejeição de agente arquivado. Não encontrei
residual concreto neste item.

## B1-RUN-02 — PASS limitado — códigos estáveis e mensagens da conta

Os três caminhos apontados pela revisão normal estão fechados:

- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:33-43`
  converte somente o `ArgumentError` de enum em `422` com `code:
  invalid_enum`; outros `ArgumentError` continuam sendo propagados, sem
  mascarar defeito de runtime.
- `app/controllers/api/v1/accounts/autonomia/agents/analytics_controller.rb:47-53`
  usa `unknown_metric` com código estável antes de consultar a relação.
- `app/controllers/api/v1/accounts/autonomia/agents/faq_suggestions_controller.rb:23-61`
  mapeia `not_pending`, `embedding_failed` e `faq_invalid` ao renderer comum;
  a frase de `RecordInvalid` ou do provedor não é devolvida.

Os cinco códigos têm entrada em inglês e pt-BR (`config/locales/en.yml:547-551`
e `config/locales/pt_BR.yml:958-962`). Cada resposta usa `current_account.locale`
e preserva o campo `error` com texto localizado, além do `code`. Os specs
correspondentes verificam o envelope e a tradução para as duas localidades:
`analytics_spec.rb:77-99`, `faq_suggestions_spec.rb:104-153` e
`external_agent_lifecycle_spec.rb:391-416`; o caso de embedding também garante
que o texto bruto do provedor não vaza.

O restante dos envelopes de Channels/Waha foi conferido no bloco normal e não é
reaberto aqui. Não encontrei residual nos três caminhos que originaram
B1-RUN-02.

## B1-RUN-03 — PASS limitado — parser único do prazo e dos limites

`app/services/autonomia/agents/draft_retention.rb:1-11` é o único parser de
`AUTONOMIA_DRAFT_REAP_HOURS`: aceita inteiro positivo e cai no default 48 para
zero, negativo ou valor inválido. `Config.draft_reap_hours`
(`app/services/autonomia/agents/config.rb:6-9`) delega a ele sem copiar a
regra. O reaper lê essa função em
`app/jobs/autonomia/agents/reap_stale_drafts_job.rb:20,76-79` e o serializer
usa a mesma função em
`app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder:23-27`.
Como a lista renderiza esse partial (`index.json.jbuilder:1-3`), o valor efetivo
chega tanto ao detalhe quanto à lista. Os casos de override, zero e valor
inválido estão em `agent_config_exposure_spec.rb:63-94`, e o fallback do job
em `reap_stale_drafts_job_spec.rb:147-160`.

Os limites de IA também têm uma única fonte: `RateLimits::DEFAULTS` e
`RateLimits.values` em `app/services/autonomia/agents/rate_limits.rb:1-14`.
`Config.ai_rate_limits` delega diretamente a esse módulo e o
`config/initializers/rack_attack.rb:116-124` lê o hash uma vez no
`after_initialize` para criar os quatro buckets, preservando a cota comum do
Builder e os limites separados de Testar, Sugerir e Copiar material. A busca
estática não encontrou leitura duplicada desses ENVs fora dos módulos
compartilhados. Os defaults, overrides e rejeição de valores inválidos estão
em `spec/services/autonomia/agents/config_rate_limits_spec.rb:3-27`; a prova
dos buckets e da identidade por conta/credencial está em
`spec/requests/api/v1/accounts/autonomia/agent_ai_rate_limits_spec.rb:1-133`.

Não há segundo parser no frontend nem prazo divergente no payload. Não encontrei
residual concreto neste item.

## Resultado

A checagem limitada B1-RUN-01/02/03 **passa documentalmente, sem residual
concreto**. Isso não é aprovação runtime final, CI final, aceite visual ou
autorização de merge/deploy: a bateria ampla, lint consolidado e os gates de
telas reais continuam sendo evidências separadas e devem ser concluídos pelo
fluxo principal.
