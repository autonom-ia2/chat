# #436 / PR0 — três bloqueios da revisão independente

Data: 2026-09-16. Escopo: `tmp/email436/pr0-independent-review.md`, código revisado `406ef3a7de` e instruções de `AGENTS.md`. Correções locais, com validação limitada a Ruby puro, sintaxe e lint. Sem declaração de PR pronto ou validação de banco.

## Decisões e alterações

1. **Manutenção:** `RecordInvalid` é isolado dentro da iteração por campanha. O log JSON contém somente evento, ID da campanha e classe da exceção, sem mensagem de validação/endereço. As demais campanhas continuam; recuperação de importações e purga ficam no `ensure` do agendamento. Falhas globais de banco/conexão continuam sendo propagadas depois da tentativa de housekeeping. A lease mantém suas validações; shadow/DNS=false continua fazendo preflight.
2. **Elegibilidade:** `campaign_allowed?` recusa importação ativa em todos os modos. Em enforce, lê candidatos pending não resolvidos em lotes de até 500 e consulta `EmailSuppression.blocking_reasons_for` na conta da campanha. Reutiliza a união autoritativa legado/estado ativo e suas regras de expiração/prioridade, sem helper novo no model, consultas por destinatário, conjunto completo de 50 mil supressões, resets de proteção ou gravações. Quarentena expirada, observação inativa e supressão de outra conta não liberam pending elegíveis; unknown/review/DNS-disabled continuam segurando esses destinatários. O gate de entrega existente continua recusando o endereço bloqueado.
3. **Evidência da importação:** endereço com UTF-8 inválido é rejeitado antes do trim/normalizador. O filtro de linhas vazias preserva strings malformadas, inclusive com nome vazio. Somente `raw_address` com NUL/UTF-8 inválido recebe escapes de bytes e limite de 320 caracteres. A linha segue `invalid_email`, conserva número/contagem e não reverte seus pares válidos. Identidade válida, normalização existente e proteção contra fórmulas no export não foram alteradas.

## Arquivos modificados por esta tarefa

- `app/jobs/email_campaigns/recipient_import_maintenance_job.rb`
- `app/services/email_campaigns/preflight_decision.rb`
- `app/services/email_campaigns/recipient_importer.rb`
- `spec/jobs/email_campaigns/recipient_import_maintenance_job_spec.rb` (novo)
- `spec/services/email_campaigns/preflight_decision_suppression_spec.rb` (novo)
- `spec/services/email_campaigns/recipient_importer_encoding_spec.rb` (novo)
- `spec/pure/email_campaigns/pr0_review_gates_test.rb` (novo)
- `spec/pure/email_campaigns/recipient_import_encoding_test.rb` (novo)
- `docs/email-campaigns/hygiene.md` (somente seções relacionadas)
- `docs/audit/436-pr0-review-fixes.md` (este registro)

`preflight_lease.rb`, modelos de supressão, engines de entrega, specs existentes, schema, migrations e configuração de CI não foram modificados. Busca pelos componentes correspondentes em `enterprise/` não encontrou override a ajustar.

## Validação executada

Ruby 3.4.4 via `eval "$(rbenv init -)"`. Comandos `bundle exec` usaram dependências já instaladas, sem instalação nem boot de Rails. Os testes puros desativam plugins de Minitest e usam somente dados sintéticos; a persistência da importação é simulada com rollback em caso de texto não persistível. ActiveSupport é carregado para os métodos Ruby usados pelo código, sem carregar ActiveRecord/Rails.

| Comando | Resultado |
| --- | --- |
| `bundle exec ruby spec/pure/email_campaigns/pr0_review_gates_test.rb` | 5 testes, 14 assertions; zero falhas/erros/skips |
| `bundle exec ruby spec/pure/email_campaigns/recipient_import_encoding_test.rb` | 2 testes, 9 assertions; zero falhas/erros/skips |
| `bundle exec ruby spec/pure/email_campaigns/hygiene_test.rb` | 13 testes, 120 assertions; zero falhas/erros/skips |
| `bundle exec ruby spec/pure/email_campaigns/preflight_batch_test.rb` | 4 testes, 50.506 assertions; zero falhas/erros/skips |
| `ruby -c` nos oito arquivos Ruby listados acima | 8 × `Syntax OK` |
| `RUBOCOP_CACHE_ROOT=/tmp/email436-review-rubocop bundle exec rubocop --no-server --cache false` com os oito arquivos Ruby explícitos | 8 arquivos, zero offenses; depois do ajuste final do filtro de linhas, os três arquivos afetados também passaram |

