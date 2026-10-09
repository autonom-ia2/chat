# Bloco de criação F2+F3 — Issue1138

Rodrigo aprovou visualmente a galeria de Seus agentes (F1) e autorizou implementar a próxima jornada completa. Aceite funcional e gate global continuam pendentes; esse OK não autoriza produção, banco de produção, merge, fila, deploy, auth ou fornecedor pago.

Issue: https://github.com/autonom-ia2/chat/issues/1138
Project3 item: PVTI_lAHOC3T16M4BX9UHzg_WAHU
Worktree: /Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd
Branch: docs/agentes-ia-prd
HEAD:532a5b7beb56902d2a0168013a3e8b657ba31488; PR1115 congelado. Dirty prévio330 entradas preservado.

Orquestração autorizada: r9_tecnica B3/publicação e Builder; r9_produto frontend de criação/i18n; registrar_decisoes B4b (teste, apresentação e proteções de ferramentas); root BE02, entradas/rotas, Guia, snapshots, testes e runtime. Não há concorrência de edição nos mesmos arquivos sem coordenação.

Inspeção confirmou ausência dos contratos publish, knows, suggested_links, reusable/copy e dependências BE12/29/30. Por isso a entrega inclui implementação local dessas dependências, mantendo separação futura de PRs backend/frontend e B4b isolado. Nenhum botão será tratado como implementado só porque aparece. Desenho do bloco em design/F2-F3-bloco-criacao.md e B3.md.

TDD: novos contratos/specs preparados antes de produto; snapshot36 RED combinado em preparação, execução ainda pendente. Uma revisão normal independente; se checagem exigir correção, causa raiz registrada antes e final limitada. Erro residual final → parar e retornar.

Recursos antes da validação: M2 Nominal, AC100%, RAM livre4,7GB/16, SSD254GB, carga/cores0,28; M4 Nominal, AC95%, SSD18,6GB, abaixo da reserva20GB. Trabalho pesado será planejado por MacCluster em snapshot oficial, sem forçar M4 nem alterar checkout de outro nó.

Prévia futura: aplicação local funcionando com dados fictícios e provider de respostas explicitamente simulado, sem chamadas de IA paga ou ferramentas externas. Não equivale a validação do fornecedor real nem de atendimento a clientes.

## Contratos antes da implementacao - snapshot 36

- Snapshot: `20261008-052046-532a5b7b-02c720ed32-408feac2`.
- SHA-256: `02c720ed32be579e9a08e472b241174b678f00a7b5362fb3054bd6f34564c760`.
- Replicas M2/M4 consistentes antes e depois. Dependencias offline e execucao no M2 via MacCluster; M4 excluido por reserva de disco.
- Ruby: 47 exemplos executados, 43 falhas, 4 passam, nenhuma pendencia nem erro fora dos exemplos. Falhas nos contratos ausentes: rascunho antes do 202, dados estruturados, rotas publish/reusable/copy e novos parametros/metadados do Testar. Os 404 de isolamento que ja passam nao provam os endpoints futuros.
- JS: 1 exemplo passa, 2 falham por metodo publish ausente; tres suites nao coletam porque os modulos de produto ainda nao existem. Nao contar essas suites como exemplos executados.
- Produto autorizado aos tres responsaveis apos leitura das falhas. Root assume rotas, integracao, materiais reutilizaveis e previa/validacao.


## Validação integrada 37 e revisão normal 1

Snapshot oficial `20261008-054959-532a5b7b-5133b1d6e3-3666520a`, conteúdo SHA-256 `5133b1d6e3a073a00c2a4edcc0a22f6bdb0843dcf62bfa1f7eec1e0cacb86d49`; réplicas M2/M4 conferidas antes/depois. HEAD permanece `532a5b7beb56902d2a0168013a3e8b657ba31488`, sem commit/push.

- Ruby: 625 exemplos executados, zero falhas; job `m2-f2ca6478cb514afeb4b5bb3e75822f5d`, wrapper de serviços de teste isolados. Nenhum eval pago.
- Vitest: 107 testes, 100 passaram e 7 falharam, com 15 erros derivados. Causas: fixture sem getter de thread hidratada (1 teste) e mocks de módulos Vue assíncronos sem `__esModule` (6 testes); fixtures corrigidas, aguardando conferência. Não declarar esta rodada verde.
- Guia e formatos: geração oficial em cópia derivada externa ao snapshot; checks em dia, 195 fluxos/189 telas/zero sem explicação. Primeira invocação importava o build sem chamar seu entrypoint: causa do check inicial falhar; comando corrigido para chamar `construir()`. Cinco saídas devolvidas por checksum; mapa de rotas permaneceu igual. Réplicas originais preservadas.
- Navegador real: runtime Rails/Vite e banco fictício loopback, provider local explicitamente simulado; APIs, jobs, salvamento e publicação reais. Rodada interrompida após evidências de contrato/contraste, sem repetir os quatro projetos com causas já conhecidas. Não é rodada aprovada; agentes criados durante testes interrompidos ficam somente no banco fictício desse snapshot.

