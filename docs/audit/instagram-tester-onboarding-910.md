> Registro histórico. Estado atual, ativação da tela, incidente 502 e pendências: [repasse atualizado](instagram-tester-handoff-910.md).

# #910 — termos de aceite e evidências de implementação

> Atualização posterior: este documento preserva a evidência histórica. O código, os testes de sessão/proxy e os gates operacionais da rodada de conclusão estão em [instagram-tester-conclusion-910.md](instagram-tester-conclusion-910.md). Os resultados anteriores não validam as alterações posteriores ao commit `e685cb0018`.

Data: 03/10/2026. Escopo: onboarding assistido de Instagram Login, código compartilhado por Autonom.ia e Hub2You.

**Decisão:** implementação e validação local disponíveis para revisão; publicação/ativação NÃO liberadas. Integração real do novo adaptador por stack permanece não executada. A flag global vem desligada e exige allowlist de contas. Um teste sintético aprovado não encerra um gate externo.

## 1. O que foi entregue

Fluxo: informar @ → selecionar perfil → consultar status → convidar somente quando ausente → orientar aceite pelo Instagram Web do computador → verificar → continuar OAuth existente.

[Guia técnico/funcional](../instagram-tester-onboarding.md) · [Runbook](../runbooks/instagram-tester-onboarding.md).

Nenhum segredo, HAR, cURL autenticado ou dado real de cliente foi incorporado às fixtures ou à documentação desta entrega. O preparador de sessão recebe captura como dados, nunca a executa. Não houve migration, alteração de workflows, instalação de dependência nova, merge ou deploy.

## 2. Matriz de aceite

PASS LOCAL significa que a implementação foi exercitada por testes no ambiente isolado. Não significa funcionamento homologado em produção.

