# #436 — entrega integrada de proteção e gestão de campanhas

Data de validação local:17/09/2026. Escopo: código e PRs, **sem autorização de merge, deploy, liberação de campanha ou backfill em produção**.

## Série de PRs e ordem de aprovação

| Ordem | Entrega | Branch | Dependência |
| --- | --- | --- | --- |
| 1 | Higiene e quarentena | `feat/436-01-email-hygiene` | main |
| 2 | Reputação e admissão segura | `feat/436-02-email-reputation` | primeira PR |
| 3 | Métricas, filtros e API | `feat/436-03-email-reports` | segunda PR |
| 4 | UI humanizada e i18n | `feat/436-04-email-ux` | terceira PR |
| 5 | Histórico, recuperação e fechamento | `feat/436-05-email-operations` | quarta PR |

As bases das PRs2–5 são temporariamente as branches anteriores para manter a revisão delimitada. **Não usar Merge enquanto a base for uma feature branch.** Após aprovação e deploy saudável da PR anterior, rebasear/retargetear a próxima para main, repetir CI e conferir o diff antes da nova aprovação. Cada merge em main aciona blue/green; não são cinco merges simultâneos.

## Gates adversariais obrigatórios antes de merge

**PR442 não está pronta para merge.** O parent deve rebasear sobre a PR441 corrigida e integrar a correção de promoção do registry da PR438. Os resultados abaixo são registros de execuções anteriores; não validam esses fixes nem as novas regressões. Reexecutar no HEAD resultante, registrar SHA, cenário, resultado e artefato em `docs/audit/`, e submeter a review antes da aprovação explícita.

| Gate pendente | Prova exigida antes de merge |
| --- | --- |
| Compatibilidade de locks no deploy misto | PostgreSQL real com caminhos da versão atualmente implantada e da candidata concorrendo; exercitar escritores de feedback/supressão e admissão. Demonstrar ausência de deadlock e preservação dos positivos antigos. Testar somente dois workers da versão nova não satisfaz o gate. Se incompatíveis, bloquear rollout misto e revisar o plano de transição. |
| Bloqueio do provedor versus claim | Forçar as duas ordens de concorrência entre persistência do bloqueio e admissão. Nenhum novo transporte admitido depois do bloqueio persistido; claim já admitido e recibo têm semântica explícita. Não basta teste sequencial ou mock de lock. |
| Progresso com feedback contínuo | Injetar feedback durante avaliação/reconciliação; demonstrar progresso de gerações, publicação e processamento de pendências sem starvation, loop infinito ou aplicação de snapshot obsoleto. Registrar limites e contagens observados. |
| Renderização HTTP real da importação | Percorrer rota autenticada, importação assíncrona, status e resposta renderizada pelo serializer/Jbuilder real. Conferir a lista preservada no 202 e leitura final; UI deve consumir esse contrato. Fixtures JSON isoladas não cobrem a integração. |
| Ordem de chegada da quarentena | Permutar eventos antigos/recentes, duplicados e expiração; provar que a ordem de chegada não encurta a proteção devida, não conta duplicata e não transforma temporário em bloqueio eterno. |
| Evidência corrigida com a mesma chave | `unknown_bounce` já auditado em `ses:m1:bounce`, EmailEvent corrigido para Permanent/General, apply autorizado termina completed com hard_bounce ativo, positivo legado e reimportação suprimida. Repetição idempotente/nova execução não promove duas vezes. Incluir prevenção corrigida, prioridade forte e auditoria append-only; executar `maintenance/corrected_evidence_spec.rb` após PR438. |
| Denominador misto | Coorte sintética com SES, DirectInbox e origem desconhecida; conferir numeradores/denominadores coerentes entre SQL, HTTP e UI, distinguindo prevenção, permanente global e métrica oficial. Não misturar entregas aceitas de uma origem com eventos de outra. |
| Erro aninhado na UI | Usar o formato de erro aninhado realmente devolvido pela API; verificar mensagem visível, estado de loading encerrado, dados preservados e retry utilizável. Não aceitar `[object Object]`, erro invisível ou sucesso indevido. |

