# #931 — vínculo OAuth com ator e instalação

Implementação local na base `149c6718f2`. Não comprova configuração ou comportamento em produção. Sem acesso a segredo real, banco, Redis real, navegador, rede externa, configurações privadas, commit, push, merge ou deploy.

## Mudança

Todos os states emitidos pelo endpoint Instagram, inclusive sem testers e na reautorização, têm `state_version=2`, `sub`, `actor_id`, `installation`, `iat`, `exp` de 15 minutos e `jti` aleatório. Não há downgrade de state antigo. Assinatura continua HS256 com a configuração OAuth existente. O endpoint e os campos públicos da requisição permanecem iguais; state é opaco para o cliente.

Selection mantém os campos assinados conta/ator/App/instalação ao sair de verify. O callback valida sua consistência com o state e a configuração do App. Não compara IDs do cadastro de papéis com instagram_id nem app_scoped_user_id: são namespaces diferentes. A confirmação do perfil continua por username normalizado, que é mutável; a mudança não afirma vínculo imutável entre esses IDs.

O callback resolve a conta ativa e a associação atual do ator e usa `InboxPolicy.create?`, cujo gate real é `AccountUser.permission_granted?('inbox_manage')`, incluindo Enterprise custom roles. Essa consulta acontece antes da troca OAuth e novamente depois das chamadas do provedor, antes de criação/atualização. A leitura usa Account.uncached para ignorar o cache de queries da requisição, inclusive ao consultar a função personalizada. Não usa Current.account_user armazenado na preparação. O ator vem da transação assinada emitida ao usuário autenticado; não acrescentamos exigência de cookie/login no callback público, que também atende a autorização iniciada via API.

O nonce é consumido atomicamente por Redis `SET NX`, com chave isolada pelo namespace e TTL de 30 minutos, antes de trocar o código. Replay é recusado. Falha Redis retorna código sanitizado e impede avanço; nenhum fallback em memória no produto. Negar OAuth também consome o nonce. Em falha de troca ou persistência, o usuário inicia outra autorização, com outro nonce.

Legado sem seleção não instancia Configuration/Client de testers e funciona com automation flag desativada, sem session namespace/configuração de testers. Usa somente as dependências normais do produto para autorização/OAuth e Redis Alfred para replay.

## Namespace e configuração

O namespace é SHA-256 da URL base confiável `FRONTEND_URL`, já usada pelo produto como base de redirect_uri. URI valida esquema http/https, host e ausência de credenciais/query/fragmento; normalizamos host, porta padrão e barra terminal. Caminho e portas diferentes permanecem distintos. Não derivamos de Host/request, seleção do cliente, AppSecret, App ID ou flag de testers. Não usamos o fallback localhost na identidade: ausência ou URL inválida não emite state e retorna meta_unavailable no endpoint.

Analisamos `INSTALLATION_IDENTIFIER`: `ChatwootHub.installation_identifier` pode criar a configuração sob demanda, e uma cópia de banco pode preservar o mesmo UUID. Não usamos essa chamada nem introduzimos gravação/configuração de instalação. O callback público configurado distingue instalações que compartilham o AppSecret sem depender de recursos testers.

Condição operacional: cada instalação independente precisa de FRONTEND_URL próprio e estável, igual ao endereço público usado para seu OAuth. Duas instalações configuradas com a mesma URL pública terão a mesma identidade; isso deve ser corrigido como configuração de rollout, não mascarado por um fallback. Nenhum valor real foi inspecionado. Trocar host/esquema/porta/caminho de FRONTEND_URL invalida states e seleções anteriores; alterações equivalentes na normalização preservam o namespace.

## Rollout, compatibilidade e rollback