Achados da revisão normal 1 do root: GET show sem estado oficial impede habilitar Ligue após teste; saída de Ligue vai para Pronto e faz PATCH desnecessário; apresentação digitada não salva ao sair; saudação indevida no Teste interno; lacunas CA-CON/CA-TES (metadados de teste, ferramentas, materiais, sugestões, retry); contraste da etapa atual 4,38:1; botões do compositor legado 36 px no contexto novo. Uma correção consolidada foi solicitada aos responsáveis, seguida de checagem limitada.

O Guia lateral aparece ao habilitar o CRM necessário ao ajudante e tem contraste preexistente 3,77:1 nos controles `data-guia-abrir`/`data-guia-entendi`. Registrar separadamente; não ampliar silenciosamente o redesign a esse componente. A acessibilidade da área de Agentes será conferida com esse limite explícito e sem excluir falhas do novo bloco.


### Revisores independentes — rodada normal única

r9_tecnica revisou B4b: catálogo seguro não incluía especialistas na persistência de `skipped_tools`; nome guiado dependia de metadata que não era escrito no fluxo real; orçamento do teste da Lia podia exceder o TTL; entrada interna não compartilhava a composição segura do Copiloto; GET show não expunha estado. registrar_decisoes revisou B3/BE-02: escopo top-level de threads não excluía sistema; create/PATCH permitiam ativar sem instrução; versões `builder`/`before_manual` faltavam; thread antiga podia declarar `applied=true` mesmo sem aplicação; erro de enqueue deixava abertura órfã. BE-02 sem defeito concreto identificado.

Interpretações operacionais: D23 mantém dispensa de **teste** no create/PATCH legado, mas BE-04 exige **instrução** em toda ativação (matriz §6.7). BE-29 vale também no interno, conforme §6.7 e CA-BE-09; a proibição de aplicar o prompt **externo** ao Copiloto não proíbe uma identidade interna própria após renomear, preservando bytes dos casos neutros. `response_window` é escolha feita em Ligue e o teste explicitamente não aplica horário; sua gravação na publicação não é motivo para exigir outro teste da instrução, e após ativação D24 preserva o estado.

Batch único de correções distribuído: B3/estado público/histórico/threads para r9_tecnica; B4b/ferramentas/orçamento/composição interna para registrar_decisoes; UX/completude/saída/retomada/contraste para r9_produto; root mantém integração, Guia, snapshots e evidências. Checagem posterior limitada a corrigidos e regressões pertinentes. Sem nova revisão ampla.


### Causa raiz — checagem limitada B3 após correção normal

A inspeção da correção de GET show encontrou um erro novo: `show.json.jbuilder` passou `list_row: @list_row` sempre, mas somente a action `show` atribuiu a variável. `create`, `update`, `publish` e `avatar` renderizam o mesmo template sem esse contexto. `_agent` testa a presença da chave e faz `fetch` no valor nil. É uma falha prevista diretamente pelo código; ainda não houve teste executado desse snapshot corrigido.

Causa raiz: contrato do serializador compartilhado foi tratado como contrato de uma única action. A conferência anterior provou apenas GET show, sem percorrer todos os chamadores de `render :show`. Parada e RCA registradas antes de uma última correção/conferência limitada B3: calcular estado fresco na fronteira comum, validar respostas create/PATCH/publish/avatar e manter instrução manual no detalhe, IP guiado oculto. Não iniciar outra revisão ampla. Falha residual B3 nessa última conferência exige parar e retornar.

D27: o aviso de ferramenta que escreve precisa existir antes do primeiro teste. O detalhe terá `writes_external` booleano seguro, calculado no servidor com permissão atual e ferramenta HTTP habilitada diferente de GET, sem expor headers/URLs. Poll/result mantém o booleano efetivamente produzido pelo teste; a UI não deve esperar esse resultado para avisar.


A checagem do achado de enqueue distinguiu estados: §6.6 define E1x somente quando a falha ocorre **antes de existir rascunho**. Após persistir E1, uma falha de enqueue mantém um rascunho recuperável; a correção retira a thread de `processing` e registra `enqueue_failed`, permitindo retomada. Não exigir exclusão de um rascunho válido ou uma transação impossível entre PostgreSQL e fila externa. O defeito comprovado era a pendência que ficava processando; a interpretação inicial de que toda falha de abertura precisava ser E1x foi corrigida contra o PRD.

## Conferência final 38 — PARADO, sem aprovação

Foi respeitada a rodada normal única, seguida de correção e conferência limitada após RCA. A conferência final ainda falhou; todos os responsáveis foram instruídos a parar. Nenhuma nova correção, teste ou revisão será iniciada nesta execução. O bloco está implementado localmente, mas não está pronto nem visualmente aprovado. Prévia F2+F3 não entregue.

Snapshot `20261008-062715-532a5b7b-9be0572339-7599ef48`, SHA-256 `9be0572339d31c5526b12ed5ce96a88b9c332f9aff8f347de924d1ae40bf90cb`. HEAD continua `532a5b7beb56902d2a0168013a3e8b657ba31488`; 367 entradas dirty preservadas. Réplicas M2/M4 consistentes antes e depois, conferência posterior executada separadamente porque o orquestrador terminou ao não encontrar nó elegível para build. Logs locais em `.codex/preview/check38/`; nenhum resultado desta rodada equivale a CI verde.

