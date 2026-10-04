# Recuperação Instagram #931 — rastreabilidade e pendências

Fechamento local em **03/10/2026 às 23:01 BRT (04/10/2026 02:01 UTC)**: os **12 achados de código têm correções/regressões e fechamento local**, sem novo bloqueador nos reviews disponíveis. Baterias finais e renders consolidados abaixo; não são homologação de produção nem garantia de ausência de regressão.
Issue #931; branch de recuperação `fix/931-instagram-audit-blockers`; base `149c6718f243c248ba3898b4d800580cd5c00fce`, posterior a #925/#930. **Publicação, CI, head, Project, reviews/aprovação e eventual merge devem ser consultados na PR do commit correspondente.** Este registro fecha a evidência local; não autoriza merge/deploy/operação autenticada.

## Resultado atual versus operação pendente

| Camada | Resultado sustentado neste recorte | Limite / pendência |
|---|---|---|
| Código e testes locais | Backend sem ENV global, frontend, runtime, helpers e DEPLOY offline encerrados nos logs abaixo; fixture OAuth, userinfo e BOOT corrigidos | Fontes de produto congeladas conforme coordenação; renders finais consolidados; revisão documental do conjunto cabe ao coordenador |
| Review | Backend limitado à fonte/memória; auth final fecha userinfo; review DEPLOY acceptance fecha os quatro achados, incluindo BOOT; arte final fecha copy/toast e aprova seu escopo visual | Sem novo bloqueio de código/visual nesses escopos; aceite de conjunto/docs e CI devem acompanhar a PR do commit |
| CI / publicação #931 | Wiring anterior preservado; helpers de toast ligados ao Node test/syntax/ESLint no job `node-contracts` | Estado de CI/publicação/aprovação consultável na PR do commit; wiring e teste local não liberam produção |
| Operação autenticada | Nenhuma ação real praticada nesta recuperação | Configuração/sessão/supervisor/alarmes atuais desconhecidos; Meta, AWS/SSM/SSH, Redis produtivo, OAuth/DM e rollback por stack não homologados |

## Fontes e 14 especialistas reais

Inventário verificado em [`agents.json`](../../tmp/instagram-931/agents.json): **14 entradas distintas**, sem contar retomadas como especialistas novos.

| Responsabilidade | Nomes do inventário | Quantidade |
|---|---|---|
| Implementação e QA | `session`, `invite`, `runtime`, `deploy`, `oauth`, `observabilidade`, `uiux`, `qa` | 8 |
| Rastreabilidade/documentação | `auditoria-documentacao` | 1 |
| Reviews independentes | `review-backend`, `review-auth-observability`, `review-runtime-deploy`, `review-integracao`, `review-arte-ux` | 5 |

Leitura: brief, consolidação, relatórios finais/follow-ups dos especialistas e os reviews de [integração](../../tmp/instagram-931/review-integracao-result.md), [auth final](../../tmp/instagram-931/review-auth-final-result.md), [deploy final anterior ao boot fix](../../tmp/instagram-931/review-deploy-final-result.md), [DEPLOY acceptance](../../tmp/instagram-931/review-deploy-acceptance-result.md) e [arte inicial](../../tmp/instagram-931/review-arte-ux-result.md), seguida da [arte final](../../tmp/instagram-931/review-arte-acceptance-result.md). Registros duráveis: [INVITE](2026-10-03-931-invitation-preflight.md), [RUNTIME](2026-10-03-931-runtime-publisher.md), [DEPLOY](931-deploy-recovery.md), [OAUTH](2026-10-03-instagram-931-oauth-binding.md), [Sentry](2026-10-03-931-sentry-http-auth.md), [UI](931-instagram-ui-functional-fixes.md), [runbook](../runbooks/instagram-tester-onboarding.md) e [contrato de onboarding](../instagram-tester-onboarding.md).

Logs/manifestos citados em `tmp/instagram-931` são fontes **locais de scratch**, não artifacts publicados. O coordenador deve preservar evidência sanitizada ligada à revisão final. Este documento registra resultados, limites e referências; não reproduz prompts, cadeia de pensamento, transcrições dos agentes ou logs brutos. Relato de agente e resultado de log têm atribuições separadas; não somar baterias sobrepostas nem transformar contagens planejadas em execução.

## Resultado local consolidado — 03/10/2026, 23:01 BRT

