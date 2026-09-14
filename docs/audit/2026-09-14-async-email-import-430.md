# Importação assíncrona de destinatários — issue #430

Implementação autorizada após a auditoria #428. Base: `5742de5fcda319c97c21b0fdf7d79b2dd793090d`. Worktree e branch exclusivos; checkout original preservado. Sem alteração em produção, merge, envio de e-mail ou uso de dados de clientes.

## Comportamento

O upload retorna HTTP 202 após persistir o arquivo e uma importação em `queued`. O job na fila `low` lê CSV/XLSX e importa em transação. Estado e resultado ficam persistidos e são retornados junto da campanha. A interface acompanha o estado na lista, nos destinatários e no editor. Mostra contagens finais e erros compreensíveis, sem expor exceções ou conteúdo de linhas.

A campanha não pode ser enviada, agendada, cancelada ou excluída durante a importação. Um bloqueio na campanha serializa admissão e envio; um índice único parcial impede duas importações ativas. O job usa lock de linha NOWAIT para excluir workers concorrentes. Destinatários, contadores e conclusão são confirmados juntos; uma falha desfaz tudo. Nova tentativa usa o arquivo retido, sem duplicação de destinatários.

O importador carrega os e-mails existentes uma vez e grava lotes de 500. Cada registro passa pelas validações de modelo, exceto a consulta de unicidade por linha, substituída pelo conjunto em memória e pelo índice único do banco. Colunas adicionais, normalização e supressões são preservadas. Busca em `enterprise/` não encontrou override do importador/modelo de destinatários/controller.

Maintenance a cada cinco minutos recupera registros sem atualização há dez minutos, sem tomar o lock de um worker vivo. Isso cobre morte do worker e falha entre commit do upload e enqueue. Arquivos têm janela de retenção/retry de 24 horas; maintenance agenda purge dos terminais expirados. Trabalho ainda executando não é interrompido pelo cleanup. Metadados/resultados permanecem, sem conteúdo da planilha.

## Validação local

Ruby 3.4.4, PostgreSQL local, banco exclusivo `chat2you_430_test`, Rails em test, ActiveJob adapter test, armazenamento Disk local e destinatários sintéticos em example.test. Nenhuma credencial real ou infraestrutura externa usada. Interface validada com componentes montados; não se afirma teste visual no navegador ou resultado em produção.

| Verificação | Evidência |
| --- | --- |
| CSV 20.004 linhas | 20.000 importados, 1 duplicado, 2 inválidos, 1 suprimido; 20.001 destinatários persistidos |
| Custo CSV | 1,981 s e 61 consultas SQL, incluindo controle do job e contadores |
| XLSX 20.000 linhas, API real | HTTP 202 em 0,223 s, antes de parsing/gravação de destinatários |
| Worker XLSX | 4,135 s, 60 consultas SQL; contagens verificadas |
| Releitura por outro cliente HTTP | Estado completed e resultado persistentes |
| Falha injetada após inserts | Zero destinatários novos; estado failed; erro sanitizado |
| Retry | Completa sem duplicar nem inflar contadores |
| Worker duplicado | Mantém resultado já confirmado; NOWAIT impede concorrência |
| Morte real do worker | Processo Ruby separado recebeu SIGKILL após inserts; banco desfez destinatários, estado processing permaneceu recuperável e maintenance concluiu a importação |
| Fila indisponível no upload | HTTP 202 com arquivo persistido; maintenance reenfileirou e concluiu; registro abandonado expirou corretamente |
| Recovery | Reagenda trabalho interrompido; ignora lock de worker ativo |
| Envio/agendamento/exclusão/cancelamento | API rejeita enquanto existe importação ativa |
| Segunda importação/retry concorrente | API rejeita; índice parcial também impede admissão duplicada |
| Tenant | Retry com campanha de outra conta retorna 404 |
| Falha de armazenamento após commit | HTTP 503, estado failed, retry do arquivo incompleto bloqueado e novo upload aceito imediatamente |
| Retenção | Retry expirado recusado; purge agendado |
| Entrega | Nenhum DeliveryJob enfileirado; nenhum e-mail enviado |
| Componentes Vue | 5 casos: preservação dos destinatários após HTTP 202, estado/resultado, erro sanitizado, polling persistente/encerramento, falha de rede |
| Ruby lint | 9 arquivos, sem offenses |
| JS lint | Zero erros; warnings de resolução de recursos de i18n na configuração existente |
| Diff | `git diff --check` sem erros |

Medições locais são evidência funcional e de redução de consultas; não constituem SLA de produção nem comparação de hardware equivalente. Não foi testada a planilha real do incidente.