| Verificação | Resultado observado |
|---|---|
| Ruby | 658 exemplos: 656 passaram, 2 falharam. Job `m2-033f09b6fe6447a4b2eac3172cd187cb`. |
| Interface/Vitest | 108 testes: 107 passaram, 1 falhou; sem os 15 erros derivados da rodada anterior. Job `m2-5329bad1a3324b2e878673c71db06f74`. |
| ESLint frontend | Zero erros, 221 avisos. |
| RuboCop | 39 ocorrências em 17 arquivos; 24 autocorrigíveis. Inclui complexidade/tamanho de métodos/classes e estilo, sem dispensas adicionadas. |
| Traduções do fork | Passou: 13 catálogos, 20.442 mensagens. |
| Guia de rotas | Passou: 195 fluxos, 189 telas, zero sem explicação. |
| Central de Ajuda | Falhou: rotas `autonomia_agent_build`, `autonomia_agent_panel_legacy`, `autonomia_agent_ready` sem artigo. |
| Formatos das ações do Guia | Falhou: `lib/operator_guide/formatos-das-acoes.json` fora de dia. Job `m2-1590228022964eaa82a90b8eaab18707`. |
| Build | Não executado: planner excluiu M2 por `stateful-pinned-local` e M4 por `insufficient disk`. Sem forçar execução após parada. |
| Navegador/galeria F2+F3 | Rodada 38 não executada. Rodada 37 interrompida; não é aceite. |

### Causas e limites da conclusão

1. `b4b_playground_contract_spec.rb:48` espera histórico já sanitizado na chamada de Playground para Copilot; a composição compartilhada sanitiza dentro do Copilot, recebendo histórico bruto nessa fronteira. A expectativa observa a fronteira errada. Não corrigido após a parada.
2. `ai_request_results_spec.rb:111` espera histórico bruto na chamada ao Answerer; a composição compartilhada agora passa o histórico com marcador de dado não confiável. A expectativa anterior não foi atualizada com essa mudança. Não corrigido após a parada.
3. `AgentCreationPage.spec.js:241` espera que Salvar e sair já esteja na lista. O teste usa `router.isReady()`, que aguarda a navegação inicial. O handler de Conte chama diretamente `router.push` para a lista; a hipótese é uma asserção antes da conclusão dessa navegação. Não houve teste adicional para confirmar; não declarar defeito funcional descartado nem comprovado.
4. As explicações do Guia foram atualizadas, mas a cobertura correspondente da Central não foi completada. O catálogo de formatos foi gerado antes das últimas mudanças de backend e a conferência atual exige regeneração oficial; é proibido corrigir arquivos gerados à mão.
5. O lote ultrapassou limites de estilo/complexidade em Ruby; testes funcionais passando não dispensam esses checks. O planner não liberou build na configuração utilizada. Não houve build nem validação visual final para provar a qualidade das novas telas.

Causa de processo: a integração do lote não fechou todas as fronteiras alteradas (expectativas de testes, arquivos gerados, Central e lint) antes da conferência final. A revisão do serializador compartilhado já havia sido corrigida após RCA; isso não torna o conjunto aprovado. Os dois testes novos do caminho assíncrono real → Redis → poll → estado E3/E4 e `writes_external` passaram; as falhas residuais continuam bloqueando a entrega.

Estado de entrega: Issue #1138 permanece aberta/bloqueada para revisão do Rodrigo. Sem novo PR, commit, push, fila, merge, deploy ou produção. PR documental #1115 permanece congelado. Nenhuma migration nova neste bloco. Runtime temporário 37 e portas 59720–59723 encerrados; galeria F1 anteriormente aprovada permanece separada. Helpers de prévia preparados não contam como prévia executada. Retomada deverá tratar os bloqueios acima sem atribuir aprovação visual a um mockup ou a testes isolados.

## Retomada autorizada após parada 38

Rodrigo instruiu: “encontre a causa raiz, resolva e continue”. Autorização para um novo lote corretivo local e validação pertinente, sem autorizar merge/fila/deploy/produção. Não repetir revisão ampla.

RCA de integração: o histórico não confiável foi centralizado corretamente, mas dois mocks continuaram esperando formatos da fronteira antiga; a saída de Conte precisa aguardar a navegação subsequente no teste (não a prontidão inicial); a cobertura de artigos da Central e a regeneração de formatos ficaram fora da etapa posterior às mudanças. RuboCop detectou métodos acumulando validação, criação e persistência; corrigir decompondo responsabilidades existentes, sem dispensas. O build estava sendo planejado no nó local M4 por ser stateful, embora o snapshot/dependências estivessem preparados no M2; usar planejamento explícito `--node m2` para esse snapshot, respeitando recursos.

Ownership retomada: r9_tecnica B3/lint, registrar_decisoes B4b/duas expectativas/lint, r9_produto espera de navegação/Central; root SourcesController/formats/geração/checks/runtime/registro. SourcesController: extraída a cópia efetiva do material para `copy_material!`, mantendo o lock, limite, referência, blob, origem e ingestão. Helpers e build somente em snapshots isolados. Checagem final residual → parar e devolver; não iniciar outro ciclo por conta própria.

## Retomada — resultado final 40 e parada

