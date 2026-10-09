# B1 — revisão independente de código: runtime e permissões

Issue #1120. Revisão normal independente, técnica e de segurança, feita sobre a
worktree `docs/agentes-ia-prd`, sem editar código de produto, sem executar RSpec,
serviços, banco, M2/M4 ou produção. Não reviso aqui o BE-19/BE-31 que escrevi;
o foco é BE-10/20, BE-14/15/21/25.

## Base e método

- baseline de referência do desenho: `6242e31695fd1c6b8b088f2fcb819c027fc5083c`;
  ele é um snapshot fixo e não é uma afirmação sobre o `origin/main` atual;
- código/documentação lidos na revisão: `docs/agentes-ia-redesign/design/B1.md`
  (SHA-256 `80973db6af09806ab695e13bc46aed416d9396491c8d82367fa434ec887e8760`),
  PRD e o inventário de 47 arquivos em
  `/tmp/chat2you-agentes-b1-review-files.json` (fingerprint
  `7aaa8c39a9a8a0980fed0c838f9492964664e1192b8ce546efd8d1962c71e119`);
- rastreei cada porta no caminho controller → guarda → relação/claim → escrita ou
  leitor, conferindo também OSS/Enterprise e os casos locais existentes.

## Achados

### B1-RUN-01 — P1 — o reaper ainda tem uma janela entre a última prova e o arquivamento

**Causa.** O job usa o lock da linha do agente, mas a entrada do dono na thread
usa outro domínio de lock.

**Prova.** Em
`app/jobs/autonomia/agents/reap_stale_drafts_job.rb:35-40`,
`reap_if_still_stale` faz `agent.with_lock`, consulta o predicado em
`stale_drafts(cutoff)` e, logo depois, chama `SoftDelete`. Já
`app/models/autonomia/agents/build_thread.rb:192-209` implementa
`append_message!` com `update_all` somente na linha da thread; não adquire o
lock do agente nem exige que o predicado permaneça verdadeiro no mesmo domínio
de concorrência.

Uma interlevação possível é: (1) o reaper adquire o agente e confirma que não
há `role: 'user'`; (2) `POST .../messages` grava uma mensagem do dono pela
atualização direta da thread; (3) o reaper arquiva o agente. O novo turno já
existe, mas o agente passa a ficar fora de `Agent.kept` e seus vínculos podem
ser liberados. Isso contradiz BE-14, que protege qualquer resposta do usuário.
O spec atual em `spec/jobs/autonomia/agents/reap_stale_drafts_job_spec.rb:71-84`
prova apenas o estado sem concorrência e não fecha essa interlevação.

**Correção mínima.** Fazer o append de uma thread já ligada ao agente e a
checagem final do reaper compartilharem o mesmo lock/ordem de transação (sem
mudar o caminho de thread ainda sem agente), e acrescentar um caso concorrente
que só permita o soft delete quando a confirmação e o arquivamento precederem
o commit da mensagem. O requisito é impedir que um append de usuário confirme
depois da última checagem e ainda assim perca para o arquivamento.

### B1-RUN-02 — P2 — algumas recusas públicas ainda saem sem `code` estável e sem localização

**Causa.** O helper agora aceita `code`, mas há portas do conjunto B1 que ainda
chamam o helper apenas com texto ou devolvem diretamente a mensagem de uma
exceção.

**Prova.**

- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:34-38`
  captura enum inválido e responde somente `{ error: error.message }`. O
  caminho é alcançável pelos enums permitidos em
  `app/controllers/api/v1/accounts/autonomia/agents_controller.rb:177-184`
  (`agent_type`, `mode`, `status` e `actuation`). O cliente recebe texto bruto
  em inglês, sem `code` e sem mensagem localizada.
- `app/controllers/api/v1/accounts/autonomia/agents/analytics_controller.rb:15-17`
  responde `unknown metric` sem `code` nem catálogo pt-BR quando a métrica não
  é reconhecida.
- `app/controllers/api/v1/accounts/autonomia/agents/faq_suggestions_controller.rb:24-29,36-37`
  responde `not_pending` e `embedding_failed` sem `code`, e usa
  `e.record.errors.full_messages.to_sentence` diretamente no corpo para
  `RecordInvalid`. A permissão do índice está correta, mas esses são os
  caminhos de erro das ações de revisão.

O contrato de `design/B1.md §3.1` exige `{ error, code }` nas chamadas que
entram no B1, e o PRD §7.1/BE-10 exige mensagem localizada com código estável;
manter o campo `error` legado não exige manter o texto cru.

**Correção mínima.** Para cada caminho, escolher os códigos já aprovados no
contrato e adicionar os pares en/pt_BR; preservar `error` para clientes
antigos, mas gerar sua mensagem pelo catálogo. Para validação de FAQ, usar um
erro estável sem despejar a frase bruta do model. Cobrir enum inválido,
métrica desconhecida, sugestão já revisada, falha de embedding e falha de
validação em request specs.

### B1-RUN-03 — P2 — o prazo real do reaper não chega à API

**Causa.** A leitura do prazo existe apenas dentro do job e não há campo
derivado para a tela.

**Prova.** `app/jobs/autonomia/agents/reap_stale_drafts_job.rb:76-81`
normaliza `AUTONOMIA_DRAFT_REAP_HOURS` com fallback de 48 horas, mas
`app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder:1-45` e
`index.json.jbuilder:1-10` não expõem esse prazo nem um valor equivalente.
Também não há controller/serializer de configuração do reaper. Assim, se o
ENV for alterado, a lista não consegue afirmar `Guardado por N dias` com o
valor efetivo; o comportamento mostrado pode divergir da limpeza executada.
Isso é explícito no PRD §7.1/BE-14, que manda a API expor o prazo configurado.

**Correção mínima.** Expor um único valor normalizado, derivado do mesmo
parser/default do job, no contrato de leitura da lista/rascunho e cobrir o
override de ENV e o fallback. Não duplicar uma segunda regra de parsing.

## Pontos conferidos sem achado

- **BE-10 / Playground, BuildThreads, Channels e Waha:** `message_required`,
  `retry_unavailable`, `build_in_progress`, erros de conexão e os códigos
  Waha têm envelopes estáveis; o Waha mantém `error` legado e não expõe a
  mensagem remota.
- **BE-20:** o extrator de rota aceita somente os sufixos previstos; a chave
  usa conta canônica + SHA-256 da credencial, com precedência do token de API,
  sem UID/IP como identidade. ENV é validado no boot, os buckets do construtor
  são compartilhados e o responder global mantém `rate_limited` +
  `Retry-After`.
- **BE-21:** `BuildThreadsController` executa a permissão `autonomia_manage`
  antes de `fetch_thread`; o escopo mantém conta e agente arquivado fora da
  leitura.
- **BE-25:** `PermissionFilterService` é aplicado antes de `includes`,
  `order` e `limit`; a extensão Enterprise preserva isolamento por conta,
  administrador e funções personalizadas. FAQ index exige `autonomia_manage`.
- **BE-15:** a janela é derivada de `REQUEST_TIMEOUT` e `MAX_RETRIES` do
  cliente real (600 s no baseline atual), e `begin_build!` faz claim atômico
  por status/janela e token.
- **BE-14:** a subconsulta de resposta filtra `autonomia_agent_id IS NOT NULL`,
  portanto não produz `NOT IN` com NULL; a falha restante é a corrida descrita
  em B1-RUN-01.

## Resultado

A revisão normal encontrou **3 achados concretos**: 1 P1 e 2 P2. O relatório
fica parado aqui para a correção consolidada do owner; não fiz nova rodada,
não corrigi os achados e não considero o B1 aprovado.
