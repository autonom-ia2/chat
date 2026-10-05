# #995 — Rails/UI para o navegador remoto

Implementação local por Iris em 05/10/2026, na branch `feat/995-instagram-vps-runtime`.
Escopo aprovado: desenvolver a parte Rails/UI do contrato `tmp/995-implementation-contract.md`.
Sem commit, push, merge, deploy, configuração real, SSH, AWS, Meta ou execução do publisher.
O diff anterior foi lido; alterações de outros agentes em runtime/gateway/infra foram preservadas.

## Comportamento

1. No Super Admin → automação Instagram, solicitar a reconexão pelo botão existente.
2. O dono de um pedido em `queued`, `running` ou `operator_required` pode abrir o navegador remoto.
3. O botão envia POST para Rails, com CSRF. Rails autentica Super Admin e lê novamente o pedido atual;
   ator e pedido não vêm de parâmetros enviados pelo cliente.
4. Uma página simples pede para continuar em até um minuto. O formulário externo envia **somente**
   `ticket` por POST para o endpoint HTTPS `/STACK/grant`, sem token em URL, redirect ou query.
5. Aguardar Chrome, concluir login/verificação Meta e fechar a janela do Chrome remoto para finalizar.
   Fechar apenas a aba do console não finaliza o processo. Instruções em inglês e português brasileiro.

O ticket usa a gem `jwt` já instalada: HS256, `typ: JWT`, nonce UUID e validade de 60 segundos.
Claims: `iss`, `aud`, `sub`, `jti`, `iat`, `exp`, `request_id`, `deadline`, `stack`.
O deadline vem da criação do pedido mais 3.600 segundos. O gate global e o reconnect permanecem intactos.
Rails não escreve no canal de controle nem na sessão para abrir o navegador.

A página do ticket usa `Cache-Control: no-store`, `Referrer-Policy: no-referrer` e apenas os estilos
do bundle existente do Super Admin, sem scripts ou widget de suporte. `ticket` é filtrado dos logs.
O gateway é responsável pela troca por cookie, pelo nonce de uso único e pelo marcador do navegador;
esta implementação não declara validação real dessas partes.

## Configuração esperada, sem provisionamento

- `INSTAGRAM_TESTER_SESSION_SOURCE`: `managed`.
- `INSTAGRAM_TESTER_RUNTIME_STACK`: `hub2you` ou `autonomia`.
- `INSTAGRAM_TESTER_OPERATOR_BROWSER_URL`: HTTPS, sem credencial/query/fragmento, caminho exato `/STACK/`.
- `INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY`: hexadecimal de tamanho par, pelo menos 64 caracteres;
  decodificado para bytes antes da assinatura. Cada stack deve receber uma chave distinta no provisionamento aprovado.
- `FRONTEND_URL`: URL HTTPS da aplicação; sua origem define `iss` e deve coincidir com a origem permitida no gateway.

O status expõe apenas `operator_browser_configured`, sem URL ou chave.
Configuração ausente/inválida mantém o botão oculto e POST direto indisponível, com mensagem fixa.
Nenhum segredo real foi consultado, configurado ou registrado.

## Timestamps da sessão

`SessionStatus` continua lendo somente o pointer público, existência e TTL das chaves.
`captured_at` vem do pointer; `published_at` vem de `updated_at` apenas no estado ativo.
Na invalidação, `updated_at` significa invalidação, portanto não é apresentado como publicação.
Quando não há horário verificável, a interface mostra horário desconhecido.
Nenhum payload é lido ou decifrado. Não houve alteração de Redis ou do publisher.

## Arquivos desta entrega

