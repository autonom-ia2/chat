# Loja E2: testes locais em 13/10/2026

## Escopo e isolamento

Autorizacao recebida para preparar Ruby e banco de testes neste Mac. Branch local
`codex/store-checkout-activation`; sem commit, push, PR, deploy ou acesso a producao.

- Ruby 3.4.4 e Bundler 2.5.16, conforme o lockfile, sem alterar o Ruby do sistema
  nem arquivos de inicializacao do shell.
- PostgreSQL 17 em `127.0.0.1:55439`, banco vazio inicial
  `chatwoot_store_e2_test`, com dados exclusivamente ficticios.
- PostgreSQL limitado a 12 conexoes, shared_buffers de 32 MB, work_mem de 2 MB.
- Redis de teste em `127.0.0.1:6397`, sem persistencia, limitado a 32 MB.
- Launcher local ignorado pelo Git em `.codex/local-test/run.mjs`: ambiente
  construido por allowlist, `RAILS_ENV=test`, sem credenciais herdadas.
- Dotenv restrito a arquivo local vazio; WebMock bloqueia HTTP externo inclusive
  no carregamento do Rails e nas tarefas de banco.
- Nenhum RDS, EC2, Auth, gateway de pagamento ou Financeiro real foi acessado.

## Resultados confirmados

| Verificacao | Resultado |
| --- | --- |
| Specs Rails da API, callback, ativacao e acesso | 38 exemplos, 0 falhas |
| Specs isolados dos contratos financeiros | 90 exemplos, 0 falhas |
| Specs JS/Vue de catalogo, publicacao, rotas e recuperacao | 29 testes, 0 falhas |
| i18n do fork | 15 catalogos; 21420 mensagens; en/pt_BR cobertos |
| Migration E2 | aplicada, revertida e reaplicada no banco local |
| Schema gerado | 4 tabelas novas e 5 FKs; nenhuma mudanca fora da loja |
| `git diff --check` | aprovado |

Comandos de verificacao Rails usam o launcher isolado:

```text
node .codex/local-test/run.mjs bundle exec rake db:schema:load
node .codex/local-test/run.mjs bundle exec rake db:migrate
node .codex/local-test/run.mjs bundle exec rake db:migrate:down VERSION=20261013140000
node .codex/local-test/run.mjs bundle exec rake db:migrate
node .codex/local-test/run.mjs bundle exec rspec spec/requests/api/v1/accounts/autonomia/store_spec.rb spec/requests/api/v1/accounts/autonomia/store_customer_spec.rb spec/requests/webhooks/financial_store_spec.rb spec/services/autonomia/store --seed 42 --format progress
node .codex/local-test/run.mjs bundle exec rspec --options /dev/null spec/contracts/autonomia/financial --seed 42 --format progress
```

A ultima rodada Rails levou 5,71 segundos de tempo total. `/usr/bin/time -l`
registrou maximum resident set size de 427032576 bytes, aproximadamente 407 MiB,
para o comando. Esta medida nao representa memoria total do Mac nem consumo
de producao. As suites foram executadas sem paralelismo.

## Falhas encontradas e corrigidas

1. Ruby 3 separa keyword arguments e hash posicional: chamadas de `checkpoint!`
   agora passam explicitamente o hash exigido pelo metodo.
2. A consulta de acesso fazia pluck de JSON de uma tabela associada sem usar o
   tipo do model correspondente. Agora parte de Entitlement e usa seu atributo
   JSON tipado, mantendo uma unica consulta e o isolamento por namespace.
3. O controller de compra herdava o wrapper JSON `store` e rejeitava corpos
   validos como campo desconhecido. O novo controller aceita somente o contrato
   plano, com `wrap_parameters false`, sem flexibilizar os campos permitidos.
4. A negativa de acesso exclusiva da loja levantava Pundit e o handler global
   convertia em 401. O gate SuperAdmin da loja retorna 403 explicitamente, antes
   de acessar Auth/Financeiro; nenhum handler global foi modificado.

Os testes cobrem reuso de intencao apos resposta perdida, bloqueio de compras
concorrentes no frontend, reserve/commit/confirmacao, cancelamento durante
reserva, lease concorrente, revogacao fora de ordem, direitos manuais preservados,
isolamento de conta/namespace e assinatura/deduplicacao do callback.

## Limites desta evidencia

- O Financeiro e o Auth foram simulados nos testes do Chatwoot. Pagamento,
  capacidade real no Financeiro e homologacao ponta a ponta seguem pendentes.
- Nao houve nova rodada de build completo nem validacao visual E2 nesta etapa.
- RuboCop foi executado e encontrou pendencias de formato/complexidade no codigo
  local novo. Esta etapa nao declara o lint Ruby aprovado nem E2 pronta para PR.
- Os avisos preexistentes de enums/Rack e de source map/i18n do Vue nao impediram
  as suites; nao foram feitas atualizacoes alheias a loja para remove-los.
- PostgreSQL e Redis de teste sao desligados ao encerrar a rodada, sem servicos
  automaticos de login. Runtime e dados ficticios ficam locais para reutilizacao.

## Proximo gate

Concluir revisao/lint e homologacao integrada de E2 antes de publicar a PR, conforme
a regra de manter o desenvolvimento local ate o final do fluxo aprovado.