| ID | Requisito | Evidência verificável | Resultado |
|---|---|---|---|
| A01 | Desligado por padrão e sem chamadas novas no fluxo legado | `configuration_spec.rb`, `testers_spec.rb`, casos browser `legacy-feature-off-*` | PASS LOCAL |
| A02 | Permissão `inbox_manage`, conta/ator corretos e allowlist server-side | Requests `testers_spec.rb`; regressões Enterprise | PASS LOCAL |
| A03 | Busca com @ opcional e validação de username | `validation_spec.rb`, client/request/UI specs | PASS LOCAL |
| A04 | Candidatos com foto/nome/@ e seleção explícita, inclusive resultado único | `TesterOnboarding.spec.js`, browser `single-result-still-explicit`, `choose-second-candidate` | PASS LOCAL |
| A05 | ID numérico exato, sem coerção de precisão e sem ID arbitrário do cliente | `selection_spec.rb`, `validation_spec.rb`, requests de seleção não assinada | PASS LOCAL |
| A06 | Seleção vinculada a conta, ator, App pai e validade | `selection_spec.rb`, requests cross-account/cross-actor; validade 2h | PASS LOCAL |
| A07 | App pai diferente do OAuthApp; configuração separada por stack | `configuration_spec.rb`, contrato do client; valores reais por stack não inspecionados | PASS LOCAL de contrato |
| A08 | Leitura de todos os grupos `instagram testers`; sem índice fixo | `response_parser_spec.rb`, grupos duplicados/vazios/conflitantes | PASS LOCAL |
| A09 | `PENDING` não reenvia convite | `invitation_spec.rb`, browser pending e verify | PASS LOCAL |
| A10 | `CONFIRMED` não reenvia e ainda exige OAuth | Specs de convite/authorization; browser `accepted-oauth-only-after-click` | PASS LOCAL |
| A11 | Esquema incompleto, erro GraphQL, estado desconhecido e paginação aberta não viram ausência | `response_parser_spec.rb`, `client_spec.rb`, browser malformed/unknown | PASS LOCAL |
| A12 | POST por ID e sucesso apenas com `payload.success=true` | `client_spec.rb` exige shape observado de URL/form/header; parser de resposta | PASS LOCAL |
| A13 | Clique duplo e concorrência não duplicam envio | `invitation_spec.rb`, browser `double-invite-prevented` | PASS LOCAL |
| A14 | Timeout/cancelamento de escrita indeterminado exige reconciliação, sem retry cego | Invitation/request specs e browser `invite-timeout-reconcile-no-loop` | PASS LOCAL |
| A15 | Reconciliação não apaga geração nova nem conserva pendente antigo após aceite observado | `invitation_outcome_spec.rb`, requests de sequência; segunda revisão independente | PASS LOCAL |
| A16 | Orientação explícita: computador, @ exato, nome configurado do app e caminho completo | Componente `TesterAcceptanceInstructions.vue`; browser `guidance` em pt_BR/en | PASS LOCAL |
| A17 | Link direto abre nova aba com `noopener noreferrer` | Browser `pending-guidance-and-blocked-external-link` | PASS LOCAL |
| A18 | Não simular detecção da conta logada no Instagram em outra origem | Texto de orientação e revisão UI/UX | ATENDIDO NO DESIGN |
| A19 | Já aceitei — verificar mantém pendente até confirmação efetiva | Composable/specs e casos browser dos estados | PASS LOCAL |
| A20 | Estado confirmado nunca é mostrado como caixa conectada | Texto, specs e revisão de arte | PASS LOCAL |
| A21 | OAuth do novo fluxo verifica aceite e vincula perfil escolhido antes de gravar canal/token | `tester_authorization_spec.rb`, callback specs perfil divergente | PASS LOCAL |
| A22 | IDs `user_id` e `app_scoped_user_id` e callbacks #898 preservados | Regressão de callbacks, deletion, model, webhook, mensagens e token refresh | PASS LOCAL |
| A23 | State novo expira e não permite replay | `oauth_binding_spec.rb`, callback specs | PASS LOCAL |
| A24 | Busca antiga, troca de perfil/conta, erro e confirmação concorrente não aplicam resultado obsoleto | Composable/specs e browser `edit-cancels-stale-search` | PASS LOCAL |
| A25 | Reautorização existente continua sem exigir seleção de testador | `Reauthorize.spec.js`, autorização legada e callback regressões | PASS LOCAL |
| A26 | Erros não expõem cookie, token, corpo bruto, parser exception ou cause | Testes de client, concern de segurança, user details e callback; revisão R1 | PASS LOCAL |
| A27 | Preparador offline não executa cURL; saída privada/atômica e fora de Git | `tests/instagram_testers/test_prepare_session.py`, 25 testes | PASS LOCAL |
| A28 | Layout simples no sistema visual existente; desktop/mobile/claro/escuro | 67 capturas do componente real, revisão independente de arte | APROVADO NO ESCOPO VISUAL |
| A29 | Alvos ≥44px, contraste ≥4,5:1, foco, texto móvel sem compressão e passos numerados | Browser e helpers de contraste; 320px/390px/desktop/200% CSS | PASS LOCAL |
| A30 | Texto en/pt_BR e Guia atualizados | `i18n:fork:check`, `guia:build/check`, fontes do Guia | PASS LOCAL |
| A31 | Sessão atual, relação dos Apps e configurações reais das duas stacks | Matriz operacional do runbook | PENDENTE EXTERNO |
| A32 | Novo adaptador autenticado ao vivo, aceite/OAuth/webhook/DM por stack | Necessita homologação autorizada sem credenciais expostas | NÃO EXECUTADO |
| A33 | CI/integrabilidade da versão final e aprovação de publicação | Checks do PR e aprovação de Rodrigo | GATE ANTES DO MERGE |
| A35 | Alarme operacional de sessão/serviço em cada stack | Não há canal de alerta novo configurado; erros próprios e runbook entregues, configuração do alarme ainda precisa ser validada | PENDENTE OPERACIONAL |
| A34 | Preservação da produção e possibilidade de interrupção/rollback | Flag OFF, sem migration, sem merge/deploy; runbook de rollback | ATENDIDO NA ENTREGA |

