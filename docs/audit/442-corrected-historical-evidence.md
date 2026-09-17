# PR442 — regressões adversariais de evidência corrigida

Data: 2026-09-17. Escopo: correção histórica integrada sobre a cadeia #438–#441 já corrigida. **Sem autorização de merge/deploy.** O parent rebaseou esta PR sobre a UI corrigida, integrou a promoção do registry da PR438 e executou os gates Rails/PostgreSQL em serviços sintéticos loopback, sem credenciais ou destinatários reais.

## Revisão e decisão

Lidos `AGENTS.md`, `Maintenance::Evidence`, `HistoricalProtectionBackfill`, Start/Request, modelo de run, specs históricos/reimport/recovery/concurrency, classificadores, escritor SNS, EmailEvent e registry. A pesquisa no overlay Enterprise não encontrou implementação correspondente de Evidence/backfill.

O caminho concreto de perda de proteção é o retorno antecipado em `SuppressionRegistry#write`: um `unknown_bounce` já registrado em `ses:m1:bounce` faz a chamada posterior retornar duplicata antes de aplicar a evidência forte. Evidence já entrega a chave ao vivo e o motivo corrigido; inventar outra chave na manutenção contornaria a autoridade compartilhada de dedupe. A correção genérica pertence a PR438. Por inspeção, espera-se que os novos casos de promoção exponham essa dependência na base atual; isso não é resultado de execução RSpec.

Não foi encontrado outro defeito comprovado de perda de dados independente do registry em Evidence/event_key. Mantidos sem edição: precedência de `mail.messageId` sobre `recipient.ses_message_id`, fallback durável por ID quando não há chave utilizável, chave de unsubscribe, escopo por conta, classificadores compartilhados, timestamps e metadados limitados. O horizonte é por ID, não snapshot de conteúdo: uma correção posterior ao cursor exige novo pedido, conforme o contrato existente, sem reabrir run terminal ou resetar cursor.

Nenhuma alteração em código de produto, UI, provider core, registry, migrations, schema, configuração ou comportamento genérico. Permanecem os testes existentes de paridade, horizonte/cursor, lotes, atomicidade, leases/fencing e concorrência. Não foram removidas expectativas nem acrescentados skips/pending.

## Regressões acrescentadas

`spec/services/email_campaigns/maintenance/corrected_evidence_spec.rb` define 13 exemplos pela expansão das matrizes, executados no gate integrado:

- Quatro correções do mesmo EmailEvent persistido, com auditoria original `unknown_bounce` em `ses:m1:bounce`: Permanent/General → hard_bounce; Suppressed, OnAccountSuppressionList e OnTenantSuppressionList → provider_suppression. Cada cenário verifica preview sem mutação, mesma classificação em apply, conclusão `completed`, estado ativo, positivo legado, auditoria original intacta, uma única prova de correção com proveniência e reimportação normalizada suprimida sob outro domínio em shadow.
- Para cada correção, replay de worker e Start com a mesma chave deixam run, estado, positivo e auditoria intactos. Novo pedido percorre o evento como duplicata sem promover de novo. Sua fase legada pode adicionar o espelhamento do positivo criado pelo primeiro apply: o teste distingue explicitamente essa prova da correção SES e exige preservação dos registros anteriores.
- Quatro prioridades fortes já presentes — unsubscribe, complaint, manual e hard_bounce — sobrevivem à promoção do mesmo evento desconhecido para prevenção do provedor. Preserva o positivo legado e as duas auditorias anteriores; exige a nova evidência provider uma única vez.
- Complaint já auditado, com o payload persistido corrigido para prevenção OnTenant, conserva a proteção complaint e a auditoria da mesma chave. Reclassificar a evidência não autoriza rebaixar proteção.

O único relaxamento de lint é `RSpec/MultipleExpectations`, justificado no novo arquivo para manter cada fluxo e suas invariantes de persistência/auditoria/replay no mesmo exemplo. Não há stub do registry nem helper alternativo de promoção. Os exemplos exigem o resultado funcional, sem prescrever o formato da chave interna que PR438 escolher para a auditoria de correção.

## Release e runbook

Atualizados `docs/email-campaigns/release-436.md` e `docs/email-campaigns/operations.md`. Os números da release foram rotulados como evidência anterior aos fixes adversariais. Foram definidos como gates obrigatórios e depois executados localmente após os rebases: compatibilidade de locks entre versões implantada/candidata; provider block versus claim nas duas ordens; progresso sob feedback contínuo; renderização HTTP real da importação; ordem de chegada da quarentena; evidência corrigida com mesma chave; denominador misto; erro aninhado na UI. Os resultados finais estão consolidados em `release-436.md`; compatibilidade entre dois workers novos, isoladamente, não comprova deploy misto.

## Validação executada

RuboCop inicial apontou estilo e quantidade de expectativas no novo spec. Ajustes de layout foram limitados a esse arquivo; a exceção de expectativas acima mantém todas as verificações. Validação final, sem autocorreção: **18 files inspected, no offenses detected**, exit 0.

```sh
eval "$(rbenv init - zsh)"
RBENV_VERSION=3.4.4 RUBOCOP_CACHE_ROOT=/private/tmp/email442-corrections-rubocop bundle exec rubocop app/services/email_campaigns/maintenance spec/services/email_campaigns/maintenance --format simple
```

Compilação estática final: **18 Ruby files compiled without execution**, exit 0.

```sh
/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby -e 'files = Dir["{app/services,spec/services}/email_campaigns/maintenance/**/*.rb"].sort; files.each { |path| RubyVM::InstructionSequence.compile_file(path) }; puts "#{files.length} Ruby files compiled without execution"'
```

Nenhum boot Rails, RSpec, banco, rede, AWS, SSH, instalação ou acesso a produção. Git usado somente em leitura (`--no-optional-locks diff --stat` e `ls-files --others`); sem stage/commit/branch/rebase/PR/Project/merge/deploy. Foram alterados apenas os dois documentos acima e acrescentados o novo spec e este registro. Sintaxe e lint não comprovam persistência, callbacks, promoção, renderização ou concorrência.

## Execução integrada pelo parent após os rebases

Ambiente: PostgreSQL17 em `127.0.0.1:15436`, Redis em `127.0.0.1:16436`, `RAILS_ENV=test`, AWS metadata desligada, arquivos de credenciais apontados para `/dev/null`, frontend sintético e sem chamadas reais de e-mail/AWS. Banco de teste recriado por `db:schema:load` antes da validação final.

- manutenção/backfill/HTTP, incluindo os 13 casos de evidência corrigida: **121 exemplos, zero falhas/pending**;
- seletor cumulativo das cinco entregas, com o novo spec incluído: **900 exemplos, zero falhas, um pending preexistente de `Account has_many autonomia_account_links`**, sem pending novo;
- gates puros finais após os contratos de lock/lease: **9 arquivos;57 testes e50.876 asserções, zero falhas/erros/skips**;
- RuboCop cumulativo final: **184 arquivos, zero infrações**. O CI remoto repetirá o gate no SHA publicado.

A suíte cumulativa demonstra a promoção pela mesma chave, prioridade forte, conclusão do run, idempotência e reimportação bloqueada pelo positivo tenant. Ela não equivale a teste de produção, nem autoriza backfill real. Evidências locais: `tmp/email436/pr442-focused.json`, `final-rspec.json`, `final2-pure.log`.
