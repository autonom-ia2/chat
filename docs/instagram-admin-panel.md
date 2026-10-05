# Painel de automação Instagram — #950

Documentação da implementação local compartilhada. Não comprova operação em produção, reconexão Meta ou aprovação de release. A entrega está empilhada sobre a base #937 ainda draft. Os recibos locais e os limites da homologação estão no [relatório de aceite](audit/950-instagram-admin-delivery.md).

## Onde fica e o que configura

SuperAdmin → Settings → Instagram (configuração OAuth) → **Abrir automação Instagram**. Settings também tem um cartão e o menu tem acesso direto. A tela dedicada é `/super_admin/instagram_automation`; a tela OAuth continua separada.

Esse caminho usa `SuperAdmin::AppConfigsController`, o partial [`_oauth_link.html.erb`](../app/views/super_admin/instagram_automation/_oauth_link.html.erb) e [`SuperAdmin::InstagramAutomationsController`](../app/controllers/super_admin/instagram_automations_controller.rb). O formulário aceita somente estes cinco metadados não secretos:

| Chave | Significado |
|---|---|
| `INSTAGRAM_META_DEVELOPER_APP_ID` | App pai no Meta Developers, usado na gestão dos testadores |
| `INSTAGRAM_META_BUSINESS_ID` | Business associado à gestão |
| `INSTAGRAM_TESTER_APP_NAME` | Nome do aplicativo que a pessoa confere ao aceitar o convite |
| `INSTAGRAM_TESTER_ADMIN_USER_ID` | Identidade do operador autorizado no perfil dedicado |
| `INSTAGRAM_TESTER_ROLES_DOC_ID` | Identificador da consulta de roles usada pelo adaptador |

**App pai ≠ app OAuth:** `INSTAGRAM_APP_ID` e seus parâmetros OAuth permanecem na configuração Instagram existente. Não substituir um ID pelo outro. Nenhum ID de autoridade pode ser inferido de cookie extraído ou de processamento de cURL com `sed`.

[`Metadata`](../app/services/instagram/automation/metadata.rb) lê `InstallationConfig` como fonte primária, com fallback ENV somente quando o registro não existe. Registro salvo com string vazia prevalece e deixa a configuração incompleta. Ler não cria registros. IDs são strings de 1–40 dígitos; nome tem até 120 caracteres, sem espaços nas pontas nem controles; não há coerção ou trim. Salvar os campos é transacional.

Cada operação usa um snapshot dos cinco valores; uma nova operação faz nova leitura. O runtime obtém `bootstrap` pelo publisher privado e exige os cinco registros válidos **salvos no banco**, sem fallback dos IDs do ENV local. A revisão dos metadados acompanha a publicação. Migrar os metadados ENV para o formulário é etapa explícita de release; não manter backend e gestor com fontes divergentes.

## Configuração, observação local e prova remota

**Verificar saúde** consulta estado local. A action de **Atualizar** faz GET sem alterar metadados, sessão ou fila. A página operacional não carrega o widget de suporte externo do layout compartilhado. Essa exclusão é restrita à tela nova e evita a criação indireta de `INSTALLATION_IDENTIFIER` ao renderizar o GET; as demais páginas preservam seu comportamento. A ausência de gravações foi verificada em testes de requisição e no navegador. [`LocalStatus`](../app/services/instagram/automation/local_status.rb), [`SessionStatus`](../app/services/instagram/automation/session_status.rb) e [`InstagramAutomationHelper`](../app/helpers/super_admin/instagram_automation_helper.rb) apresentam evidências diferentes:

| Indicador | O que demonstra | Limite |
|---|---|---|
| Configuração completa | Cinco valores presentes e válidos | Não autentica na Meta |
| Sessão `active` | Ponteiro/payload presentes e TTL positivo | Leitura local, sem descriptografar ou validar a sessão remotamente |
| Sessão `missing` / `invalidated` | Sessão ausente / invalidada | Precisa de diagnóstico ou operador |
| Sessão `invalid` / `unavailable` | Estado inválido / leitura indisponível | Não é sessão saudável |
| Proxy / coordenação configurados | Configuração local presente; proxy passa validação local | Não comprova rede, credenciais ou conectividade |
| Gestor `healthy` | Heartbeat recente com `observed_at` e idade | Não equivale a prova Meta |
| Gestor `operator_required` / `unavailable` / `unknown` | Operador necessário / falha reportada / sem evidência válida | Ausência de heartbeat não confirma recuperação |
| Meta `unknown` / `disabled` | Sem prova remota / criação bloqueada administrativamente | O painel não executa um remote check Meta |

