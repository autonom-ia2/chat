# Publicação autorizada PR 1134 — 2026-10-08

Rodrigo autorizou merge do head `ca7e158040e56532f9500ca41df585d5504579d4`, ambos os deploys AWS, preservação da VPS/perfis e reativação somente Hub2You para o piloto exato conta 18/placementseg. Autonom.ia permanece off. Convite somente com status ausente/alvo exato já autorizado; unknown nunca repetir; sem DM. Meta login/2FA somente com intervenção humana quando realmente pedido.

A fonte corrige duas chamadas Redis pela conexão existente. Revisão Nexo aprovada, dez verificações com fachada/Redis reais (baseline d278 reproduz erro), 26 checks concluídos: 24 success e dois de e-mail fora do escopo skipped. Merge requerido pela fila normal, sem bypass; pedido com `--match-head-commit ca7e158...`.

Baseline anterior: ambosAWS d278, web/worker/targets/listeners saudáveis, flags ausentes; SSM Hub11unset; VPSd278, oito units saudáveis, Hub eAutmanagerflagabsent/perfis/capspreservados. Revalidar antes do deploy pois o estado pode ter mudado.

Plano: mergeSHA concreto, ambosAWS comflagunset, healthsource/runtime/worker/lister; comprovar identidade scriptsVPSd278 e não reinstalar; HubSSM11→12 true + bluegreen exclusivoHub; managerHubflagtrue comhelper revisado; health→read/search/status→fluxoexato. Se falha antesdeescrita, drain/offflag com deploy normalunset; não usar workflowactionrollback inseguro. Nunca alterar banco/dados/n8n/Traefik/DNS/IAM.


## Baseline e fila

Merge solicitado sem bypass às 06:22:56 UTC, posição 1; candidato da fila `372ca4eb5da63a6d87d01d3c40f78344b4c2d7cf`, ainda não apresentado como merge realizado. No head aprovado PR há 26 checks concluídos (24 success/2 email fora do escopo skipped). Na fila há testes próprios ainda em andamento.

Leitura AWS direta às 06:26:42 UTC: ambos d278, web/worker rodando, targets/listeners atuais saudáveis/corretos, operações browser ausentes, instâncias anteriores paradas/registradas/distintas. Baseline Atlas também comprovou AutSSM8 e HubSSM11, SecureString/KMS/identidade/gates e Redis isolados. Recibos `.codex/pr1134-baseline-health.json` e `.codex/release-1134-aws-baseline-20261008.json`.

Iris confirmou VPSd278, oito units ativas/enabled/NRestarts0/caps/perfis preservados, flagsHub/Autabsent e scripts/ops idênticos ao ca7. O helper manager ec2 só valida VPSd278; o verificador aa2 recebe backendexpectedSHA como argumento. Sem reinstalação necessária; sem execução de ativação/Meta.


## Merge e deploys automáticos

PR1134 mergeado pela fila normal em `372ca4eb5da63a6d87d01d3c40f78344b4c2d7cf`, pais d278 e ca7. Fonte do Store idêntica ao head revisado; scripts/ops idênticos à VPSd278; sem reinstalação. Só Store e audit mudaram. Recebido evento push/main, que iniciou automaticamente os dois deploys: Aut `37738381995`, Hub `37738381932`, ambos head372. Não foi executado POST manual nem dispatcher bilateral; não duplicar execuções. Acompanhar conclusão/health antes de ativar flagHub.

### Revisão operacional final e espera do deploy

- Nexo conferiu os hashes finais do writer e dispatcher Hub-only; revisão verde com gates externos. Receipt: `995-pr1134-helper-final-review-20261008.json`.
- Preparação read-only Hub concluída no merge `372ca4e`, SSM v11 unset e saúde das duas stacks comprovada. Nenhuma escrita SSM ou POST manual nesta fase.
- Os dois workflows automáticos chegaram ao passo de manutenção que aguarda 300 segundos antes de desligar a instância anterior. A raiz aguarda `Deploy Green: success`, rollback skipped e nova saúde direta antes da escrita Hub-only.
- Uma leitura anterior de saúde durante a transição retornou `read_failed`; o preparador subsequente concluiu saúde completa. Não atribuímos causa adicional sem evidência.
- Tela autorizada conta 18 aberta; nenhum novo `Buscar perfil` executado nesta retomada.

