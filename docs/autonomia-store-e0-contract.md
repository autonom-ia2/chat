# Loja: E0 de contrato e cliente

Status: proposta de contrato revisada com Financeiro - Asaas em 09/10/2026.
Nao declara que as APIs novas estejam implementadas ou publicadas.

## Escopo desta PR

Schemas JSON Schema draft 7, fixtures ficticias compartilhadas e cliente Ruby com
testes de protocolo sem Rails, banco ou chamadas externas. Nenhuma rota, menu,
job, migration, configuracao de producao ou fluxo de login e alterado.

`Autonomia::Financial::StoreClient` estende o cliente financeiro existente, mas
nao e chamado por controllers ou jobs nesta fase. O cliente atual de assinatura,
faturas e pagamentos permanece inalterado. Nao conectar o novo cliente a uma
rota de produto enquanto o Financeiro nao publicar o contrato escopado.

## Autoridades e identidade

- Financeiro reutiliza `service`, `FinancialPlan`, `PlanPrice` e `PlanLimit`.
- Comprador e o administrador autenticado, identificado pelo subject canonico.
- Chatwoot deve validar membership administrativa na account beneficiaria antes
  de uma futura operacao. Ter um token ou uma referencia de contrato nao basta.
- Instalacao e produto sao derivados de credencial de maquina escopada pelo
  Financeiro. Os responses incluem `namespace.installationId` e
  `namespace.productCatalogItemId`; o cliente rejeita divergencias.
- O cliente recebe explicitamente OAuth access token, chave de instalacao,
  namespace e subject do comprador verificados pelo backend. Nao recebe headers
  de sessao Chatwoot, ID token, email ou identidade fornecida pelo browser.
- Nenhum env novo, fallback para chave interna compartilhada ou token de
  superadmin e criado nesta PR. A futura credencial escopada depende do Financeiro.
- Validar o schema nao autentica evento, comprador, recurso ou concessao.

## Rotas: existentes e propostas

| Rota | Situacao |
| --- | --- |
| `/financial/me/subscription`, `/billing-preview`, `/invoices`, `/payments` | Existentes; fora desta alteracao |
| `POST /financial/internal/usage-reservations` | Existente; extensao escopada por servico ainda pendente |
| `POST /financial/internal/usage-reservations/:id/commit` | Existente; ocupacao duravel ainda pendente |
| `POST /financial/internal/usage-reservations/:id/release` | Existente; liberacao de ocupacao confirmada ainda pendente |
| `GET /financial/internal/store/catalog?page=1&pageSize=20` | Proposta |
| `GET /financial/internal/store/service-subscriptions/:id` | Proposta |
| `POST /financial/internal/store/checkout-sessions` | Proposta |
| `GET /financial/internal/usage-reservations/:id` | Proposta |
| `POST /api/autonomia/financial/store-events` | Proposta de callback; nenhum handler nesta PR |

A listagem de contratos e o status de checkout ainda nao tem envelope final
definido; nao inventamos metodos para essas respostas. O evento comercial
`store.subscription.updated` tambem precisa fechar o formato de `data`.
O schema `storeEvent` desta fase cobre somente `store.entitlements.snapshot`.

## Correlacao do checkout

A resposta proposta de checkout inclui `namespace`, `buyer.cognitoSub` e
`servicePlanPriceId`. O Financeiro deve deriva-los do escopo autenticado e da
sessao persistida, nao de uma identidade enviada pelo browser. O cliente exige
instalacao/produto e comprador esperados, alem do preco solicitado, antes de
devolver `checkoutUrl`. Divergencia produz `outcome=unknown`, sem retry ou
ativacao local. Esses campos adicionais ainda dependem de confirmacao e
implementacao no Financeiro; esta E0 nao e um consumidor ativo dessas rotas.

## Schemas e fixtures

- `config/autonomia_store/contract.v1.json`: documento compartilhavel com
  definicoes de namespace, catalogo, oferta, contrato pessoal de servico,
  checkout, reserva, commit, release e snapshot de concessoes.
- `spec/fixtures/autonomia_store/contracts.v1.json`: dados ficticios em dominios
  `.test`, sem usuarios, tokens ou referencias de pagamento reais.
- `StoreContract.validate!` valida tipos/valores sem coercao e devolve o payload
  original. Erros apresentam mensagem fixa e caminhos, nunca valores do payload.
- Shapes de `plan`, `price` e `limits` reutilizam entidades existentes e permitem
  seus campos adicionais. Os envelopes e requests novos sao estritos.
