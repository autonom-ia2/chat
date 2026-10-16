# Loja E2: homologacao integrada local

## Autorizacao e estado

Em 13/10/2026, o usuario autorizou coordenar com Financeiro - Asaas a conclusao
de pagamento, capacidade e callbacks, seguida da homologacao E2 completa.
Continuam proibidos PR, push, merge, deploy, producao e pagamentos reais.

**Estado: E2 homologada localmente, inclusive repeticao no head final do
Financeiro com a protecao 059.** Foram homologados quatro cenarios entre
os backends reais, com gateway e Identity ficticios nas bordas. Nao foi usada
atualizacao SQL de contrato para declarar sucesso de pagamento integrado.
Esta evidencia nao autoriza publicacao nem equivale a uma compra em producao.

As duas branches locais sao `codex/store-checkout-activation`, nos checkouts
`chatwoot-store-integration` e `autonomia-financial-store-checkout`. O contrato
continua E2-20261013-v1; contrato e fixtures foram comparados e estao identicos.

## Ambiente isolado

- PostgreSQL 17 em 127.0.0.1:55439: 12 conexoes, shared_buffers 32 MB,
  work_mem 2 MB, maintenance_work_mem 32 MB. Sem servico automatico.
- Bancos separados: `chatwoot_store_e2_test` e `financial_store_e2_integration`.
- Redis de testes em 127.0.0.1:6397, limite 32 MB, sem persistencia. Redis
  preexistente em outra porta nao foi alterado.
- Ruby 3.4.4 e gems locais; launcher com ambiente allowlist, dotenv vazio,
  Rails test e bloqueio de conexoes externas. Nenhum Rails em producao.
- Financial HTTPS localhost:3009, Identity/JWKS localhost:3011/me e callback
  HTTPS localhost:5192/api/autonomia/financial/store-events.
- CA ficticia confiada somente pelo launcher local. TLS do produto nao foi
  desabilitado. Proxy restrito as rotas da loja, hosted checkout, webhook
  Stripe, Identity/JWKS e callback. Diagnosticos nao passam pelo proxy.
- Callback/BFF em Puma local com um thread HTTP e um consumidor de jobs. O
  controller, HMAC, schema, inbox, job e PostgreSQL sao os reais da aplicacao.
- Credenciais ficticias independentes, arquivos ignorados com permissao 0600.
  Nenhum token, segredo, URL de pagamento ou payload sensivel no relatorio.

## Correcoes adicionais no Chatwoot

1. `EventJob` agora verifica buyer, namespace, preco e IDs de correlacao depois
   de adquirir o lock da intencao. Um teste reproduziu a substituicao indevida
   de um ID alterado entre a leitura inicial e o lock; passou apos a correcao.
2. Criacao e consulta de status do checkout agora preservam IDs previamente
   correlacionados pelo callback, verificando-os sob lock. Uma assinatura
   divergente gera erro sanitizado e nao substitui a assinatura confirmada.
3. Testes de callbacks cobrem resposta de checkout perdida, pagamento unpaid,
   replay, versao antiga, buyer/namespace/preco divergentes, falha de aplicacao
   com inbox pending e reenvio de evento pending.
4. Testes de ativacao cobrem limite esgotado, commit com resposta perdida e
   release com resposta perdida. A mesma intencao e reutilizada, sem reservar
   novamente ou conceder acesso durante recuperacao.
5. Testes do componente de retorno, com StoreAPI substituido no teste, cobrem
   consulta de status do BFF,
   completed/expired/failed, cancelamento no browser sem cancelamento financeiro,
   polling limitado, abort ao fechar e rejeicao de operacao externa.
6. A autorizacao da feature contratada recusa conta suspensa, sem apagar
   direitos ou alterar a configuracao manual legada.
7. O frontend traduz limite esgotado e sessao expirada usando mensagens
   fechadas, sem expor resposta financeira ou marcar recurso como disponivel.

## Evidencias ja verificadas

