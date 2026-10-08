# Issue 995 — falha de liberação do navegador persistente

## Resultado observado

A revisão e os testes do PR #1161 passaram, mas não comprovaram a sequência real de operações Meta no mesmo navegador persistente. O critério de liberação foi insuficiente. Não houve aprovação técnica do objetivo de reduzir o tempo em dez vezes.

O piloto do backend publicado em 49a5b76b86f9574af427a08fc8d8e80a38565c78 encontrou o perfil em 12,456 segundos (registro criado → resultado publicado). A confirmação seguinte não terminou em 120 segundos. Não apresentar esse resultado como melhoria de dez vezes ou sucesso da conexão.

Às 16:32:33 UTC, o manager Hub2You encerrou com código 1. O journal sanitizado confirmou `route.continue: Route is already handled!` em `session-manager.mjs:386`. Não foi OOM. O callback permanente do contexto não continha a rejeição assíncrona da rota; o callback temporário da operação já tratava falhas de rota. A origem exata do duplo tratamento não foi reproduzida e continua em investigação.

## Contenção operacional

Rollback somente da VPS para o artefato anterior 61f20cfd107361a431fda51f02cace751cc4978d. As aplicações AWS permanecem em 49a5b76b86f9574af427a08fc8d8e80a38565c78. Não houve outro deploy AWS durante esta correção.

O rollback usou compare-and-swap do caminho current, parada graciosa do processo principal, verificação de cgroups/UID sem processos de navegador e preservação dos perfis/cookies/Singletons. O lock vazio órfão da Hub2You foi movido para a pasta privada de auditoria após essas verificações; não foi apagado nenhum perfil. Foram restauradas as duas configurações anteriores de CPU dos publishers a partir dos backups com hash verificado. O recibo confirmou oito serviços ativos sem reinícios, Node privado preservado, gateways 401 sem cookie e bootstrap dos dois publishers. Isso comprova restauração dos serviços, não aceitação Meta nem conexão OAuth.

## Correção proposta

Conter a rejeição de continue/abort no callback permanente. Rota já concluída não recebe novo abort. Nas outras falhas, abortar com diagnóstico fixo protegido. Página fechada conclui a observação uma vez e encerra o ciclo para liberar contexto e lock. A falha nunca permite continuar uma requisição rejeitada pela política. Não alterar allowlist, convites, permissões, timeouts ou configuração AWS.

## Validações executadas

- Node 24: `node --test --test-name-pattern='persistent guard contains' tests/instagram_testers/session-manager.test.mjs`: com o código publicado, 2 falhas com o mesmo erro; com a correção local, 2 passam.
- `node --test tests/instagram_testers/session-manager.test.mjs`: 62 passam, zero falhas/pendências na rodada ampliada.
- Os dois casos novos injetam rejeição de continue/abort no manager, verificam a continuação de busca seguida de status e verificam que uma requisição não autorizada continua bloqueada. São testes sintéticos; não substituem Playwright/Chrome e Meta reais.
- O planner MacCluster não encontrou nó elegível: m2 sem este working tree; m4 com disco insuficiente. Esses testes leves de Node foram executados localmente, sem build ou instalação de dependências.

## Gate pendente

Não liberar esta proposta com base apenas nos testes acima. Antes da próxima ativação, validar o callback com Chrome/Playwright real em perfil descartável e depois a sequência Meta real repetida no piloto autorizado. Medir busca e confirmação separadamente. Confirmar que o aceite retorna autorização para o OAuth original sem nova operação VPS; esse ponto não foi alcançado pelo piloto que falhou. Ainda falta comprovar redução em dez vezes.

## Rodada de estresse antes do merge (PR #1163)

Merge bloqueado enquanto houver falha ou evidência ausente. O novo pedido do Rodrigo é ampliar caminhos tristes antes de publicar. Não houve merge, deploy AWS nem ativação de candidato VPS nesta rodada.

### Processo e transporte

Comando executado com Node 24 local: `node --test tests/instagram_testers/session-manager.test.mjs tests/instagram_testers/publisher-channel.test.mjs tests/instagram_testers/vps-publisher.test.mjs`. Resultado: **150 testes executados, 150 aprovados, zero pendências** (62 manager, 10 canal, 78 publisher).

A cobertura inclui 1 e 1.000 rejeições concorrentes de rota, falha do escritor de diagnóstico, continuidade busca/status, página fechada com conclusão única e liberação de lock; fila FIFO, cancelamento de um pedido sem cancelar o seguinte, perda de resposta de permissão de convite sem reenvio, EOF, parada de serviço, limite de buffer, concorrência, troca de CURRENT com pedidos em fila e prewarm rejeitado.

### Chrome real com isolamento

Fixtures executados na VPS com DynamicUser, PrivateTmp, rede restrita a localhost, teto de CPU/memória e prazo da unidade. Código candidato copiado com hash; Playwright fixado do artefato 49a5, Node privado verificado e Chrome real instalado. Dados Meta/IDs/cookies são sintéticos; perfis de produção não foram utilizados. Serviços e current comparados antes/depois, sem alteração.

A matriz contém dez sequências busca/status/convite incerto (cada convite sintético somente um POST), dez rejeições reais de rota já tratada, navegação interrompida, resposta atrasada, timeout, conexão interrompida, página fechada, origem não autorizada, HTTP 401/403/407/429/500, JSON inválido, HTML de login, dados com erro, paginação parcial e status conflitante. UI: botão, campo ou opção ambíguos, opção invisível/desabilitada e documento sem Roles. Lifecycle: processo completo com página fechada, deadline e retomada no mesmo perfil descartável.