Causas funcionais anteriores corrigidas; novo lote autorizado validado no snapshot `20261008-071353-532a5b7b-2966013e0b-955329f7`, SHA-256 `2966013e0b20e0c553a67fb2538d7230c2118e34dd0c5a12ed9a3f6fb5a8dd1a`. Réplicas M2/M4 consistentes antes e depois; HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488` preservado. Logs `.codex/preview/check40/`. Todos os subagentes congelaram escritas antes da geração e snapshot. Sem nova revisão ampla.

- Ruby: **658 exemplos, zero falhas**, job `m2-cebad210d63e474a99feef7d7e54b4c5`.
- Vitest: **108 testes em 18 suites, zero falhas**, job `m2-6168c825074f45ef813741b29beec2ea`.
- Traduções: passou, 13 catálogos/20.442 mensagens.
- Guia: passou, 195 fluxos/189 telas/zero sem explicação.
- Central: passou, 184 artigos/189 telas cobertas.
- Formatos: regeneração oficial em cópia derivada do snapshot39; devolução por checksum guardado. Snapshot40 confirmou `[guia:formatos] em dia`.
- Build frontend: **passou**, `vite build --mode production`, 6.858 módulos, 55,28 s; job `m2-33b52509749e4f979061803972a41cac`. Execução isolada `RAILS_ENV=test`/`NODE_ENV=production`, saída em `public/vite-test`; não é deploy nem validação de configuração de produção. Planner explícito M2 resolveu o bloqueio anterior sem forçar M4. Avisos de Browserslist/chunks/import misto permanecem não bloqueantes.
- ESLint: **falhou**, 1 erro/221 avisos. O teste alterado usa retorno implícito no executor da Promise (`AgentCreationPage.spec.js:239`, `no-promise-executor-return`). A espera `router.afterEach` corrigiu o teste funcional, mas a forma da função viola o padrão.
- RuboCop: **falhou**, 7 ocorrências em 20 arquivos. `AgentsController` ainda tem 179 linhas para limite175; extração reduziu229→179 mas não fechou o limite. `SourcesController:98–100`: argumentos da nova extração `copy_material!` desalinhados, 6 apontamentos (ArgumentAlignment/HashAlignment sobre3linhas). Root introduziu esse desalinhamento ao separar a responsabilidade; não é defeito preexistente. Métodos/complexidade B3/B4b e concerns novos restantes passaram no mesmo check, sem suppressions.

RCA residual: a correção de navegação foi validada funcionalmente e formatada, mas não passou pelo ESLint completo antes do congelamento. A decomposição de Ruby foi conferida por sintaxe, mas o tamanho final da classe e alinhamento dos argumentos não foram medidos pelo RuboCop antes do congelamento. Sintaxe/Prettier e testes não substituem esses checks. Restam três pontos concretos, não falhas funcionais comprovadas: forma do executor de Promise; quatro linhas acima do limite da classe; alinhamento de argumentos da cópia de material.

Conforme regra e compromisso da retomada, **parado após a conferência final com erro residual**, sem nova correção nesta execução. Não executar navegador/galeria40 após a parada; helpers preparados no namespace externo do snapshot não contam como execução. Não há prévia real aprovada F2+F3 para entregar. O protótipo foi aberto em Chromium headless isolado com “Todas as telas” e barras de estados; primeiro launcher não recebeu o caminho do cache compartilhado do navegador, corrigido somente no harness de referência, sem alterar produto. Servidor temporário de referência local encerrado. Nenhum runtime40/banco fictício40 foi iniciado.

Artefatos de RCA dos responsáveis: `2026-10-08-agentes-b3-qualidade38-causa-raiz.md`, `2026-10-08-agentes-f2-f3-r38-navegacao-central.md`, `2026-10-08-agentes-b4b-codigo-causa-raiz.md`. Issue1138 atualizada. PR1115 congelado; sem novo PR, commit, push, fila, merge, deploy, produção ou migration nova. Próxima retomada deverá resolver os três pontos residuais e concluir gate visual real; os 766 testes aprovados e build não autorizam release nem comprovam UX visual.

## Correção dos três pontos de lint — concluída, conferência 41

Rodrigo autorizou “pode corrigir e retornar”. Escopo restrito aos três pontos residuais, sem iniciar nova revisão ampla nem prévia/navegador. r9_tecnica compactou a chamada do Publisher em AgentsController, reduzindo179→175 linhas; root alinhou os argumentos de `copy_material!` e retirou retorno implícito do executor de Promise do teste de navegação. Comparação contra snapshot40 confirmou só essas mudanças nos três arquivos de código/teste; sem alteração de argumentos, contratos ou regra de negócio. `git diff --check` passou.

Snapshot `20261008-072349-532a5b7b-0a5b77b12f-badcc634`, SHA-256 `0a5b77b12ff1a20871ebb9be8fc7c265a629ef7ce0d5b4de4a97d60ad8a8da61`; HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`, 372 entradas dirty preservadas. Réplicas M2/M4 consistentes antes/depois. Execução pelo MacCluster no snapshot M2, com ambiente limpo e wrapper de testes Ruby isolados. Logs `.codex/preview/check41/`.

