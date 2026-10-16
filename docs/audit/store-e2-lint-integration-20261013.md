# Loja E2: lint e primeiro gate integrado local

## Escopo autorizado

Em 13/10/2026, o usuario autorizou corrigir o lint e coordenar homologacao local
com a thread Financeiro - Asaas, sem PR ou deploy. O trabalho permanece na branch
local `codex/store-checkout-activation`, sem commit/push nesta rodada.

Este documento complementa `store-e2-local-tests-20261013.md`: as pendencias de
lint daquela rodada foram resolvidas. Nao declara E2 completa nem autorizacao
para publicar, usar credenciais reais ou acessar producao.

## Correcoes de qualidade

- Separacao do checkout em `StoreCheckoutController`, com os mesmos endpoints,
  guards e DTOs publicos. O controller cliente permanece responsavel por servicos
  e ativacoes. Chamadas HTTP de checkout nao mantem uma transacao DB aberta.
- Assinatura de requests, validacao de origem/credenciais/Identity, assinatura
  de callbacks e correlacao de eventos organizadas em unidades menores.
- Lease e checkpoints continuam compare-and-set atomicos no PostgreSQL. As
  unicas dispensas pontuais de SkipsModelValidations documentam essa atomicidade;
  os limites globais do lint nao foram alterados.
- Migration declarativa permanece unica e reversivel, seguindo a convencao do
  repositorio para metricas de declaracoes de schema.
- Specs de protocolo movidos para caminhos correspondentes as classes testadas.
- Labels fechados dos enums da loja centralizados com chaves i18n literais, sem
  concatenar nomes vindos do backend. A tela de ativacao respeita `available=false`.
- ESLint da loja agora le seus catalogos `financial.json`, sem desabilitar cops
  ou alterar o comportamento de lint de outros modulos.
- Guia, formatos de acoes e parametros de leitura regenerados pelos comandos
  oficiais, sem editar arquivos gerados manualmente.
- `.env.example` documenta `FINANCIAL_STORE_WEBHOOK_SECRET` vazio; nenhum segredo
  real foi gravado nem houve mudanca operacional de ambiente.

## Validacoes locais

| Verificacao | Resultado |
| --- | --- |
| RuboCop dos 34 arquivos Ruby da loja | 0 infracoes |
| ESLint JS/Vue da loja com `--max-warnings 0` | 0 erros, 0 avisos |
| Specs Rails da loja | 38 exemplos, 0 falhas |
| Specs Ruby dos contratos | 90 exemplos, 0 falhas |
| Specs JS/Vue da loja e rotas | 31 testes, 0 falhas |
| i18n en/pt_BR do fork | 15 catalogos; 21420 mensagens cobertas |
| Guia e formatos gerados | build/check aprovados |
| Schema e migration | conservados da rodada up/down/up anterior |
| Contrato e fixtures E2 versus Financeiro | identicos |
| Build do preview com componentes reais | aprovado em 4,03 s; 87 modulos |
| `git diff --check` | aprovado |

Total de testes locais focados: 159, mais um cenario de integracao entre os
backends. Os avisos de runtime preexistentes de enums/Rack, registro duplicado de
i18n nos testes e source map do ProseMirror nao sao infrações do lint da loja.

O build completo Vite foi tentado com heap limitado a 2048 MB e parou por
JavaScript heap out of memory. O Mac estava sob pressao de memoria; o limite nao
foi aumentado nem o build tratado como verde. O preview compilou com teto de
1536 MB. Build completo em CI/ambiente com memoria suficiente continua pendente.

## Primeiro gate integrado confirmado

Os processos usaram exclusivamente loopback, bancos vazios separados e dados
ficticios. O backend Financial utilizou buildServer/registerRoutes, repositories,
verificacao do JWT/JWKS e assertion reais, sem substituir seus handlers por
fixtures. SecretStore e issuer Auth foram simulados nas bordas autorizadas.

O request spec do Chatwoot exercitou:

1. Token OAuth ficticio gravado e lido pelo TokenStore criptografado real.
2. `StoreIdentity` chamando `/me` com TLS validado por CA local de teste; o issuer
   ficticio verificou assinatura RS256, issuer, audience e token_use.
3. Catalogo Financial real retornando o servico piloto configurado.
4. POST checkout real com assertion fresca, namespace, hash do corpo e intencao
   duravel correlacionados, criando somente a intencao/contrato unpaid.