Esses gates complementam as suítes existentes de horizonte/cursor, batch, fencing, idempotência e paridade preview/apply. Nesta rodada foram autorizados somente sintaxe e RuboCop; Rails/Postgres e os gates integrados ficam para o parent após os rebases, em harness isolado. Nenhum gate pendente pode ser substituído pelos números históricos a seguir.

## Evidência integrada anterior aos fixes adversariais

| Gate | Resultado local | Evidência |
| --- | --- | --- |
| Backend cumulativo das cinco entregas + regressões | 829 exemplos, zero falhas; um pending preexistente de Account | `tmp/email436/final-series-rspec.json` |
| Frontend completo | 459 arquivos,5.058 testes aprovados; zero falhas/pending | `436-reports-integration/tmp/email436/ui-integrated-vitest-final.json` |
| Idiomas | 57 módulos,43 ativos;262 chaves/módulo;14.934 mensagens compiladas/renderizadas; fallback false | `ui-integrated-locales.log` e script de i18n |
| Build | Vite test aprovado, CSS/componentes reais | `ui-integrated-build.log` |
| Browser | 137 checks aprovados;97 capturas | `visual/results.json` e PNGs no harness/artefato CI |
| Ruby lint | 177 arquivos cumulativos sem infrações | `final-series-rubocop.log` |
| Contratos Ruby puros | 38 testes,50.733 asserções; sem falhas/erros/skips | `final-series-pure.log` |
| ESLint | Zero erros/chaves literais ausentes; apenas warning nativo de chave dinâmica | `ci/eslint.json`, com verificação de idiomas separada |

Os testes backend usaram PostgreSQL/Redis exclusivos em loopback, `RAILS_ENV=test`, ambiente sem credenciais herdadas e WebMock. O browser usa componentes/CSS reais com respostas sintéticas e rede externa bloqueada; **não é um teste de envio real nem de produção**. A fonte de frontend da última PR é idêntica à validada na PR de UI. O CI dedicado repete os gates no SHA publicado e inclui os artefatos sintéticos; não se declara verde antes de seu término.

## Matriz de aceite

| Critério | Implementação e prova |
| --- | --- |
| Reimportar endereço com falha permanente não reenvia | Registry/espelho legado por conta; importer, mixed-version, SNS e reimport backfill specs |
| Spam/descadastro não são liberados por nova lista/domínio remetente | Precedência forte, chave account+email e testes de reimportação |
| Falha temporária não vira bloqueio eterno | Contagem deduplicada e expiração; testes puros/registry |
| Domínio impossível não chega ao provedor em enforce | DNS/Null MX/fallback A/AAAA/timeout; preflight e admission specs |
| Typo nunca é corrigido silenciosamente | Sugestão/review, sem alteração da identidade do endereço |
| Importação explica excluídos e preserva evidência rejeitada | Issues por linha, CSV seguro, NUL/UTF-8 rejeitado sem perder a lista válida |
| Status humanizados em outros idiomas | Catálogos reais e renderização sem fallback em57 módulos |
| Filtro, busca, paginação e CSV usam os mesmos critérios | RecipientQuery compartilhado e testes HTTP/CSV >10mil linhas |
| Eventos permanentes/temporários/prevenção são distintos | Classificadores compartilhados, métricas e fixtures SES reais em formato |
| Prevenção do provedor não vira nova denúncia de spam | ComplaintClassifier em ingestão, contador, relatórios e histórico |
| Limiares de reputação e volume mínimo são consistentes | Policy/LegacyDecision/ProviderGate, sem elevar o teto aprovado |
| Pausa impede o próximo envio admitido | Verificação por claim, locks curtos ordenados e testes concorrentes |
| Retomada não contorna proteção | Reavaliação atual, geração/feedback, veto do provedor e permissões; UI/HTTP negativos |
| Proteção compartilhada do SES | Monitor/gate/release explícito, simulados nos testes; sem ativação operacional |
| Histórico pode alimentar proteção sem reprocessar indevidamente | Preview padrão, apply explícito, idempotência, cursor/ceiling/lease/retry3 |
| Snapshot de pausa e auditoria não são apagados | Invariantes PostgreSQL em migration/schema-load e retenção |
| Sem perda de opt-out por recibo/concorrência | Admissão, SNS, tracking, link e recibo preservam estado forte |
| Aceitação não é apresentada como prova de caixa de entrada | Proveniência SES/direct/unknown e legenda/denominadores na UI |
| Listagem não faz três agregações por campanha | Teste SQL real de1 versus20 campanhas em estados/modos diferentes |
| Operação/rollback documentados | Runbooks de higiene, reputação, relatórios e manutenção vinculados abaixo |