- Ambos deploys automáticos concluídos: `Deploy Green: success`, rollback skipped, head/merge372.
- O executor local teve recusa EMFILE antes de criar processo; retomou com shell mínimo, sem alteração do host ou da VPS. Nenhuma escrita durante a falha local.

### Ativação Hub-only autorizada

- Saúde direta pós-deploy concluída em 06:52:44 UTC: web/worker372 e flags unset nas duas stacks; destinos atuais saudáveis e listeners corretos. Instâncias anteriores paradas/registradas; não são um rollback imediatamente saudável.
- Writer revisado `72a3a350…`: Hub SSM 11→12 true, readback verificado, demais linhas preservadas. Aut SSM 8 unset.
- Dispatcher Hub-only `d32cbe414…` executado uma vez pelo root: run `37740164591`, head372, `Deploy Green` observado/queued. Isso ainda não comprova conclusão.
- Manager VPS Hub permanece OFF até o workflow concluir com sucesso e a saúde fresca confirmar Hub true / Aut unset. Novas operações da Autonom.ia permanecem OFF. Sem Meta/OAuth/DM nessa fase.

### Aceite anterior preservado

- Receipt privado `natural-renewals-verification.json` e checkpoint documentam sessão legítima e duas renovações naturais em cada stack, anteriores ao PR1134. A recuperação humana inicial não foi contada.
- Resume controlado no release1129 preservou os oito serviços, perfis/caps/locks, com captura/publicação/heartbeat novos. Não houve reboot do host.
- Não reclassificamos esses registros como prova de renovação posterior ao PR1134 ou conexão OAuth atual. O piloto real continua pendente.

### Saúde de ativação e gestor VPS

- Run Hub-only `37740164591` concluído com sucesso; `Deploy Green: success`, rollback skipped, source372.
- Leitura direta às 07:06:52 UTC: web/worker372 saudáveis nos dois ambientes, Hub flagtrue e Aut unset, listeners/destinos corretos.
- Root executou helper VPS congelado `ec2cdfd2…` em `apply --execute`; terminou exit0 às 07:07:20 UTC. Hub manager habilitado e saudável por dez segundos; Aut flag ausente. Outras unidades preservadas.
- Perfis preservados; aguardamos o baseline de fila/operações antes de qualquer busca.

### Piloto real e desativação segura

- Baseline fresco às 07:07:38 UTC: 0 registros e 0 itens na fila; sessão administrativa ativa e manager saudável.
- `Buscar perfil` foi enviado uma vez para `placementseg` pelo painel autorizado da conta18. Às07:08:08 o leitor viu queued1; às07:08:55 confirmou failed/meta_unavailable, fila0, channel0. Não há aceite funcional.
- Screenshot real: `hub18-pr1134-search-result-20261008.jpg`, preservado fora do Git. Sem convite, OAuth ou DM.
- Metadata `meta_or_oauth_called:false` do leitor descreve somente o diagnóstico read-only; não comprova se a busca chegou à Meta. A falha agregada exige fase/classe adicionais.
- Root executou rollback do manager: exit0 às07:09:47 UTC, Hub flag ausente e demais serviços preservados.
- Não havia operação queued/running; restou apenas o registro terminal failed da única ação search, preservado para diagnóstico.
- Writer revisado restaurou Hub SSM12→13unset às07:10:52 UTC, readback confirmado e demaislinhas preservadas.
- Dispatcher Hub-only normal `deactivate` iniciou run `37741910042`, head372 e DeployGreen observado. Não foi usado workflow actionrollback. A recuperação ainda depende da conclusão e da saúde fresca.

### Encerramento da desativação

- Run `37741910042` concluído às 07:24:25 UTC: Deploy Green success, rollback job skipped.
- Saúde direta às 07:25:06 UTC: web/worker372 rodando, destinos atuais saudáveis e listeners corretos nas duas stacks; browser operations unset nas duas. VPS permanece d278 com operações Hub/Aut desligadas.
- Instâncias anteriores paradas e destinos anteriores não saudáveis: não representam rollback imediato pronto.
- Leitura limitada às 07:23:59 UTC confirmou permissões atuais do Admin e sessão ativa, 0 registros/0 fila. Não reproduziu a falha histórica; o registro terminal já expirou.
- Próxima ação local: diagnóstico limitado de fases do gestor/executor, branch `codex/995-browser-operation-diagnostics`. Não repetir piloto nem publicar esta mudança sem revisão e aprovação concreta.
