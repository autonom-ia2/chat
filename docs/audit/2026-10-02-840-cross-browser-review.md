# QA de Firefox e Safari — PR #840

Data: 02/10/2026. SHA testado: `9b60773a7cdba194f4bcd8323bb4fa1117753b25`. Issue #839. Testes na worktree original `/Users/rodrigosilva/dev/worktrees/chat2you/839-kanban-zoom`, sem editar o produto ou os roteiros versionados. O PR em `autonom-ia2/chat` continua aberto no SHA acima na consulta explícita desta execução.

## Ambiente e limites

Aplicação Vue/Rails e API CRM reais em loopback. Banco sintético existente `chat2you_839_dev`, Redis próprio em 6839, Rails em 3839 e Vite inicialmente em 35839. Sem produção, dados de clientes, merge, deploy, mensagens ou migrations. Seed existente reutilizado; reset restrito às etapas dos cards sintéticos.

Firefox do Playwright iniciou com versão 148.0.2, sem usar navegador pessoal. WebKit é o motor empacotado do Playwright; não equivale ao Safari instalado no Mac. Safari real 27.0 foi testado por safaridriver em uma janela de automação isolada, após liberação temporária.

## Firefox

Matriz principal contra assets de produção com sessão sintética já autenticada: **29 grupos aprovados; zero erros de execução; processo encerrado com código 0**.

Cobertura: 70/80/87/90/100/110/117/120/130%, presets, limites, geometria estável da interface externa, escala de cards/colunas, rolagem horizontal/vertical, arraste entre etapas com HTTP 200 e destino persistido após reload, ausência de novas consultas CRM ao ajustar zoom, escolha exata ao recarregar/trocar funil/conta, Lista/Calendário, teclado/Escape/foco/clique externo e larguras 1366/1024/390. O roteiro não executa emulação de toque em Firefox.

Matriz complementar em Firefox contra Vite: **29 grupos funcionais aprovados**, incluindo ordenação automática, arrastar e retornar sem abrir o card, drawers sem escala, arraste à última etapa com rolagem de borda, busca e preferência sobrevivendo ao reinício do processo de navegador. Essa execução terminou com código 1 no assert global de ausência de erros devido ao erro de login descrito abaixo. Não é apresentada como suíte integralmente verde.

## Achado de login separado do zoom

O login por formulário dispara import assíncrono de `DashboardAudioNotificationHelper`; o redirecionamento cancela requisições do import no Firefox (`NS_BINDING_ABORTED`) e gera pageerror. Reproduzido em roteiro que só faz login e não abre o Kanban. Import isolado do mesmo módulo sem redirecionamento passou. Os arquivos do login e do helper não são alterados pelo PR.

O erro apareceu tanto com Vite quanto com assets de produção. Portanto, não foi atribuído somente ao modo de desenvolvimento. Não se verificou uma baseline executada de main nem produção: o fato de os arquivos estarem inalterados não substitui essa comparação para estabelecer quando o problema começou.

Para separar as verificações, foi reutilizada a sessão sintética previamente salva em `.codex/839/auth.json`. Nenhum erro foi filtrado ou ignorado no assert final. A matriz principal autenticada teve zero pageerrors; o achado no login continua registrado e não foi corrigido nesta tarefa.

## Safari real

**25 grupos aprovados; nenhuma falha funcional na rodada final; processo encerrado com código 0.** Frontend compilado em modo produção, Rails/API local e fixtures reais sintéticos.

Cobertura: nove percentuais, geometria fixa da interface externa, escala exata das colunas, dois eixos de rolagem, arraste entre etapas e destino confirmado em um documento novo após reload; arraste até a última etapa com rolagem de borda em 70/100/130%; limites desabilitados em 70/130; 87% após recarga; Lista/Calendário sem controle de zoom e preferência preservada ao retornar.

O roteiro usa WebDriver W3C, cliques e ações nativas de ponteiro. A verificação de persistência espera um documento novo e o card na etapa de destino, não somente o DOM anterior ainda visível durante uma navegação. Foram adicionados um marcador de documento, espera de pintura e seleção explícita da única janela de automação após falhas iniciais de temporização/controle de janela. As tentativas anteriores com falha continuam nos logs; só a rodada final foi aceita.

