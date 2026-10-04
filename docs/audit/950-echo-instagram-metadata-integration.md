# Echo — integração de metadados Instagram, 2026-10-04

Escopo: cinco getters de `Instagram::Testers::Configuration` delegam a `Instagram::Automation::Metadata#values`. Registro existente prevalece inclusive vazio/nil; somente ausência permite ENV; leitura sem criar registros ou memoizar valores. O status local já consulta o mesmo serviço e foi preservado. Sem mudança em proxy/secrets/runtime/control/feature; alterações preexistentes preservadas; sem commit/push.

Specs escritos primeiro em `spec/services/instagram/testers/configuration_metadata_spec.rb`: 18 exemplos de precedência, vazio, ausência sem criação, nil, atualização do mesmo leitor, status local e cache direcionado. A limpeza de cache dos próprios exemplos também é direcionada.

Validação:

- `RAILS_ENV=test AWS_EC2_METADATA_DISABLED=true bundle exec rspec tmp/950-implementation/echo_contract_spec.rb --format progress`: RED 16 exemplos/11 falhas; GREEN 16 exemplos/zero falhas. Serviços reais com consulta de registros substituída por doubles, sem PostgreSQL.
- `bundle exec rspec --require ./tmp/950-implementation/gauss-cache-only.rb spec/lib/global_config_spec.rb --example '.clear_cache' --format progress`: cinco exemplos/zero falhas; não valida callbacks de banco.
- `RUBOCOP_CACHE_ROOT="$PWD/tmp/950-implementation/echo-rubocop-cache" bundle exec rubocop --no-server app/services/instagram/testers/configuration.rb spec/services/instagram/testers/configuration_metadata_spec.rb --cache false --format simple`: dois arquivos/zero infrações, sem auto-fix. Ruby inicializado via rbenv.
- `git diff --check` focal: aprovado.
- `bash tmp/950-implementation/run-specs.sh spec/services/instagram/testers/configuration_metadata_spec.rb spec/services/instagram/testers/configuration_spec.rb spec/models/installation_config_spec.rb spec/lib/global_config_spec.rb --format progress`: bloqueado antes dos exemplos por PostgreSQL local de teste, `Operation not permitted` no sandbox. Zero exemplos integrados executados; pendência antes de aprovação/merge.
- `maccluster work plan -- bundle exec rspec ...`: nenhum nó elegível, M2 offline/M4 bundle-deps-missing. Infraestrutura preservada.

Relatório e logs: `tmp/950-implementation/echo-result.md`, `echo-contract-red.log`, `echo-contract-green.log`, `echo-cache.log`, `echo-rubocop-final.log`, `echo-focal-final.log`. Entrega local na branch da Issue #950; PR/Project/merge/deploy não executados, conforme o pedido sem commit/push.