| Verificacao | Resultado |
| --- | --- |
| Callback HTTPS assinado ao Rails real | 202, inbox persistido e EventJob processed |
| Autorizacao de recurso pelo callback do smoke | Nenhuma ativacao/grant foi criado |
| Specs Rails da loja, EventJob, status e unpaid | 56 exemplos, 0 falhas |
| Specs Ruby de protocolo | 90 exemplos, 0 falhas |
| Specs JS/Vue da loja e rotas | 40 testes, 0 falhas |
| Quatro cenarios integrados entre backends | Repetidos no Financial d15a983: 4 exemplos, 0 falhas, 3,43 s + boot 2,26 s |
| RuboCop focado da loja e protocolos alterados | 40 arquivos, 0 infracoes |
| ESLint das 29 unidades JS/Vue novas/focadas | 0 erros, 0 avisos com max-warnings 0 |
| Sidebar e painel existentes modificados | 0 erros; 89 e 6 avisos preexistentes, sem aumento |
| i18n com aviso de limite excedido | 15 catalogos, 21422 mensagens cobertas |
| Contrato e fixtures compartilhados | Identicos ao Financeiro |
| Guia gerado | Check aprovado: 201 fluxos, 191 telas |
| Preview dos componentes reais | Build aprovado: 87 modulos, 6,61 segundos |
| Navegador desktop e mobile | Fluxo pago, ativacao, release e restricao de perfil aprovados |

O evento ficticio do smoke foi removido pelo ID exato apos o teste para nao
contaminar os testes transacionais seguintes. Nenhuma limpeza ampla foi feita.
Avisos de enums Rails, Rack, i18n duplicado e source map ja existiam e nao foram
mascarados. A verificacao ampliada tambem encontrou aviso de chave dinamica no
helpers.js financeiro preexistente; esse arquivo nao foi alterado. O aviso novo
de FINANCIAL.STORE.TITLE na sidebar foi resolvido lendo o catalogo financeiro,
sem desabilitar regras. Build completo Vite segue com a limitacao de memoria documentada
no relatorio anterior; nao foi tratado como aprovado.

## Dispatcher implementado nesta coordenacao

Com ownership confirmado pela thread Financeiro, foram implementados somente
os arquivos `src/store-event-dispatcher.ts` e `tests/store-event-dispatcher.test.ts`
do checkout Financial. A outra thread continua responsavel por writers de
outbox, settlement, billing runner, rotas e integracao do dispatcher no harness.

- Claim de um evento por vez com SKIP LOCKED e lease de 60 segundos, sem lock
  da registry SELECT-only. Ordem por stream; evento posterior nao ultrapassa
  evento anterior pending. Batch padrao 4, teto 25.
- Ack/retry compare-and-set por lease token e prazo; lease vencido e recuperavel.
- Payload/eventId persistentes; assinatura HMAC nova por tentativa, com o
  contrato exato timestamp.eventId.rawBody. Apenas 2xx confirma entrega.
- Retry com backoff/Retry-After limitados a uma hora, sem apagar o evento.
- HTTPS sem redirects, corpo de resposta descartado sem parse/acumulacao.
  DNS validado e IP pinado; IP direto, private/metadata/reservado, credenciais,
  query e fragmento recusados. CA/localhost:5192 permitidos somente no teste.
- Segredo independente do API key hash e actor secret; chamadas ao SecretStore
  e transporte com timeout. Logs somente IDs tecnicos, contadores e codigos.
- Filtros de caller/event IDs/streams para nao drenar fixtures UNIT alheias.

Verificacao: 28 testes UNIT e dois testes PG17 reais passaram (30 no total).
Dois backend PIDs diferentes com `financial_api_runtime` reclamaram um evento
uma unica vez; pg_stat_activity confirmou xact_start NULL durante HTTP. Outro
teste recuperou lease vencido sem dar UPDATE na registry. Fixture UNIT propria
foi removida pelos IDs exatos; nenhum root ou pagamento foi modificado.

O transporte HTTPS nativo tambem enviou um evento ficticio ao Rails e recebeu
202. O inbox ficou pending inicialmente porque o reload de classes do Rails
substituiu o adapter do job no harness. Foi corrigido somente o harness de
teste: adapter global restrito aos EventJobs. Reenvio do mesmo eventId/body,
com assinatura fresca, confirmou processed sem duplicar. O smoke foi limpo
pelo ID exato. Essa prova e de transporte/inbox, nao de pagamento.

## Primeiro ensaio do gate completo

O orquestrador local usa o BFF, TokenStore, Identity/JWKS, assertions, hosted
GET com nonce e POST/start com Origin correto. Contrato unpaid foi recusado
para ativacao. Nenhuma URL ficticia Stripe foi seguida.

Um desajuste no DTO do diagnostico `/evidence` foi corrigido no orquestrador
(`scenarioId` apenas). Em seguida, o status interno do webhook foi assertado,
identificando erro 400 no caminho real de pagamento. O teste parou antes de
declarar pagamento, conceder acesso ou consumir capacidade.

