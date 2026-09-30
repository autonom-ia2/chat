# Campanhas implementadas — capturas da aplicação completa

Issue #800, PR #801. As capturas em `full-application/` são feitas no navegador da aplicação Rails/Vue completa, executada localmente. Menu, marca, componentes, rotas e APIs são os reais do produto; os registros são sintéticos da conta local **362 — Hub2You QA**. Idioma: português brasileiro. Não são capturas de produção, nem da conta 16.

A marca foi conferida em leitura na conta 16: logo `/brand-assets/hub2you-icon.png` e fundo da barra lateral `#0b1e3f`. O ambiente local usa esse mesmo ativo e o componente oficial de navegação. Itens do menu seguem as configurações disponíveis no ambiente; o Guia não está habilitado localmente porque depende de configuração de provedor.

| Tela | Captura da aplicação completa |
|---|---|
| Campanhas, resumo, filtros e Disparar | [Desktop](full-application/01-campanhas.jpg) |
| Editor com modelo aplicado e propriedades | [Desktop](full-application/02-editor.jpg) |
| Biblioteca com os 14 designs | [Desktop](full-application/03-modelos.jpg) |
| Revisão de mensagem, remetente e destinatários | [Desktop](full-application/04-revisao.jpg) |
| Confirmação final aberta e cancelada | [Desktop](full-application/09-confirmacao.jpg) |
| Público, exclusões e envio/agendamento | [Desktop](full-application/10-publico-e-agendamento.jpg) |
| Revisão com destinatários ausentes | [Desktop](full-application/05-pendencia.jpg) |
| Lista no celular | [390 px](full-application/06-campanhas-mobile.jpg), [ações após rolagem](full-application/14-campanhas-mobile-acoes.jpg) |
| Lista com colunas alinhadas em telas menores | [1280 px](full-application/11-campanhas-1280.jpg), [1024 px](full-application/12-campanhas-1024.jpg), [768 px](full-application/13-campanhas-tablet.jpg) |
| Biblioteca no celular | [390 px](full-application/07-modelos-mobile.jpg) |
| Biblioteca no tablet | [768 px](full-application/08-modelos-tablet.jpg) |

Desktop de QA: 1440 × 900 px; celular: 390 × 844 px; tablet: 768 × 900 px. Os painéis rolam verticalmente. As abas da lista permitem rolagem horizontal no celular. JPEGs foram capturados diretamente pelo navegador, sem edição de marca, cores ou conteúdo. Os modelos mantêm seus textos, marcas e links ilustrativos originais; precisam ser adaptados ao destinatário antes de um envio real.

## Integração verificada

- Navegação da lista à biblioteca, 14 modelos globais, prévia Computador/Celular e retorno à campanha.
- Aplicação de um modelo pronto pelo botão oficial, salvamento real na API local, assunto/prévia persistidos e seleção de bloco no GrapesJS com propriedades ativas.
- Revisão atualizada pela API local: 3 aptos, 1 protegido por hard bounce e prontidão positiva, com provedor saudável sintético. A confirmação final foi aberta e cancelada; nenhum envio executado.
- Modelo próprio salvo pela UI na conta de QA e confirmado na aba Meus modelos. Lista mostra 4 destinatários totais após atualizar os contadores pelo método oficial local.
- Lista e biblioteca com documento de 390 px no celular; biblioteca com documento de 768 px no tablet, sem expansão horizontal do documento.
- A integração encontrou um erro real com o código `pt_BR` em busca/datas/números. Corrigido usando os formatadores compartilhados que normalizam o idioma para o navegador; testes cobrem `pt_BR` e `zh_CN`.

## QA e limite da evidência

O agente `/root/qa_800` aprovou a aplicação local após conferir as dez capturas, a lista com quatro destinatários e os fluxos de revisão, confirmação cancelada e agendamento. A rodada frontend atual passou com 486 testes de frontend em 16 arquivos, zero falhas, após os últimos ajustes de remetente e contagens. Lint cumulativo do CI passou com zero bloqueios; Prettier e build também passaram. Os 12 exemplos Ruby corrigidos passaram em banco local novo `email800_ci`, sem depender de seed anterior, e foram repetidos pelo QA no parecer final. O CI remoto completo precisa passar no HEAD final antes de publicar.

A rodada inicial de 159 exemplos Ruby foi em ambiente previamente populado e não comprovava independência de fixtures. O CI mais amplo encontrou oito falhas de contrato/fixture, corrigidas nos specs; seu resultado final deve ser consultado no PR.

As capturas antigas em `previews/` foram feitas no harness `tests/qa/email-workspace/`, com shell e API sintéticos. Permanecem somente como evidência isolada histórica e foram substituídas pelas capturas acima para a aceitação visual.

Nenhum deploy, seed ou banco de produção foi alterado. Não há prova de entrega real de e-mail nesta rodada. Plano: `docs/campaigns/email-workspace-release-800.md`.

## Correção do alinhamento — 30/09/2026

A lista usava linhas flexíveis independentes: uma campanha agendada, com menos botões, deslocava destinatários e situação em 38,90 px em relação aos rascunhos. As linhas agora compartilham as mesmas larguras de colunas no desktop; em telas menores, os blocos continuam empilhados. O resumo superior também usa colunas com títulos alinhados pelo topo. Handlers, condições de ações e permissões foram preservados.

As capturas da lista foram atualizadas com o build `dashboard-Bx2hXWX9.js`. O relatório [alignment.json](full-application/alignment.json) registra posições reais antes/depois: mesmas posições nas três linhas em 1440 e 1280 px, títulos do resumo no mesmo eixo em desktop e documento sem expansão horizontal em 1440, 1280, 1024, 768 e 390 px. A captura adicional no celular mostra as ações após rolagem.

Validação direcionada desta correção: 3 testes da lista aprovados, zero falhas; lint do arquivo com zero bloqueios, Prettier, build e diff check aprovados. Os checks remotos anteriores passaram no HEAD `4b190153de` (6891 testes frontend, 1063 exemplos Ruby, zero falhas e dois casos Ruby em quarentena preexistente). A correção de alinhamento precisa de checks no seu próprio HEAD antes da publicação. Nenhum envio, banco de produção, merge ou deploy nesta rodada.

Parecer independente final `/root/qa_800`: **alinhamento aprovado** nas cinco larguras. Capturas de desktop e celular e relatório DOM conferidos; nenhum bloqueador visual encontrado. Fluxos e permissões preservados. CI do novo HEAD e revisão de Rodrigo permanecem como etapas anteriores a merge/deploy.
