# Revisão normal independente — F0 produto/UX e testes

Issue de revisão: #1123. O autor do desenho F0 foi outra lente da R9; esta é a revisão independente normal de produto/UX e testes. A fonte visual conferida no escopo é `docs/agentes-ia-redesign/mockup/src`, confrontada com `PRD.md` e `aceite-telas-reais.md`. O desenho revisado é `design/F0-mapeamento.md`, que continua rascunho.

Não executei testes, build, navegador, produção ou banco. Não alterei `design/F0-mapeamento.md` nem código. Os achados abaixo formam um único bloco de revisão; cada um tem prova, causa, efeito e correção mínima.

## Achados

### F0-TEST-01 — alta — `page.route` permite fabricar estados que deveriam vir do backend

**Prova:** `design/F0-mapeamento.md:126-136` manda preparar Clara, Lia, caixas e rascunhos locais, mas também diz que os estados de carregamento, erro e vazio serão feitos por `page.route`. O aceite exige implementação real, contrato de API e persistência/efeitos locais (`aceite-telas-reais.md:13-15`), e exige provar a persistência das escritas (`:65-71` e `:81-88`). O helper Playwright já existente só usa `page.route` como bloqueio de rede externa e deixa o backend local continuar (`tests/playwright/tests/relationships/helpers.ts:48-53`); ele não fabrica payloads de sucesso.

**Causa:** o desenho mistura estado legítimo do backend (vazio e carregamento) com falha controlada de transporte/provedor. Isso deixa uma captura passar mesmo se a projeção, a permissão ou o leitor de persistência estiverem quebrados.

**Efeito:** a futura `visual.spec.ts` pode testar uma tela cenográfica e ainda afirmar que a jornada real funciona, contrariando o aceite e a exigência de `page.route` restrito a erro/provedor local.

**Correção mínima:** fixar no F0 que seed, vazio, loading normal e todas as respostas de sucesso vêm do banco/API local; `page.route` só pode cumprir uma falha explicitamente nomeada ou o provedor simulado local. O handler deve falhar fechado para host externo e não pode `fulfill` payload de sucesso. Toda escrita deve ser relida pela API e após reload antes da captura.

### F0-TEST-02 — alta — fixtures não definem identidades, escopos e ciclo de persistência

**Prova:** o F0 só define “browser isolado e conta de teste local” e uma lista de dados (`design/F0-mapeamento.md:130-136`). A matriz de perfis aparece apenas como rótulos (“Pode editar”, “Só ver”, “Administrador da conta”, “SuperAdmin”), sem usuário, tipo, permissão, conta B, sessão ou limpeza (`:138-147`). O aceite exige três perfis com limites diferentes e recusas diretas de escrita (`aceite-telas-reais.md:28-36`), além de uma conta local semeada com Clara, Lia e quatro caixas (`PRD.md:1181-1184`). O padrão real do repositório usa credencial sintética local, `POST /auth/sign_in`, cookies da sessão, contexto de API autenticado e fixture isolada (`tests/playwright/tests/relationships/helpers.ts:9-62`).

**Causa:** a infraestrutura foi descrita por entidades visuais, sem contrato de identidade e sem ciclo `seed → ação real → leitura → reload → limpeza`.

**Efeito:** os cenários podem rodar sempre como administrador e só verificar texto/print; não provam `autonomia_view`/`autonomia_manage`, SuperAdmin, conta diferente, 401/404, ocupação de caixa ou que uma pausa, retomada, material e ligação sobreviveram ao reload.

**Correção mínima:** acrescentar ao F0 uma matriz de fixtures com editor, só-ver (incluindo custom role quando aplicável), administrador da conta, SuperAdmin e conta B; autenticação pelo endpoint local real; IDs criados no setup; recursos e caixas de teste isolados; cleanup explícito. Para cada mutação, exigir resposta HTTP, leitura posterior da API e releitura da tela. O caso de conta B deve provar que a lista e as rotas não atravessam o escopo.

### F0-TEST-03 — alta — as 14 famílias não estão ligadas a testes, leitores e capturas concretas

**Prova:** o F0 manda criar uma única `visual.spec.ts` e nomear capturas (`design/F0-mapeamento.md:128-136`), depois resume perfis e famílias em quatro linhas (`:138-147`). Não há tabela família → arquivo/spec → fixture → ação → leitor (API/banco) → captura. O aceite enumera as 14 famílias e todas as variantes, inclusive E1x, E2m, Lia, ajudante, conexão, gaveta e só-ver (`aceite-telas-reais.md:46-189`); o PRD exige capturas com o mesmo nome nos dois lados (`PRD.md:1179-1202`) e que cada controle tenha leitor provado por spec (`:872-873`).

**Causa:** o desenho tem uma lista de cobertura, mas não tem rastreabilidade executável nem uma afirmação de pós-condição por cenário.

