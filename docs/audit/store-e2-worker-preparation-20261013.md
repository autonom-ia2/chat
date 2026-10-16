# Loja E2: preparacao do job de callbacks

## Escopo autorizado

Em 13/10/2026, o usuario autorizou somente o item 1 da proxima etapa:
conectar o dispatcher financeiro a um job agendado e preparar rede/segredos
em codigo. Os itens 2 (build completo do Chatwoot), 3 (gateway sandbox real)
e 4 (comissoes) foram adiados para depois da implementacao completa.

**Resultado: item 1 implementado e validado localmente. Nao operacional na AWS.**
Nenhuma PR, push, deploy, aplicacao de infraestrutura ou alteracao de dados e
segredos de producao. Nenhum Rails em producao. A E2 funcional local anterior
permanece homologada; esta rodada nao altera frontend, Auth ou pagamentos.

## Implementacao no Financeiro

Checkout local: `autonomia-financial-store-checkout`, branch
`codex/store-checkout-activation`, head `f1cc664`, worktree limpo no checkpoint.

- `src/store-event-outbox-runner.ts`: entrypoint agendado com flag default false;
  desabilitado nao abre PostgreSQL, SSM ou Invoke.
- `src/store-event-lambda-transport.ts`: Invoke privado, sincrono, timeout/abort
  de 20 segundos, sem retry do SDK. Outbox continua sendo a autoridade de retry.
- `src/store-event-bridge.ts`: HTTPS fora da VPC reutilizando o transporte
  existente, sem DB, SSM, JWT, segredo de assinatura ou endpoint HTTP publico.
- `src/store-event-dispatcher.ts`: guarda opcional de tempo antes de cada claim;
  nao reserva evento que nao tenha orcamento para uma entrega.
- `serverless.yml`: agenda configuravel, inicialmente DISABLED; roles dedicadas
  para worker e bridge. Nenhum NAT, mudanca de subnets ou workflow de deploy.

O worker herda a VPC privada existente e usa o interface endpoint Lambda para
a bridge. O projeto ja usa este padrao em outras integracoes. Referencias:
[AWS VPC e permissoes ENI](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html)
e [AWS Invoke por interface endpoint](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc-endpoints.html).
Essas referencias nao comprovam conectividade de recursos de producao.

## Limites e segredos

| Controle | Preparado |
| --- | --- |
| Ativacao | FINANCIAL_STORE_EVENT_WORKER_ENABLED=false |
| Agenda | rate(1 minute), configuravel; DISABLED no artefato compilado |
| Lote | 4 por default; 1 a 25; envio sequencial e sujeito ao orcamento |
| Worker | timeout 55 s, concorrencia 1, async retry Lambda 0 |
| Orcamento | 45 s; exige margem antes de iniciar outra entrega |
| Lease | 60 s, sem alteracao |
| Bridge e Invoke | timeout 20 s; sem seguir redirects |
| PostgreSQL | pool 1; connection 3 s, statement 5 s, lock 1 s |

HMAC, payload, eventId, ordem por stream, compare-and-set de lease, backoff e
idempotencia foram preservados. Resultado ambiguo nao confirma entrega; o
evento permanece recuperavel com o mesmo ID e assinatura fresca no retry.

Somente o worker pode ler os dois SecureStrings por caller, com nomes:

```text
/autonomia/<stage>/financial/store/callers/<callerUuid>/webhook-secret
/autonomia/<stage>/financial/store/callers/<callerUuid>/actor-assertion-secret
```

Nao foram criados valores reais. O segredo webhook continua independente do
segredo de assertion e da chave do caller. Referencias fora desse prefixo falham
fechadas. IAM concede GetParameter e decrypt condicionados ao contexto STORE,
Invoke exclusivo da bridge e logs proprios; nao permite escrever parametros.
A bridge tem somente logs. Permissoes ENI sao para o servico Lambda; uma Deny
por SourceFunctionArn impede uso pelo codigo do worker. Nenhuma role antiga
ou permissao PostgreSQL de producao foi alterada.

## Evidencias

- Financeiro informou 1079 testes aprovados, 239 opt-in/externos skipped,
  lint/typecheck/build aprovados no checkpoint final.
- Handler real aprovado em PostgreSQL 17 com financial_api_runtime restrito:
  um evento delivered e outro pending/retry; caller sem UPDATE e outbox sem DELETE.
- Banco novo exclusivo: financial_store_event_worker_integration, no cluster
  loopback 55439. Nao drenou nem resetou financial_store_e2_integration.
- Testes cobrem disabled sem dependencias, falta de configuracao, budget,
  assinaturas, falhas/ambiguidade no Invoke, timeout, segredo fora do prefixo,
  erros sanitizados, DNS publico/privado misturado, IP pinado e redirect sem follow.
- Mutation removendo/invertendo o guard de tempo foi detectada; fonte restaurada.
- Package do Serverless real em stage ci com env ficticio e rede bloqueada.
  Revisao independente nesta thread confirmou no CloudFormation gerado:
  DISABLED, timeout/concurrency, roles proprias, VPC somente no worker, ausencia
  de variaveis DB/JWT/API na bridge, DescribeSubnets e Deny ENI na role nova.
- git diff --check aprovado e cluster local conferido desligado por pg_ctl.
  Nenhum Redis, Rails ou Vite precisou iniciar nesta rodada.

Os testes simulam SecretStore e Invoke/provider nas bordas. Nao sao evidencia
de EventBridge, IAM, endpoint, KMS ou callback funcionando em producao.

## Gates mantidos

1. Os itens 2, 3 e 4 permanecem adiados por decisao do usuario, nao aprovados
   nem executados nesta entrega.
2. Publicacao e ativacao futuras exigem aprovar CI/PR/workflow, conferir endpoints,
   ingress/RDS e key policy, provisionar segredos independentes e registrar caller.
3. Workflow existente nao passa automaticamente as novas variaveis STORE;
   preparar essa ativacao pelo fluxo aprovado, nao habilitar a agenda por acidente.
4. Rollback desabilita agenda/flag, aguarda lease e preserva outbox/inbox, versoes,
   contratos, pagamentos e dados. Nao apagar registros para reiniciar a fila.

Detalhamento do componente e comandos de verificacao no repositorio Financeiro:
`docs/store-event-worker.md`.
