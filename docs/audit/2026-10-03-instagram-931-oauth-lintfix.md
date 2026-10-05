# #931 — ajuste de lint exclusivo OAUTH

Rodada solicitada pelo coordenador após ruby-lint.log. Sem commit, push, merge, deploy, rede externa ou mudanças em código de outros responsáveis. Relatório da rodada anterior permanece histórico; esta rodada passou a usar o wrapper local limpo explicitamente autorizado pelo coordenador.

## Diff incremental desta rodada

Artefato: `tmp/instagram-931/oauth-lintfix.diff`. Mostra somente a diferença entre o início e o fim desta rodada, não todas as mudanças de #931 nem trabalho de outros autores.

Seis arquivos de código/specs modificados:

1. `app/services/instagram/testers/oauth_binding.rb`: extraiu `valid_context?` privado da expressão de `validate_payload!`, reduzindo a complexidade sem remover validações ou alterar sua ordem.
2. `spec/services/instagram/testers/oauth_binding_spec.rb`: trocou `where.update_all` por `find_by!.update!` para alterar o papel com validações e callbacks reais, mantendo `AccountUser.uncached(dirties: false)`.
3. `spec/controllers/instagram/callbacks_controller_spec.rb`: duas inclusões de shared examples passaram a `it_behaves_like`, mantendo os mesmos casos para legado e seleção.
4. `spec/helpers/instagram/integration_helper_spec.rb`: alinhamento de argumento/hash.
5. `spec/requests/api/v1/accounts/instagram/tester_authorization_spec.rb`: alinhamento de argumento/hash.
6. `spec/services/instagram/testers/selection_spec.rb`: alinhamento de argumento/hash.

Nenhum controller/helper de produto, política, rota, nonce, TTL, refresh, callback Meta, relay, sessão, convite, tracing, runtime, deploy ou frontend foi alterado nesta rodada. Nenhum cop foi desativado, limite relaxado, gate reduzido, exemplo removido ou skip acrescentado.

## Validações preservadas

A fronteira continua exigindo Hash, versão exata, instalação local, conta e ator inteiros positivos, iat/exp inteiros, exp futura, iat não futura, intervalo de 1 até 15 minutos, jti String com 36 caracteres. A única extração agrupa versão/instalação/conta/ator. O teste de seleção/App, a autorização pela política real e o consumo atômico de nonce permanecem iguais.

O caso de cache preserva sua evidência: primeiro observa administrador; altera o banco com update! dentro de uncached(dirties:false); prova que uma leitura comum ainda encontra administrador em cache; finalmente exige forbidden na reconsulta sem cache feita por authorize!. Esse caso passou na suíte real, com validações/callbacks habilitados.

## Execuções e resultados

Ambiente: `tmp/instagram-931/run-local.sh`, ambiente limpo e serviços de teste locais nos endpoints definidos pelo coordenador. Nenhum snapshot paralelo ou caminho alternativo usado. O cache RuboCop ficou explicitamente em tmp/instagram-931 dentro da worktree, sem servidor compartilhado e sem escrita em diretório externo.

Lint executado:

```sh
tmp/instagram-931/run-local.sh env RUBOCOP_CACHE_ROOT="$PWD/tmp/instagram-931/oauth-rubocop-cache" bundle exec rubocop --no-server --cache false app/helpers/instagram/integration_helper.rb app/services/instagram/testers/oauth_binding.rb app/services/instagram/testers/selection.rb app/controllers/api/v1/accounts/instagram/authorizations_controller.rb app/controllers/instagram/callbacks_controller.rb spec/helpers/instagram/integration_helper_spec.rb spec/services/instagram/testers/oauth_binding_spec.rb spec/services/instagram/testers/selection_spec.rb spec/controllers/api/v1/accounts/instagram/authorizations_controller_spec.rb spec/controllers/instagram/callbacks_controller_spec.rb spec/requests/api/v1/accounts/instagram/tester_authorization_spec.rb spec/enterprise/services/instagram/testers/oauth_binding_spec.rb
```

Resultado: **12 files inspected, no offenses detected**, exit 0. Log: `tmp/instagram-931/oauth-lintfix-lint.log`.

Suíte executada:

```sh
tmp/instagram-931/run-local.sh bundle exec rspec spec/helpers/instagram/integration_helper_spec.rb spec/services/instagram/testers/oauth_binding_spec.rb spec/services/instagram/testers/selection_spec.rb spec/controllers/api/v1/accounts/instagram/authorizations_controller_spec.rb spec/controllers/instagram/callbacks_controller_spec.rb spec/requests/api/v1/accounts/instagram/tester_authorization_spec.rb spec/enterprise/services/instagram/testers/oauth_binding_spec.rb --format progress
```

Resultado: **81 examples, 0 failures**, exit 0. Duração: 11,15 s, mais 7,14 s de carregamento. Log completo lido: `tmp/instagram-931/oauth-lintfix-rspec.log`. Avisos de depreciação existentes sobre enums/Rack permaneceram; não alteramos outros escopos para suprimi-los.

`git diff --check` nos seis arquivos modificados: exit 0.

Esta evidência cobre a suíte OAuth indicada, inclusive Enterprise e o cache obsoleto. Não reexecutamos a bateria geral de 439 exemplos nem atribuímos seu resultado a esta rodada. Review independente continua sob responsabilidade do coordenador.