| Bateria / fonte explícita | Resultado local encerrado | Limite da evidência |
|---|---|---|
| [Backend sem ENV global](../../tmp/instagram-931/backend-clean-env-final.log) | **443 exemplos, zero falhas**, após fixture corrigida; execução sem `FRONTEND_URL` global conforme coordenação | MockRedis e dados sintéticos; não Redis distribuído/produção nem resultado do CI |
| [Frontend final](../../tmp/instagram-931/frontend-final.log) | **129 testes, dez arquivos passaram** | Última bateria ampla após copy final. Warnings de Browserslist/source map conhecidos, sem ocultação |
| [Runtime parent final](../../tmp/instagram-931/runtime-final.log) | **72 passaram; zero falhas/cancelados/skips/todo** | AWS/SSM/SSH/browser substituídos; plugin/launchd reais não homologados |
| [QA helpers release](../../tmp/instagram-931/qa-helpers-release.log) | **23 passaram; zero falhas/cancelados/skips/todo**, incluindo dois casos dos helpers de toast | Não substitui render; [QA toast final](../../tmp/instagram-931/qa-toast-final-result.md) atribui lint/formatação ao autor |
| [Regressão Guia](../../tmp/instagram-931/guide-regression-final.log) | **40 exemplos, zero falhas** | Execução do coordenador; este auditor não editou/regerou arquivos gerados |
| [Preparer](../../tmp/instagram-931/preparer-final.log) | **25 testes, OK** | Parser/saída privada sintéticos; não captura ou sessão administrativa real |
| [Autoloader](../../tmp/instagram-931/autoload-final.log) / [build](../../tmp/instagram-931/build-final.log) | Autoload `All is good`; build concluído (6.667 módulos) | Warnings do build preservados; nenhum resultado autentica operação |
| [i18n](../../tmp/instagram-931/i18n-final.log) | **10 catálogos; 17.222 mensagens compiladas**; paridade en/pt_BR coberta | Contagem de mensagens, não de testes. Copy final relata novo check e compilação específica |
| [RuboCop](../../tmp/instagram-931/ruby-lint-final.log) | **25 arquivos, zero infrações** | Última bateria; confirmar escopo/revisão final |
| [ESLint](../../tmp/instagram-931/js-lint-final.log) | **Zero erros, 22 warnings conhecidos de i18n** | Warnings mantidos; não declarar lint sem warnings |
| [Sentry/auth final](../../tmp/instagram-931/review-auth-final-result.md) | Revisor executou **17 specs Sentry/zero falhas** e **16 checks independentes/zero falhas** | SDK 5.19.0/transporte em memória; não ativação/exportação produtiva |
| [Fixture OAuth](../../tmp/instagram-931/oauth-fixture-final-result.md) / [log sem ENV](../../tmp/instagram-931/oauth-env-isolation-final.log) | `FRONTEND_URL` sintético no próprio `settings`; resultado focal **30 exemplos/zero falhas** disponível | Parent sem ENV global encerrado em **443/0** no log acima; não depender da ENV global do wrapper |
| [Copy final UI](../../tmp/instagram-931/ui-copy-final-result.md) | Somente `MANUAL_HELP` en/pt_BR alteradas; autor relata **72 testes focais**, i18n e compilação dos catálogos aprovados | Não somar aos 129; copy final coberta pelos renders e review de arte abaixo |
| [Boot fix DEPLOY](../../tmp/instagram-931/deploy-boot-receipt.json) | Controle vermelho: **12 falhas em três grupos**; depois **nove grupos focais, zero falhas**; hashes conferem com as quatro fontes locais | [Parent congelada](../../tmp/instagram-931/deploy-frozen-final.log): **19 testes, OK, 403,493 s**; [review acceptance](../../tmp/instagram-931/review-deploy-acceptance-result.md) aprova os quatro achados, com 26 cenários atuais aprovados e dois controles históricos que reproduziram sobreposição; não somar baterias |

## Matriz achado → arquivo/regressão → resultado

**Os 12 achados estão fechados no código/evidência local**, com os limites dos reviews e testes indicados. Código, teste e operação são colunas distintas; operação autenticada permanece pendente em todas as linhas.

