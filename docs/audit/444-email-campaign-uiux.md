# Issue 444 — Gestão de campanhas: UX e apresentação

## Escopo aprovado

Uma única PR de frontend, i18n, testes de apresentação e QA. Nenhuma alteração no motor de envio, regras de proteção, banco, migrações, integrações ou flags operacionais. O merge não está autorizado; ele aciona blue/green.

A interface deve falar com o cliente do Chat2You, sem identificar infraestrutura do provedor. Busca, filtros, exportação e permissões existentes devem ser preservados.

## Implementação

Resumo de proteção com contadores relevantes e histórico recolhido; remoção de linhas sem dados; cinco escolhas no filtro principal de destinatários; detalhes de problemas em segundo filtro contextual; componentes FilterSelect/Button/Icon e tokens do Chatwoot; distinção visual de falha temporária, permanente e spam; cards mobile para destinatários e cliques.

## Revisão visual preliminar

O reviewer inicial identificou clipping na tabela de cliques mobile. A lista passou a renderizar cards com URL e os dois contadores; o harness ganhou prova de geometria e captura específica. Também foram aproximada a ajuda contextual do cabeçalho e acrescentadas capturas dos dropdowns abertos. O gate atual do navegador registra 186 verificações sem falhas e 134 capturas, mas será repetido após integração com main.

## Atualização de base

A implementação partiu do merge 2b1fe44b22. A main avançou em outras entregas e adicionou useCanManage às ações de campanha. O rebase preservou essas permissões e os testes correspondentes; não é permitido trocar arquivos completos por versões anteriores.

## Validação final

Pendente neste checkpoint. Os logs locais anteriores e o CI de versões anteriores não substituem os gates do HEAD final. Registrar aqui resultados exatos, limitações, review e matriz dos 14 aceites antes de entregar a PR como pronta.

## Correções do review adversarial

O review sobre 562a0ed8be identificou quatro P2: seleção por teclado ausente nos dropdowns; afirmação excessiva de entrega; perda de detalhamento por evidência; e taxa permanente com rótulo de falhas gerais. Todos receberam correções com testes: opt-in `keyboardNavigation` usando os componentes existentes; descrição precisa de aceitação pelo servidor; disclosure dos dois contadores originais; percentual junto à classificação permanente, sem nomes da infraestrutura.

O opt-in limita a mudança de comportamento do FilterSelect aos três seletores da gestão de campanhas. A configuração Vitest alinha VueUse/Vuex à instância Vue da aplicação, para executar componentes reais sem stubs, corrigindo duplicação local de Vue em testes. Nenhum lockfile, dependência instalada ou configuração de runtime mudou.

Primeiro gate integrado depois do rebase e dessas correções: **434 testes focados aprovados** (14 aceites e teclado incluídos), sem falhas/pending. Um teste de visibilidade precisou de `attachTo: document.body` para que jsdom invalide corretamente o estilo dos ancestrais; manteve-se a asserção de abrir/fechar e o gate de navegador. Full suite/build/browser/CI finais ainda serão registrados abaixo. Browser plugin não está listado nesta sessão; a validação usa o Playwright/Chromium já instalado.