“Parar imediatamente” refere-se a não admitir **novo** transporte após o bloqueio persistido. Uma chamada já aceita pelo serviço externo não pode ser recolhida; o recibo continua sendo persistido sem apagar opt-out. Enfileiramento/latência de avaliação e o cron de reconciliação são observáveis, não se promete latência zero.

## Ressalvas da suíte geral, sem ocultar falhas

A investigação ampla executou8.827 exemplos antes da interrupção graciosa, com13 falhas/97 pendentes; não foi uma execução completa verde. Sete falhas reproduziram na main inalterada (matcher de convite, callback Autonomia, quatro redirects Slack e expectativa SAML dependente de FRONTEND_URL). As outras seis eram vazamento da fixture concorrente nova de inbox/horários: corrigido, com a ordem TickJob→WorkingHour aprovada em23 exemplos e WorkingHour adicionado ao gate cumulativo. Detalhes em [auditoria ampla](../audit/436-broad-regression.md). Nenhum pending novo foi usado para esconder defeito da entrega.

Não foi realizada revisão humana nativa das57 traduções, teste de todos os navegadores nem envio para caixas reais. O CI de campanhas e a suíte frontend inteira não equivalem à certificação de ausência absoluta de qualquer regressão no produto.

## Rollout e rollback

1. Aprovar a PR seguinte somente com CI no HEAD e diff esperado; merge único e aguardar blue/green saudável.
2. Preservar defaults de análise/monitoramento desativado no deploy inicial; as proteções legadas e supressões fortes não são apagadas.
3. Após validação operacional separadamente autorizada, passar por shadow, warning e enforcement. Ativação de DNS/monitor global/backfill apply é decisão operacional, não efeito escondido da migração.
4. Backfill começa por preview e aplica apenas com flag+confirmação+SuperAdmin persistido e escopo correto. Nunca retoma campanhas ou libera SES automaticamente.
5. Rollback de aplicação usa o procedimento blue/green vigente. Manter tabelas/aditivos, eventos, supressões e snapshots; não fazer rollback destrutivo de banco nem limpar flags para forçar envio.

[Higiene](hygiene.md) · [Reputação](reputation.md) · [Relatórios/API](reports.md) · [Operações e rollback](operations.md) · [QA visual](../../tests/qa/email-campaigns/README.md). O board é Autonom.ia Dev, com Projeto=Hub2You (opção existente para Chat2You), Status, Tipo, Prioridade, Risco, Próxima ação e Ambiente preenchidos em cada item.

## Fontes técnicas primárias conferidas

A taxa local por coorte não é a métrica oficial de volume representativo do SES. `NoEmail` não comprova caixa inexistente; `Suppressed` global permanece nocivo para a reputação; prevenções OnAccount/OnTenant não são novos eventos de reclamação. Referências: [conteúdo SNS](https://docs.aws.amazon.com/ses/latest/dg/notification-contents.html), [supressão global](https://docs.aws.amazon.com/ses/latest/dg/sending-email-global-suppression-list.html), [Complaint API](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_Complaint.html), [processo de revisão SES](https://docs.aws.amazon.com/ses/latest/dg/faqs-enforcement.html). Conferência:17/09/2026.