Resultados finais: **39/39 casos de rotas em 76 operações**, **6/6 UI**, **2/2 proxy**, **4/4 ciclos do manager**. Zero unhandled rejections. Cookies persistentes sintéticos semeados apenas no primeiro ciclo, restaurados três vezes sem addCookies. Deadline disparado somente depois de o POST atrasado chegar. Cada ciclo publicou uma sessão; 8 POSTs Roles e zero typeahead/convite no lifecycle. Recibos em `995-stress-results-20261008.json`.

Os quatro grupos de Chrome têm steps independentes no CI: uma reprovação não impede os demais. Adicionado gatilho para `tests/qa/instagram-automation/**`. O manager-lifecycle integra o gate e o ESLint.

### Aceite e fluxo original

`useInstagramTester.authorize` envia a prova recebida na confirmação e redireciona para a URL original. `authorizations_controller` chama BrowserAuthorization.prepare quando essa prova está presente. O spec `tester_authorization_spec.rb` exige que BrowserOperations não seja criado nesse caminho; também cobre prova ausente, expirada ou de outro perfil/conta/ator, ACL, nonce novo e reconexão de caixa existente sem infraestrutura de testadores. Isso comprova contrato em código/testes; ainda falta comprovação na conta 18 publicada.

### Critérios reais que permanecem obrigatórios

- Busca Meta real: no máximo 8,0966 s (referência histórica 80,966 s).
- Status Meta real: no máximo 4,2506 s (referência 42,506 s).
- Confirmação de aceite: no máximo 5,1028 s (referência 51,028 s).
- Resposta total ao operador abaixo de 120 s, com erro claro quando necessário. Não ampliar limites para declarar melhoria.
- Aceite confirmado → OAuth original sem novo pedido de abertura/preparação VPS.
- Conexão e reconexão autorizadas funcionando na conta 18, sem novo convite nem mensagens reais.

O último piloto real foi busca 12,456 s e status sem conclusão em 120 s. Não atingiu dez vezes e não concluiu conexão. Nenhum benchmark de localhost substitui esses números.

## Checklist antes do merge

| Verificação                                        | Resultado          | Evidência/limite                                                        |
| -------------------------------------------------- | ------------------ | ----------------------------------------------------------------------- |
| Processo, canal e publisher                        | PASSOU             | 150/150, zero pendências                                                |
| Rotas concorrentes e diagnóstico quebrado          | PASSOU             | 1/1.000 falhas contidas                                                 |
| Sequências e falhas no Chrome                      | PASSOU             | 39/39, 76 operações, zero unhandled                                     |
| UI ambígua/incompleta                              | PASSOU             | 6/6, zero convite, recuperação accepted                                 |
| Proxy sem autorização                              | PASSOU             | 2/2, CONNECT 407 confirmado por TCP, sem falso accepted                 |
| Página fechada/deadline/lock                       | PASSOU             | 4 ciclos completos, watchdog não disparou                               |
| Perfil preservado ao reiniciar                     | PASSOU (sintético) | cookies restaurados 3 vezes sem adicioná-los novamente                  |
| Isolamento de produção                             | PASSOU             | oito serviços/PIDs/quotas/current inalterados, nenhum perfil real usado |
| Revisão independente                               | PASSOU             | Nexo sem bloqueio funcional; condição final 39/39 cumprida              |
| CI do commit final                                 | PENDENTE           | snapshot anterior não aprova a nova versão                              |
| Meta real: busca/status/aceite em 10×              | NÃO VALIDADO       | último piloto busca 12,456 s; status sem conclusão em 120 s             |
| Conta 18 conectada/reconectada pelo OAuth original | NÃO VALIDADO       | contrato coberto, sem exercício real concluído                          |
| Renovação natural/reboot com sessão Meta legítima  | NÃO VALIDADO       | perfil sintético não comprova isto                                      |

**Não liberar merge/deploy por enquanto.**

### Diagnósticos e limites

O falso erro de bootstrap do fixture veio da assinatura do publisher sintético; corrigida para command/payload/options. O watchdog continua reprovando hang. Opções inválidas são rejeitadas durante typeahead_response, antes de invite_execution; ajustada apenas a fase esperada, preservando invalid_selection, contagens e zero convite.

O Chrome consome HTTP 407 como requestfailed ERR_UNEXPECTED_PROXY_AUTH, sem entregar resposta 407 à página. Outro teste confirmou CONNECT 407 por TCP e ERR_INVALID_AUTH_CREDENTIALS no Chrome. Resultado meta_unavailable de transporte, nunca accepted. A matriz exige a causa exata observada. Não foi alterada produção para forçar proxy_unavailable.

Playwright 1.59.1 e Chrome 154.0.8037.97, com hashes registrados. Fonte candidata testada com dependências fixadas do artefato 49a5, não uma instalação Meta autenticada. Lifecycle usa chromiumSandbox=false apenas no launcher injetado do fixture; não muda sandbox de produção. Perfis/cookies sintéticos, localhost, zero convite real.

### Próxima liberação e rollback

A mudança executável está no manager VPS. Aplicações AWS continuam com o código já publicado em 49a5; este diff não justifica outro deploy AWS. Concluir CI/revisão antes de ativação; preservar 61f20 para rollback, verificar exclusividade de perfil/lock e artefato imutável/dependências/Node privados. O piloto autorizado deve medir os tempos Meta reais, OAuth original e conexão/reconexão. Reverter se o processo cair, voltar a abrir/preparar Instagram na VPS após aceite ou falhar conexão. Não remover perfil/cookies/Singletons nem concluir a Issue 995 por fixtures.
