# #436 — entrega integrada de proteção e gestão de campanhas

Data de validação local:17/09/2026. Escopo: código e PRs, **sem autorização de merge, deploy, liberação de campanha ou backfill em produção**.

## PR final de integração e trilha técnica

As PRs #438–#442 continuam como **decomposição técnica e histórico de review**. Elas não devem ser mergeadas individualmente. A única PR deployável desta entrega é a **#443**, branch `feat/436-email-protection-final-integration`, diretamente contra `main`, contendo integralmente as cinco frentes.

| Papel | PR | Entrega | Merge/deploy |
| --- | --- | --- | --- |
| Trilha técnica | #438 | Higiene e quarentena | Não mergear separadamente |
| Trilha técnica | #439 | Reputação e admissão segura | Não mergear separadamente |
| Trilha técnica | #440 | Métricas, filtros e API | Não mergear separadamente |
| Trilha técnica | #441 | UI humanizada e i18n | Não mergear separadamente |
| Trilha técnica | #442 | Histórico e recuperação | Não mergear separadamente |
| **Integração final** | **#443** | **#438 + #439 + #440 + #441 + #442** | **Um merge em `main` → um blue-green** |

Qualquer mudança no HEAD da #443 exige CI próprio e nova revisão do diff consolidado. As fases `shadow`, `warning` e `enforce` são ativações operacionais posteriores ao único deploy, controladas por flags e aprovações próprias; não representam novos merges desta série.

## Gates adversariais obrigatórios antes de merge

A revisão externa da #443 no SHA `28fb2997e8222d63c8c8ab10c2df977aadc3a76a` encontrou dois P1 e um P2. Os três foram corrigidos na worktree final e convertidos em regressões. **Isto ainda não autoriza merge**: o novo HEAD precisa de CI próprio verde e nova revisão independente. Os gates locais abaixo foram executados em PostgreSQL/Redis descartáveis em loopback, sem produção, AWS ou envio real.

| Gate adversarial | Fechamento local |
| --- | --- |
| Locks entre versão intermediária e candidata | Ordem `Account → state → campaign → recipient` e regressões cross-caller/mixed-version; nenhuma confirmação falsa de opt-out no gate final. |
| Provider block versus claim/monitor | Ambas as ordens claim/latch continuam cobertas. Poll nocivo antigo que conclui depois de telemetria saudável mais nova preserva a telemetria nova, mas incrementa `harmful_generation`, adiciona `blocked=true` e auditoria quando cria o latch. `ProviderRelease` captura a geração **antes da rechecagem externa** e recusa liberar se qualquer nocivo for persistido durante a operação, inclusive se a própria consulta nociva terminar fora de ordem. |
| Feedback contínuo | `shadow`/`warning` aplicam `LegacyDecision` e `enforce` aplica a policy nova; observação superseded somente adiciona proteção, nunca publica métricas obsoletas nem libera. Regressões reais cobrem os três modos. |
| Importação HTTP real / rollback | GET, multipart import e retry passam pelo Jbuilder/DTO real. As FKs de `email_campaign_import_issues` usam `ON DELETE CASCADE`; teste de upgrade `main schema → migrations #443 → código real da main` destruiu campanha/import/issue sem FK/500. |
| Quarentena fora de ordem | Permutações, replay, janela antiga/futura e expiração usam evento qualificante mais recente sem encurtar proteção. |
| Evidência corrigida na mesma chave | Promoção append-only única, prioridade forte preservada, apply completed e reimportação bloqueada. |
| Denominador misto | SES usa apenas aceites SES; DirectInbox/unknown não entram no denominador oficial/local SES e a UI explicita proveniência. |
| Erro aninhado e estado da UI | `protection.code` real é consumido, filtros sobrevivem refresh/IA, loading/retry permanecem coerentes. |
| Exclusão local versus proteção tenant | `invalid/review` local não é rotulado como blacklist/proteção; supressão tenant real mantém precedência. |
| Contador de enviados após prevenção | `sent_count` deriva de `sent_at`; prevenção posterior não apaga aceite já persistido. |

O CI dedicado deve repetir os gates no SHA final. Testes locais não certificam comportamento em produção nem substituem a observação do único blue-green antes de qualquer ativação operacional.