- ESLint da área nova/API: zero erros, 221 avisos de catálogo já presentes. Job `m2-f20db145748947838c746567684cdf36`.
- RuboCop dos dois controllers corrigidos: dois arquivos, zero ocorrências. Job `m2-7e405e0983a647918c4db5a32094f3e2`. Os outros18arquivos passaram na rodada40 e não foram alterados.
- `AgentCreationPage.spec.js`: 5 testes, zero falhas.
- Requests `publisher_spec.rb`, `reusable_sources_spec.rb`, `config_contract_spec.rb`: 58 exemplos, zero falhas. Job `m2-f50d30f7e40446b6ac7db08ed8adb020`.
- Formatos do Guia: o check inicial41 detectou referências de origem desatualizadas, pois compactar a chamada no controller deslocou linhas. Regeneração oficial `bundle exec rails autonomia:guia:formatos` em cópia derivada do snapshot41 e check oficial concluído: `[guia:formatos] em dia`. Não houve edição manual de gerados. Diff estruturado confirmou mudanças apenas em `origem` (referências do código), não contratos. Única saída alterada `formatos-das-acoes.json`, SHA-256 `1941d3daa888854b8b060fa3c989bbfa9d79f103e5581ce887f890f2a796fcfa`; outras quatro saídas permaneceram iguais. Devolução guardada pelo checksum do conteúdo anterior; réplicas originais intactas.

Correção pedida concluída: **63 testes afetados passaram e lint sem erros**. Não repetir766testes/build da rodada40 após mudanças de formatação; histórico40 preservado sem atribuir suas contagens à rodada41. Nenhum novo teste, migration, commit, push ou PR criado. PR1115 continua congelado. Sem fila, merge, deploy, produção ou chamada de IA paga.

Pendente do objetivo maior: prévia real F2+F3 navegável, matriz de telas/cenários e aceite visual do Rodrigo. Não confundir correção do lint com aprovação das telas. Em futura retomada da prévia, gerar snapshot novo que inclua o catálogo devolvido e os registros atuais; helpers preparados para snapshot40 precisam apontar para esse novo conteúdo. Conforme pedido, encerrar esta execução e retornar o resultado.

## Prévia real 42 — execução autorizada em andamento

Rodrigo autorizou “pode seguir” e “continue” após as correções41. Escopo atual: aplicação local F2+F3, testes de jornada/capturas/galeria de cenários, sem publicar PR/merge/deploy/produção. Snapshot novo `20261008-073253-532a5b7b-1db65143d5-a31143e1`, SHA-256 `1db65143d5a137ed7dd4b1f241604d7953f0ce7d4137f38160f68bc9427f4886`, inclui catálogo oficial corrigido. Réplicas M2/M4 conferidas antes e após dependências offline.

Runtime dedicado M2, portas59720–59723 loopback, banco `chat2you_agentes_ia_prd` em cluster PostgreSQL novo externo ao snapshot. Somente dados fictícios dos seeds F1/criação. Provider de respostas/embeddings simulado e rotulado; APIs/jobs/Redis/estado/persistência/publicação reais. IA paga e WhatsApp de produção não são acionados. Matriz48testes prevista (F1+criação4perfis), um worker/retries0/para na primeira falha; extra de reutilizar material em4perfis se matriz passar. Não contar testes previstos como aprovados.

Skill Product Design audit aplicada para evidência visual, comparação e limites; preflight sem contexto salvo. Browser integrado não disponível na tentativa anterior; manter Chromium headless isolado já utilizado e autorizado neste fluxo, sem navegador pessoal. r9_produto captura referências atuais aprovadas; registrar_decisoes prepara galeria; root runtime/matriz/export/inspeção. Helpers permanecem externos ao snapshot e ignorados pelo Git. A galeria não será gerada sem capturas reais; observação humana O1 permanece obrigatória antes de deploy.

### RCA da primeira captura real42 — contraste na Escolha

Native42 executou dois testes: portal passou; primeira captura da Escolha falhou no Axe color-contrast. “COMECE AQUI” usa `text-n-slate-10` sobre `bg-n-background`, cor#80838d/fundo#f7f7f7, contraste3,53:1 para12px, abaixo4,5:1. O contraste da etapa já havia sido corrigido na revisão anterior, mas esse rótulo secundário não foi medido naquela tela. Causa: token de tom intermediário usado para texto pequeno em fundo quase branco, sem conferir contraste efetivo da combinação. Correção mínima: trocar só esse texto para `text-n-slate-11`, padrão de texto secundário da mesma tela, preservando resto da UI/contratos.

Rodada42 não aprovada:1pass/1fail/46nãoexecutados; ferramenta também reportou1errofora dos testes sem detalhe independente além da interrupção (não suprimir nem contar como passado). Material extra não executado. Runtime42 encerrou pelo cleanup do wrapper e réplicas seguiram consistentes. Corrigir após RCA e executar uma conferência final43; erro residual43 exige parar e retornar, sem novo ciclo. Não ampliar a revisão de produto.

## STOP43 — prévia real bloqueada

**Data:** 2026-10-08  
**Snapshot:** `20261008-073655-532a5b7b-f821462254-accd6713`  
**Árvore:** `f821462254dce472ebe36cbe6eaeebe4f4ad01bb45f32c3561be158f6e495d2c`

A verificação nativa 43 terminou com **1 caso aprovado, 1 caso falho e 46 casos não executados**.
O job `m2-972d8f350c50413e9e604e33fe84baf2` terminou com `exit 1`; a verificação antes/depois do
snapshot permaneceu consistente. O contraste baixo no fluxo **Conte** continuou bloqueando a prévia
aprovável mesmo após a correção anterior do `slate-10` para `slate-11`.

