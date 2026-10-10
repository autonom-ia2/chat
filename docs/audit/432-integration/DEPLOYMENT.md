# Execução de publicação — 2026-09-14

Rodrigo aprovou explicitamente merge e deploy bluegreen da PR #433, head 5bb72e19832d9576bc1a181e2534c416d0920519. CI 34899841517 passou. Merge não executado.

Preflight:
- Hub2You AWS 354307071110, instância atual i-0475b7167d81d7a7c running, status EC2 sistema/instância ok.
- ALB: unhealthy, Target.Timeout; HTTP público sem resposta em 20 segundos.
- Autonom.ia HTTP 200. Credencial AWS local default inválida; último workflow de deploy desse destino consta success.
- SSM último ping 18:42:52 -03. Prova sintética enviada às 18:47:44 -03, sem início de execução registrado (Start null, ResponseCode -1), cancelada. Diagnóstico subsequente Pending também cancelado. Não há prova de execução nem de gravação do objeto sintético.
- SSM parâmetro de ambiente filtrado: ACTIVE_STORAGE_SERVICE=amazon, CRM_KANBAN_ENABLED=true, EMAIL_CAMPAIGN_ENABLED=true. Nenhum secret registrado.
- A causa da indisponibilidade ainda não foi determinada. EC2 checks ok não comprovam saúde do processo Rails/SSM.

Merge/deploy autorizado permanece pendente da recuperação. Reinício da instância atual é uma intervenção separada em produção, ainda não executada; solicitar aprovação antes dessa recuperação com indisponibilidade potencial. Não alterar PR/head aprovado para registrar este checkpoint.

## Recuperação aprovada e preflight concluído

Rodrigo autorizou reinício com cuidado em produção. Reboot EC2 solicitado em 2026-09-14T22:01:57Z, mesma instância/disco. SSM retornou às 19:06:10 -03. Web/worker iniciaram e HTTP voltou 200; ALB healthy; navegador autenticado carregou a aplicação. Não houve stop/start nem alteração de banco. Causa original ainda não determinada.

Prova de storage concluída sem boot Rails: SDK S3 isolado, identidade IAM existente, limite 25s, web gravou objeto sintético, worker leu conteúdo e removeu. Comando fdf2e3de-cd84-4240-9e62-cc98f348c468 Success. Duas primeiras tentativas leves falharam imediatamente por presumir credencial estática ausente; corrigida a prova para IAM, sem alterar configuração da aplicação.

Merge #433 concluído em 2026-09-14T22:08:43Z. Commit main 6eb50928dd249b304e948b8b8d1b3c55fa4fdebc. Workflows automáticos em acompanhamento.

Workflows: Hub2You 34902603484, Autonom.ia 34902603558, CI main 34902603634. PRs originais #427/#431 marcadas MERGED pelo GitHub via ancestralidade.

Métrica ALB UnHealthyHostCount (janela consultada 18:30-19:10 -03) teve primeiro ponto unhealthy às 18:50 e último às 19:06. Isso não determina causa. Ausência de Start no comando SSM não permite concluir categoricamente se algum subprocesso chegou a começar sem reportar estado. Não se atribui nem se exclui causalidade da tentativa de diagnóstico; não repetir boot Rails adicional na instância de produção.

## Hub2You publicado e QA

Nova instância i-06027d92c0af2d72b. Inspeção leve confirmou web e worker ativos com imagem 6eb50928dd249b304e948b8b8d1b3c55fa4fdebc. HTTP 200 após troca.

UI autenticada do funil: dois modos em pt_BR; modo lembrete explica decisão da IA e remove referência a template. Medição DOM desktop: topo dos campos de hora e grupo de dias ambos y=179.5, sem overflow. Largura 390px: grupo/linha sem overflow. Edição temporária fechada com Cancelar, sem salvar; reabertura confirmou checkbox de ativação original desmarcado. Nenhuma configuração existente foi alterada. Screenshot de inspeção foi limitado ao painel, sem registrar dados de clientes nesta auditoria.

Não executar importação volumosa em produção. CSV/XLSX de 20 mil contatos foi validado no banco local isolado antes do merge; em produção foi comprovado o storage web/worker com objeto sintético pequeno e removido. Não afirmar E2E de importação em produção.

Console da aplicação apresentou erro do commandbar/route resolver ao trocar conta, fora dos arquivos alterados. Funil carregou e os controles funcionaram; sem triagem geral desse erro durante o deploy. Não se afirma console global sem erros.

Migration 20260914190000 CreateEmailCampaignImports confirmada no log do green Hub2You: migrated (0.1462s), às 22:29:15Z. Apenas grep do log, nenhum Rails extra.

Hub2You workflow 34902603484 success; instância anterior i-0475b7167d81d7a7c stopped e referenciada no parâmetro previous-instance-id, nova i-06027d92c0af2d72b running. Autonom.ia já transferiu Sidekiq/listener e passou smoke SSO, pendente término da janela de cinco minutos. Ambos os endereços HTTP 200 e páginas autenticadas de conversas renderizadas no navegador.

## Conclusão

Autonom.ia workflow 34902603558 success. Ambos os bluegreen concluídos, CI main 34902603634 success. Checagem final registrada em 2026-09-14T22:42:52.794240+00:00. Importação em produção não foi reexecutada; limites de QA acima permanecem.