**Efeito:** “todas as telas” pode significar apenas as telas fáceis de abrir; estados de erro, perfis, tipos e efeitos de escrita podem ser omitidos sem o gate perceber. Uma galeria de PNG não demonstra a jornada simples nem a persistência.

**Correção mínima:** incluir uma matriz de 14 linhas no plano de testes, com pelo menos setup, perfil, caminho de rota, ação, resultado visual, leitura de API/banco e nome das quatro capturas. Marcar explicitamente os estados “novo” do PRD e exigir que cada escrita tenha GET/reload e uma asserção de efeito. O padrão já provado é a edição real seguida de leitura e reload em `tests/playwright/tests/relationships/acceptance.spec.ts:82-130`.

### F0-ROUTE-01 — alta — deep link/F5 promete preservar `threadId`, mas não define como ele é encontrado

**Prova:** a tabela de rotas do F0 só coloca `agentId` e `step` em `agents/:agentId/build/:step` (`design/F0-mapeamento.md:79-86`), mas o guard é obrigado a preservar `agentId`, `threadId` e query params e as specs devem provar deep link/F5 e fallback (`:88-96`). No contrato atual, a API só lê uma thread quando recebe o id (`app/javascript/dashboard/api/autonomia/buildThreads.js:37-39`) e o store só tem `fetch({ threadId })` (`app/javascript/dashboard/store/modules/autonomiaBuildThreads.js:165-176`). O estado do builder também fica em store durante a página, não na URL (`app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentBuilderPage.vue:23-32`).

**Causa:** o desenho exige continuidade da thread, mas não define o leitor de uma thread salva ao abrir a rota diretamente nem um parâmetro documentado que a identifique.

**Efeito:** refresh, link copiado ou troca da flag pode abrir Conte/Teste vazio, perder o ponto salvo ou fazer o fallback antigo não receber a mesma thread, violando CA-GERAL-12 e os estados E1–E4.

**Correção mínima:** registrar no contrato da rota o comportamento observável de resolução da thread salva do mesmo agente/conta, os casos de thread ausente/ilegítima e a preservação no fallback; acrescentar isso à spec de deep link e à fixture de retomada. A solução escolhida deve ser validada pelo guard e pelo leitor do backend, sem thread inventada no front.

### F0-UX-01 — média — as cinco etapas não têm contrato de estado e navegabilidade

**Prova:** o F0 decide reutilizar `StepsBar` preservando o contrato de Campanhas (`current`, `reachable`, evento `go`, teclado) e criar um adaptador `AgentSteps` (`design/F0-mapeamento.md:46-59`), mas não mapeia as cinco etapas da jornada para rotas, estado ou alcance. O caminho atual do construtor ainda tem uma barra de duas etapas, “Conversa + materiais → Revisão” (`app/javascript/dashboard/routes/dashboard/autonomia/components/builder/BuilderStepBar.vue:5-9` e `:35-57`). A jornada aprovada é `Escolha → Conte → Teste → Ligue → Pronto` (`aceite-telas-reais.md:38-44`), e o PRD já fixa as rotas correspondentes (`PRD.md:656-670`).

**Causa:** a reutilização técnica de uma barra de Campanhas foi definida, mas o contrato de produto da nova máquina de estados não foi escrito.

**Efeito:** uma implementação pode exibir a barra antiga, liberar Teste antes das quatro respostas/teste válido, permitir salto indevido para Ligue ou não saber para onde vai “Pronto”; isso quebra a jornada de uma pessoa leiga mesmo com componentes compartilhados verdes.

**Correção mínima:** adicionar uma tabela `etapa → rota → estado mínimo → reachable → destino ao voltar`, incluindo E1x, E2m, E4 e perfil só-ver. Exigir que o adaptador preserve teclado/foco de `JourneyStepper` e que a fonte do alcance seja o estado tipado do backend, nunca texto da conversa.

### F0-TEST-04 — média — o helper de axe planejado não existe nas dependências Playwright

**Prova:** o F0 exige `expectNoSeriousA11y` com `@axe-core/playwright` (`design/F0-mapeamento.md:130-136`) e o PRD o usa como critério (`PRD.md:850-854`), mas `tests/playwright/package.json` não declara `@axe-core/playwright` e nenhum dos dois lockfiles contém esse pacote.

**Causa:** o gate de acessibilidade foi incluído como nome de arquivo, sem fechar a dependência e o comando que o executará.

**Efeito:** o check pode falhar por módulo ausente ou ser omitido, deixando a afirmação “axe sem serious/critical” sem evidência.

**Correção mínima:** escolher a dependência já aprovada no repositório ou declarar `@axe-core/playwright` no pacote Playwright e lockfile, junto de um comando/projeto que faça o helper rodar em cada família, viewport e tema. Não considerar o gate existente até a execução ser demonstrável.

### F0-D4-01 — média — o inventário de `#0D2344` fica aberto e contradiz o número usado como escopo