O resultado é STOP: a galeria de telas reais não está pronta para aceite. Não houve correção de
produto, nova execução pesada, publicação, merge, push ou deploy neste registro. O lint da prévia
registrou zero erros e 13 avisos, sem transformar isso em aprovação visual.


### Causa e evidência exata do STOP43

A captura real da etapa Conte falhou em dez nós de texto pequeno (12 px) usando `text-n-slate-10`, cor #80838d: rótulo CONTE (3,53:1); aviso de alterar respostas (3,78:1); explicação da primeira versão (3,78:1); quatro valores de O que ele sabe (3,50:1); formatos de arquivo (3,47:1); estado vazio de materiais (3,78:1); explicação de reutilização (3,78:1). O mínimo esperado pelo check era 4,5:1. Causa comum: uso desse tom em texto pequeno sobre fundos claros. A correção42 alterou somente COMECE AQUI na Escolha; sua extensão foi insuficiente para tratar a mesma combinação nos demais componentes. Não corrigido após a conferência final, conforme limite autorizado.

Portal/login passou; captura da Escolha passou nesta execução. Conte bloqueou no estado parcial de respostas. Teste, Ligue, Pronto, perfis celular/escuro e extra de materiais não foram validados nesta rodada. Há ainda a mensagem do runner `1 error was not a part of any test`, sem detalhe independente no log; não tratá-la como aprovação.

Screenshot exato exportado e inspecionado em resolução original: `.codex/preview/check43/conte-falha-43.png`. Serviços próprios encerrados: consulta de sockets M2 confirmou portas59720,59721,59722,59723 fechadas. Nenhuma galeria43 foi gerada/servida. Subagente produto terminou96capturas do protótipo aprovado no M2, que permanecem referências e não evidência de telas reais aprovadas. Sem novo PR, commit, push, fila, merge, deploy, produção ou migration.

## Retomada44 — regra de revisão vigente

Rodrigo esclareceu que falhas de testes, lint e build são validação e não contam como revisão. Elas devem ser corrigidas autonomamente antes de chamar o revisor, com nova validação pertinente.

A cadência normativa desta retomada é: **implementar → revisão 1 → corrigir os achados → revisão 2 pelo mesmo revisor**. Se a revisão 2 ainda reprovar, registrar a causa raiz antes da correção, corrigir a causa e chamar o mesmo revisor para a **revisão 3**. Se a revisão 3 ainda encontrar erro, fazer STOP e retornar ao Rodrigo; não abrir um quarto ciclo.

Esta seção atualiza a regra de processo sem apagar o histórico STOP43 acima. Não declara galeria, telas reais ou jornada aprovadas, não corrige produto e não autoriza novo PR, commit, push, fila, merge, deploy, produção ou migration. A correção do contraste e a validação da jornada seguem dependentes do lote local coordenado pelo root.


### Validação44 e correção do harness

Snapshot44 `20261008-080253-532a5b7b-eb2961812e-0ba7d842`, hash `eb2961812e890ca0019e0a3ecd64d6b941a85415684190798efde30b69ed4f24`, réplicas consistentes antes/depois. Lint da área e filhos materiais: zero erros,57avisos de catálogo. Native44:13pass/1fail/34nãoexecutados, job `m2-92671f654a7a4350acb10464f7198e58`. Jornada completa desktopclaro e cenários F1 passaram; celularclaro interrompeu em um seletor inválido do próprio teste (`getByRole(progressbar)` ausente sem materiais). Não é revisão nem motivo de STOP. Corrigir seletor pela seção real de respostas/materiais.

Inspeção de capturas desktop mostrou também que aguardar só E4 na API capturava Teste ainda pensando; sincronizar captura com resultado/estado do botão na interface, e respostas do Construtor com o resumo exibido. Desativar apenas no runtime local fictício o badge RackMiniProfiler via flag existente DISABLE_MINI_PROFILER; não modificar configuração de produção. Nome fictício humano e captura sem transições de animação para manter evidência fiel. Revisão independente ainda não iniciada (contador0).


## Retomada45–46 — evidência visual, revisão 1 e limite de sessões do harness

A matriz45 no snapshot `20261008-081600-532a5b7b-cd06d71cdc-e0648b13` terminou com 34 casos aprovados, um falho, dois pulados e 11 não executados. O portal no quarto perfil recebeu HTTP409 em `/auth/sign_in`. Causa comprovada no controller Sessions: limite padrão de25tokens ativos. O harness fazia um login novo por teste; acumulou sessões na mesma conta fictícia. Não é autorização para alterar auth do produto. A fixture46 reutiliza o login legítimo por worker/baseURL/conta/papel, e o caso do portal verifica explicitamente HTTP200 do login. Nenhuma configuração/controlador de autenticação foi alterado.

A leitura independente das13capturas desktop claras45 e cinco referências aprovadas contou como revisão1 produto/UX (parecer `revisoes/F2-F3-retomada44-produto-r1.md`). Achados: Error/AxiosError exposto, toast de publicação falha sobrevivendo ao sucesso, confirmação sem canal e texto provisório `canal(is)`. Causas: computed devolvia objeto Error; erro era emitido no toast global sem ciclo de vida da publicação; hidratação lia `name` embora o DTO de canais conectados forneça `inbox_name`. Correção local: mensagem i18n no computed; erro de publicação inline limpo ao retry; leitura da chave oficial `inbox_name`; texto `Canais ocupados ({count})` em en/pt_BR.

