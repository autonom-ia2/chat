# #950 — Lina: canal operacional tipado

2026-10-04; M4; branch existente `feat/950-instagram-admin-panel`. AGENTS.md lido. Sem commit/push, alterações de produção, abertura de navegador real ou ações externas.

Controle novo exclusivamente em Redis::Alfred, duas chaves determinísticas `instagram_testers:operator:<session_namespace>:{manager,current}`, TTL explícito 960/3600 segundos. UUID, ação única reconnect, estados queued/running/operator_required/succeeded/failed e transições com WATCH/MULTI. Payload não secreto/allowlisted; nenhuma mudança de Redis global, CoordinationRedis, configuração/TTL de sessões ou invitation outcomes.

Controller responde HTML/JSON; LocalStatus incorpora status sanitizado. Runtime exige envelopes tipados (operador 512 bytes/resposta 1024 bytes). Wrapper inicia waiter após operator_required. Headful somente após solicitação/claim; mesmo perfil, fechamento antes do manager. Primeira publicação bem-sucedida conclui; login/2FA ainda necessário volta à espera por novo pedido, sem loop automático. Nenhuma edição de feature/UI/metadata por Lina.

RED: módulos ausentes antes da implementação; teste comportamental de falha do navegador; controle negativo Ruby em processo isolado ignorando UUID, detectado pelo spec (7 exemplos/1 falha esperada). GREEN: `node --test tests/instagram_testers/{session-manager,runtime-publisher,operator-control,session-observer}.test.mjs` = 81/81; Ruby `spec/services/instagram/automation/{operator_control,session_publisher,reconnect_contract}_spec.rb` = 18 exemplos/0 falhas, sem PostgreSQL e com Redis simulado. RuboCop 9 arquivos/0 offenses; ESLint, sh -n e diff --check aprovados.

Integração Rails bloqueada antes dos exemplos por conexão PostgreSQL local negada (`Operation not permitted`); Redis descartável via Unix socket também negado. Concorrência em Redis real e fluxo ponta a ponta permanecem pendentes; os testes unitários não comprovam operação real. Atualizar Rails/runtime juntos em eventual release; nenhuma ação de instalação/merge/deploy autorizada ou realizada nesta etapa.

Evidência detalhada e comandos: `tmp/950-implementation/lina-result.md`. Sem secrets, credenciais ou dados de clientes nos relatórios.