A thread Financeiro confirmou a causa no PostgreSQL restrito: SQLSTATE 42501
em `payment_settlement_sources`. O ledger fazia SELECT FOR UPDATE em uma tabela
append-only com SELECT+INSERT; PostgreSQL exige UPDATE para esse row lock.
Nao e falha de assinatura nem justificativa para ampliar permissoes. A correcao
concluida serializa por payment com advisory transaction lock, mantendo
fontes/eventos imutaveis. A nova migration 058 substitui o trigger sem modificar
a migration 036 aplicada. Seis testes PG17 verificaram capture, replay concorrente,
reversal, divergencia 409 e UPDATE/DELETE ainda negados. Depois do checkpoint,
o mesmo fluxo integrado passou com invoice paid, payment e ledger canonicos.
Nenhum contrato foi ativado por SQL.

O teste independente encontrou tambem FOR SHARE no trigger
`guard_payment_settlement_event_scope` da migration 036. Financeiro manteve
ownership do codigo do ledger e da nova migration 058/rollback: nao editar 036,
nao ampliar grants, preservar todos os checks/FKs e serializar por payment.
Essa segunda correcao resolveu o mesmo bloqueio; a prova de pagamento veio
depois, pelo webhook assinado e persistencia canonica, nao da migration isolada.

## Checkpoint recebido do Financeiro

A thread Financeiro - Asaas informou a correcao accessVersion 2 versus 0,
replay/hash, rotas reserve/read/commit/release, resolver consistente e rollback
da migration 056. Seu checkpoint final local d15a983 teve 1050 testes aprovados e
238 testes opt-in/externos skipped, lint/build/typecheck aprovados. Informou
seis testes PG17 reais de ultima vaga concorrente, replay, agregacao/release,
expiracao e namespace, seis do ledger e 30 do dispatcher. Esses numeros sao
evidencia comunicada pela thread responsavel, nao execucao de producao.

Esses testes de repository usam roots UNIT isolados. Seus contratos active e
outbox UNIT **nao sao evidencia de pagamento** e nao podem ser utilizados no
cenario integrado. Os dados gate 1 unpaid foram preservados.

Hosted checkout acordado:

```text
GET  /financial/public/store/checkout-sessions/:id
POST /financial/public/store/checkout-sessions/:id/start
GET  /financial/public/store/checkout-sessions/:id/return?result=return|cancel
```

GET apresenta a cotacao e nonce; POST usa nonce emitido pelo GET, sem overrides
de preco, gateway ou retorno. Handoff retorna 303 para o provider, sem remover
fragmento da URL. O retorno usa somente origem/conta/intencao persistidas e nao
confirma pagamento nem cancela contrato. Implementacao e fluxo HTTP reais
foram exercitados nos quatro cenarios abaixo.

## Gate final requerido

Cada cenario utiliza buyer/intencao novos e registros ficticios committed, para
o receptor Rails enxergar as linhas. Nenhuma regra de negocio e substituida.
Somente Identity/JWKS, SecretStore e gateway sao bordas ficticias autorizadas.

| Cenario | Prova requerida | Estado |
| --- | --- | --- |
| Checkout pago | Binding + invoice/payment/ledger + contrato autorizado | Integrado aprovado; replay sem dinheiro duplicado |
| Trial | Card setup oficial, invoice positiva pending, zero payment/ledger | Integrado aprovado; contrato trialing |
| Falha e retorno cancelado | Sem grant; redirect nao cancela nem confirma | Integrado aprovado |
| Resultado desconhecido | Mesma sessao/intencao, read-only recovery no provider | Integrado aprovado; sem segunda chamada de compra |
| Capacidade integrada | Reserva/commit reais apos contrato autorizado | Integrado aprovado |
| Callback integrado | Outbox real, dispatcher HTTPS/HMAC, inbox e projecao | Integrado aprovado; 202 seguido de processed |
| Feature piloto | Prospecting somente na conta beneficiaria confirmada | Integrado aprovado; demais contas negadas |
| Ultima vaga | Concorrencia e erro de limite sem acesso indevido | PG17 concorrente aprovado; segunda conta recusada no integrado |
| Release | Desabilita acesso, devolve ocupacao e preserva dados | Integrado e navegador aprovados; vaga reutilizada |
| Eventos repetidos/fora de ordem | Inbox idempotente e versoes por stream | Specs verdes; replay de pagamento integrado sem duplicacao |
| Renovacao | Billing runner existente, sem StripeSubscription paralelo | Testes financeiros mensal/anual; nao houve ciclo real no browser |
| Isolamento | Buyer/namespace/conta e SuperAdmin nas fronteiras | Specs verdes; ordinary admin negado no browser e BFF 403 |

Nao ha alteracao planejada no Auth: OAuth access token, `/me.user.cognitoSub` e
TokenStore existentes permanecem o contrato de identidade. Se a homologacao
mostrar uma incompatibilidade real, ela sera registrada antes de mudar o Auth.