## 3. Execuções locais registradas

Ambiente isolado: Ruby 3.4.4, Node 24.x, PostgreSQL/Redis de teste em portas exclusivas. Nenhuma suite utilizou banco ou ENV de produção.

| Bateria | Resultado observado | Escopo/limite |
|---|---|---|
| RSpec amplo | 271 exemplos, 0 falhas, 29 arquivos | Instagram inteiro por caminho de spec + duas suites Enterprise; não é suite total do repositório |
| Vitest | 86 testes, 0 falhas, 9 arquivos | Novo onboarding/API, reautorização, cancelamento e regressões adjacentes de caixas |
| Browser Chromium | 33 casos, 0 falhas, 67 capturas | Componentes reais + CSS real + API interna simulada; sem shell/wizard completo ou Meta real |
| Helpers de browser | 10 testes, 0 falhas | Fixtures, contraste, alpha/filtros e falha explícita em superfícies não suportadas |
| Importador de sessão | 25 testes, 0 falhas | Dados sintéticos; parser offline/permissões/overwrite/symlinks/segurança |
| i18n | 10 catálogos, 16.986 mensagens compiladas | Paridade de chaves/parâmetros en/pt_BR |
| Guia | 175 fluxos, 173 telas, sem explicação faltante | Fonte `porques.md` e artefatos gerados |

Manifestos e logs completos permanecem localmente em `tmp/instagram-910/`, ignorado pelo Git. Fontes dos testes são versionadas e reproduzíveis; nenhum conteúdo de sessão é necessário para testes sintéticos.

A inspeção inicial RuboCop reproduziu duas infrações preexistentes no `DashboardController` da base: `Lint/NonLocalExitFromIterator` e `Style/RegexpLiteral`. O hook normal de commit corrigiu somente o delimitador do regex existente, sem mudar seu padrão/comportamento; não foi criada expressão regular nova. Permanece a infração preexistente `Lint/NonLocalExitFromIterator`. Não tratar a varredura integral desses arquivos como totalmente verde, nem como regressão da linha de flag adicionada. ESLint não retornou erros; avisos do resolvedor de catálogos/dynamic key são acompanhados de compilação i18n e verificação de ausência de chaves faltantes no browser. Há avisos preexistentes de depreciação Rails/Rack, Browserslist e sourcemap de dependência; não foram feitas atualizações de dependências fora do escopo.

## 4. Revisões independentes e correções

Foram usados subagentes reais especializados em UI/UX, direção de arte, backend, frontend, planejamento de testes, QA de navegador, ferramenta operacional, documentação e revisão de segurança/código.

| Revisão | Achado | Correção e verificação |
|---|---|---|
| Segurança R1/P1 | Resposta OAuth malformada podia aparecer em logger/tracker antes da sanitização do callback | Erros próprios sem body/parser/cause; reprodução com token sintético e assertions em callback real; revisor encerrou R1 |
| Segurança R2/P2 | Cache pendente podia sobreviver a aceite e remoção posterior | Reconciliação por geração; revisão adicional detectou corrida no EXEC; compare-delete limitado `unknown:G` depois `pending:G`; novas gerações preservadas; revisor encerrou R2 |
| Arte | Contraste insuficiente dos botões e título confirmado | Tokens existentes locais, sem alterar Button global; normal/hover/foco medidos e rechecados por pixels |
| Arte | Trocar perfil comprimia identificação móvel | Ação em linha própria abaixo de `sm`; identidade mantém largura e quebra por palavras |
| Arte | Densidade e passos sem numeração visível | Suporte após CTA e lista decimal; medição de ordem/estilo e revisão de 16 capturas novas |
| QA browser | Input de 40px e link de 17px | Ajuste somente no fluxo novo; alvos de 48/44px confirmados |