## Evidência integrada local após os fixes adversariais

Base da correção externa: #443 em `28fb2997e8222d63c8c8ab10c2df977aadc3a76a`. Os resultados abaixo incluem as correções P1/P1/P2 e o fechamento do race residual de `ProviderRelease`, ainda antes do novo commit publicado. O SHA que receber esses commits deve repetir o CI próprio da #443 e a revisão externa.

| Gate | Resultado local | Evidência |
| --- | --- | --- |
| Backend cumulativo das cinco entregas | **909 exemplos, zero falhas; um pending preexistente de Account** | `tmp/email436/external-review-final.json` |
| Manutenção/backfill focado | **121 exemplos, zero falhas/pending** | `tmp/email436/pr442-focused.json` |
| Ruby puro | **9 arquivos;57 testes;50.876 asserções; zero falhas/erros/skips** | `tmp/email436/external-review-pure.log` |
| RuboCop cumulativo | **185 arquivos, zero infrações** | `tmp/email436/external-review-final-rubocop.log` |
| Frontend completo | **461 arquivos /5.087 testes; zero falhas/pending** | PR441 `tmp/email436/p2-final-full-vitest.json` |
| Idiomas | **57 módulos,43 ativos,263 mensagens/módulo,14.991 renderizações; fallback false** | PR441 `tmp/email436/p2-final-i18n.json` |
| Build | Vite test real aprovado | PR441 `tmp/email436/p2-final-build.log` |
| Browser/componentes reais | **170 checks, zero falhas,131 PNGs; zero rede externa/console/page errors** | PR441 `tmp/email436/visual/results.json` |

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

1. Revisar **somente a PR #443** contra `main`, exigir CI próprio verde no HEAD exato e aprovação explícita do Rodrigo.
2. Um único merge da #443 dispara **um blue-green**. Não mergear #438–#442 separadamente. Acompanhar as duas stacks, confirmar versão/saúde e executar apenas o smoke previamente autorizado antes de qualquer mudança de flags.
3. Deploy inicial mantém `EMAIL_CAMPAIGN_HYGIENE_MODE=shadow`, `EMAIL_REPUTATION_MODE=shadow`, DNS=false, provider monitor=false e backfill apply=false, salvo decisão operacional explícita em contrário.
4. `warning` e depois `enforce` são mudanças operacionais independentes, somente após observação, evidência e aprovação. DNS, monitor global e backfill apply continuam opt-ins separados.
5. Backfill começa por preview e aplica somente com flag + confirmação + SuperAdmin persistido e escopo correto. Nunca retoma campanhas ou libera SES automaticamente.
6. Rollback de código deve drenar/suspender os jobs novos antes de voltar a leitor antigo. Preservar tabelas, eventos, supressões, quarentenas, snapshots e auditoria; não executar down destrutivo nem limpar flags para forçar envio.
7. Compatibilidade de exclusão com leitor antigo é mantida no banco: as FKs novas de `email_campaign_import_issues` para campanha/import têm `ON DELETE CASCADE`. O gate local `main schema → migrations #443 → código real da main` terminou com campanha/import/issue removidos (`0/0/0`).

[Higiene](hygiene.md) · [Reputação](reputation.md) · [Relatórios/API](reports.md) · [Operações e rollback](operations.md) · [QA visual](../../tests/qa/email-campaigns/README.md). O board é Autonom.ia Dev, com Projeto=Hub2You (opção existente para Chat2You), Status, Tipo, Prioridade, Risco, Próxima ação e Ambiente preenchidos em cada item.

## Fontes técnicas primárias conferidas

A taxa local por coorte não é a métrica oficial de volume representativo do SES. `NoEmail` não comprova caixa inexistente; `Suppressed` global permanece nocivo para a reputação; prevenções OnAccount/OnTenant não são novos eventos de reclamação. Referências: [conteúdo SNS](https://docs.aws.amazon.com/ses/latest/dg/notification-contents.html), [supressão global](https://docs.aws.amazon.com/ses/latest/dg/sending-email-global-suppression-list.html), [Complaint API](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_Complaint.html), [processo de revisão SES](https://docs.aws.amazon.com/ses/latest/dg/faqs-enforcement.html). Conferência:17/09/2026.
