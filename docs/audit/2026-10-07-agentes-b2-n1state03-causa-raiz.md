# B2 — causa raiz N1STATE03

## Registro antes da correção

O ensaio real do snapshot23 (`20261007-184308-532a5b7b-9803329751-205ae53c`, SHA-256 `9803329751ae3fce6fd8cec442e77faa9170b38434587aac62a8e81438e480ad`) mediu a projeção da lista com o catálogo nativo ativo. A disponibilidade de cada rascunho chama `agent.account` e os gates de seguros chamam `Autonomia::Insurance::Connection.for_account` novamente. O resultado foi nove `SELECT`s para um agente e 47 para vinte agentes, embora os agentes compartilhem a conta e a conexão.

Isso é um N+1 introduzido na integração STATE03. A correção precisa manter a política de cada ferramenta: cada agente continua usando somente seus próprios `ferramentas_nativas`, inclusive a Lia, sem união dos slugs por conta. A leitura em lote pode preparar a disponibilidade por `account_id`, mas deve reutilizar esse resultado apenas durante uma execução de `ListProjection`; não pode criar cache global ou persistente.

## Refinamento antes da correção

A checagem do bloco apontou que os helpers de disponibilidade aceitavam formas heterogêneas (`respond_to?`, objetos ou IDs) sem um chamador de produção que precisasse disso. Essa abstração escondia entradas inválidas e podia transformar ausência de conta em falso silencioso. O contrato será fechado: a projeção passa uma lista de IDs inteiros já deduplicada, e os gates passam a conta real já carregada.

A mesma checagem registrou sete ofensas de `Layout/HashAlignment` em três specs privadas do bloco, no receipt `f49efd6a375c67e27917650318a1db8b0481db9152779979d60a7960ac5e7898`, job `m2-fe6f0614241d4f99b172d448e5caab0a`, inventário de 100 arquivos e 23 ofensas. O ajuste autorizado é somente alinhamento das hashes nas linhas `spec/enterprise/controllers/api/v1/accounts/autonomia_agent_audit_logs_spec.rb:105-107`, `spec/requests/api/v1/accounts/autonomia/agents/message_reports_spec.rb:43-45` e `spec/services/autonomia/agents/analytics_spec.rb:163-165`; não há mudança de expectativa ou comportamento.

## Correção autorizada neste bloco

1. A projeção carregará a associação `account` junto com os agentes e fará uma única leitura de conexões por conta, selecionando somente `id`, `account_id` e `status`. Credenciais e blobs cifrados não entram na consulta.
2. `Connection` fornecerá um contexto temporário, restaurado em `ensure`, para que os dois gates existentes (`InsuranceCapabilities` e `InsuranceQuote`) consultem a disponibilidade já carregada. Fora desse contexto, a chamada original `for_account(account).any?(&:ready?)` permanece intacta.
3. `Registry.for_agent` continuará avaliando os slugs do próprio agente e as políticas atuais de cada ferramenta. Um método de lote apenas repetirá essa política individual dentro do contexto temporário. A projeção guardará o vetor resultante por agente e o entregará ao `TestDigest`, sem alterar o Registry global, o runtime das ferramentas ou os modelos.

## Trace do residual no snapshot24, antes da correção

O caso de vinte agentes do snapshot24 foi executado isoladamente pelo principal apenas para identificar
as tabelas consultadas, sem imprimir SQL, valores, credenciais ou dados de cliente. Foram observados 14
`SELECT`s; os dois extras do bloco N1 são:

- `accounts`, causado pelo `includes(:account)` da projeção;
- `autonomia_insurance_connections`, causado pelo `preload_for_accounts` incondicional, mesmo quando
  nenhum rascunho tinha ferramenta nativa que precisasse de disponibilidade.

Os demais nomes aquecidos foram `autonomia_agents`, attachments/blobs/variant records, `autonomia_agent_inboxes`,
`inboxes`, a leitura da última thread, `autonomia_agent_sources`, `autonomia_agent_knowledge`,
`autonomia_agent_tools` e `autonomia_agent_events`. A causa está restrita às duas leituras acima; a
política por agente e os slugs da Lia permanecem inalterados.

O limite de consultas e a preservação dos slugs individuais serão comprovados pelo snapshot seguinte
coordenado pelo root. Nenhum teste, banco, serviço, build ou ambiente de produção foi executado por esta
sessão.

## Aplicação local após o trace

O ajuste local removeu `includes(:account)` e pré-carrega somente os rascunhos por meio de
`ActiveRecord::Associations::Preloader`, com `available_records: [@account]`. Assim, a associação pertence
à conta já autenticada sem abrir um `SELECT` de contas nem aceitar uma conta de outro escopo.

O preload de `autonomia_insurance_connections` agora só é chamado quando algum rascunho tem um vetor
canônico não vazio em `Agent#ferramentas_nativas`. O contexto temporário e a avaliação individual do
`Registry` permanecem os mesmos; não há união de slugs, cache global ou alteração de política da Lia.

Também foram aplicados somente ajustes de legibilidade no `ListProjection` e alinhamento dos três hashes
dos specs indicados no refinamento. O RuboCop direcionado aos quatro arquivos tocados passou; não houve
execução da suíte, banco, serviço, build ou produção. O snapshot25 coordenado pelo root é a validação
dinâmica pendente.
