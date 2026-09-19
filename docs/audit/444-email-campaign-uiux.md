# Issue 444 / PR 468 — Gestão de campanhas: aceite de UI/UX

## Escopo e decisão

Uma única PR de frontend, apresentação internacionalizada e QA, destinada à `main`. A implementação não altera backend, banco, migrações, processamento de campanhas, regras de proteção ou flags operacionais. O merge continua dependendo de aprovação explícita de Rodrigo e dispara blue/green.

A interface atende o cliente do Chat2You: explica resultados e decisões sem identificar a infraestrutura do serviço de envio. A simplificação não transforma aceitação pelo servidor em garantia de chegada à caixa de entrada nem elimina a informação disponível na API.

Base integrada: `4254ef06a81053b7adfea8f151e4df2f9d8ebc40`. As permissões de gestão acrescentadas pela main durante o trabalho foram preservadas. A referência `main` local de outra worktree não substitui essa base remota.

## Matriz dos 14 critérios

| # | Critério | Entrega e evidência | Resultado |
|---|---|---|---|
| 1 | Sem select nativo na tela | Seletores de campanhas, destinatários e caixa usam componentes do Chatwoot. Fonte e navegador verificam ausência de `select`. | PASS |
| 2 | Até cinco opções no filtro principal | Todos, aguardando envio, entrega registrada, requer atenção e descadastro; cinco valores de API, com rótulos localizados. Menu aberto inspecionado e contado no navegador. | PASS |
| 3 | Detalhamento de problemas contextual | Segundo filtro aparece somente em Requer atenção e mantém os parâmetros de busca, paginação e CSV. | PASS |
| 4 | Controles alinhados em desktop | Grid responsivo para busca/filtros/ações; geometria verificada também na largura reduzida pela sidebar. A caixa do formulário de links e os inputs vizinhos medem 40 px. | PASS |
| 5 | Mobile utilizável | Destinatários e cliques por link usam cards com status, identidade, contadores e ações acessíveis, sem exigir rolagem lateral para a informação principal. | PASS |
| 6 | Temporária e permanente distintas | Temporária: âmbar e setas de repetição. Permanente: rubi e círculo com X. Verificação de cor calculada e ícone, incluindo tema escuro. | PASS |
| 7 | Spam distinto de bounce | Escudo de alerta e texto próprio, sem confundir com falha temporária ou permanente. | PASS |
| 8 | Sem tabelas de placeholders | Dados ausentes são omitidos; não são convertidos em métricas zero nem em fileiras de travessões. | PASS |
| 9 | Sem mensagem contraditória de análise | Estado efetivamente pausado não anuncia que os resultados deixaram de impedir envio. Motivo e precedência da restrição são preservados. | PASS |
| 10 | Linguagem independente de infraestrutura | Textos visíveis, detalhes e ajuda contextual são voltados à decisão do usuário. O navegador verifica ausência de nomes da infraestrutura na superfície de cliente. | PASS |
| 11 | Informação diagnóstica preservada | Avaliação atual, motivo original e suas datas ficam recolhidos; resumo misto preserva os dois contadores de evidência no disclosure. | PASS |
| 12 | i18n preservado | 57 módulos, 43 ativos, 263 mensagens/chaves exigidas por módulo e 14.991 compilações/renderizações com `fallback=false`. Nenhuma cópia de texto em inglês usada como substituto de locale. | PASS |
| 13 | RTL preservado | Interface árabe e seus controles mantêm direção RTL; e-mails usam isolamento LTR e identidade completa permanece disponível nos detalhes. | PASS |
| 14 | Revisão visual real | Capturas de desktop, menu aberto, mobile, tema escuro, RTL e disclosure foram inspecionadas. Os problemas de clipping encontrados nas revisões foram corrigidos antes do fechamento. | PASS |

## Implementação e compatibilidade

O painel apresenta primeiro motivo, contadores e ações relevantes; histórico e explicações detalhadas ficam em segundo plano. Os seletores usam `FilterSelect`, `Button`, dropdowns, ícones e tokens existentes. O comportamento de teclado foi adicionado ao componente compartilhado com `keyboardNavigation=false` por padrão e ativado somente nos seletores desta tela. Não foram criados um design system paralelo, dependências novas ou mudanças em lockfiles.

Busca, filtros, limpar, paginação, exportação e refresh por IA preservam o contrato existente. As ações continuam condicionadas às permissões e capabilities atuais; um usuário somente leitura não recebe ações de alteração ou exportação. A distinção entre exclusão local de endereço e proteção real da conta foi mantida.

O ajuste de `vitest.config.ts` processa VueUse/Vuex com o mesmo Vue da aplicação, para testar dropdowns reais sem stubs. Ele não muda a configuração de runtime.

## Revisões adversariais e correções

A revisão inicial identificou quatro P2: seleção por teclado ausente nos dropdowns; afirmação excessiva de entrega; perda da discriminação das evidências; e taxa permanente com nome de falhas gerais. As correções preservaram respectivamente os controles reais, a descrição de aceitação, os dois contadores no disclosure e a classificação permanente junto de seu percentual.