Diretor de arte aprovou a renderização corrigida no escopo examinado; revisor de segurança encerrou os achados e aprovou código para PR. Nenhum deles declarou homologação da Meta real ou do wizard completo.

Contraste mínimo observado dos botões: **4,913:1 claro / 5,390:1 escuro**. Título confirmado: **11,255:1 / 9,239:1**. QA coletou 195 medições de botões, 30 de título, 17 de identidade móvel e 27 verificações de sequência/suporte. O caso 200% é zoom CSS, não teste de zoom da barra do navegador.

## 5. Gates que não podem ser escondidos

O POC anterior do usuário demonstrou pesquisa, convite e `PENDING → CONFIRMED` no painel. Isso não prova que a implementação atual foi autenticada e homologada nos dois ambientes. A tentativa de probe ao vivo nesta execução encontrou bloqueio da ferramenta e não foi repetida/delegada. Falta validação autorizada do adaptador atual e do fluxo OAuth/mensagens, separadamente nas duas stacks, com sessão atual e apropriada.

**Não existe garantia absoluta de ausência de regressão.** A evidência cobre as suites e renderizações descritas; integração externa, configuração produtiva e suite completa do monorepo não foram inferidas como verdes.

Push de código na `main` dispara deploy nas duas stacks. Portanto, PR não deve ser mesclado enquanto os gates de CI, homologação e aprovação não forem resolvidos. Desligar a feature não equivale a impedir deploy. Não remover testadores ou canais, reenviar a clientes confirmados ou alterar secrets para fabricar evidência.

## 6. Integração com a base atual

A branch exclusiva foi reaplicada, sem conflito, sobre `fd7d20d0239707a42d9a9aafa38f86b4412a3920` (main após #909). O código revalidado é `80fdee5feb`; os próximos commits desta entrega registram documentação/evidências/artefatos gerados. Nenhuma mudança foi aplicada à main.

Após essa atualização, passaram novamente 271 exemplos RSpec, 86 Vitest, build completo de assets, eager load (`zeitwerk:check`), i18n e mapa do Guia. O novo verificador de formatos do Guia exigiu geração: foram atualizados pelo comando oficial 492 contratos de ações (somente metadados/novos campos desta feature), e o recheck passou. O catálogo gerado continua explicitando entradas cujo tipo não é inferido; não foi editado manualmente para fingir cobertura.

O browser foi reexecutado sobre o build atual: 33/33 casos, 67 capturas, hashes de fonte estáveis; 63 imagens idênticas à rodada visual aprovada. A inspeção específica das quatro imagens iniciais identificou contraste insuficiente do placeholder herdado. O campo novo recebeu override local usando `n-slate-11`, sem alterar o componente compartilhado. QA incluiu 20 medições de `::placeholder` normal/foco: mínimos 5,077:1 claro e 8,591:1 escuro, com 33/33 casos e 10/10 helpers aprovados. O diretor de arte reinspecionou os pixels e aprovou a tela inicial, mantendo a aprovação dos demais estados.

Capturas representativas versionadas em `docs/assets/instagram-testers-910/`: perfis e respostas são **sintéticos**. São componentes reais, não imagens conceituais e não prova de aceite de cliente real.

### Limites operacionais adicionais

O lock/idempotência usa o Redis da instalação. Caso as duas stacks compartilhem o mesmo App pai mas Redis separados, essa trava não oferece exclusão mútua entre as instalações. A matriz do runbook precisa resolver esse cenário antes de habilitação conjunta. Não foi implementado serviço distribuído novo para presumir uma topologia não verificada.

Foram entregues códigos de erro próprios, limites, proteção de sessão e runbook. Não foi configurado ou acionado um alarme real de monitoramento em nenhuma stack nesta execução. Esse item não deve ser apresentado como entregue só pela existência de tratamento de erro.
