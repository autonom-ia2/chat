# Agentes de IA — F4: painel e resultados

Execução local em 08/10/2026. Issue #1160, vinculada à épica #1114 e ao Project 3. Branch docs/agentes-ia-prd, HEAD 532a5b7b, na worktree existente. Sem novo PR, commit, push, migration, fila, merge, deploy ou produção.

## Aprovação e escopo

Rodrigo aceitou o bloco de criação e autorizou o próximo bloco: Como está indo, resultados e conversas atendidas. O PRD §6.3/§11.4, CA-PAINEL/CA-RES e o mockup aprovado definem o desenho. Plano: docs/agentes-ia-redesign/design/F4.md. As demais abas reutilizam consumidores existentes; seu redesign completo continua em F5–F7.

A limpeza de snapshots foi redirecionada pelo Rodrigo a outro chat antes de qualquer exclusão. Preservar prévia 54, banco 50, agente claro 30 e F1.

## Referência visual

O protótipo foi percorrido no M2 por Todas as telas e Ver esta tela como: 36 capturas, nove cenários em quatro perfis visuais, sem erro de página. SHA-256 do HTML: c0895b0b116de805dbc562ac19be87f38a8a4d7414ca0d012cc1b45f32edb9dc. Essas imagens são referências, não capturas do produto.

## Implementação local

- Backend mantém a API analytics, os escopos de conta/Enterprise e o limite de 50. Acrescenta aviso de conversas ocultas e envelope de conversa às marcações de resposta errada. Specs existentes ampliadas. Ruby -c e diff check passaram no worker; RSpec ainda não executado.
- A API frontend aceita signal opcional em analytics e analyticsConversations, preservando as chamadas antigas.
- Entrada, página, casca, resumo e gaveta novos estão em integração pelo worker frontend. Testes, capturas e seed sintético exclusivo ficam com o QA.
- A explicação do painel foi atualizada em porques.md. Arquivos gerados do Guia ainda aguardam geração oficial.

CA-RES-03 define “Ensinar → O que sabe”; BE-28 define a leitura das marcações. O protótipo screens-extra.js também navega para essa aba. F4 reutiliza a gestão funcional de materiais, sem criar endpoint ou diálogo novo de correção. Remover a query report_id sem consumidor. Motivo e sugestão permanecem visíveis na gaveta.

## Ambiente separado

Helper F4 preparado, mas ainda não iniciado: portas 59740–59743, banco chat2you_agentes_ia_f4, runtime-m2-panel-f4 e manifesto externo fixtures-panel.json. Guards de snapshot, branch e hash, ambiente env -i, schema apenas no banco novo e seed exclusivo. Bash -n passou.

A integração encontrou dois ajustes do harness antes da execução: exportar a autorização do seed apenas com --seed e permitir no seed o caminho externo exato do manifesto F4. O primeiro já foi aplicado; o segundo está com o QA. Preparação não significa jornada executada.

O comando maccluster work plan --cwd <worktree> -- node scripts/guide-map/build.mjs retornou: “nenhum nó elegível: m2=cwd-missing, m4=insufficient disk”. maccluster resources mostrou M4 com 6,3 GB livres e M2 com 203,8 GB livres. Geração e testes usarão o snapshot oficial no M2, sem contornar a exclusão do M4.

## Acompanhamento e validação

Project atualizado e lido de volta: Em desenvolvimento, Hub2You, Feature, P1, Médio, Local. Próxima ação: implementação e telas reais. Recibos em .codex/preview/check55/project-f4-update.json e project-f4-readback.json. git diff --check dos arquivos coordenados pelo root passou. Esses checks não substituem testes, navegador, build ou CI.

Snapshot F4, validações estáticas, RSpec, Playwright, capturas reais, revisão independente e aceite visual permanecem pendentes. Nenhum PASS geral ou R1 declarado. Regra: implementar → corrigir validação → R1 → corrigir → mesmo R2; se R2 reprovar, corrigir a causa raiz → mesmo R3; se R3 reprovar, parar e retornar ao Rodrigo. Sem R4.

## Causa raiz de integração: ramos da cotação