- Instalar a emissão e a validação juntas no mesmo release. Evitar pools com versões diferentes recebendo callbacks: o callback antigo ignora os novos campos e não aplica as novas proteções.
- Antes do release, confirmar em contexto autorizado que FRONTEND_URL está configurado, é estável e distingue cada stack. Não trocar secrets ou criar nova configuração para esta correção.
- States anteriores, inclusive os de testers com exp/jti mas sem ator/versão/contexto, são recusados pela validação. States inválidos/antigos/expirados vão para `/app` sem troca de código ou gravação; é necessário reiniciar OAuth. Não existe período de aceitação legado, pois os dados ausentes não permitem provar autorização/instalação. Seleções assinadas anteriores também devem ser refeitas.
- Inboxes e tokens já persistidos não são migrados/revogados. #898 (callbacks Meta e IDs separados), #920 (relay webhooks) e #925 (refresh OAuth) permanecem intactos.
- A reautorização emite state novo v2 mesmo com testers desligados, atualiza o canal existente sem substituir o nome personalizado da inbox e mantém os IDs separados.
- Rollback para a versão anterior reabre as lacunas: não é rollback de segurança equivalente. Se necessário por falha operacional, interromper novas autorizações/callbacks no controle de release autorizado antes de voltar; não aceitar v2 no callback antigo presumindo que ele respeita os campos novos. Não há mutation de infra implementada aqui.

## Arquivos da responsabilidade OAUTH

Produto:

- app/helpers/instagram/integration_helper.rb
- app/services/instagram/testers/oauth_binding.rb
- app/services/instagram/testers/selection.rb
- app/controllers/api/v1/accounts/instagram/authorizations_controller.rb
- app/controllers/instagram/callbacks_controller.rb

Specs:

- spec/helpers/instagram/integration_helper_spec.rb
- spec/services/instagram/testers/oauth_binding_spec.rb
- spec/services/instagram/testers/selection_spec.rb
- spec/controllers/api/v1/accounts/instagram/authorizations_controller_spec.rb
- spec/controllers/instagram/callbacks_controller_spec.rb
- spec/requests/api/v1/accounts/instagram/tester_authorization_spec.rb
- spec/enterprise/services/instagram/testers/oauth_binding_spec.rb (novo)

Coordenação: `spec/requests/api/v1/accounts/instagram/testers_spec.rb` também emite Selection. Seu dono/coordenador deve incluir FRONTEND_URL sintético no hash settings, conforme `tmp/instagram-931/oauth-progress.md`. Não editar arquivo alheio nem adicionar fallback no produto para satisfazer a fixture.

## Evidência e limites

1. `bundle exec ruby tmp/instagram-931/oauth-offline-check.rb`: 21 verificações, zero falhas, zero serviços reais. Carrega helper, Selection, OauthBinding, InboxPolicy e módulo Enterprise reais, com armazenamento/Account/AccountUser exclusivamente sintéticos. A primeira execução do harness falhou por namespace Enterprise ausente no harness; ele foi corrigido e executado com sucesso.
2. Reprodução antes: o script executa o helper e Selection do HEAD com constantes renomeadas. State legado perde ator, atravessa duas FRONTEND_URL com o mesmo segredo sintético e Selection.verify perde conta/ator. Os três comportamentos foram confirmados.
3. Depois: estado completo, isolamento entre URLs com segredo idêntico, assinatura/tampering, expiração, nonce/replay, associação removida, permissão perdida, ator cruzado, conta suspensa, seleção inconsistente e permissão Enterprise foram exercitados sem Rails. Isso não substitui os testes de banco/controllers.
4. `ruby -c` nos 12 arquivos Ruby de produto/specs: todos passaram.
5. `git diff --check` nos arquivos OAUTH: passou. Diff vazio nos arquivos dos callbacks Meta #898, relay #920 e refresh #925 listados na verificação.
6. RuboCop com `--cache false` bloqueado por EPERM ao criar cache do servidor fora da worktree. Não repetido nem contornado. Lint não está aprovado.
7. Rails/RSpec não executado: brief reserva testes DB/Redis/socket ao coordenador em ambiente isolado. Specs escritos cobrem revogação antes da troca e depois do provedor antes de criação/reauth, replay/expiração, cache de queries com permissão revogada (fixture mantém o resultado antigo em cache via uncached dirties:false), mesma chave em stacks distintas, estado em voo, flag off, token/perfil divergente, IDs separados e Enterprise. Não declarar que esses specs passaram.

Suites a executar no contexto isolado do coordenador: os sete arquivos de specs acima e o request testers após ajuste de fixture; incluir regressões de `spec/requests/instagram/data_deletions_spec.rb`, `spec/requests/webhooks/instagram_relay_spec.rb`, `spec/services/instagram/refresh_oauth_token_service_spec.rb` e `spec/jobs/instagram/refresh_tokens_job_spec.rb`. Não executar estes arquivos nesta rodada restrita.

Pendente: execução Rails/Enterprise, lint em contexto autorizado e review independente. Sem declaração de produção pronta.
