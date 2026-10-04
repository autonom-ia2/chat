# Issue #950 — invalidação targeted e lifecycle de InstallationConfig

Escopo: revisão do diff local em `feat/950-instagram-admin-panel`, após ler `tmp/950-integration/brief.md`. Preservados os trabalhos de outras frentes. Sem commit, PR, merge, deploy, produção, ACL, CONFIG, flush, instalações ou configuração de infraestrutura. PR/Project e integração pertencem ao processo principal, conforme o brief.

## Defeito e correção

O callback local usava `after_commit` com `name`, `name_before_last_save` e `name_in_database`. Em A→B→C no mesmo objeto/transação, o último save deixa apenas B/C nesses atributos; o callback único não inclui A. Confirmado pela leitura do modelo e do Dirty/Transactions do ActiveRecord **7.2.3.1 instalado**. A reprodução funcional permanece bloqueada; não foi declarada uma execução RED bem-sucedida.

`after_save`, `after_destroy` e `after_touch` capturam os nomes de cada escrita em variável local e registram a invalidação na API pública `current_transaction.after_commit`. O lifecycle do ActiveRecord transfere os callbacks de savepoints confirmados ao pai e descarta os de rollback. Não há histórico em ivar para limpar ou vazar para a próxima transação. Redis só é invalidado depois do commit aplicável; não se promete consistência linear entre leituras concorrentes, banco e cache, nem se reescreveu GlobalConfig.

Preservados do diff local: `GlobalConfig.clear_cache(*config_keys)` deduplica nomes, ignora nil e expira somente chaves literais quando há argumentos; `GlobalConfigService.load` invalida somente o nome solicitado. Sem argumentos, a API global continua com o mesmo KEYS do namespace e EXPIRE 0 de cada chave. Não há mudança no TTL de outras chaves no caminho targeted. A pesquisa em `enterprise/` não encontrou override desses três componentes.

## Specs entregues, ainda sem execução funcional

- Modelo: fixtures transacionais desativadas no grupo de lifecycle para testar commits/rollbacks reais; nomes aleatórios e limpeza somente dos nomes gerados. Renames múltiplos com B lido/cacheado durante a transação; destinos com cache de miss; rollback e reutilização da mesma instância; savepoint confirmado/rollback; rename+destroy na mesma transação; create/destroy com rollback; CRUD e destroy com rename não salvo.
- `spec/services/instagram/automation/redis_isolation_spec.rb`: cliente real Redis 5.0.6 com middleware local de gravação que chama `super`, sem substituição de resultados. Usa exclusivamente `TEST_REDIS_URL`, loopback numérico, porta 59511, DB 0, sem auth/query/fragment. Não usa REDIS_URL como fallback. Sem endpoint explícito, os exemplos ficam **pending por infraestrutura ausente**, para não exigir o servidor descartável da #950 em toda suíte comum. Endpoint informado incorretamente, falha de conexão ou falha de asserção são erros reais; não são resgatados/filtrados.
- Redis real: targeted múltiplo/literal/nil; CRUD; A→B→C; rollback sem histórico no objeto; rename+destroy; destroy com rename não salvo; default load criando ou encontrando registro; API global sem argumentos. Sentinelas de GlobalConfig não relacionado, lock, sessão, chave persistente e chave fora de Alfred. Valores e **PEXPIRETIME exato** permanecem iguais, sem tolerância que possa esconder alteração de TTL. Gravação proíbe KEYS/SCAN/FLUSHDB/FLUSHALL em todas as operações targeted. O caso legado verifica o KEYS permitido separadamente.
- Teardown restaura `$alfred` antes do cleanup global da suíte, fecha cliente/pool e deleta apenas chaves/nomes conhecidos e gerados pelo teste. Não encerra o servidor pertencente ao processo principal.

## Validação executada e bloqueios

- `maccluster node`: M4. `maccluster work plan -- bundle exec rspec spec/models/installation_config_spec.rb`: sem nó elegível (M2 offline; M4 bundle-deps-missing). Sem alterar cluster/snapshot ou dependências.
- Ruby via rbenv, versão 3.4.4. `bundle exec rubocop --no-server --cache false` nos três componentes e quatro arquivos de specs: **7 arquivos, zero infrações**. Log `tmp/950-integration/gauss-cache-rubocop.log`.
- `git diff --check`: aprovado. `ruby -c` do modelo e dos dois arquivos de specs alterados/criados nesta revisão: Syntax OK.
- `redis-cli -h 127.0.0.1 -p 59511 PING`: sandbox recusou TCP com **Operation not permitted**. Não houve comando aceito pelo servidor nessa tentativa.
- Antes da correção, `tmp/950-integration/run-local.sh bundle exec rspec spec/models/installation_config_spec.rb --example 'multiple renames' --format progress`: falhou no carregamento de `rails_helper`, ao conectar PostgreSQL loopback **59510**, com **Operation not permitted**. **Zero exemplos executados; um erro fora dos exemplos.** Não é prova RED, nem aprovação. Log `tmp/950-integration/gauss-cache-lifecycle-red.log`.
- Conforme o brief, parei a execução funcional após a recusa. Não contornei o sandbox por outro conector. Nenhum teste de banco foi executado em paralelo, nenhum resultado foi convertido em sucesso e nenhum mock de banco/Redis foi usado para alegar prova funcional.

## Execução serial a cargo do processo principal

O runner existente fixa ambiente limpo, Rails test, PostgreSQL 59510 e TEST_REDIS_URL do Redis exclusivo 59511. Executar um comando de cada vez, sem outra suíte usando esse banco:

```sh
# RED: somente no processo de teste, restaura o callback local defeituoso.
tmp/950-integration/run-local.sh bundle exec rspec \
  --require ./tmp/950-integration/gauss-cache-previous-lifecycle.rb \
  spec/services/instagram/automation/redis_isolation_spec.rb \
  --example 'after A to B to C in one transaction' --format documentation

# Correção e regressões: não filtrar exemplos ou falhas.
tmp/950-integration/run-local.sh bundle exec rspec \
  spec/models/installation_config_spec.rb \
  spec/lib/global_config_spec.rb \
  spec/lib/global_config_service_spec.rb \
  spec/services/instagram/automation/redis_isolation_spec.rb \
  --format documentation
```

O controle negativo é um require temporário ignorado pelo Git: reinstala exatamente o callback reviewed no processo RSpec, sem editar produto, configuração ou dados fora dos próprios exemplos. Espera-se falha do RED por A permanecer cacheado. Ambos os comandos acima **não foram executados aqui**. A revisão ainda depende desses recibos para afirmar reprodução e ausência de regressão funcional.