- `app/controllers/super_admin/instagram_automations_controller.rb`
- `app/helpers/super_admin/instagram_automation_helper.rb`
- `app/services/instagram/automation/operator_browser_ticket.rb`
- `app/services/instagram/automation/local_status.rb`
- `app/services/instagram/automation/session_status.rb`
- `app/views/super_admin/instagram_automation/show.html.erb`
- `app/views/super_admin/instagram_automation/browser.html.erb`
- `config/routes.rb`
- `config/initializers/filter_parameter_logging.rb`
- `config/locales/en.yml`
- `config/locales/pt_BR.yml`
- `spec/services/instagram/automation/operator_browser_ticket_spec.rb`
- `spec/services/instagram/automation/session_status_spec.rb`
- `spec/services/instagram/automation/operator_browser_contract_spec.rb`
- `spec/services/instagram/automation/local_status_spec.rb`
- `spec/requests/super_admin/instagram_automations_spec.rb`
- `spec/requests/super_admin/instagram_automation_ui_spec.rb`
- `docs/audit/995-rails-ui.md`

Não há rota de painel ou recurso do Guia da Plataforma alterado: a rota nova é exclusiva do Super Admin.
Nenhum arquivo gerado do Guia foi editado.

## Validação local

Ruby 3.4.4 via `eval "$(rbenv init -)"`; `bundle check` aprovado.
RSpec executado com ambiente limpo (`env -i`), `RAILS_ENV=test`, valores sintéticos,
banco/Redis apontados para loopback porta 1, sem acesso a serviços reais. Redis no ambiente Rails test é MockRedis.
Os contratos mockam o controle, a sessão e o manifesto de assets; não exigem schema ou publisher.

```sh
bundle exec rspec \
  spec/services/instagram/automation/operator_browser_ticket_spec.rb \
  spec/services/instagram/automation/session_status_spec.rb \
  spec/services/instagram/automation/operator_browser_contract_spec.rb \
  spec/services/instagram/automation/reconnect_contract_spec.rb --format progress
```

Resultado: **25 exemplos, 0 falhas**. Inclui assinatura/claims/expiração, configuração de ambas as stacks,
ator/pedido/estado/deadline, CSRF real no pipeline do controller, rejeição de parâmetros,
rota somente POST, corpo externo com campo único `ticket`, filtro de logs, headers, renderização real
dos templates en/pt_BR e timestamps sem acesso a payload. A autenticação é mockada nos contratos offline;
a verificação com Devise real continua na suíte de requests.

`bundle exec rubocop --no-server ... --cache false --format simple` nos 12 arquivos Ruby alterados,
com `RUBOCOP_CACHE_ROOT=tmp/iris-rubocop`, sem mudar permissões do sandbox: **12 arquivos, nenhuma infração**.
`pnpm i18n:fork:check`: **10 catálogos, 17.592 mensagens compiladas, cobertura en/pt_BR aprovada**.
`git diff --check`: aprovado.

Tentativa de executar os dois specs de requests e `local_status_spec.rb`: **0 exemplos executados,
3 erros de carregamento** em `ActiveRecord::Migration.maintain_test_schema!`.
Motivo real: sandbox impediu conexão TCP ao banco de teste (`PG::ConnectionBad`, `Operation not permitted`).
Não se tentou contornar o sandbox nem iniciar/configurar banco ou Redis.
Esses três specs foram atualizados e passaram pelo lint, mas **não estão declarados aprovados**.

Build de assets, inspeção visual em navegador, revisão independente e integração com gateway real permanecem
para a etapa de revisão/validação do coordenador. Não houve aprovação ou execução de novo merge/deploy.

## Correção de integração do coordenador: origem do formulário

A página de ticket usa agora `Referrer-Policy: strict-origin` no header e no meta.
A especificação Fetch (§ append request Origin) transforma Origin em null em POST
navegação com no-referrer; isso conflitaria com o Origin estrito do gateway.
Não aceitar Origin null: preservar a origem HTTPS, sem caminho/query do SuperAdmin.
O token continua exclusivamente no corpo POST, nunca em URL/referer. O form que
abre a página Rails usa noopener, sem noreferrer que também anularia Origin.
Referência: https://fetch.spec.whatwg.org/#append-a-request-origin-header
A política no-referrer do console no gateway permanece: lá não há envio do ticket.