**Prova:** o F0 diz que o PRD registra quatro arquivos e manda fazer o inventário depois (`design/F0-mapeamento.md:61-67`); o próprio PRD registra os quatro usos em `:89`. No checkout há 12 arquivos de produto com o literal: `components-next/CampaignJourney/StepReview.vue`, `components-next/CampaignResult/ResultKpiStrip.vue`, `routes/dashboard/automacoes/components/AutomacaoHeroi.vue`, `AutomacaoSugestao.vue`, `AutomacaoConversaPage.vue`, `routes/dashboard/campaigns/journey/AudiencesPage.vue`, `CampaignJourneyPage.vue`, `routes/dashboard/campaigns/metaAds/components/MetaAdsHero.vue`, `MetaAdsPanel.vue`, `MetaAdsSummary.vue`, `metaAds/metaAdsHelpers.js` e `routes/dashboard/campaigns/pages/EmailCampaignsPage.vue`.

**Causa:** o desenho reconhece ocorrências adicionais, mas não classifica quais pertencem ao D4 nem registra exceções semânticas para as demais.

**Efeito:** F0 não tem critério objetivo: pode deixar telas novas/antigas com hex proibido ou migrar gradientes e produtos fora do escopo sem revisão visual. Isso também impede conferir claro/escuro de forma consistente.

**Correção mínima:** anexar ao F0 o inventário completo do SHA revisado, com cada uso classificado como migrar para `n-navy` ou exceção justificada, e transformar essa lista no check do PR. Não fazer substituição cega.

### F0-DOC-01 — média — Guia e Central não entram no fechamento da fundação

**Prova:** o F0 lista gate, D9, token, i18n, kit, rotas e Playwright como entregáveis (`design/F0-mapeamento.md:5-16`) e só menciona “Guia” como ação da lista futura (`:100-120`); não exige geração, check ou matriz de explicação. O PRD exige bloco/`cobre:` por rota, reescrita dos blocos antigos, `pnpm guia:build && pnpm guia:check` e conferência da Central (`PRD.md:689-692`). O gerado atual ainda contém o painel antigo em `lib/operator_guide/guia-produto.md:792-817`.

**Causa:** o mapa de rotas foi tratado como contrato de runtime, sem ligar a mudança de entrada/menu aos artefatos gerados e às explicações que a pessoa verá.

**Efeito:** as telas podem estar visualmente corretas e a rota funcionar, mas o Guia/menus e a Central apontarem para o fluxo antigo ou não explicarem a nova tela, quebrando a jornada orientada para uma pessoa sem conhecimento técnico e a trava de documentação do repositório.

**Correção mínima:** incluir no F0 uma linha rota → bloco em `porques.md` → saída gerada → artigo/`me_leve_ate_la`, com `guia:build`, `guia:check` e `node scripts/central-de-ajuda/conferir.mjs` no fechamento. Os arquivos gerados continuam sendo atualizados somente pela geração.

### F0-UX-02 — média — alteração do `SidePanel` comum não tem contrato de não-regressão para seus consumidores

**Prova:** o F0 manda fazer o `SidePanel.vue` comum usar `useModalFocus` (`design/F0-mapeamento.md:49-50` e `PRD.md:649-654`). Hoje o componente controla foco inicial/retorno, `Escape`, scroll lock e diálogos aninhados (`app/javascript/dashboard/components-next/side-panel/SidePanel.vue:47-87`), e é consumido por drawers de Campanhas, Conversas, Relatórios, Templates e Captain, além do painel de desempenho dos agentes. O F0 só exige uma spec do destino comum, sem listar os comportamentos dos consumidores a preservar.

**Causa:** D9 trata a extração como troca de import, mas a mudança incide numa peça compartilhada com contratos de foco e fechamento já usados fora de Agentes.

**Efeito:** a gaveta nova pode passar no teste isolado e quebrar foco de retorno, `afterLeave`, scroll ou Escape de uma tela existente, justamente a jornada de Campanhas usada como fonte de reutilização.

**Correção mínima:** registrar no F0 uma matriz de não-regressão do `SidePanel` com pelo menos `AudienceSidePanel` de Campanhas, um drawer de Conversas/Relatórios e a gaveta de Agentes: abrir, foco inicial, Tab/Shift+Tab, diálogo aninhado, Escape, clique fora, retorno ao gatilho e `afterLeave`. A extração só fecha com esses consumidores preservados.

## Conclusão

**F0 não está aprovado.** Há nove achados concretos, sendo quatro altos e cinco médios. O bloqueio principal é de evidência: o desenho ainda permite sucesso cenográfico (F0-TEST-01), não fecha identidades/persistência (F0-TEST-02), não rastreia as 14 famílias (F0-TEST-03) e não define a retomada de thread em deep link (F0-ROUTE-01). A revisão normal termina nesta rodada; a correção deve atacar as causas registradas antes de qualquer implementação de F0 ou aceite de telas reais. Nenhum merge, fila, deploy ou produção foi executado ou autorizado.
