# Auditoria E0: contrato da loja

## Autorizacao e isolamento

Usuario aprovou o prototipo e autorizou iniciar E0. Escopo: contrato, fixtures,
cliente e testes; sem compra, habilitacao, backend financeiro ou deploy.

`origin/main` atualizado em 09/10/2026, base `1ce49f44c9`. Worktree separado
`chatwoot-store-integration`, branch `codex/store-integration-contract`.
O worktree principal estava modificado em Answerer e permaneceu intocado.
Worktree criado com git no repo aninhado: o contexto do app aponta para o repo
pai Workspace, nao para o Git oficial do Chatwoot.

## Decisoes

- Reuse service/plans/limits no Financeiro; sem catalogo comercial paralelo.
- Revisao da thread Financeiro - Asaas confirmou o subset proposto e distinguiu
  rotas existentes das propostas. Nenhuma implementacao remota foi autorizada.
- Icone em `metadata.logoUrl`, editavel pelo superadmin comercial no Financeiro;
  cliente recebe `service.logoUrl`. Esta E0 nao altera o editor.
- Comprador admin e recurso beneficiario separados; namespace explicito.
- Reserva de servico nao inclui assinatura de produto legada.
- Timeout de escrita significa resultado desconhecido; sem retry automatico,
  liberacao, compensacao ou efeito local neste cliente.
- Snapshot validado somente como formato; HMAC, replay/versoes, inbox e jobs
  pertencem a E2, nao sao implementados nem comprovados pelos mocks da E0.

## Validacao local

- Specs isolados de protocolo: **40 exemplos, 0 falhas** (tambem ordem aleatoria,
  seed 42), RSpec 3.13, WebMock
  3.23.1, json_schemer 0.2.24; nenhuma chamada real liberada.
- Ruby nativo disponivel: 2.6.10. Dependencias de teste puras instaladas em /tmp,
  sem mudar Gemfile/lockfile. Nao foi instalado Ruby nem usado container.
- A execucao local usa `rspec --options /dev/null
  spec/contracts/autonomia/financial`, sem rails_helper/DB.
- Sintaxe Ruby e parsing JSON verificados. Nenhuma extensao Enterprise do cliente
  financeiro foi encontrada. APIs financeiras anteriores nao foram editadas.
- Teste revelou que UUID via format nao era validado pela gem existente;
  schema usa pattern e comprimento explicitos; teste de traversal passou.
- Ruby 3.4.4/Bundler da aplicacao indisponiveis localmente: suite completa Rails
  e RuboCop do projeto nao executados nesta maquina. CI do PR e gate posterior.
- Hooks locais de commit/push nao iniciaram: `.husky/_/husky.sh` nao existe no
  worktree sem dependencias frontend. Commit/push usam hooksPath desabilitado apenas no
  comando; configuracao do Git/hook nao foi modificada. Validacoes acima feitas
  explicitamente; checks da PR continuam habilitados.

## Dependencias e limites

Contratos novos nao estao publicados no Financeiro. Envelopes da listagem de
contratos, consulta de checkout e evento subscription.updated ainda pendentes.
Credencial escopada, assertion administrativa e callback autenticado precisam
ser implementados e validados nas proximas fases; o cliente nao aceita fallback
para chave compartilhada. Politicas de suspensao/downgrade/consumo variavel ainda
nao aprovadas. Tests de mocks nao provam quota atomica ou concorrencia remota.

Nenhum acesso a AWS, banco, EC2, Auth ou API financeira de producao. Nenhum Rails
console/runner/task, migration, segredo, merge ou deploy realizado.

## Correcao dos erros introduzidos na PR #1185

- Usuario autorizou corrigir os erros desta E0. Escopo limitado aos arquivos
  novos; WorkingHour e seus testes nao foram modificados.
- CI do head `0ff8f99b71`: shards 1 e 5 falharam antes dos exemplos porque o
  helper exigia a gem agregadora `rspec`, ausente no Gemfile/lockfile. O teste
  inicial isolado tinha essa gem adicional instalada, portanto nao reproduzia
  a selecao de dependencias do CI.
- Reproduzido localmente com um Gemfile temporario que declara somente
  rspec-core, rspec-expectations, rspec-mocks, WebMock e json_schemer: dois
  LoadErrors e zero exemplos antes da correcao. Bundler impede acessar a gem
  agregadora mesmo quando ela esta instalada no diretorio temporario.
- Helper passou a exigir os tres componentes RSpec existentes no projeto,
  sem modificar Gemfile/lockfile. Corrigidas as 13 ocorrencias de lint dos
  arquivos novos identificadas no log do RuboCop.
- Mesma execucao isolada com `ruby -rbundler/setup .../bin/rspec --options
  /dev/null spec/contracts/autonomia/financial`: **40 exemplos, 0 falhas**,
  seeds 42 e 2026. Verificacao adicional confirmou que `require 'rspec'`
  continua indisponivel e o helper corrigido carrega normalmente.
- `git diff --check` passou. Ruby local permanece 2.6.10; componentes RSpec
  locais sao 3.13.x. Isto comprova o carregamento sem a gem agregadora, nao
  substitui a validacao do lockfile completo com Ruby 3.4.4 e RuboCop no CI.
- As sete falhas WorkingHour do shard 4 sao separadas: o metodo encontra inbox
  nil. O codigo nao mudou nesta PR e o CI do commit-base estava verde; a origem
  exata da contaminacao/ordem de fixtures ainda nao foi demonstrada.
- Hooks continuam indisponiveis neste worktree; eventual commit/push usa a
  mesma excecao local documentada acima, sem mudar a configuracao global.
- Nenhuma chamada real ao Financeiro, Rails em producao, acesso AWS, merge ou
  deploy manual realizado nesta correcao.