`checked_at` é o horário da leitura local; `manager.observed_at` é o registro do heartbeat. Nenhum deles vira timestamp de sucesso remoto. Uma prova remota exige recibo de operação real e seu horário, fora desta leitura local.

## Reconectar sessão

O botão só fica disponível em modo `managed`, com gestor pedindo operador, canal de controle disponível e sem pedido `queued`/`running`. [`OperatorControl`](../app/services/instagram/automation/operator_control.rb) também valida esses requisitos e reaproveita o pedido em andamento. O ator vem do SuperAdmin autenticado; a UI não envia cookie, cURL, comando ou segredo.

O pedido tipado percorre publisher → [`operator-waiter.mjs`](../scripts/instagram_testers/runtime/operator-waiter.mjs) → [`session-browser.mjs`](../scripts/instagram_testers/session-browser.mjs) → [`session-manager.mjs`](../scripts/instagram_testers/session-manager.mjs). O navegador visível abre somente para o operador no **M4 dedicado**. Perfil e caminho vêm da configuração do runtime; não há caminho de máquina fixado nesta documentação. Não abre Chrome no computador do cliente. Login e 2FA continuam manuais; o operador fecha a janela antes de o gestor retomar a publicação.

| Estado do pedido | Significado | Próxima ação |
|---|---|---|
| `queued` | Pedido aceito, aguardando claim | Atualizar o painel; não duplicar |
| `running` | Runtime assumiu o pedido, com concessão renovável | Operador concluir login/2FA no M4 e fechar a janela |
| `operator_required` | Intervenção ainda necessária | Diagnosticar no M4; pedir nova tentativa quando o canal estiver disponível |
| `succeeded` | Publicação da sessão concluiu e o pedido foi atualizado | Conferir horário/estado e validar o fluxo desejado; não implica inbox conectada |
| `failed` | Falha ou concessão vencida | Conferir runtime/transporte e estado atual antes de novo pedido |

Com o M4 ou transporte offline, a recuperação fica indisponível; um heartbeat anterior pode permanecer até vencer. O operador deve verificar/iniciar o gestor ou waiter e seu transporte no host dedicado, depois atualizar o painel. Não presumir navegador aberto nem recuperação concluída. Timeout/resposta perdida exigem consulta do estado antes de repetir.

## Comportamento por conta e reautorização

`instagram_assisted_onboarding` é uma flag nativa por conta. **ON** escolhe a preparação assistida; prontidão depende também do gate global `INSTAGRAM_TESTER_AUTOMATION_ENABLED`, allowlist `INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS`, sessão, metadados, proxy e coordenação. ON indisponível pede suporte/nova verificação, sem fallback OAuth direto. **OFF** segue OAuth direto sem consultar o tester.

[`Configuration`](../app/services/instagram/testers/configuration.rb) exige também `channel_instagram`. A flag assistida não concede canal, plano, limite de caixas ou permissões. A UI de conta EE usa `all_features`; OSS tem um controle específico em [`AccountDashboard`](../app/dashboards/account_dashboard.rb). As demais flags, limites e planos devem ser preservados e verificados na integração final.

Reautorizar uma inbox existente usa `inbox_id` inteiro positivo explícito e `return_to=inbox`; a caixa deve pertencer à conta, ser Instagram e respeitar a permissão de gerenciar caixas. O state assina inbox e identidade do perfil; o callback revalida conta, vínculo, caixa, canal e identidade antes de substituir credenciais. Mantém a mesma inbox e perfil, sem exigir seleção de testador para essa reautorização.