Captura03c é complemento do fim da tela Conte, para provar o botão Continuar, emparelhada com03 do topo. Rótulo da galeria46 explicita esse enquadramento. IA/provedor simulados somente no ambiente de dados fictícios; APIs/jobs/estados da aplicação são reais. Snapshot46 e validação em execução; nenhum resultado46 antecipado como aprovado. Mesma revisão de produto receberá revisão2 após as capturas finais. Sem commit/push/PR novo, CI novo, migration, fila, merge, deploy ou produção.


## Validação46 e correção47–48 — recuperação e materiais

Native46:45 aprovados/zero falhos/três pulados na matriz principal (6,4min). Os três pulados repetiriam a mutação de estado da fixture F1; pausa/religação/exclusão executadas no desktop claro. O cenário adicional de cópia de material falhou no primeiro perfil por `aria-required-children`: BuilderKnowledgePanel declarava role=list mas MaterialCard não era listitem. Saída global1; não declarar native46 completo/verde. Corrigido role=listitem na chamada do card, preservando as demais utilizações; ações pequenas de material receberam alvo44px.

Revisão técnica1 encontrou entryError persistente após recuperação em Conte e eco duplicado/bolha fantasma após transporte falho. entryError limpo antes de envio/reenvio/anexo; store remove somente eco local rejeitado, preserva client_message_id para retry e repetição legítima após aceitação. Unit existente ampliado com mutations em estado real, retry/transporte/409 e repetição legítima; Playwright simula primeiro envio falho, usa Tentar de novo e exige zero alertas e uma única mensagem no histórico depois do sucesso. Snapshot47:109JS aprovados; i18n não executado por planner sem nó elegível (M2 thermal unknown; M4 abaixo da reservaSSD), sem forçar exclusão. Snapshot48/final ainda pendentes. Nenhuma falha de teste é contada como revisão2.

## Retomada49 — validação local concluída; produto R2 e galeria pendentes

Rodrigo autorizou a retomada local sem autorizar merge, fila, deploy ou produção. O snapshot49 foi criado e
verificado nas duas réplicas: `20261008-084433-532a5b7b-4fa8870ab2-12cb4cad`, SHA-256
`4fa8870ab2c1a9f932ab874f20b6975f28abf4e8ba91f97c7ba66f583345f3d8`. O HEAD de origem continua
`532a5b7beb56902d2a0168013a3e8b657ba31488`; não houve commit ou push.

### Evidências locais

- Native49: 48 casos no log, 45 aprovados, zero falhos e três pulados. O mesmo log registra quatro extras de
  cópia de material pela API real, com doador preservado e chegada a E4; isso não substitui a revisão visual.
- Vitest: 109 testes aprovados em 18 arquivos (`.codex/preview/check49/js49.log`).
- i18n: 13 catálogos, 20.442 mensagens, chaves e parâmetros en/pt_BR cobertos
  (`.codex/preview/check49/i18n-fork-check49.log`).
- Lint do bloco: zero erros e 57 avisos de chaves de catálogo em `lint-choice49.log`; os avisos não foram
  promovidos a falha.
- As 36 capturas mobile reais, 18 claras e 18 escuras, foram lidas em resolução original. O inventário e a
  inspeção estão em `.codex/preview/check49/mobile-inspection.json`; não houve branco, overflow horizontal,
  texto ilegível ou ação estruturalmente cortada.
- O estado 14 é uma lacuna de evidência: a captura clara mostra `Enviando/Revisando` e a escura mostra
  `Falha ao ler/Revisando`. A captura não prova visualmente o estado final de material copiado, embora o bloco
  permaneça legível.

### Limites do resultado

A revisão técnica R2 está aprovada. A revisão de produto R2 ainda não foi concluída e o PASS do navegador da
galeria ainda está pendente. A resposta API 201/E4 da execução inicial não comprovava que o material estava pronto;
ela não deve ser usada como prova. Os quatro extras só contam porque estão explicitamente registrados no
`native49-verify.log`.

A regra vigente continua: implementar → revisão 1 → corrigir → revisão 2 pelo mesmo revisor; se a revisão 2 reprovar,
registrar a causa raiz antes de corrigir e chamar o mesmo revisor na revisão 3; se a revisão 3 reprovar, fazer STOP
e retornar ao Rodrigo. Não há quarto ciclo.

Issue1138 e este handoff não foram marcados como aprovação final. A galeria, as telas reais e o produto continuam
sem aceite. Sem novo PR, commit, push, fila, merge, deploy, produção ou migration neste registro.

## Retomada50 — evidências locais antes do aceite final (histórico)

O preparo50 passou os checks registrados em `.codex/preview/check50/results.json`: snapshot, dependências,
lint, Vitest, i18n e verificação antes/depois retornaram zero. O snapshot
`20261008-091254-532a5b7b-b457c63ab6-9f631cfe`, SHA-256
`b457c63ab6d08def94e64efb599ef2dc859b12565fafd381378a4b9c70958836`, está consistente nas réplicas M2/M4.
O runtime50 terminou com 48 casos: 45 aprovados, zero falhos e três pulados; os quatro extras de cópia de
material também passaram, com doador preservado e chegada a E4. Evidência: `.codex/preview/check50/native50-verify.log`.
Essa validação local não equivale a aprovação de produto, galeria ou aceite do Rodrigo.