Comandos: `bundle exec rails db:create db:schema:load db:migrate` com banco exclusivo; `bundle exec rails runner .codex/verify_import.rb`; `bundle exec rails runner .codex/verify_api.rb`; `vitest run --config .codex/vitest.config.ts .codex/recipient-import.test.js`; RuboCop e ESLint limitados aos arquivos alterados. Cenários adicionais: `.codex/verify_storage_failure.rb`, `.codex/verify_worker_crash.rb` e `.codex/verify_outbox.rb`. Roteiros e fixtures sintéticos em `.codex/`, sem adicionar specs permanentes conforme orientação do projeto. O primeiro merge de configuração Vitest ampliou indevidamente o escopo; a execução ampla foi interrompida e substituída pela execução focada de quatro casos. Um teste de cleanup de polling levou à inclusão de encerramento explícito ao desmontar/desativar o componente.

Dependências instaladas apenas no worktree (pnpm 10, lockfile preservado). Hooks não são instalados pelo setup `--ignore-scripts`; os checks são executados explicitamente.

## CI do PR

Run `34896294176`, commit `8f9c6b784`: oito shards RSpec e Vitest concluíram com sucesso; jobs de lint também verdes. RuboCop local dos nove arquivos Ruby alterados não tem offenses. Os jobs de segurança e lint do repositório usam `continue-on-error`; verde não significa relatório vazio. Brakeman reportou 45 warnings e bundle-audit reportou vulnerabilidade de path traversal na versão existente de rubyzip; não houve alteração de Gemfile/lockfile neste PR. O relatório Brakeman não apontou os novos arquivos de importação. Não foi feita triagem geral dos alertas fora deste escopo.

## Deploy e rollback propostos — dependem de aprovação

1. Revisar e aprovar PR. Não há deploy automático autorizado.
2. Executar a migration aditiva antes de disponibilizar o novo código; manter o schema em eventual rollback.
3. Garantir que web e worker novos compartilham o mesmo ActiveStorage persistente (S3 na implantação distribuída), que `low`, `housekeeping` e `active_storage_purge` são consumidas e que o cron maintenance está carregado.
4. Na troca blue/green, o worker com as novas classes deve assumir antes de o web novo aceitar uploads. Não deixar workers antigos consumirem os novos jobs.
5. Após aprovação específica, importar uma lista controlada sem enviar campanha e conferir 202, conclusão, contagens e recarga da página. Monitorar falhas/idade das importações, fila e armazenamento sem registrar conteúdo dos arquivos.
6. Rollback de aplicação somente com importações ativas drenadas ou tratadas explicitamente e com os novos jobs retirados de circulação de forma controlada. Não reverter o schema nem apagar arquivos/resultados. A versão antiga volta à importação síncrona e não entende os novos estados/jobs; rollback cego durante processamento é inadequado.

## Review adversarial independente

Review somente leitura por agente independente do implementador, snapshot `8f9c6b784`. Achados e tratamento:

- **P1 — Enqueue sob lock na maintenance:** confirmado. Enqueue movido para depois da transação. Reproduzido com dispatcher que inicia imediatamente o worker em outra conexão PostgreSQL; agora conclui, em vez de descartar por NOWAIT.
- **P2 — Feature flag nos jobs:** corrigido nos dois novos jobs. Teste com flag desligada confirma ausência de mutação, enqueue ou purge. Desligar a flag impede novas execuções; não mata job já em execução. Por isso o plano de rollback continua exigindo drenagem.
- **P3 — HTTP 202 limpava a lista visível:** corrigido no store; a resposta de aceitação preserva destinatários existentes. Teste montado confirmou estado queued sem apagar a lista.
- **P2 — Tradução pt-BR:** não aplicada por instrução explícita superior do usuário e do AGENTS atual: alterar somente inglês; traduções comunitárias seguem o fluxo próprio. As novas mensagens usam fallback inglês. Essa limitação está declarada, não é lacuna oculta.
- **Risco condicionado de fila:** housekeeping tem menor prioridade que low; backlog contínuo pode atrasar maintenance/purge. Sem evidência de starvation atual. Operação deve monitorar idade das importações e latência de housekeeping; cron de cinco minutos não é promessa de execução em cinco minutos.

Testes focados dos achados em `.codex/verify_review_fixes.rb` e `.codex/recipient-import.test.js`: três verificações backend e cinco frontend passaram. Revalidação independente dos deltas solicitada; parecer final será registrado no PR #431 sem alegar aprovação de merge/deploy.