A revisão independente sobre `9a27ea42f023850fe927933ba25aac441021ba4c`, contra a base acima, concluiu `PASS_WITH_NONBLOCKING_RISKS`, sem P0/P1/P2 aberto. As capturas fecharam os achados anteriores de menu não mostrado, destinatários fora da área visível no mobile e ausência de prova RTL.

Foram tratados também os dois pontos finais de apresentação/QA:

- A caixa no formulário de links tinha altura menor. A correção final usa somente utilitários Tailwind locais sobre o botão padrão, mantendo `triggerRef`, posicionamento, teclado e seleção do `FilterSelect`. Uma tentativa intermediária com slot customizado foi descartada após o reviewer apontar perda da referência de posicionamento. O fechamento específico desse ponto recebeu PASS.
- O harness ainda não registrava FloatingVue. Passou a usar o plugin já instalado com as mesmas opções da entrada real do dashboard. O teste faz hover, confere a explicação, verifica ausência de jargão e acompanha a ocultação. A primeira consulta de teste procurava um papel ARIA que essa versão da biblioteca não emite; foi corrigida para o DOM real, sem simular a ajuda nem suprimir warnings. O gate final confirma que a diretiva está registrada em todas as telas.

Os relatórios independentes completos permanecem nos artefatos locais `tmp/email444/closure-review-468.md`, `polish-closure-review.md` e `trigger-preservation-review.md`; este documento consolida decisões e limites para que não dependam apenas da conversa.

## Evidências registradas

| Gate | Resultado registrado |
|---|---|
| Suíte completa de frontend | 5.127 testes em 465 arquivos, sem falhas ou pending, executados localmente e no CI da revisão integrada |
| Frontend focado + teclado, após ajuste final | 434 testes em 11 arquivos, sem falhas ou pending |
| Navegador, após fechamento da altura e tooltip | 212 verificações, zero falhas, 148 PNGs; servidor local encerrado no final |
| Internacionalização | 57 módulos / 14.991 mensagens compiladas e renderizadas, sem fallback |
| Fixtures/helpers do navegador | 11 testes aprovados |
| Build | Bundle Vite real aprovado; não foi substituído por CSS desenhado para a demonstração |
| Lint e formato | Zero erros bloqueantes; Prettier aprovado. ESLint mantém avisos de resolução estática de chaves i18n, explicitamente não apresentados como zero warnings |
| Backend de regressão delimitada no CI | 909 exemplos, zero falhas, um pending preexistente em `Account has_many autonomia_account_links` |
| Contratos Ruby puros no CI | 57 testes / 50.876 asserções, zero falhas, erros ou skips |

O CI integrado de referência `35432094053` aprovou o SHA `9a27ea42`. A publicação que contém este fechamento deve ter seu próprio CI verde antes de ser considerada pronta; o run e SHA finais são registrados na PR #468. CI de um SHA anterior nunca substitui o gate da publicação final.

Logs locais do fechamento: `tmp/email444/closure-focused-final.json`, `closure-browser-verified.log`, `closure-eslint-final.log` e `tmp/email436/visual/results.json`. O CI publica relatórios e PNGs no artifact `email-protection-frontend`; não contém dados de clientes ou credenciais.

## Ambiente e reexecução

Fluxo: Gestão de campanhas → campanha pausada → detalhes recolhidos/expandidos → busca e filtros → paginação/CSV → ações permitidas → mesmo percurso por teclado e em viewport estreita/RTL.

Browser plugin não estava disponível; foi usado o Playwright/Chromium já instalado, em `127.0.0.1:3437`, com componentes e estilos reais, APIs sintéticas e rede externa bloqueada. Foram testados desktop 1280×900, mobile 390×844, largura reduzida pelo espaço da sidebar, temas claro/escuro e idiomas representativos. O harness não usa o backend de produção.

Gates reproduzíveis pelo workflow `.github/workflows/email-protection.yml`: `vitest run` completo com `TZ=UTC` e até dois workers; `node scripts/check-email-protection-i18n.mjs`; ESLint/Prettier dos arquivos selecionados; build Vite em modo test; `node --test tests/qa/email-campaigns/*.test.mjs`; `node tests/qa/email-campaigns/run.mjs`. A infraestrutura de teste e a ausência de credenciais de produção ficam definidas nesse workflow.

## Limites e aprovação

Não houve certificação humana nativa dos 57 idiomas, teste de leitor de tela ou execução de envio real. A jornada de busca longa/teleport do seletor possui cobertura com componentes reais em jsdom; isso não equivale a testar todas as combinações possíveis em navegador. A implementação já existente de limpar filtros pode produzir chamada adicional por watcher; os testes certificam o escopo final correto, não uma garantia inédita de requisição única.

Nenhum acesso de escrita a produção, mudança de flag, merge ou deploy foi realizado nesta tarefa. Após a aprovação explícita, somente a PR #468 deve ser mergeada, produzindo um único blue/green. O smoke pós-deploy deve conferir a tela, permissões, filtros e exportação sem enviar e-mails reais. Rollback é da aplicação; esta PR não introduz dados ou migrações a reverter.
