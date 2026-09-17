# #436 — verificação ampla e isolamento dos testes

Em17/09, a execução ampla foi interrompida graciosamente após cerca de14,5min para preservar o relatório: **8.827 exemplos executados,13 falhas e97 pendentes**. Ela não é declarada uma suíte completa verde. Evidência local: `436-operations-integration/tmp/email436/backend-full.json`.

A comparação foi feita numa worktree destacada da **main inalterada `cd30dba0c922f0716866ec6f46d1d0f79222b864`**, usando outro banco sintético e o mesmo ambiente. Seis falhas reproduziram diretamente: callback Autonomia, quatro redirecionamentos Slack e expectativa SAML dependente de FRONTEND_URL. A falha do matcher de convite do AgentBuilder reproduziu com a ordem original AccountBuilder→AgentBuilder:17 exemplos, uma falha idêntica. Os respectivos arquivos de produto e specs não foram alterados por #436. Logs: `436-baseline-verification/tmp/email436/baseline-comparison.json` e `baseline-builders-order.json`.

As seis falhas restantes revelaram **vazamento da fixture concorrente nova**, não uma alteração do modelo WorkingHour: Inbox remove horários de forma assíncrona; o teardown do TickJob deixava112 horários órfãos (16 inboxes ×7). O teste agora apaga somente os horários de sua própria inbox antes de removê-la. Não foi mudado o ciclo de exclusão da aplicação, nenhuma regra de negócio nem a suíte antiga para ocultar o defeito.

A ordem TickJob→WorkingHour foi executada no PostgreSQL sintético após a correção: **23 exemplos, zero falhas**. WorkingHour também foi incluído no gate cumulativo de CI para impedir recorrência desse vazamento. O gate funcional de campanhas continua sendo separado da execução ampla com problemas de baseline; nenhum pending foi adicionado para esta feature.

Não houve Rails em produção, alteração de infraestrutura/flags, envio real, merge ou deploy. A inspeção da base é somente para comparação; não corrige os sete defeitos/expectativas já existentes fora do escopo de campanhas.

O gate cumulativo ampliado, agora incluindo WorkingHour depois da fixture concorrente, foi repetido: **495 exemplos, zero falhas e um pending preexistente de Account** (`tmp/email436/pr1-final-regression.json`). O teste de ordem específico também permaneceu verde. Lint do arquivo de teste passou. As13 falhas da execução ampla estão assim explicadas: sete reproduzidas na main inalterada e seis de isolamento da fixture nova, corrigidas e protegidas pelo CI; a execução ampla interrompida não é rotulada como sucesso completo.
