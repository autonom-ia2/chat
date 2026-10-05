# Operação do painel Instagram — #950

> **Atualização — 04/10/2026, 20:53 UTC:** transporte PASS encerrado nas duas stacks
> pelo confronto AWS/recibos das 20:48 UTC (TLS/auth/epoch, proxy e egress).
> O [runbook de release #960](instagram-release-960.md) rege o corte e os gates
> atuais, superando as pendências históricas de transporte abaixo. ENV assistido
> está `true` em ambas; ENV de coordenação legado presente no Hub2You e ausente
> na Autonom.ia não representa o auxiliar novo testado. Aplicação nova, runtime
> ativo e homologação Meta não estão comprovados. Merge/deploy ainda exigem
> aprovação explícita do Rodrigo; iniciar gestor só após metadados/versão conferidos.

Leia o [guia do painel](../instagram-admin-panel.md). Procedimentos futuros dependem de aprovação do Rodrigo para produção, auth, secrets, infraestrutura, rollout e deploy. Nenhum comando operacional de produção foi executado nesta entrega.

## Inspeção pelo SuperAdmin

1. Abra Settings → Instagram → **Abrir automação Instagram** (`/super_admin/instagram_automation`).
2. Confira os cinco metadados não secretos. App pai Meta Developers não é `INSTAGRAM_APP_ID` do OAuth. ID do operador deve vir da configuração autorizada, nunca de cookie/cURL extraído.
3. Para migrar de ENV, salve explicitamente os cinco valores no formulário. BD prevalece; vazio salvo bloqueia o fallback. Bootstrap do runtime exige todos os registros salvos e válidos.
4. Clique **Verificar saúde**. Separe configuração presente, leitura local `checked_at`, heartbeat `observed_at`/idade e prova remota. Meta continua `unknown` sem remote check; presença local não comprova autenticação.
5. Se criação Meta estiver bloqueada, respeite o bloqueio. Flag assistida ON não concede canal nem ultrapassa plano, limites ou papel do usuário.

Fontes: `SuperAdmin::InstagramAutomationsController`, `Instagram::Automation::{Metadata,LocalStatus,SessionStatus,OperatorControl}` e `SuperAdmin::InstagramAutomationHelper` nos arquivos apontados pelo guia.

## Reconexão e indisponibilidade

**Reconectar sessão** enfileira pedido tipado, com ator do SuperAdmin autenticado. Disponível somente com sessão gerenciada, gestor em `operator_required`, `control_available=true` e nenhum pedido em andamento. Não enviar cookie, cURL, credenciais de proxy/Redis ou comandos pela UI.

O M4 dedicado precisa estar online, com gestor/waiter e transporte privados funcionando. O perfil é definido por `INSTAGRAM_TESTER_BROWSER_PROFILE`, sem caminho hardcoded aqui. O wrapper [`manager-launchagent-wrapper.sh`](../../scripts/instagram_testers/runtime/manager-launchagent-wrapper.sh) aciona [`operator-waiter.mjs`](../../scripts/instagram_testers/runtime/operator-waiter.mjs) após necessidade de operador.

Ao receber claim, o waiter abre o navegador visível **no M4 dedicado**. Operador faz login/2FA manualmente e fecha a janela; só então o gestor tenta publicar. Não há promessa de abrir Chrome no computador do cliente nem de dispensar 2FA.

| Resultado | Ação |
|---|---|
| `queued` / `running` | Atualizar e acompanhar; não repetir a reconexão |
| `operator_required` | Intervir no M4; nova solicitação somente após conferir disponibilidade |
| `succeeded` | Conferir publicação/horário e validar o fluxo; não assumir inbox conectada |
| `failed` | Investigar runtime, claim e transporte; consultar estado antes de repetir |
| Gestor `unknown` / `unavailable`, canal indisponível | Operador verificar/iniciar gestor ou waiter e transporte no M4; atualizar o painel |
| `instagram_control_offline` no waiter | Transporte offline; nenhum navegador aberto/recuperação confirmada; corrigir no host dedicado |

Heartbeat tem validade limitada; um registro ainda presente não garante que o host esteja online agora. Pedido running tem concessão renovável e prazo máximo; expirado aparece como falha. Não limpar sessão, lock, outcomes ou pedido para simular recuperação. Resposta perdida não autoriza repetição automática.

## HTTP e códigos observáveis

| Caminho/contrato | Resultado real | Próxima ação |
|---|---|---|
| GET painel; POST salvar/health | JSON 200; salvar/health HTML redirecionam | Salvar é configuração; health é leitura local |
| POST reconnect aceito | JSON 202 com `request`; HTML redireciona com aviso de pedido | Acompanhar estados, não declarar reconectado |
| Reconnect indisponível | JSON 503 `operator_channel_unavailable`; HTML 303 com alerta | Verificar modo managed, heartbeat e transporte no M4 |
| Params/configuração inválidos | 422 `invalid_configuration`; HTML mantém apenas campos seguros | Corrigir os cinco campos/formato e reenviar |
| CSRF inválido | 422 `invalid_request` | Recarregar a sessão/formulário legítimo |
| API tester/OAuth | `error_code` em [`Instagram::Testers::Error`](../../app/services/instagram/testers/error.rb) | Distinguir erro de configuração, autorização e resultado incerto |
| `not_enabled` / `forbidden` | 404 / 403 | Conferir flag, allowlist, canal, permissões e bloqueio Meta |
| `meta_unavailable`, `meta_session_expired`, `proxy_unavailable`, `operator_required` | 503 | Suporte/operador; conferir estado local e runtime |
| `invalid_selection`, `invalid_username`, `invite_rejected`, `session_update_rejected` | 422 | Corrigir seleção/entrada; publicação é do canal privado |
| `busy` / `rate_limited` | 409 / 429 | Aguardar operação/limite e verificar antes de repetir |
| `invite_unknown` / `unknown_status` | 503 / 502 | Resultado incerto: consultar estado antes de reenviar convite |

## Ativação por conta e rollback

No SuperAdmin → Accounts → editar, controle `instagram_assisted_onboarding`: EE usa lista de features existente; OSS usa checkbox específico. OFF segue OAuth direto sem tester; ON exige preparação assistida pronta. Gate global desligado ou allowlist restritiva tornam ON indisponível, sem fallback.

Novas contas recebem default ON após sync normal de `ConfigLoader`; valor OFF já cadastrado é preservado. Existentes exigem dry-run da tarefa `instagram:rollout_assisted_onboarding`, revisão das contagens e aprovação antes de aplicar. `DRY_RUN` padrão é `true`; aplicação exige `false` e confirmação exata `INSTAGRAM_ROLLOUT_CONFIRM=instagram_assisted_onboarding`. Esses parâmetros documentam o contrato, não são autorização nem comandos para executar em produção.

O rollout salva novo bit e marcador `instagram_assisted_onboarding_rollout` sob lock. OFF manual pelo novo formulário também salva marcador; reexecução não religa essa conta. OFF histórico sem marcador não permite distinguir ausência antiga de decisão manual: revisar antes de aplicar.

**Rollback funcional aprovado:** desligar a flag pelo SuperAdmin e preservar marcador e inboxes existentes. Conferir demais flags, limites e planos após salvar. Não remover marcador nem restaurar um bitmap inteiro. Reauth permanece na mesma inbox/perfil com `inbox_id` explícito e vínculo assinado.

## Release do protocolo e reversão

Backend [`SessionPublisher`](../../app/services/instagram/automation/session_publisher.rb), [`session_publisher.rb`](../../scripts/instagram_testers/session_publisher.rb), Node [`operator-protocol.mjs`](../../scripts/instagram_testers/runtime/operator-protocol.mjs), [`publisher-tunnel.mjs`](../../scripts/instagram_testers/runtime/publisher-tunnel.mjs), [`forced-publisher.sh`](../../scripts/instagram_testers/runtime/forced-publisher.sh) e gestor devem sair em conjunto, em deploy aprovado. O novo bootstrap/revisão/ator/timestamps muda o contrato; não misturar versões antigas e novas.

Antes da aprovação de merge/deploy: concluir a composição #937/#956 na release #962; registrar versões compatíveis, review/CI do candidato e rollback. Depois do deploy aprovado, persistir os cinco metadados no banco de cada instalação e validar bootstrap canônico e rejeição de revisão divergente, antes de ativar o gestor. A ordem operacional vigente está em [release #960](instagram-release-960.md). Caminhos do wrapper/LaunchAgent pertencem à máquina dedicada; a preparação deve atender às duas instalações sem gestores concorrentes no mesmo perfil. Não refazer secrets, resetar sessões ou reprovisionar o Redis para obter prova.

Se a release falhar, seguir reversão conjunta previamente aprovada das versões backend/publisher/wrapper/runtime e conferir saúde. OFF por conta mitiga onboarding assistido, mas não reverte protocolo. Preservar metadados/marcador/inboxes; não apagar dados de sessão/coordenação. Cookie canônico permanece cifrado no Redis da instalação. Os recibos de 04/10/2026 às 20:44 UTC, referenciados em [release #960](instagram-release-960.md), comprovam o transporte dedicado e a saída Webshare das duas stacks; não comprovam sessão Meta, renovação ou conexão de caixas.

`InstallationConfig` invalida nomes afetados após commit; `GlobalConfig.clear_cache` legado sem argumentos permanece. Não prometer cache linear nem zero regressão absoluta. Aprovação requer relatório final dos achados reportados na fase 1, incluindo CAS aninhado, caminho 500 controller/helper e forced protocol. A renderização da nova página opta por não carregar o widget de suporte externo; testes reais de requisição comprovaram ausência da gravação indireta de `INSTALLATION_IDENTIFIER`. As outras páginas mantêm seu comportamento. Não remover esse opt-out sem repetir a prova de GET sem escrita.

## Validação local exclusiva — coordenador, em série

Comandos abaixo são **para teste local**, não foram executados por Clio. Usar somente serviços exclusivos loopback PG59510/Redis59511 do coordenador e o ambiente limpo [`run-local.sh`](../../tmp/950-integration/run-local.sh); não usar endpoints de produção, flush nem execução concorrente no mesmo banco. Inicializar rbenv antes de Ruby. O arquivo-lista é seleção de specs, não resultado.

```sh
# Backend amplo selecionado, incluindo compatibilidade Instagram e cache/flags
tmp/950-integration/run-local.sh ruby -rjson -e 'exec("bundle", "exec", "rspec", *JSON.parse(File.read("tmp/950-integration/rails-file-list.json")), "--format", "progress")'
# Cache real: TEST_REDIS_URL exclusivo 127.0.0.1:59511/0; sem fallback/flush
tmp/950-integration/run-local.sh bundle exec rspec spec/models/installation_config_spec.rb spec/lib/global_config_spec.rb spec/lib/global_config_service_spec.rb spec/services/instagram/automation/redis_isolation_spec.rb --format documentation
# Flag administrativa EE e boot OSS real (processos separados)
tmp/950-integration/run-local.sh bundle exec rspec spec/requests/super_admin/instagram_account_feature_spec.rb spec/controllers/super_admin/accounts_controller_spec.rb --format progress
tmp/950-integration/run-local.sh env DISABLE_ENTERPRISE=true bundle exec rspec spec/requests/super_admin/instagram_account_feature_spec.rb --format progress
# Handoff/publisher/manager com fixtures, sem Meta externa
node --test tests/instagram_testers/session-manager.test.mjs tests/instagram_testers/runtime-publisher.test.mjs tests/instagram_testers/operator-control.test.mjs tests/instagram_testers/session-observer.test.mjs
# Fluxos frontend alterados
pnpm exec vitest run app/javascript/dashboard/composables/specs/useInstagramTester.spec.js app/javascript/dashboard/routes/dashboard/settings/inbox/channels/instagram/TesterOnboarding.spec.js app/javascript/dashboard/routes/dashboard/settings/inbox/channels/instagram/Reauthorize.spec.js app/javascript/dashboard/routes/dashboard/onboarding/specs/inbox-setup/InboxChannelsDialog.spec.js app/javascript/dashboard/routes/dashboard/onboarding/specs/inbox-setup/useChannelConnect.spec.js --no-coverage
pnpm i18n:fork:check
```

Browser: depois dos testes seriais, marker de liberação e build existentes, usar o comando com caminhos locais do [`README QA`](../../tests/qa/instagram-automation/README.md). Runner: `node tests/qa/instagram-automation/run.mjs`, 18 casos executados com sucesso na rodada registrada, contexto isolado/headless, Rails/ERB real e fixtures locais. Extras precisam de receipts próprios. Contar apenas casos/asserções executados no `results.json`, separando bloqueios e screenshots; não é E2E Meta ou produção.

CI existente: [`testes.yml`](../../.github/workflows/testes.yml) executa RSpec por shards e `pnpm run test`; [`instagram-tester-onboarding.yml`](../../.github/workflows/instagram-tester-onboarding.yml) tem contratos Node, Vitest e QA anterior. Não inferir cobertura nova #950: conferir inclusão do operator-control, boot OSS, Redis real 59511 e novo browser runner. Infra de CI é isolada; não copiar seus endpoints para os testes locais desta entrega.

O coordenador gera/checka Guia e formatos conforme o código final; Clio não edita gerados. Preencher a matriz do guia com recibos da versão final, depois Review → Approval → Merge → Deploy/Rollback. Relatórios históricos, dry-run de specs, lint e plano browser não substituem execução nem revisão final.

## Evidência atual e isolamento entre execuções

O [relatório final](../audit/950-instagram-admin-delivery.md) substitui as pendências históricas que já receberam teste, preservando as limitações externas. O novo [workflow de storage real](../../.github/workflows/instagram-admin-integration.yml) fornece comandos e serviços reproduzíveis sem depender do arquivo de scratch local. O SDK de suporte é explicitamente simulado no harness para as páginas legadas; nunca interpretar isso como validação de seu serviço externo.

O harness cria registros sintéticos persistidos no banco de QA. Antes de repetir RSpec no mesmo banco exclusivo, reconstruir somente esse schema descartável confirmado ou remover os registros próprios por identificação exata. Nunca executar essa preparação contra banco compartilhado ou de produção. RSpec e browser não executam simultaneamente na mesma instância de QA.

Verificar saúde continua sendo diagnóstico local limitado; estado Meta não verificado não pode ser convertido em sucesso por configuração presente. A publicação concluída do pedido exige retorno do store, mas o commit da sessão e o commit do estado do pedido são distintos. Resposta perdida exige reconciliação; não prometer atomicidade entre ambos.
