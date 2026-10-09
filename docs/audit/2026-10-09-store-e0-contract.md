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
- Hook local de commit nao iniciou: `.husky/_/husky.sh` nao existe no worktree
  sem dependencias frontend. Commit usa hooksPath desabilitado apenas nesse
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