Fontes: [`Reauthorize.vue`](../app/javascript/dashboard/routes/dashboard/settings/inbox/channels/instagram/Reauthorize.vue), [`AuthorizationsController`](../app/controllers/api/v1/accounts/instagram/authorizations_controller.rb), [`OauthBinding`](../app/services/instagram/testers/oauth_binding.rb), [`IntegrationHelper`](../app/helpers/instagram/integration_helper.rb) e [`CallbacksController`](../app/controllers/instagram/callbacks_controller.rb). O novo state adiciona proteção; não é idêntico ao antigo em todos os casos. O formato dos tokens OAuth persistidos não muda por essa proteção.

## Default, rollout e rollback

[`features.yml`](../config/features.yml) acrescenta a flag ao fim de `feature_flags_ext_1`, sem renumerar bits existentes. Default ON para novas contas depende do sync de [`ConfigLoader`](../lib/config_loader.rb) em `ACCOUNT_LEVEL_FEATURE_DEFAULTS`; o sync normal preserva um default já cadastrado OFF. Não forçar reconciliação para contornar isso.

Contas existentes dependem de dry-run revisado e aplicação explicitamente aprovada de [`AccountRollout`](../app/services/instagram/automation/account_rollout.rb). A tarefa altera o novo bit e o marcador `instagram_assisted_onboarding_rollout`, preservando demais flags/atributos. OFF manual pelo novo formulário grava o marcador na mesma transação e não pode ser religado pela tarefa. Bit OFF antigo sem marcador é ambíguo e exige decisão de rollout revisada.

Rollback funcional: desligar a flag da conta pelo SuperAdmin, preservando inboxes existentes e marcador. Não apagar marcador, sessões, locks ou outcomes. Reautorizar uma caixa existente continua sujeito às regras acima. O [runbook](runbooks/instagram-admin-panel.md) separa esse rollback de reversão do runtime.

## Fronteiras da entrega

Cookie canônico é cifrado por `Redis::SecureStorage` no Redis da instalação, conforme [`SessionStore`](../app/services/instagram/testers/session_store.rb); controle usa namespace próprio com TTL. A UI não contém credenciais de proxy ou Redis. Esta entrega não instala runtime em produção, não cria infraestrutura Redis e não demonstra solução de HTTP 407.

O protocolo tipado muda o contrato Ruby/Node/forced-wrapper: exige deploy conjunto aprovado. [`InstallationConfig`](../app/models/installation_config.rb) agenda invalidação direcionada após commit; [`GlobalConfig.clear_cache`](../lib/global_config.rb) sem argumentos continua disponível para o caminho legado e [`GlobalConfigService`](../lib/global_config_service.rb) usa o nome específico. Isso não garante consistência linear entre cache e banco nem ausência absoluta de regressão.

O SuperAdmin usa rotas Rails, fora do mapa do Guia do dashboard; não se inventa rota no registro nem exceção `_fora_do_guia` sem rota correspondente. O fluxo dashboard `conectar_instagram` já aponta para `settings_inbox_new`; explicação atualizada em `porques.md`, geração a cargo do coordenador.

## Evidências de aceite

A matriz final, os resultados e as limitações estão em [950 — entrega e aceite](audit/950-instagram-admin-delivery.md). As capturas abaixo usam dados sintéticos e a aplicação Rails/ERB real, com serviços externos substituídos exclusivamente no harness de QA. Não representam produção.

[Desktop](assets/instagram-admin-950/desktop-identificadores.png) · [Mobile](assets/instagram-admin-950/mobile-identificadores.png) · [Tema escuro](assets/instagram-admin-950/desktop-escuro.png) · [Solicitação na fila](assets/instagram-admin-950/reconexao-na-fila.png) · [Publicação concluída em teste](assets/instagram-admin-950/reconexao-concluida.png).

O job dedicado [`instagram-admin-integration.yml`](../.github/workflows/instagram-admin-integration.yml) executa provas concorrentes com PostgreSQL e Redis reais descartáveis. Mantém os guards de loopback e não depende de endpoints de produção. O restante das regressões continua no CI do fork; resultados remotos precisam ser vinculados ao SHA final do PR.