Primeira tentativa de RuboCop encontrou `EPERM` no cache padrão fora da área gravável; a tentativa com `--server=false` foi rejeitada pela CLI. Resolvido com cache temporário e `--no-server`. O primeiro teste puro da manutenção encontrou duração Integer no double; corrigido para `10.minutes`/`1.day`, sem alterar ou enfraquecer assertions. Ajustes de estilo foram restritos aos oito arquivos Ruby desta tarefa.

### Contraprova no código antigo

Leitura somente de objetos Git: `git show 406ef3a7de:<arquivo>` para os três arquivos de produção. Cópias em `/tmp/email436-review-before-k2z5tn7w`, com os mesmos testes novos e dependências locais de parser/normalizador, sem escrever no Git ou substituir código do checkout.

- `bundle exec ruby /tmp/email436-review-before-k2z5tn7w/spec/pure/email_campaigns/pr0_review_gates_test.rb -n '/invalid_campaign|blocked_pending_batches/'`: 2 testes; 1 erro `ActiveRecord::RecordInvalid` e 1 falha por `campaign_allowed? == false` apesar de todos os candidatos bloqueados.
- `bundle exec ruby /tmp/email436-review-before-k2z5tn7w/spec/pure/email_campaigns/recipient_import_encoding_test.rb`: 2 testes; 2 erros esperados. NUL rejeitado pelo simulador de persistência (`unpersistable text`); UTF-8 inválido falha no trim, inclusive antes de classificar a linha quando o nome está vazio. Ambos passam com o código corrigido.

## Handoff ao pai

Os três specs Rails novos estão escritos e passaram sintaxe/lint, **não foram executados**. Cobrem FK real de inbox excluída, continuidade de enqueue/recovery/purge, propagação de falha global, opt-out posterior com peer valid/fresh e gate bloqueado, quarentena ativa/expirada, legado após expiração, estado forte novo sem legado, observação inativa, isolamento por conta, importação ativa em todos os modos, holds de preflight, lotes 500+1 e persistência de NUL/UTF-8 inválido com outra linha válida.

SQL/TTL/FK e commits PostgreSQL exigem execução pelo pai. As simulações puras não comprovam banco nem entrega real. Despacho real com conexões/transações distintas, aceite e opt-out/cancelamento entre claim/dispatch e preservação do recibo continuam na integração PR1 do pai. Nenhum engine de entrega foi tocado.

Sem execução de Rails/RSpec/DB/AWS/SSH/SMTP/rede, leitura de env real, instalação, writes Git, CI remoto ou produção. Issue/branch/PR/Project/review/approval/merge e plano de deploy/rollback continuam sob responsabilidade do pai.

## Gate funcional do integrador

Após os três consertos, a mesma seleção do CI (incluindo os novos arquivos rastreados) passou em PostgreSQL/Redis exclusivos locais, com `RAILS_ENV=test`, credenciais herdadas removidas, metadados AWS desabilitados e WebMock: **266 exemplos RSpec, 0 falhas**. Existe **1 pending preexistente** em `Account has_many autonomia_account_links`, já marcado como quarentena na base; não foi criado nem alterado por esta entrega. Todos os testes novos executaram.

Os quatro arquivos puros passaram: **24 testes, 50.649 asserções, 0 falhas/erros/skips**. RuboCop cumulativo dos arquivos Ruby alterados terminou sem infrações. Logs locais: `tmp/email436/pr0-reviewed-rspec.json`, `pr0-reviewed-rspec.log`, `pr0-reviewed-static.log`. O CI remoto será conferido no SHA publicado; o primeiro run não chegou aos testes por opção CLI incompatível e esse erro foi corrigido preservando o gate contra zero exemplos. Nenhum acesso ou mutação de produção, envio real, merge ou deploy.
