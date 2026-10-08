# Issue 995 — falha de liberação do navegador persistente

## Resultado observado

A revisão e os testes do PR #1161 passaram, mas não comprovaram a sequência real de operações Meta no mesmo navegador persistente. O critério de liberação foi insuficiente. Não houve aprovação técnica do objetivo de reduzir o tempo em dez vezes.

O piloto do backend publicado em 49a5b76b86f9574af427a08fc8d8e80a38565c78 encontrou o perfil em 12,456 segundos (registro criado → resultado publicado). A confirmação seguinte não terminou em 120 segundos. Não apresentar esse resultado como melhoria de dez vezes ou sucesso da conexão.

Às 16:32:33 UTC, o manager Hub2You encerrou com código 1. O journal sanitizado confirmou `route.continue: Route is already handled!` em `session-manager.mjs:386`. Não foi OOM. O callback permanente do contexto não continha a rejeição assíncrona da rota; o callback temporário da operação já tratava falhas de rota. A origem exata do duplo tratamento não foi reproduzida e continua em investigação.

## Contenção operacional

Rollback somente da VPS para o artefato anterior 61f20cfd107361a431fda51f02cace751cc4978d. As aplicações AWS permanecem em 49a5b76b86f9574af427a08fc8d8e80a38565c78. Não houve outro deploy AWS durante esta correção.

O rollback usou compare-and-swap do caminho current, parada graciosa do processo principal, verificação de cgroups/UID sem processos de navegador e preservação dos perfis/cookies/Singletons. O lock vazio órfão da Hub2You foi movido para a pasta privada de auditoria após essas verificações; não foi apagado nenhum perfil. Foram restauradas as duas configurações anteriores de CPU dos publishers a partir dos backups com hash verificado. O recibo confirmou oito serviços ativos sem reinícios, Node privado preservado, gateways 401 sem cookie e bootstrap dos dois publishers. Isso comprova restauração dos serviços, não aceitação Meta nem conexão OAuth.

## Correção proposta

Conter a rejeição de continue/abort no callback permanente. Após falha, tentar abortar a requisição e emitir somente marcador fixo, sem URL, corpo, cookies ou detalhes da exceção. A falha nunca permite continuar uma requisição rejeitada pela política. Não alterar allowlist, convites, permissões, timeouts ou configuração AWS.

## Validações executadas

- Node 24: `node --test --test-name-pattern='persistent guard contains' tests/instagram_testers/session-manager.test.mjs`: com o código publicado, 2 falhas com o mesmo erro; com a correção local, 2 passam.
- `node --test tests/instagram_testers/session-manager.test.mjs`: 58 passam, zero falhas/pendências.
- Os dois casos novos injetam rejeição de continue/abort no manager, verificam a continuação de busca seguida de status e verificam que uma requisição não autorizada continua bloqueada. São testes sintéticos; não substituem Playwright/Chrome e Meta reais.
- O planner MacCluster não encontrou nó elegível: m2 sem este working tree; m4 com disco insuficiente. Esses testes leves de Node foram executados localmente, sem build ou instalação de dependências.

## Gate pendente

Não liberar esta proposta com base apenas nos testes acima. Antes da próxima ativação, validar o callback com Chrome/Playwright real em perfil descartável e depois a sequência Meta real repetida no piloto autorizado. Medir busca e confirmação separadamente. Confirmar que o aceite retorna autorização para o OAuth original sem nova operação VPS; esse ponto não foi alcançado pelo piloto que falhou. Ainda falta comprovar redução em dez vezes.