O reader inicial de PanelQuoteKnowledge usava insurance/quote_agent, que exige insurance_view. CA-SAB-07 e BE-17 exigem que os ramos sejam legíveis com autonomia_view pelo GET do próprio agente, mesmo sem insurance_view. A causa é reutilizar um reader com domínio de permissão diferente. Correção em andamento: quote_branches account-scoped no DTO do agente, com slug/nome públicos, e frontend sem chamadas a insurance/*. O gate de Cotação permanece intacto. QA acrescenta cenário com editor sem insurance_view. Não houve alteração de produção nem rodada independente de revisão.

Snapshot preliminar 20261008-133420-532a5b7b-6fac45297f-344de13e, SHA de conteúdo 6fac45297f3a7b8fb968718aa16e9f12b47a1c17cab03efb44758495e3dfbeb6: fonte e réplicas verificadas nos dois nós. Este snapshot antecede a correção BE-17 e serve apenas para preparar dependências e obter diagnóstico; não representa aceite final.

## Preparação e geração executadas

A preparação oficial workspace prepare recusou um symlink preexistente em docs/campaigns/mockups/800; o snapshot já havia sido validado por checksum nos dois nós. Sem mudar a ferramenta, o fallback previamente usado no projeto executou pnpm install --frozen-lockfile --offline em env -i pelo maccluster work plan/run, no M2. Resultado: código 0, dependências reaproveitadas do cache, nenhuma alteração dos lockfiles.

O gerador oficial do Guia, construir({ escrever: false }), foi executado no snapshot e exportou os resultados para fora de src: 195 fluxos, 189 rotas, zero telas sem explicação. O root sincronizou somente os outputs permitidos. guia-produto.md mudou; guideRouteRegistry.js permaneceu idêntico. A geração oficial Autonomia::Guide::Formatos.gerados também terminou com código 0; os três outputs permaneceram idênticos. Recibos SHA em generated-guide-receipt.json e generated-formats-receipt.json. Checks finais ainda pendentes.

BE-17 corrigido na fonte: quote_branches só no detalhe do agente de cotação, com especialistas reais habilitados/disponíveis, slug e nome. PanelQuoteKnowledge agora consome exclusivamente esse DTO. Specs e jornada cobrem autonomia_manage sem insurance_view, mantendo insurance/* negado. Os resultados dessas provas ainda não foram executados.

## Primeira execução da bateria F4

Snapshot 20261008-133841-532a5b7b-2b343c3aff-d17ac5b0, conteúdo 2b343c3aff57d192a076e52ca09d8c6177d0fc545b056050f33e0c1f02fc4ab9. Dependências raiz/Playwright e prepare do wrapper Ruby terminaram com código 0. Não havia RSpec/prepare concorrente no M2 antes de preparar o banco descartável.

Bateria: Vitest 44 passaram, seis falharam e três rejeições não tratadas; RSpec 27 exemplos, duas falhas; ESLint um erro e 90 avisos; RuboCop quatro ofensas; i18n fork passou. Formatos:check falhou porque seu runner não fixou a porta 55432 e tentou localhost:5432, recusada. Sem aprovação geral.

Causas corrigidas na fonte: mock assíncrono de módulo Vue inválido, expectativa de chave i18n em vez de texto traduzido, teste de gaveta fora do fluxo real de mudança de métrica, prop sem uso, contrato de SQL anterior ao novo exists?, evento-base extra na fixture de permissão e ofensas de estilo. O isolamento do cenário continua exigindo count=1 e ausência de identidades ocultas. O runner de formatos agora fixa o mesmo banco descartável oficial em env -i.

A jornada diagnóstica falhou antes do navegador: seed tentou criar participante sem vínculo prévio à caixa; validação User must have inbox access. Correção do seed com QA, sem suprimir validação. Runtime F4 encerrou pelo trap; banco parcial de fixtures foi preservado para continuação idempotente. Nenhuma edição humana ou dado real nesse banco. Reexecução e revisão independente ainda pendentes.

## Segunda execução e contrato do harness

Snapshot corrigido 20261008-134616-532a5b7b-d87508385d-a649f15f, conteúdo d87508385db515e277ab18c2945c455c9de7de26c67575e8872df725314c6fd5. Vitest: 50/50 em dez arquivos; ESLint: zero erros e 90 avisos conhecidos; i18n: 13 catálogos e 20.526 mensagens; RuboCop: seis arquivos, nenhuma ofensa; formatos do Guia: em dia. RSpec: 27 exemplos, uma falha restante na própria assertiva, que buscava display_id=3 como substring de timestamps no JSON bruto. Corrigida para verificar IDs e nomes nos campos estruturados, mantendo a prova de ausência de identidades ocultas. Reexecução dessa prova pendente.

O seed corrigido passou e o runtime iniciou. A jornada parou antes do navegador porque o loader do manifesto ainda restringia o caminho ao .codex interno. Causa: guards de leitores/escritores divergentes. QA alinhou loader, seed e saídas ao caminho externo exato com marcador oficial de branch/head/hash. Não houve afrouxamento de namespace.

Após o outro chat liberar disco no M4, o planner automático escolheu esse nó para guia:check, mas suas dependências desse snapshot não estavam preparadas. A tentativa falhou por vite ausente. O root corrigiu a seleção para o M2 preparado: guia:check terminou com código 0. Build Vite em modo production, com RAILS_ENV=test e env -i, segue em execução; não é deploy.

## Backend aprovado na validação e primeiro navegador real

Snapshot QA 20261008-135831-532a5b7b-f1310d3f22-b8a03ce3, conteúdo f1310d3f221edd94b50dc5d156e3e4db6027dcd0262517c0eb612df808005229. Comparação binária de 10.446 arquivos de aplicação, bibliotecas, configuração, banco e dependências contra o snapshot corrigido: nenhuma alteração; as correções finais atingiram testes/harness. Build Vite completo passou (6.864 módulos), sem deploy. RSpec executado pelo wrapper oficial isolado no M2: 27 exemplos, zero falhas. Receipts em check55/build-f4-result.json e rspec-f4-qa-ready-result.json.

A matriz nativa de 52 testes iniciou no runtime F4 separado e parou no primeiro cenário: Axe acusou aria-label inválido em spans das barras, contraste dos textos slate-10 no painel e título global vazio no ambiente local. A imagem real foi inspecionada pelo root. Autores investigam/corrigem as causas; nenhuma verificação foi suprimida. R1 independente está em leitura, sem aprovação final de runtime/visual. Banco F4 contém somente fixtures sintéticas, preservado inativo; previews anteriores e banco com claro/30 foram mantidos.

## R1 independente: correções concretas

O agente f4_revisao_independente fez a leitura antecipada enquanto a pré-validação visual era corrigida. R1 sem aprovação: estado active+enabled:false já é E6, mas Shell/Page usavam somente status; seção de motivos sumia sem dados em vez de apresentar o vazio normativo; cartão de transferência omitia handoff_count; cópias de voltar/visibilidade divergiam do aprovado. Também havia expectativa incorreta no teste both, que deve manter somente o resumo externo. Autores corrigem este pacote antes do próximo freeze. R2 será com o mesmo revisor depois da matriz e imagens reais. R2 reprovar implica causa raiz e mesmo R3; R3 reprovar encerra e retorna ao Rodrigo, sem R4.

Causas da pré-validação: spans genéricos usavam aria-label; textos slate-10 não atingiam contraste; seed não criava INSTALLATION_NAME já lido pelo layout; cenários de captura duplicavam o prefixo panel no manifesto; spec da cotação ainda esperava O que sabe ausente apesar de BE-17. Correções por ownership, sem remover Axe ou ampliar permissões. A entrada de navegação local é um helper ignorado, loopback, banco F4 exclusivo e contas sintéticas; nenhuma alteração de auth de produto nem credencial real.

## Pré-validação após as correções da R1

Snapshot 20261008-141057-532a5b7b-f9c5ca69d3-95bbe08a: 61 testes Vitest em 12 arquivos, 27 exemplos RSpec sem falhas, ESLint sem erros (99 avisos), RuboCop seis arquivos sem ofensas, i18n fork e formatos em dia. A bateria inclui SidePanel e ReportDrilldownCard compartilhados. Correções de acessibilidade preservam contratos e navegação: roles das barras, contraste slate-11, metadados/timestamps sem aria-label em span genérico e região de gráfico navegável por teclado. A navegação de O que sabe na cotação usa amber-12 para não herdar link azul com contraste insuficiente.

Build completo do snapshot 20261008-142415-532a5b7b-4bbed851b1-d9c7cd76 passou (1m18s). Sua matriz nativa executou todos os 52 casos: 44 passaram, oito falharam por duas causas no harness repetidas nos quatro perfis. Seed omitia o slug canônico do especialista; a expectativa de E1 usava Rascunho em vez de Falta terminar. Correções somente em seed/spec, sem mudar BE-17 ou estado de produto. A inspeção da captura também encontrou skeleton prematuro; a captura agora espera analytics carregado depois de Home e verifica a geometria do primeiro separador. Nenhuma falha foi removida da matriz.

Snapshot final de QA 20261008-143449-532a5b7b-a6e251da9f-b5fe3d2c, conteúdo a6e251da9f3a2fc2447d553590c43b3d9c421bd32343d9f2b6ce0c02fb05ac8a: ambas as réplicas verificadas. Comparação binária de 10.444 arquivos app/enterprise/lib/config/db e manifests de dependências contra o build anterior: zero alterações. Dependências raiz e Playwright preparadas offline no M2, código 0. Nova matriz integral em execução; isso ainda não é aprovação R2.

A limpeza de snapshots/worktrees/branches foi transferida pelo Rodrigo a outro chat. Nenhum item foi excluído por esta sessão.

## Matriz final de QA: diagnóstico preciso

Execução native-f4-ready-gallery concluiu 52 casos: 46 passaram e seis falharam. A projeção de cotação passou (slug e nome canônicos); a falha restante era o gate de recurso do runtime sintético devolver 404 antes da autorização esperada 403. A rota /autonomia/insurance/quote_agent existe (config/routes.rb:481). Insurance::BaseController aplica ensure_feature_enabled antes de insurance_view. O runner/conta não habilitavam INSURANCE_QUOTING_ENABLED/autonomia_insurance_enabled. QA habilita somente esses gates locais para manter a prova de 403 sem alterar permissão de produto. As duas falhas mobile expuseram aba focada parcialmente escondida após End→Home. A fonte recebeu foco preventScroll e scrollIntoView nearest; reexecução ainda pendente. Não houve nova rodada independente.

Inspeção das imagens originais da gaveta 400 versus protótipo: contato/canal truncados pelas três colunas, status Open bruto e dois horários compactos sem distinção. Correção de apresentação F4 em andamento por uso opt-in do cartão compartilhado, para manter padrão Reports e evitar regressão fora do bloco. Não considerar Axe isoladamente como aprovação visual.

## Pacote visual corrigido e compilado

Snapshot visual 20261008-144748-532a5b7b-22b9984e90-6e055a09 (22b9984e901374e036350ca33e1c2915adc9b082cf74e65a3130e9ae247b2b77): build Vite completo em modo production/RAILS_ENV=test passou (104s com orquestração). Opt-in agentPanel preserva apresentação Reports; alinhamento items-start é exclusivo do F4. Na gaveta F4, status usa tradução CRM existente, nomes não truncam no celular e horário é único com tooltip.

O primeiro check teve 62/63 testes passando: stub sem tipo Boolean recebia string vazia no atributo bare, diferente do componente real. Corrigido somente o stub. Snapshot de provas 20261008-145021-532a5b7b-ed3386c036-50674f9c (ed3386c0364950bd5ef22b99749828975f59baf79b6c31b8f27774d71d1f19ec), réplicas verificadas. Comparação de 10.444 arquivos contra o build: única diferença é PanelConversationsDrawer.spec.js. Checks focais reexecutados: 63/63 Vitest em 12 arquivos, ESLint sem erros (102 avisos), i18n fork em dia (13 catálogos, 20.528 mensagens). Backend/config/db/libs são binariamente idênticos ao pacote aprovado com 27/27 RSpec, RuboCop e formatos; recibo visual-fixed-backend-parity.json. Nenhuma migration. Matriz nativa integral desse snapshot em execução; R2 ainda pendente.

## Jornada e inspeção visual dos originais

Matriz do snapshot ed3386c036: 48 casos aprovados; quatro falharam somente por expectativa HTTP403 no gate de Insurance. O contrato comum Pundit é401, confirmado em código e spec existente quote_agent_spec.rb. QA corrigiu a expectativa canônica para401. Cópia externa do spec com apenas imports relocados foi comparada normalizada e executada sem modificar src imutável: quatro casos Cotação aprovados nos quatro projetos. Aplicação e banco são os mesmos; 52 casos validados em48+4, não uma única execução52/52. Nenhuma permissão foi alterada. Recibos native-f4-proofs-result.json e native-f4-gate-final-result.json.

Exportação original:72PNG verificadas porSHA, sem banco/credenciais. Builder remoto recusou manifest cru com caminhos absolutos; o exportador já produz o manifest reduzido com basename+SHA. A galeria final usa esse manifest verificado, sem afrouxar os guards.

Inspeção dos PNG originais pelo root encontrou CRM.CONVERSATION_STATUS_OPEN aparecendo em vez de Aberta. Causa: CRM é catálogo lazy apenas da rotaCRM. Correção na fonte troca para seis chaves próprias AGENTS en/pt_BR (status e última atividade), carregadas no painel; não adiciona dependência do CRM nem muda Reportsdefault. Snapshot 20261008-150440-532a5b7b-6f586c6dcc-9494930b (6f586c6dcc8c80092a18ab3855db44f5e034cafda4bcab174a4dc103b435f844), réplicas verificadas. Paridade contraed3386: só ReportCard/spec e catálogos agents en/pt_BR mudaram dentre10.444 arquivos de app/config/db/libs/deps. QA canônico também passa a exigir status realopen/Aberta e ausência de chaves cruasCRM/AGENTS nos cartões. Reexecução focal das três jornadas de gaveta ×4 perfis em preparação, com novos checks/build. R2 independente ainda não executada.

A tentativa inicial de servir foi recusada por thermal Heavy no M2; não houve bypass. Depois do recurso voltar aModerate, a prévia iniciou. Para trocar a versão, root identificou o único bash com comando exato de helper/src/head (PID97300) e enviouTERM; trap preserva banco e encerra só seus filhos. Previews54/50/F1 e túnel59720 permanecem intactos.

## Pacote real entregue à segunda revisão

Snapshot final de aplicação: 20261008-150440-532a5b7b-6f586c6dcc-9494930b, conteúdo 6f586c6dcc8c80092a18ab3855db44f5e034cafda4bcab174a4dc103b435f844. Fonte e réplicas verificadas; SHA de conteúdo não é commit. HEAD Git permanece 532a5b7beb56902d2a0168013a3e8b657ba31488.

Checks finais: 63/63 Vitest em12 arquivos, ESLint zero erros/102 avisos, i18n fork13 catálogos/20.540 mensagens. Build Vite modo production com RAILS_ENV=test terminou código0 em100,58s com orquestração; não é deploy. Backend/Enterprise/config/db/Guia permanecem idênticos aos arquivos já validados:27/27 RSpec, RuboCop seis arquivos sem ofensas, guia:check e formatos em dia. Recibos checks-f4-i18n-fixed-result.json, build-f4-i18n-fixed-result.json, i18n-fixed-source-parity.json e visual-fixed-backend-parity.json em .codex/preview/check55/.

A repetição final no navegador passou16/16: quatro cenários em quatro perfis, cobrindo os cinco resultados, motivos/Ensinar, escopos de participante/viewer/conta e estados vazios7/30dias. O caso month_empty agora seleciona efetivamente30dias, espera GET range=30d e exige Testar dentro de empty-total; a imagem anterior capturava7dias e foi substituída. QA externo é equivalente ao canônico após normalizar somente imports; proveniência em final-qa-overlay-provenance.json. Recibo native-f4-drawers-empty-final-result.json. A matriz integral anterior permanece48+4, sem inventar uma execução única52/52.

Galeria final:72PNG originais,18 cenários × computador/celular × claro/escuro. Cada item tem SHA/proveniência no panel-capture-manifest.json (manifestSHA d5cb13ed2c0cfad13d2e39171802a1b4d86bffaffafd89d7fac710604cc74981):24 imagens renovadas no6f586c6dcc e48 reaproveitadas de componentes idênticos noed3386c036. Diretório local .codex/preview/agents/screenshots/panel-f4/i18n-final; não usar current, que preserva o diagnóstico antigo. Galeria HTML em .codex/preview/agents/panel-f4-gallery.html, servida em http://127.0.0.1:59740/preview-telas. Comparações usam36 referências do mockup aprovado, sem apresentar referência como produto. O root leu os PNG originais de cabeçalho, interno, cotação, gavetas e vazio total; Aberta aparece traduzido, metadados cabem no celular e30dias/Testar estão corretos.

Portal http://127.0.0.1:59740/preview-painel: dez cenários sintéticos abrem aplicação real. Validação portal-f4-final-check-result.json passou dez destinos,72 cartões/filtros18por perfil e teclado do gráfico. Ciclo por API real passou active+enabled:false→Pausado/Ativar→Atendendo→Pausar com confirmação→Pausado; fixture voltou ao estado pausado. Rede restrita ao ambiente local. Galeria e portal responderam200/text-html pelo túnel M4↔M2. Prévia F4 usa59740–59743 e banco exclusivo; prévias54/50/F1 e agente claro30 preservados.

R2 formal iniciada com o mesmo revisor independente, somente docs/agentes-ia-redesign/revisoes/F4-r2.md sob seu ownership. Resultado ainda pendente neste registro. Aplicação congelada durante revisão; documentos podem registrar evidência. R2 reprovada exige causa raiz e correção antes do mesmo R3; R3 reprovada exige STOP, semR4. Aceite visual do Rodrigo ainda pendente. Sem novo PR/commit/push/migration/fila/merge/deploy/produção; limpeza fica no outro chat.

## R2 reprovada — causa raiz antes da última correção

O mesmo revisor independente reprovou R2 em revisoes/F4-r2.md, com três achados. Não é autorização de release nem quarta rodada.

1. Contagem: analytics_controller monta meta.count com records.size após first(50). Causa é confundir total do escopo visível com tamanho da página. Corrigir no controller com COUNT do escopo já autorizado antes do limite; manter payload ≤50, has_more e aviso de ocultas. Prova de request deve usar mais de50 conversas visíveis e uma identidade fora do escopo, verificando simultaneamente total/página/privacidade.
2. Interruptor: Shell criou botões genéricos de Ativar/Pausar duplicados em desktop/mobile; testes só verificavam ação, não papel e estado acessíveis. Causa é substituir o controle aprovado por botão sem contrato. Reusar AgentSwitch/LabeledSwitch com role=switch, aria-checked por E5/E6 e rótulo de estado/nome; manter confirmação e endpoints existentes. Provas nativas nos quatro perfis.
3. Textos: resumo reutiliza PERFORMANCE legado, herdando termos técnicos e formato handoff2%·1. Causa é usar copy anterior em tela redesenhada. Criar/reusar chaves próprias REDESIGN en/pt_BR com texto aprovado, sem alterar catálogo legado, e manter percentual com quantidade legível.

Ownership separado: f4_contagem_r3 no controller/spec; f4_abas_visuais na casca/resumo/specs/catálogos; r9_produto na jornada e helpers. Root registra, integra e executa checks/build/navegador isolados. Não alterar produto durante a última revisão. Depois destas correções e provas, o MESMO revisor executará R3. Se R3 reprovar, STOP e retornar ao Rodrigo; não há R4.

## Fonte da última correção e verificação de réplicas

Causas corrigidas pelos owners: visible.count antes de limit, request com51 visíveis e caixa restrita; AgentSwitch existente em desktop/mobile com estado acessível; chaves REDESIGN próprias para métricas/seções en/pt_BR e percentual(N). QA canônico exige total55/payload50, interruptor E5/E6 e textos aprovados nos quatro perfis. O legado não teve suas chaves PERFORMANCE alteradas.

Snapshot20261008-152520-532a5b7b-626dbf314f-fd291593, SHA626dbf314f58bd003e109517d60d7daecd311e191f77e77ca5c94bd8e61fdd7c. A chamada interativa perdeu o stdout por timeout do REPL, mas o snapshot já existia: não foi criado outro. Verificação oficial maccluster workspace verify <snapshot> --json passou nos dois nós, com hashes idênticos; recibo verify-f4-r3-replicas-result.json/log. Primeira tentativa do verify tinha --cwd inválido e não executou; forma posicional corrigida. Nenhum bypass do verificador.

Dependências raiz e Playwright preparadas somente no snapshot M2, pnpm offline/frozen, código0. Helpers fora de src. Runtime6f anterior foi identificado pelo comando exato do bash/PID13284 e recebeuTERM; trap encerrou somente seus filhos, preservando o banco. Nenhuma exclusão e previews54/50/F1 intactas. Bateria completa da fonte626 em andamento; R3 independente ainda não começou.

## Validação da correção R2, antes da R3

Na fonte626:69/69 Vitest em14 arquivos (incluindo AgentSwitch/LabeledSwitch), ESLint0 erros/102 avisos, i18n fork aprovado, RuboCop6 arquivos/0 ofensas e formatos em dia. Primeiro RSpec28 exemplos/uma falha: caso antigo has_more ainda exigia count1 quando duas conversas eram visíveis com limit1. Controller retornou2 corretamente; corrigida somente essa expectativa, preservando payload1, limit1 e has_moretrue. Prova nova51visíveis+caixa restrita já passava.

Reexecução RSpec completa passou28/28 no wrapper isolado oficial. Para evitar outro snapshot por uma expectativa, spec corrigido foi copiado byte a byte para helper externo (analytics_spec.rb, SHA7ec76b49f23439751db4dff27bb2b5ce2783509dbc58ec379ceea6a74ddedbec), mantendo app/src imutáveis; recibo r3-ruby-spec-provenance.json. Não houve remoção de prova ou bypass de permissão. Build completo626 aprovado em79,71s com orquestração. Recibos checks-f4-r3-result.json (falha histórica da expectativa), rspec-f4-r3-final-result.json (passou) e build-f4-r3-result.json. R3 formal só após jornada/capturas atualizadas.

A matriz integral626 terminou48 aprovados/4 falhos. As quatro falhas são a mesma expectativa QA: materiais exigia “respostas que usaram seus materiais”, enquanto PRD §6.3 e nova chave própria dizem “% que usaram seus materiais”. Nenhum defeito de produto identificado nesses erros. Corrigida somente a expectativa canônica, mantendo rótulos/percentual/quantidade, privacidade, limite e interruptores. Repetição focal dos quatro perfis em andamento no mesmo banco/app626 por cópia externa com imports relocados equivalentes; r3-qa-overlay-provenance.json. As capturas dos demais cenários já são desta mesma fonte626, não reutilizadas do pacote6f. Sem início da R3 formal ainda.

## Pré-validação visual adicional: gráfico de30 dias

Os quatro casos de copy repetidos passaram. Exportação626 terminou72PNG verificadas (manifestSHA7db32216c2bd6f24ebfa4cfde8acb0efbbe29527eb2c570b8a3779818c77c17a). Leitura original pelo root confirmou interruptor e total55/página50, mas expôs gráfico aparentemente vazio no desktop1440: min-w-max com30 colunas w-8/gap3 coloca o dia recente com54 respostas fora da largura visível. Os testes conferiam quantidade/roles/keyboard, mas não a geometria da última barra. É uma falha visual de aplicativo descoberta antes da R3, não rodada adicional de revisão.

Frontend corrige largura responsiva para todos os dias caberem no desktop e início no trecho recente do celular; QA acrescenta primeira/última barra no viewport no desktop e última no celular após7→30dias. Root repetirá matriz completa em nova fonte final, pois esta alteração afeta produto. Nenhum revisor foi chamado para R3 ainda; ela continua sendo a última rodada. O job da galeria remota626 recusou --kind analysis inválido; não executou. Usar build/analyze permitido e --application-url /preview-painel na galeria final. Não apresentar a galeria626 como final aprovada.

Fonte final com gráfico corrigido: snapshot20261008-154042-532a5b7b-3277e2d51f-b378d453, conteúdo3277e2d51f2f90e583fb361f41f8cf84bafed6f4389e78ec4a1dad16cb73ca31. Snapshot oficial código0/23,58s, duas réplicas verificadas, captura consistente. Inclui também as expectativas Ruby/QA corrigidas; agora não há overlay de teste. Primeiro preparo recusado por thermal unknown; maccluster resources e novo planner confirmaramNominal/elegível antes do retry, dependências offline raiz/Playwright código0, sem bypass.

O runtime626 identificado pelo bash/comando exatos(PID50828) recebeuTERM e preservou o banco. Fonte3277 tem seu namespace sintético separado. Desktop usa largura flexível para30pontos; celular abre no trecho recente após nextTick e mantém role/tabindex/teclado. QA exige30pontos, rótulos de datas, última barra horizontalmente visível em todos os perfis e primeira/última dentro da largura no desktop. Bateria completa3277 em andamento; ainda sem R3 formal.

Freeze final de formatação: snapshot20261008-154459-532a5b7b-49f6df2a1b-6569bd77, conteúdo49f6df2a1bc1b437f52a19322622c8ee83f8ac3a5d86d726e9b1481d158a9b07, duas réplicas verificadas. A fonte3277 passou70Vitest/28RSpec, mas lint pediu juntar a expressão isMobile em uma linha; root aplicou somente essa formatação. Fonte49 inclui app+QA+specs canônicos corretos, sem overlays.

checks-f4-r3-final-source terminou código0:70/70 Vitest em14 arquivos,28/28 RSpec no wrapper isolado, ESLint0erros/103avisos, i18n13 catálogos/20.568mensagens, RuboCop6/0 e formatos do Guia em dia. Dependências offline com código0. Build e matriz nativa completos da mesma fonte49 seguem antes da última R3. Nenhuma aprovação antecipada.

Build completo final49 aprovado (build-f4-r3-final-source-result.json), código0 em60,50s com orquestração/51,08s Vite. Matriz nativa usa spec canônico direto do mesmo snapshot,52 casos/quatro perfis, sem overlays ou reuso de imagens intermediárias. R3 independente aguardará esses resultados e galeria/portal finais.

Matriz nativa final49 aprovada integralmente:52/52, zero falhas, todos os quatro perfis, em279,47s com orquestração/4,2min Playwright. Source app/spec/QA do mesmo snapshot, sem overlays. As provas agora incluem total55/página50/has_more, switch Atendendo/Pausado e aria-checked em E5/E6, textos aprovados e geometria do gráfico30dias (dia recente visível, primeira+última no desktop). Recibo native-f4-r3-final-source-result.json. Galeria/portal e R3 ainda pendentes neste ponto.

Galeria final49:72PNG originais da mesma aplicação,18 cenários/quatro perfis, todos os hashes verificados. Manifesto final-source-capture-manifest.json, SHA9abaa2618a919178218f5bdd426d52be3cb08911e4a08fb257167c8b08ffb878. Imagens em .codex/preview/agents/screenshots/panel-f4/r3-graph-final, não usar os diretórios intermediários. Galeria M2/M4 gerada com código0 e application-url=/preview-painel; HTTP200/text-html nas duas entradas pelo túnel M4. Root leu originais desktop30dias claro, detalhe30dias celular escuro, pausado celular claro e gaveta celular escuro: barras recentes/datas aparecem, switch correto e título55/página50 legíveis.

Primeiro driver standalone do portal falhou esperando o painel em5s; o config nativo agents.config.ts usa15s para expect/action e30s para navegação. Alinhado somente o driver ignorado a esses tempos, com diagnóstico de caso/path/título/contagem, sem alteração de app/auth e sem retry dentro do cenário. Reexecução da checagem do portal em andamento; R3 formal aguarda o resultado.

## Portal final aprovado e retomada da mesma R3

portal-f4-r3-final-source-aligned-result.json terminou código0/44,96s: dez cenários abrem aplicativo real,72 cartões/quatro filtros18, teclado móvel30dias e ciclo active+enabled:false→Pausado/off→Atendendo/on→Pausar confirmado→Pausado/off. Fixture restaurada. Galeria e portal HTTP200/text-html pelo túnel M4. Esse recibo substitui a pendência do parágrafo anterior; primeira falha histórica de timeout5s permanece registrada. Não houve mudança de app/auth para o retry do driver alinhado ao config nativo15s/30s.

Fonte final49 mantém70Vitest/28RSpec/build/52nativos integrais/72PNG da mesma fonte aprovados. Última R3 formal iniciada pelo mesmo f4_revisao_independente com app/spec/QA congelados; houve interrupção Fatal error: application network permission was revoked, sem parecer nem arquivoF4-r3.md. A ferramenta recomenda followup_task; root retomou o MESMO agente/rodada. Não é reprovação nemR4. Parecer ainda pendente; se R3 reprovar, STOP sem correção/R4. Documentação/Issue/Project atualizados separadamente do aplicativo. Prévia e túnel preservados para Rodrigo; sem release/produção/migration/limpeza.

## Encerramento técnico F4 — R3 aprovada

O MESMO revisor finalizou revisoes/F4-r3.md: APROVADA, sem achados acionáveis. Conferiu fonte congelada49, correções R2/R1, PRD/mockup, permissões/privacidade/legado e causas C1–C15 aplicáveis. Declarou limite de ferramenta: não abriu nova sessão CUA após a falha de permissão de rede; parecer utilizou capturas locais finais e recibos nativos/portal da mesma fonte. Não houve novos jobs, testes, alteração de app, banco ou QA durante a R3.

Root conferiu o parecer e atualizou handoff/plano/Issue1160/Project. Galeria http://127.0.0.1:59740/preview-telas e jornada /preview-painel entregues ao Rodrigo; HTTP final200text/html registrado em check55/final-handoff-http-status.json. Os serviços continuam ativos por job de duração limitada. Revisão técnica encerrada; aceite visual F4 do Rodrigo pendente. Nenhum PR de implementação, commit, push, migration, fila, merge, deploy, produção ou exclusão. Validação local não é CI/release.