## Navegador com BFF real

A pagina local usou os componentes Vue reais da loja, ChoiceSelect e Dialog,
com requests reais ao BFF Rails. Apenas o shell e os perfis foram fixtures.
Na borda do checkout, uma ponte local seguiu GET/nonce/start reais e emitiu
o evento de gateway ficticio pela verificacao canonica de assinatura. Nenhuma
URL de provider externo foi seguida, nenhum pagamento real foi feito.

1. Catalogo, detalhes e selecao do plano Pilot: contrato inicial unpaid.
2. Confirmacao pelo webhook/ledger/outbox/callback: Ativa e 0 de 1 conta.
3. Conta escolhida por combobox: Capacidade reservada, depois Disponivel e 1 de 1.
4. Desabilitar: acesso retirado, capacidade 0 de 1 e registro preservado.
5. Perfil administrador sem SuperAdmin: loja nao exibida; BFF real respondeu 403.
6. Desktop 1280x720 e mobile 390x844: popup limitado, lista sobreposta e largura
   do documento igual a 390 no mobile. Escape fechou popup e devolveu foco ao
   botao Habilitar. Capturas locais em .codex/local-test/store-e2-{desktop,mobile}.jpg.

Essa prova nao cobre o login real do Auth, o shell completo do dashboard,
uma cobranca no Stripe/Asaas ou o deploy AWS. O checkout gratuito com preco zero
nao faz parte do MVP; trial nao e tratado como pagamento zero.

## Revisao final e limites de publicacao

A revisao financeira encontrou um risco concreto: trocar accountId ou mode de
um gateway no mesmo ID apos bind altera o contexto lido por recovery/renovacao
e pode invalidar callbacks antigos. Nao foi comprovada cobranca cruzada ou
bypass de JWT. O Financeiro implementou a nova migration reversivel 059, sem
editar 020, ampliar grants de producao, adicionar colunas ou fazer backfill.
Ela estende o guard existente a checkout e contrato STORE vinculados e impede
mudar operador, registry/provider, public key, account e mode. Segredos, label
e status continuam mutaveis conforme a regra existente.

O bind adquire FOR SHARE no gateway operacional/mutavel e compara novamente
o contexto antes de vincular checkout/root na mesma transacao. O UPDATE usa
o mesmo fence. A API converte a recusa do guard em 409. Os nove testes PG17
passaram, incluindo bloqueio entre duas conexoes nos dois ordenamentos, contexto
stale recusado antes de efeito externo e rotacao permitida. Os testes focados
tambem cobriram rollback preservando dados, webhook no contexto original,
recovery e renovacao mensal/anual com novas credenciais no mesmo contexto.
UPDATE na fixture local de company_gateways reproduz o CRUD operacional ja
previsto em 033; ledger append-only e caller SELECT-only nao receberam grants.

Continuam fora desta rodada: build completo Vite (heap local insuficiente),
entrypoint, agenda e egress do dispatcher em AWS, credenciais de producao, homologacao
com gateway sandbox real, criacao de instancia de agente contratado (fase
posterior) e liberacao da loja a administradores comuns. Sem PR/push/deploy.

Atualizacao posterior em 13/10/2026: o usuario autorizou somente preparar o job
agendado/rede/segredos em codigo. Esse item foi concluido localmente no Financeiro
head f1cc664, com agenda DISABLED, bridge privada e roles separadas. Nao houve
aplicacao ou ativacao AWS. Build completo do Chatwoot, sandbox real e comissoes
foram explicitamente adiados para depois da implementacao completa. Evidencia
e limites em [preparacao do worker](store-e2-worker-preparation-20261013.md).

## Limpeza e encerramento

A fixture UI foi removida apenas pelos dois user IDs, account ID e eventos do
buyer/namespace exatos, depois de verificar ativacao disabled e acesso negado.
Contratos/pagamentos ficticios no Financial foram preservados para auditoria;
nao foi feito reset amplo. A capacidade dos cenarios aprovados foi devolvida.
Uma tentativa inicial interrompida deixou fixture remota isolada, nao usada
como prova de sucesso; nao foi feita limpeza SQL de contrato financeiro.

Vite, Puma e proxies desta rodada foram encerrados; Financial/JWKS foram
encerrados pela thread responsavel. Redis 6397 e PostgreSQL 55439 exclusivos
de teste tambem foram desligados. Nenhum listener das nove portas da rodada
permaneceu ativo. O Redis preexistente e o prototipo independente da loja nao
foram alterados. Runtime e evidencias ficticias permanecem locais e ignorados
pelo Git, sem inicializacao automatica.