| Achado original | Arquivo / regressão | Código | Teste local / review | Operação |
|---|---|---|---|---|
| 1. Revogação/CAS com +240 s | `session_store{,_helpers}.rb`; `session_store_spec.rb`: revisão, interleaving, tombstone, TTL | Fechado localmente | Correção presente; última backend 443/0; contrato de recaptura/rollout abaixo | Pendente |
| 2. Query SSM | `publisher-tunnel.mjs`; `runtime-publisher.test.mjs`: envelope completo e projeção | Fechado localmente | `CommandInvocations`; última runtime 72/0 | Pendente |
| 3. Falhas do instalador ocultadas | Dois workflows DEPLOY, helper e `deploy-recovery_test.py`: 13 etapas obrigatórias | Fechado localmente | AND explícito/regressão; parent congelada 19/0 e review dos quatro achados favorável, ambos offline | Pendente |
| 4. Rollback/CURRENT | Helper/workflows/teste: listener→target→instância, workers, recuperação/drenagem | Fechado localmente | **Quatro achados fechados, incluindo P1 BOOT**, pelo review acceptance; parent congelada 19/0 | Pendente |
| 5. Continuidade/prazos do gestor | `session-manager.mjs`, wrapper e testes: versão, corpo, SIGTERM, conclusão tardia | Fechado localmente | Última runtime 72/0; três ciclos e limites sintéticos | Pendente |
| 6. Claim retido pré-POST | `client.rb`, `error.rb`, `invitation{,_outcome}.rb` e specs | Fechado localmente | Zero POST pré-envio/limpeza própria; proteção pós-transporte preservada; última backend 443/0 | Pendente |
| 7. Ator/permissão no callback | Helper/controllers, `selection.rb`, `oauth_binding.rb`; specs OSS/Enterprise | Fechado localmente | Contexto e policy sem cache antes da troca/escrita; auth final favorável e última backend 443/0 | Pendente |
| 8. Limite/proxy/restrição/recuperação UI | `Instagram.vue`, `TesterOnboarding.vue`, composable, specs e en/pt_BR | Fechado localmente | Última ampla frontend 129/0; copy final focal relatada 72/0; renders finais 37/37 e 72/72, arte final favorável | Pendente |
| 9. Falso verde/QA/CSS | Fixtures/harness/evidence e testes QA | Fechado localmente | Últimos helpers 23/0; componente 37/37 e wizard 72/72 finais, toast/copy e hashes estáveis; arte final favorável | Pendente |
| 10. OAuth entre instalações | Helper/binding/selection e specs de isolamento/replay | Fechado localmente | State v2; auth final favorável; fixture com `FRONTEND_URL` corrigida, parent sem ENV global 443/0 | Pendente |
| 11. Query/userinfo Sentry | Initializer/scrubber/spec com objetos/envelopes do SDK | Fechado localmente | **P1 userinfo fechado pelo review-auth-final**; 17 specs e 16 checks do revisor | Pendente |
| 12. EOF do túnel | Túnel/teste Node stdin e cleanup | Fechado localmente | Controle com filho Node incluído na última runtime 72/0; não prova plugin real | Pendente |

