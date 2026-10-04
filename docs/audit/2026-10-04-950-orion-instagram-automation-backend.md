# #950 — Orion: backend Instagram Automation

Data: 2026-10-04. Branch observada: `feat/950-instagram-admin-panel`. Escopo: rota/controller/services e specs da página Super Admin. Sem commit/push, merge, deploy ou operações de produção.

Specs request/service foram escritos primeiro. Implementação aceita somente os cinco metadados não secretos autorizados, com validação estrita e transação InstallationConfig. Leitura preserva registro vazio e usa ENV apenas na ausência. Status usa fatos locais sanitizados; sessão managed consulta ponteiro e existência/TTL sem abrir payload; sessão ENV permanece unmanaged e presença desconhecida. Health apenas relê; reconnect retorna 503/operator_channel_unavailable e não invalida sessão. Manager/Meta permanecem unknown. Nenhuma alteração de Orion no runtime, flags, view ou i18n. Alterações concorrentes de outros responsáveis foram preservadas.

Validações:

- `maccluster node`: M4. `maccluster work plan -- bundle exec rspec spec/services/instagram/testers/validation_spec.rb`: nenhum nó elegível (M2 offline, M4 bundle-deps-missing).
- `eval "$(rbenv init -)"`, `ruby -v`, `bundle check`: Ruby 3.4.4; dependências locais satisfeitas.
- `bash tmp/950-implementation/run-specs.sh --format progress`: bloqueado antes dos exemplos por conexão PostgreSQL local negada (`Operation not permitted`); banco explicitamente de teste. Tentativa de iniciar PostgreSQL descartável também negada por shmget. Não comprova RED/GREEN integrado.
- `RAILS_ENV=test RACK_ENV=test AWS_EC2_METADATA_DISABLED=true bundle exec rspec tmp/950-implementation/local_contract_spec.rb --format progress`: 14 exemplos executados, zero falhas, armazenamento simulado e sem PostgreSQL. Encontrou proxy sem host lançando AddressFamilyError; correção limitada ao leitor do painel.
- `RAILS_ENV=test RACK_ENV=test AWS_EC2_METADATA_DISABLED=true bundle exec rspec --require ./tmp/950-implementation/load-only.rb --dry-run spec/services/instagram/automation spec/requests/super_admin/instagram_automations_spec.rb --format progress`: 24 exemplos carregados. Helper temporário apenas evita preparação do banco durante dry-run; asserções não executadas.
- `RUBOCOP_CACHE_ROOT="$PWD/tmp/950-implementation/rubocop-cache" bundle exec rubocop --no-server app/controllers/super_admin/instagram_automations_controller.rb app/services/instagram/automation spec/services/instagram/automation spec/requests/super_admin/instagram_automations_spec.rb --cache false --format simple`: 7 arquivos, zero offenses.
- `pnpm guia:build`, `pnpm guia:check`: mapa em dia, 180 fluxos/176 telas, zero sem explicação; sem diff do mapa. Avisos preexistentes de seleção declarada e Browserslist.
- `git diff --check`: aprovado.

Pendente: executar specs de request/persistência em banco e Redis de teste isolados. Contrato e evidências detalhados em `tmp/950-implementation/orion-result.md`. Esta nota não registra dados de clientes, credenciais ou payloads secretos.
