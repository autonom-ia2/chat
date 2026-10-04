# #950 — integração operacional Lina (2026-10-04)

Worktree feat/950-instagram-admin-panel, base11b41b1030. Bootstrap privado canônico dos cinco metadados, revision+CASSessionStore sob locksDB, heartbeat observado backend, ator interno e concessão running90s, sucesso só após publicação e CAS, shutdown/lifecycle corrigidos. Não alterados proxy/auth/controller/Metadata; alterações paralelas preservadas.

Evidência detalhada: [LINa-proof.md](../../tmp/950-integration/LINa-proof.md). Contrato coordenado em tmp/950-integration/progress.md e shared-contract.md.

Validação:95 testes Node e29 exemplos Ruby sintéticos aprovados. ESLint8 arquivos, RuboCop7 arquivos, sh -n e git diff --check aprovados. Revisão independente encontrou6 defeitos e confirmou correções. Teste Ruby usa SessionStore real sobre Redis sintético; não comprova Redis/PostgreSQL reais.

Bloqueio: spec local_status carrega rails_helper e sandbox rejeitou PG loopback59510 antes dos exemplos. Coordenador deve executar LocalStatus+SessionStore no slot serial59510/59511 e validar concorrênciaDB. Nenhuma chamada externa/produção, leitura de segredos, DB real, commit, PR/Project, merge ou deploy executada. Aprovação/release e rollback real dependem do coordenador; preservar storage/outcomes/sessão antiga.

Correção posterior ao parecer Atena:3P2 corrigidos (close, Buffers UTF8, reorder/sortwriter);109 Node aprovados; nenhuma execução Rails paralela. Receipts/SHA atuais em tmp/950-integration/lina-atena-*. A aprovação independente da versão anterior não representa aprovação deste diff; parecer Atena renovado pendente pelo parent.