O envelope público AWS usa `CommandInvocations`, conforme [documentação CLI confirmada na auditoria](https://docs.aws.amazon.com/cli/latest/reference/ssm/list-command-invocations.html) e modelo público SDK local (`ListCommandInvocationsResult`: `CommandInvocations`, `NextToken`) conferido na primeira rodada. Sem chamada AWS ou rede nesta atualização.

## Fechamentos de review e pendências novas

- **P2 documental da integração:** corrigido neste registro/runbook/onboarding; backend 439/uma falha, QA 18, Sentry 15/userinfo aberto e reviews DEPLOY anteriores deixam de ser o quadro atual e permanecem históricos abaixo. Esta atualização documental ainda precisa de revisão final do coordenador e CI posterior.
- **P2 fixture de CI:** [`oauth-fixture-final-result.md`](../../tmp/instagram-931/oauth-fixture-final-result.md) confirma `FRONTEND_URL` sintético no próprio spec, sem fallback no produto. O resultado focal sem ENV está no quadro; a parent posterior sem `FRONTEND_URL` global encerrou **443/0** no [log explícito](../../tmp/instagram-931/backend-clean-env-final.log), conforme ambiente informado pela coordenação. Isso fecha a pendência local; consultar o CI na PR do commit correspondente.
- **P1 Sentry userinfo:** [`review-auth-final-result.md`](../../tmp/instagram-931/review-auth-final-result.md) fecha o achado e aprova somente o código inspecionado. URLs compostas, autoridade codificada e retorno dos callbacks cobertos; nenhuma transmissão real comprovada.
- **DEPLOY anterior:** [`review-deploy-final-result.md`](../../tmp/instagram-931/review-deploy-final-result.md) fecha PREVIOUS validado antes de mutações, retomada do worker após troca aplicada com erro e drenagem/espera de publicação em trânsito. Seu parecer ainda era desfavorável pelo BOOT; não apagar essa ressalva histórica.
- **Novo BOOT:** integração classificou P1 (review deploy anterior classificou residual P2). [`deploy-boot-fix-result.md`](../../tmp/instagram-931/deploy-boot-fix-result.md) registra ordem nova: validar PREVIOUS → parar/aguardar worker atual → ligar anterior, com guarda de mesma instância. O teste modela autostart e não só starts SSM explícitos. Nove grupos focais passaram; o [review-deploy-acceptance](../../tmp/instagram-931/review-deploy-acceptance-result.md) fecha os quatro achados, sem residual nesse escopo, após 26 cenários atuais aprovados e dois controles históricos. Na leitura daquele revisor, a parent ainda estava aberta; posteriormente o [log congelado completo](../../tmp/instagram-931/deploy-frozen-final.log) encerrou **19 testes, OK**, em 403,493 s. Se boot falha, retorna erro/preserva recursos e o worker atual pode permanecer parado: não prometer disponibilidade contínua.

Os quatro hashes de fonte do receipt de boot foram conferidos localmente sem divergência; SHA-256 do manifesto informado pelo autor: `5f3b2df58b18dbadafcc477cd4ab38618f4c379a84323bb3a81c8fb45575de79`. Isso identifica o fix focal, não a revisão final de todo #931.

## Renders finais e review de arte — encerrados localmente

| Execução de 04/10/2026 UTC (03/10 BRT) | Manifesto / log parent | Resultado | SHA-256 do manifesto |
|---|---|---|---|
| Componente, fim **01:55:02,520Z** | [Manifesto](../../tmp/instagram-931/qa-evidence/results.json) / [log completo](../../tmp/instagram-931/browser-component-release.log) | **PASS 37/37**, zero falhas/bloqueados, **73 capturas** | `26f19cf9e000a08d13d7705ff2479774115264f4f59bd00e1213e77840c266b8` |
| Wizard, fim **01:57:21,093Z** | [Manifesto](../../tmp/instagram-931/qa-evidence/wizard/results.json) / [log completo](../../tmp/instagram-931/browser-wizard-release.log) | **PASS 72/72**, zero falhas/bloqueados, **76 capturas** | `6be776abdd74004ba764119ddc69d9428b1bc0d69c237185ae7334fd3f0f3398` |

Os dois manifestos contêm **6.658 hashes de fontes**, iguais antes/depois e ao disco na conferência deste fechamento; estilos antes/depois também iguais. Logs completos conferem com os resultados; exit 0 confirmado pela ferramenta do parent. Incluem a copy final das duas chaves `MANUAL_HELP` en/pt_BR e host real de Snackbar/useAlert. Componente e wizard são baterias distintas, sem somá-las às suites frontend/helpers.

O [review de arte final](../../tmp/instagram-931/review-arte-acceptance-result.md), disponível neste fechamento de **03/10/2026, 23:01 BRT**, inspecionou **12 capturas atuais por visão direta**, conferiu manifestos/logs/fontes e fechou a ressalva de copy e a lacuna do toast OAuth legado. Aprova seu escopo visual, sem bloqueio novo. O review inicial de 42 imagens e a falha/confirmação anteriores do wizard ficam no histórico, sem promover a galeria antiga a evidência final.

Agentes/conclusão/reautorização são contextos sintéticos separados. Render real com API simulada não comprova jornada Rails/Meta fim a fim, autorização de cliente ou produção. O banner compacto de reconexão mobile permanece observação preexistente fora do escopo #931. Publicação de assets/footnotes pertence ao QA/coordenador; este auditor não edita harness ou seu README.

## Histórico anterior e rodadas locais de 03/10/2026 BRT

- **PR #913 MERGED/deploy success:** merge `2d493fe4a77aeb0912d2d8f27d6f802766cd465f`; receipts históricos de publicação nas duas stacks (green/worker/HTTPS/SSO). Rollback `skipped`; nenhuma jornada autenticada derivada disso. Notas anteriores de rascunho/deploy pendente descreviam seus respectivos momentos.
- Backend anterior **439/uma falha TTL**; expectativa do MockRedis ajustada em TTL−1s/exato/+1s. Foi sucedido pela última bateria **443/0**; não declarar que o antigo teste passou retroativamente.
- Runtime parent anterior **71/72**; fixture 0755 afetada por umask 077 corrigida com chmod. Última parent final **72/0**; sem mudar gate do produto ou usar skip.
- QA helpers anteriores **18/0** e render inicialmente BLOCKED por CSS/grafo virtual, depois 35 passes/dois fails e bloqueio de manifesto; minfix chegou a **21/0**, sucedido por **23/0** após os dois helpers de toast. Nenhuma dessas tentativas soma cobertura adicional.
- Sentry original relatava **15 specs**, mas o review encontrou userinfo aberto. Fix/review posterior **17 specs +16 checks independentes** fechou o P1; não afirmar que os 15 originais cobriam a omissão.
- DEPLOY autor: baterias anteriores de dez/depois 16 grupos, separadas do fix focal BOOT de nove grupos. Primeira Python parent (`deploy-recovery-final.log`) **invalidada por concorrência de fontes**: resultado bruto com falhas/erros não é PASS nem diagnóstico conclusivo da versão congelada. Segunda parent foi **CANCELLED antes do boot fix**, conforme coordenador: não conta como PASS. [`deploy-frozen-final.log`](../../tmp/instagram-931/deploy-frozen-final.log) estava parcial no recorte anterior; agora encerrou **19 testes, OK**. Review acceptance posterior fechou os quatro achados. As tentativas anteriores continuam invalidadas/canceladas.
- Wizard: primeira tentativa encerrou em **04/10 01:39:36,724 UTC** (03/10 BRT), com **71/72, timeout de navegação de 10 s** em `wizard-instagram-search-empty-mobile-light` ([registro](../../tmp/instagram-931/wizard-final-first-run.json)); causa não estabelecida. Confirmação sem alteração de fonte encerrou em **01:43:42,002 UTC**, **72/72** ([log](../../tmp/instagram-931/browser-wizard-confirmation.log)). Copy/toast posteriores receberam a nova rodada final de **01:57:21,093 UTC**. Nenhum PASS apaga a falha anterior.
- Reviews que não aprovavam Sentry/DEPLOY permanecem válidos como histórico daquele snapshot; a aprovação/correção posterior não é autorização para merge/deploy.

## Contrato de sessão e rollout futuro

Conforme SESSION e fonte local: `version` permanece opaca `string | null`; namespace, schema, cifra, metadados e TTL não mudam. Invalidação bem-sucedida avança a revisão no CAS, inclusive ao invalidar novamente a revisão atual de um pointer já invalidado. Invalidação atrasada da revisão anterior retorna `false` e não altera uma substituta. `null` só permite primeira publicação sem pointer; corrupção não permite sobrescrita inicial.

Sessões ativas existentes continuam legíveis. Captura preparada antes da revogação perde o CAS mesmo com relógio +240 s; recuperação exige ler a revisão nova e **recapturar**, sem trocar apenas `expected_version`. O servidor não comprova recaptura se um publisher reciclar a captura trocando a revisão: cumprir “ler → recapturar → publicar” é condição do contrato. Frescor, captura crescente, seis horas máximas e cinco minutos de tolerância futura continuam controles separados. A cerca expira com o TTL existente; não prometer revogação permanente além dele.

**Código novo sozinho não cerca tombstones anteriores.** No rollout autorizado, suspender publishers e drenar invalidadores/consumidores antigos envolvidos; instalar código consistente nas instâncias relevantes. Para cada namespace, verificar somente o estado do pointer: tombstone legado exige avanço de revisão pelo store novo com sucesso confirmado, ou expiração efetiva enquanto publishers permanecem suspensos. Não invalidar sessão ativa automaticamente, apagar pointer corrompido ou restaurar payload antigo. Só retomar após descarte das capturas em trânsito e leitura/recaptura novas. Nenhuma dessas operações foi executada ou autorizada por esta documentação.

## Contrato OAuth, identidade e compatibilidade

Fonte OAUTH atual: todos os states recém-emitidos, com/sem seleção e na reautorização, usam `state_version=2`, conta, ator, identidade da instalação, `iat`/`exp` de até 15 minutos e `jti` de uso único. O callback verifica associação/`InboxPolicy.create?`, incluindo permissões Enterprise, antes da troca e novamente antes da gravação. Sem seleção, não exige configuração/flag de testers; payload da API e caminho de reautorização continuam sem seleção obrigatória. Isso não preserva o formato antigo do state.

A identidade OAuth/seleção deriva de digest da base de callback normalizada de `FRONTEND_URL` confiável, sem Host do request nem fallback de localhost. Não é o namespace Redis `INSTAGRAM_TESTER_SESSION_NAMESPACE`. A seleção de duas horas mantém conta, ator, instalação, App pai, ID de papel e username até o callback; o App pai atual é revalidado. `INSTAGRAM_META_DEVELOPER_APP_ID` e `INSTAGRAM_APP_ID` são identidades diferentes: o primeiro governa papéis; o segundo é OAuth. Conferir a relação por stack sem publicar valores, fingerprints de secrets ou tokens. Igualdade de App pai não prova igualdade de OAuthApp/segredo nem de identidade do perfil.

**States/seleções anteriores em trânsito serão recusados.** Avisar para reiniciar a busca/seleção quando assistida e reiniciar OAuth também no legado/reautorização; não dar bypass ao state anterior. Trocar a base de callback invalida os artefatos anteriores. Caixas, tokens OAuth persistidos, conversas e papéis existentes não são migrados por esta mudança. Novo state também não é compatível com um conjunto misto de emissores/callbacks antigos; revisar o cutover das rotas e workers.

## Rollback futuro e limites operacionais

Rollback exige aprovação e plano por stack, SHA alvo, saúde e responsáveis. Suspender a automação antes: código antigo reintroduz revogação sem avanço de revisão e validação antiga de OAuth. Não considerar um retorno de imagem proteção equivalente ao #931. Descartar states/seleções/capturas em trânsito e exigir reinício compatível após estabilizar emissores/callbacks. Conferir listener, target, workers e ponteiros `CURRENT_*` juntos para que o publisher não siga o green abandonado; exercer o helper DEPLOY no teste e depois na homologação autorizada.

Preservar namespace, chaves de cifra, sessão revogada, proteção de convite incerto (até 24 horas), caixas e dados existentes. Não limpar `unknown` nem reenviar por inferência de ausência. Erro comprovadamente anterior ao transporte libera somente o claim próprio; após início, conservar a proteção salvo rejeição booleana explícita validada/reconciliação prevista. Não incluir CLI de produção para execução nesta rodada.

Configuração/allowlist carregada, Apps/Business atuais, sessão administrativa, gestor/supervisor instalados, proxy/origem green, coordenação Redis comum e alarmes atuais são **desconhecidos e fora da inspeção autorizada**. Notas históricas de piloto Hub2You/conta 18 ou automação OFF não descrevem o estado atual nem reduzem o escopo posterior registrado para ambas stacks/contas autorizadas.

## Critérios de pré-release e campos pendentes

1. Fontes de produto congeladas conforme coordenação; concluir freeze de docs e evidência final, identificar revisão/hashes e arquivar resumos sanitizados/logs completos em evidência controlada. Não somar as últimas baterias nem presumir que passaram após mudanças posteriores.
2. Fechamentos locais disponíveis: review acceptance BOOT/quatro achados, Python parent congelada **19/0** e backend sem ENV global **443/0**. Vincular esses logs à revisão final e ao CI posterior; cancelamento, concorrência, log parcial ou resultado focal anterior não liberam o conjunto.
3. Renders finais e review de arte encerrados: componente **37/37**, wizard **72/72**, toast real/copy final, claro/escuro e desktop/mobile; hashes estáveis. Preservar manifestos/logs e referências finais QA; nova alteração de fonte exige revalidar a evidência afetada.
4. Vincular testes/lint/i18n/build/Guia locais, inclusive os 22 warnings conhecidos, à revisão correspondente. Conferir review de conjunto/docs, checks e aprovação na PR do commit; wiring não é resultado de CI.
5. O fluxo de publicação segue Issue → Branch → PR → Project update → Review → Approval → Merge → Deploy/Rollback. Consultar cada etapa na PR do commit; aprovação operacional e plano verificado por stack continuam requisitos próprios, sem inferir autorização da evidência local.

**Gate operacional de preparação humana do rollout, ainda não executado:** publishers pausados e invalidadores antigos drenados; tombstones legados rotacionados pelo contrato verificado do store novo ou expirados efetivamente antes da retomada; descartar capturas antigas e recapturar com nova revisão. States/seleções OAuth anteriores reiniciam; emissão/callbacks novos devem entrar juntos. Canais, tokens persistidos, conversas e papéis existentes preservados. Não pedir ao usuário execução manual de scripts Redis novos sem contrato verificado; o coordenador deve concretizar o procedimento operacional em contexto autorizado, sem inventar CLI nesta documentação.

Antes de liberar esse gate, responsáveis humanos devem revisar o procedimento por stack/namespace, a confirmação de pausa/drenagem, o critério de rotação/expiração, a comunicação de reinício OAuth e o plano de rollback. Campos pendentes: responsáveis, revisão alvo, janela, evidência de cada etapa e aprovação operacional. Nenhuma preparação ou mutação real de sessão/Redis/OAuth foi praticada nesta rodada.

## Homologação futura — separada da implementação

Após aprovação operacional específica, comprovar por stack configuração/identidade App e namespace sem publicar valores; publisher instalado, transporte, coordenação, primeira publicação, renovação posterior, revogação concorrente e alerta entregue. Em conta/perfil de teste aprovados, busca/status/convite somente quando necessário, aceite humano, OAuth do perfil escolhido, agentes/caixa, callback #898, webhook/DM nos dois sentidos e reautorização. Depois registrar cobertura do escopo autorizado; piloto não conclui todas as contas.

Exercitar recuperação/rollback conforme o contrato, sem restaurar sessão invalidada, apagar proteção de convite incerto ou revogar cliente confirmado para obter evidência. Nenhum desses passos foi executado nesta recuperação; configuração/sessão/alarmes atuais seguem desconhecidos. Sem cookies, HARs, headers completos, tokens, dados de cliente ou prompts nos registros.

## Validação da primeira atualização documental — 03/10/2026 BRT (histórico)

- `git diff --check -- docs/audit/instagram-931-recovery.md docs/runbooks/instagram-tester-onboarding.md docs/instagram-tester-onboarding.md .github/workflows/instagram-tester-onboarding.yml`: exit 0 para arquivos rastreados; arquivo novo também conferido localmente quanto a whitespace.
- Conferência local de existência dos módulos Node novos ligados no workflow e leitura dos três documentos: exit 0. Diff do workflow limitado a cinco linhas de Node test/syntax/ESLint; nenhum caso/gate/piso removido.
- Modelo público local AWS lido sem cliente/autenticação: `ListCommandInvocationsResult ['CommandInvocations', 'NextToken']`.
- Nenhuma suíte de produto, render, lint de produto, serviço, geração do Guia ou operação autenticada foi executada por este auditor. A execução/evidência final pertence ao coordenador.

## Validação da retomada de wiring/documentação — 03/10/2026 BRT (histórico)

- Parser YAML 2.8.2 já presente no projeto: workflow válido, gate apenas no passo do render após build/install, paths/testfiles existentes e ausência dos paths antigos #910. Comparação com `HEAD`: bloco dos asserts originais idêntico.
- `/bin/bash -n` em cada bloco `run` do workflow e no helper DEPLOY: aprovados, sem executar comandos. AST Python do novo teste e whitespace dos quatro arquivos: aprovados. `git diff --check` do escopo: aprovado.
- Primeira versão do verificador local falhou ao ler `name` de step `uses` sem nome; corrigido apenas o verificador transitório com acesso opcional. Conferência repetida concluiu exit 0. Não era falha do workflow/suite.
- Sem suíte, browser, instalação, pipeline externo, infraestrutura, produção ou commit nesta retomada. Resultados parent/especialistas permanecem atribuídos aos respectivos logs/relatórios, com reruns e re-reviews pendentes.

## Validação documental anterior — 03/10/2026 BRT (histórico)

Na atualização anterior, 56 links relativos dos três documentos e o link do README foram conferidos; whitespace e `git diff --check` passaram. Nenhum workflow/produto/teste foi alterado naquela retomada. Este resultado permanece histórico.

## Wiring de toast e validação — 03/10/2026 BRT (histórico)

Na retomada anterior, somente este registro central e o [workflow dedicado](../../.github/workflows/instagram-tester-onboarding.yml) foram editados naquela retomada. Diff adicional do workflow: **cinco linhas**, uma para `node --test toast-helpers.test.mjs`, duas para `node --check` e duas para ESLint dos módulos `toast-helpers.mjs`/`toast-helpers.test.mjs` existentes, no job `node-contracts`. Todos os testes, asserts, pisos, paths #931 e gate de readiness QA anteriores foram preservados. Não alterar README do harness durante o snapshot de render.

Relatórios finais e encerramentos dos logs explícitos lidos, sem copiar logs brutos; resultados de suítes/renders acima pertencem aos autores/coordenador. Validação local concluída (exit 0): YAML via dependência `yaml` existente; `/bin/bash -n` nos 15 blocos `run` e no helper DEPLOY; `node --check` nos dois helpers de toast; 44 referências de arquivos do workflow existentes; asserts originais idênticos a `HEAD`; readiness restrito ao passo QA após install/build. Diff adicional do workflow confirmado **+5/−0**; 47 links relativos deste registro e 64 no conjunto dos três docs conferidos, sem link ausente; whitespace e `git diff --check` aprovados. Não executar os blocos para validar sua sintaxe. Duas tentativas do verificador transitório falharam por delimitador de heredoc/nome de comando build incorretos no próprio verificador; corrigidos sem alterar workflow. A conferência final acima encerrou exit 0. Nenhuma suíte, render, lint de produto, operação externa, geração do Guia ou commit foi executado por este auditor. **Última documentação ainda exige revisão final do coordenador e CI posterior; não é garantia de ausência de regressão.**

## Validação deste fechamento documental — 03/10/2026, 23:01 BRT

Nesta etapa, somente os três documentos próprios foram atualizados. Manifestos finais, logs completos de browser, backend sem ENV global 443/0, fixture focal 30/0 e review de arte acceptance lidos; nenhum teste ou render foi executado por este auditor. Conferência local concluída: **67 links relativos válidos** nos três documentos (50 na auditoria, quatro no runbook e 13 no onboarding); whitespace e `git diff --check` do escopo aprovados, exit 0. Hashes do workflow e README do harness iguais aos do início desta etapa; inventário reconferido com 14 especialistas distintos. Workflow, produto, harness e arquivos gerados não foram editados. Evidência local consolidada não libera produção; revisão final dos docs e checks/aprovação são consultados na PR do commit correspondente.

## Capturas e fechamento da revisão de integração

A revisão independente final aprovou o código no escopo examinado, após fechar BOOT, fixture `FRONTEND_URL` e atualização documental. Os 57 arquivos de código/testes/workflows permaneceram idênticos entre a leitura inicial e final do revisor. A ressalva de proveniência foi corrigida: as capturas completas estão **localmente**, e o workflow está preparado para coletá-las em uma execução futura do CI; não houve afirmação de artifact remoto já existente.

A direção de arte aprovou a rodada final: copy de indisponibilidade direta, toast real de falha OAuth visível, agentes selecionados com dropdown fechado e clique de reautorização registrado. Referências permanentes, com dados exclusivamente sintéticos:

[Desktop pendente](../assets/instagram-931/pending-desktop.png) · [Mobile pendente](../assets/instagram-931/pending-mobile.png) · [Aceito no tema escuro](../assets/instagram-931/accepted-dark.png) · [Indisponível no mobile](../assets/instagram-931/unavailable-mobile-dark.png) · [Falha com toast](../assets/instagram-931/legacy-error-toast.png) · [Seleção de agentes](../assets/instagram-931/agents-desktop.png).

O [manifesto de evidências](../assets/instagram-931/manifest.json) contém hashes das seis cópias e das 6.658 fontes verificadas, datas de execução e hashes dos relatórios completos/CSS. O componente registra 37/37 casos e 73 capturas; o wizard registra 72/72 e 76 capturas. Os contextos das etapas são separados e as APIs são simuladas: não é comprovação de Meta/SSM/SSH, Redis produtivo, renovação real ou mensagens de clientes.

Essa conclusão permite preparar commit, PR e CI, mantendo aprovação de merge/deploy e preparação/homologação operacional como gates independentes. Não foi alterado nenhum recurso de produção nesta correção.

Fechamento do gate pelo coordenador em 03/10/2026 (Brasília): após releitura e novo stage, o Gitleaks encerrou exit 0, sem achados, sem modificar suas regras. A fixture final Sentry foi reexecutada: 17 exemplos, zero falhas; lint focal sem infrações. Os 173 hashes e dois literais sintéticos da primeira varredura permanecem documentados como falsos positivos verificados, não credenciais reais.