Esta cobertura é de Safari desktop no Mac. Não inclui iOS, teste de toque, diff visual pixel a pixel ou observação global de pageerrors equivalente ao Playwright. Não se declara zero erros JavaScript globais no Safari.

A criação de sessão estava inicialmente bloqueada porque `Allow remote automation` estava desativada. Rodrigo autorizou liberação temporária; o Mac exigiu confirmação local e, após ação do usuário, a opção ficou habilitada. Não foi obtida/entrada senha do Mac pelo agente.

Antes dos testes, foram restauradas opções extras que haviam sido liberadas, pois não eram necessárias: restrições de arquivos locais/cross-origin, JavaScript de Eventos Apple e JavaScript na barra de busca permaneceram no estado original restrito. Após a rodada final, a interface confirmou **automação remota desativada (Value 0)** e **exibição de recursos de desenvolvedor desativada (Value 0)**. Não foram alteradas outras preferências pessoais.

## WebKit complementar

Matriz principal autenticada com assets de produção: **29 grupos aprovados; zero pageerrors; código 0**. Mesma matriz funcional principal de Firefox. A rodada inicial que incluiu login por formulário teve 28 grupos funcionais aprovados e um erro de import de módulo; não foi considerada integralmente verde. WebKit complementa a evidência e permanece separado do Safari real.

## Rastreabilidade

Logs e relatórios privados sob `.codex/839` da worktree original:

- `firefox-retest-20261002.log`, `retest-firefox-20261002/report.json` e `firefox-interactions-20261002/report.json`: resultados com login por formulário.
- `firefox-login-diagnostic.log`: reprodução isolada do cancelamento de import durante login.
- `firefox-production-assets.log`: reprodução do mesmo erro com frontend compilado.
- `firefox-authenticated-assets.log` e `authenticated-assets-firefox-20261002/report.json`: matriz principal verde, assets de produção, sessão sintética preexistente.
- `webkit-authenticated-assets.log` e `authenticated-assets-webkit-20261002/report.json`: matriz complementar verde em WebKit com assets de produção.
- `safari-real-acceptance-20261002.log` e `safari-real-20261002/report.json`: 25 grupos verdes no Safari real; screenshots por percentual na mesma pasta.
- `safari-real-20261002.log`, `safari-real-final-20261002.log` e `safari-real-diagnostic-20261002.log`: tentativas iniciais com falhas de roteiro/controle da janela, não aceitas.
- `safari-retest.mjs`: roteiro privado de WebDriver para a sessão nativa, sem alterações no produto.
- `build-cross-browser-20261002.log`: build do commit atual aprovado, 6.639 módulos transformados, aproximadamente 1m50s; avisos de tamanho de chunks, sem falha.
- `cross-browser-retest.mjs`, `production-assets-retest.mjs`, `authenticated-assets-retest.mjs` e `firefox-interactions.mjs`: cópias locais dos roteiros, com import absoluto, espera de estabilização pós-login, seleção de motor, diretórios próprios de evidência e estado de autenticação sintético quando indicado. Não modificam asserts para esconder erros.

Não publicar fixture, auth, env, perfis ou logs Rails. Este relatório sanitizado está salvo somente na worktree de revisão e não foi commitado/publicado.

Encerramento: etapas dos fixtures sintéticos restauradas pelo reset autorizado; processos Rails, Vite, Redis e safaridriver iniciados nesta execução encerrados. As sessões de navegadores foram fechadas pelos roteiros. Os assets locais e as evidências privadas foram preservados.

## Veredito

O zoom do Kanban passou nas matrizes finais de Firefox, Safari real e WebKit, com os limites de cobertura descritos acima. Não foi encontrado defeito bloqueante do zoom nessas execuções. O fluxo de login tem um erro separado observado em Firefox, registrado sem atribuição indevida ao PR e sem correção nesta tarefa. Aprovação funcional desta feature não equivale a ausência de erros em toda a plataforma.