- UUID usa pattern explicito: a gem json_schemer 0.2.24 nao implementa esse
  formato nativamente. `accessVersion` e string decimal, nunca float.
- `target` e feature conhecida ou principal de agente da mesma instalacao.
  Registro/publicacao/autorizacao do target ficam na E1, nao no browser.

## Icone comercial

Reutilizar `catalog_items.metadata.logoUrl` e expor `service.logoUrl` no catalogo.
O controle de edicao pertence ao cadastro de servico do Financeiro/SDK, exclusivo
do superadmin comercial autorizado pelo backend. Admin da account nao ganha essa
permissao. O avatar do agente principal pode ser sugerido apenas na publicacao;
mudancas posteriores no avatar nao sobrescrevem o icone escolhido no servico.
Sem icone, o frontend da E1 usa seu fallback visual. Esta PR nao cria editor.

## Reservas, idempotencia e timeout

O fluxo novo usa `serviceSubscriptionId`; nao envia tambem `userSubscriptionId`
nem mistura os dois contratos. Requests nao aceitam quota, vendedor, comprador
ou comportamento de metrica definidos pelo chamador.

`occurredAt` e a chave de intencao sao obrigatorios e devem ser persistidos pelo
futuro orquestrador. Este cliente nao gera horario, compra, reserva ou retry.
Checkout usa `Idempotency-Key`; reserva/commit/release mantem a chave no body,
conforme as rotas financeiras existentes. Tokens rotacionados nao entram no hash
comercial. Identificadores de reserva sao validados antes de compor o caminho.

- `allocation`: confirmar ocupa capacidade; nao reinicia mensalmente; confirmar
  uma ocupacao nao pode deixar `expiresAt` de reserva provisoria. Desabilitar o
  recurso local antes de liberar capacidade confirmada no Financeiro.
- `reserved`: exige `expiresAt` como date-time, nunca null. Outros estados
  continuam permitindo null, com null obrigatorio em allocation committed.
- Commit exige resposta `committed`; release exige `released`, inclusive em
  replay idempotente. ID correto com estado diferente produz `outcome=unknown`.
- `consumption`: acumula no periodo configurado. Confirmacao usa a quantidade
  reservada; quantidade variavel na confirmacao nao e implementada na E0.
- Timeout, erro de transporte, 5xx ou resposta invalida numa escrita produz
  `outcome=unknown`: pode ter ocorrido efeito remoto. Nao liberar ou recomprar.
- Resposta HTTP malformada e sintaxe de header invalida sao erros de transporte
  sanitizados: leitura falha; escrita permanece desconhecida, sem retry.
- Consulta de recuperacao malsucedida nao prova inexistencia nem liberacao.
- Repetir a mesma intencao deve devolver a mesma reserva; conflito ou ultima
  vaga excedida e falha explicita, nunca habilitacao local antecipada.
- O cliente verifica namespace, IDs e alvo retornados; erros expostos sao
  sanitizados. Nao registra requests, tokens ou responses do Financeiro.
- Atomicidade, quota e dedupe de ocupacao sao responsabilidades do Financeiro;
  mocks desta PR nao comprovam concorrencia no banco financeiro.

## Snapshot e fases seguintes

O snapshot traz todas as concessoes efetivas para instalacao, produto, servico
e recurso. Revogar uma nao revoga outra valida. O callback da E2 deve validar
assinatura/timestamp e escopo, persistir inbox antes do 2xx, ignorar duplicados e
versoes antigas e processar assincronamente. Redirect de checkout nao ativa nada.

Policies de suspensao, downgrade abaixo da ocupacao e quantidade efetivamente
consumida permanecem pendentes de aprovacao. Nenhuma dessas decisoes foi embutida
como comportamento destrutivo nesta E0.

## Validacao

Com Ruby/Bundler do projeto configurados:

```sh
bundle exec rspec --options /dev/null spec/contracts/autonomia/financial
bundle exec rubocop app/services/autonomia/financial/store_*.rb spec/contracts/autonomia/financial
```

Os specs exigem somente RSpec, WebMock e json_schemer, ja presentes no Gemfile.
Nao carregam rails_helper, nao consultam banco e bloqueiam HTTP real.

Proximos gates: Financeiro reutilizar as mesmas fixtures/schema; fechar os tres
envelopes pendentes; implementar credencial escopada e rotas; testar isolamentos
e ultima vaga simultanea no backend financeiro. Depois, E1 conecta publicacao e
catalogo ao frontend aprovado. Esta PR nao autoriza merge ou deploy manual.