5. Perda de resposta injetada no cliente depois do POST real ter sido processado:
   o Chatwoot marcou reconciling e recuperou a mesma intencao por resolve.
6. Replay do mesmo checkout retornando o mesmo ID, sem nova compra.
7. Consulta/lista indicando acesso ainda negado: zero ativacoes locais e feature
   nao habilitada. Nao houve redirecionamento ao gateway nem pagamento.
8. Outro comprador nao conseguindo consultar o checkout alheio.

O cenario passou: 1 exemplo integrado, 0 falhas. Nenhum stub de resposta do
Financial, Identity ou banco foi usado. A unica falha injetada foi a entrega da
resposta apos o handler Financial real terminar.

Proxies HTTPS locais preservaram a validacao de TLS do produto:

- `https://localhost:3009` para Financial HTTP `127.0.0.1:3008`.
- `https://localhost:3011` para Identity/JWKS ficticio `127.0.0.1:3010`.
- Allowlist restrita as rotas da loja, `/me` e JWKS; diagnosticos do harness
  permaneceram em HTTP loopback fora do proxy.
- Configuracao/JWTs ficticios ficaram em bundle ignorado, modo 0600; nao foram
  impressos nem incluidos no Git. CA confiada somente nos launchers de teste.

Financeiro - Asaas tambem confirmou smoke HTTP/HTTPS proprio e runtime PG17
restrito: duas contratacoes ficticias unpaid, zero invoices e zero payments.
Essa contagem e evidencia comunicada pela thread Financeiro, nao consulta de
producao. A suite Financial ainda tem uma falha conhecida no WIP de capacidade;
nao a classificamos como totalmente verde.

## Reproducao local

O harness Financial e os proxies precisam estar iniciados. O spec usa o segundo
comprador ficticio, reservado para essa rodada, porque o smoke Financial utiliza
o primeiro. A intencao unpaid remota permanece no banco Financial depois do
rollback dos exemplos Rails; nao repetir outra compra para o mesmo comprador
sem preparar um novo cenario ficticio pelo harness.

```text
node .codex/local-test/run.mjs --integration bundle exec rspec .codex/local-test/gate1_spec.rb --seed 42 --format progress
node .codex/local-test/run.mjs bundle exec rspec spec/requests/api/v1/accounts/autonomia/store_spec.rb spec/requests/api/v1/accounts/autonomia/store_customer_spec.rb spec/requests/webhooks/financial_store_spec.rb spec/services/autonomia/store --seed 42 --format progress
node .codex/local-test/run.mjs bundle exec rspec --options /dev/null spec/contracts/autonomia/financial spec/contracts/autonomia/store --seed 42 --format progress
```

O harness e o spec de integracao sao artefatos locais ignorados pelo Git, sem
credenciais de producao. A futura automatizacao em CI requer completar o segundo
gate e preparar fixtures/reset de cenario proprios; nao foi criada pipeline aqui.

## Bloqueios para o segundo gate

Pendencias confirmadas pela thread Financeiro - Asaas:

1. Binding oficial do gateway, lease externo, pagina hospedada de checkout,
   recuperacao do resultado desconhecido e expiracao segura de intent unpaid.
2. Confirmacao canonica invoice/payment/ledger/contrato, com validacao de
   empresa, operator, gateway, valor, moeda e customer; trial setup sem fatura
   zero, e renovacao pelo billing runner existente.
3. Rotas reserve/read/commit/release e entitlements.resolve. A migration 056 e
   `store-capacity-repository.ts` estao WIP; o teste accessVersion 2 versus 0
   continua falhando. Atomicidade da ultima vaga exige validacao PG17 real.
4. Eventos subscription.updated e snapshots efetivos, outbox atomico, versoes
   por stream, dispatcher HTTPS/HMAC, retry e callback/inbox Rails reais.

Somente apos essas implementacoes sera possivel homologar:
pagamento -> contrato ativo -> reserva -> commit -> outbox -> callback ->
ativacao -> limite excedido -> release.

Nenhum sucesso dessa cadeia foi simulado ou atribuido ao redirect do browser.
O Chatwoot continua fail-closed sem confirmacao de grant. E2 permanece parcial.

## Encerramento

A thread Financeiro encerrou apenas Financial/JWKS. Nesta thread os proxies,
PostgreSQL e Redis exclusivos de testes sao encerrados ao finalizar, preservando
runtime/dados ficticios locais para reutilizacao e sem servicos automaticos.