A RCA do bloco49 identificou duas causas de preparação local, sem alteração do produto:
- o fake reviewer com enum vazio tratava a resposta como `needs_resend`, impedindo a prontidão aceita; o helper
  passou a usar o contrato de enumeração explicitamente nomeado;
- o desenvolvimento mantém `config.eager_load=false`, enquanto a produção usa `config.eager_load=true`; o helper
  passou a pré-carregar o Dispatcher real para refletir o carregamento de produção, evitando `ingestion_error` sem
  mudar a configuração de produção.

A nova asserção de readiness exige `source.status='ready'`, `source.review.status='accepted'` e a presença
no DOM de Pronto/Nota92.
Essa prova encontrou contraste 4,1:1 em `bg-teal-3`/texto `teal-11`. A correção local usa `teal-12`; os
casos nativos 07/09 aguardaram o alerta sair da rolagem antes da captura. O runtime50 terminou sem falha de
contraste, incluindo os quatro extras que mostram o badge aceito; naquele momento produto R2 ainda estava pendente. A revisão técnica R2 mantém aprovação no
escopo registrado, incluindo limpeza de erro, eco e ARIA.

A inspeção mobile do check50 leu 36/36 capturas originais, 18 claras e 18 escuras, junto com as 10 referências
mobile do ref42. O estado14 agora mostra Pronto, Nota 92 e confiança geral 92% nos dois temas; os alertas dos
estados07/09 estão inteiros dentro do viewport. Não houve achado visual de branco, overflow horizontal, texto
ilegível ou ação cortada. Evidência detalhada: `.codex/preview/check50/mobile-inspection.json`.
Naquele ponto do registro, a galeria ainda aguardava o PASS do navegador e o produto R2/aceite do Rodrigo. Esse
estado foi superado pela seção Resultado50 abaixo. Issue1138 e o banner do handoff só foram atualizados depois das
evidências finais, preservando este histórico. Sem novo PR, commit, push, fila, merge, deploy, produção ou migration
neste registro.

## Resultado50 — produto R2 e galeria do navegador concluídos; aceite do Rodrigo pendente

O runtime50 terminou com 45 casos aprovados, zero falhos e três pulados; os quatro extras de cópia de material
passaram pela API real, preservando o doador e chegando a E4. O snapshot
`20261008-091254-532a5b7b-b457c63ab6-9f631cfe`, SHA-256
`b457c63ab6d08def94e64efb599ef2dc859b12565fafd381378a4b9c70958836`, foi verificado nas réplicas M2/M4.
A revisão de produto R2 do mesmo revisor terminou sem achados acionáveis em
`docs/agentes-ia-redesign/revisoes/F2-F3-retomada50-produto-r2.md`.

O PASS do navegador da galeria está registrado em `.codex/preview/check50/gallery-verify50.log` e
`.codex/preview/check50/gallery-diagnostic50.log`: HTTP 200/HTML, 68 capturas, 20 comparações, 108 imagens
carregadas, filtros computador/celular claro/escuro em 16/16/18/18 e portal HTTP 200 com autenticação chegando à
Escolha real. O diagnóstico confirma tráfego somente loopback. As duas PNGs de renderização da galeria e os
originais foram lidos pelo responsável visual; as 36 capturas mobile do export50 também estão registradas em
`.codex/preview/check50/mobile-inspection.json`, sem achados visuais. Os estados07/09 mantêm seus alertas inteiros
no viewport e o estado14 mostra Pronto/Nota 92 nos dois temas.

A primeira tentativa da galeria falhou no helper ignorado `build-creation-gallery50.py`, por faltar `;` após uma
atribuição `onclick`, causando `Unexpected identifier filter`. O helper foi corrigido e a galeria foi regenerada;
não houve alteração do produto ou do snapshot. As URLs locais são
`http://127.0.0.1:59720/preview-telas` e `http://127.0.0.1:59720/preview-criacao` enquanto o runtime estiver
ativo.

A criação e a ativação estão prontas para o aceite visual do Rodrigo. Isso não aprova o redesign inteiro, não é
CI verde, não autoriza release e não constitui evidência de produção. A regra de revisão continua implementa →
revisão1 → correção → revisão2; reprovação na revisão2 exige causa raiz e revisão3 pelo mesmo revisor; reprovação
na revisão3 exige STOP e retorno ao Rodrigo, sem quarto ciclo. Sem migration nova, commit, push, PR novo, fila, merge,
deploy ou produção neste registro.

A conferência dos inventários confirmou 68/68 arquivos originais: 32 desktop e 36 mobile. Relatórios em
`.codex/preview/check50/desktop-inspection.json` e `mobile-inspection.json`. O manifesto
`.codex/preview/check50/gallery-inputs.json` vincula as imagens ao snapshot e ao HTML; o SHA-256 do HTML
servido pela URL local coincide com o arquivo lido (`4d59e74cff0cc5bf84f8a44336df1bc7d268d6fab4e4e306ed9eda174bb12397`).
