# Checagem específica pós-D7 — contrato do F0

**Resultado: STOP — há três bloqueios concretos no desenho.**

**Alvo:** `docs/agentes-ia-redesign/design/F0-mapeamento.md`, SHA-256
`9c878aff38937afb191f6255ac8a14e3d509096685ccdc7d256ccacaa152613d`.

**Escopo:** leitura estática do F0, do PRD e das entradas/consumidores reais de rota e das quatro peças
do D9. Não executei código, testes, build, navegador, banco ou serviço; não revisei novamente a checagem
antiga do F0 e não alterei o desenho nem o produto.

## Bloqueios

### F0-D7-01 — o legado `InviteConnectionPage` não tem disposição de transição

- **Prova:** o F0 declara “nenhuma rota de conexão em Agentes” e o atalho central
  (`F0-mapeamento.md:128-160`), mas não classifica nem remove/encaminha o fluxo já existente.
  O código ainda importa `InviteConnectionPage` e expõe
  `autonomia_invite_connection` em `app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js:19,107-112`.
  O fluxo continua alcançável pelo menu (`app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue:89-96`),
  pelo registro do Guia (`app/javascript/dashboard/helper/guideRouteRegistry.js:35`), pelo retorno de SSO
  (`app/services/autonomia/sso/provisioner.rb:103-105,127-142`) e pelo recurso Rails
  (`config/routes.rb:454-457`).
- **Causa:** D7/CA-GERAL-12 proíbem InviteConnectionPage, QR, criação e `from` no fluxo de Agentes, enquanto
  o mapa do F0 só define as entradas novas e a rota de painel legado. Uma implementação pode cumprir a tabela
  nova e deixar o menu, o Guia ou o SSO entregarem a tela antiga de conexão.
- **Efeito:** fica indeterminado se o fluxo existente é uma superfície externa preservada, se deve ser retirado
  da área de Agentes ou se deve encaminhar para `settings_inbox_new`; em dois desses caminhos a jornada ainda
  oferece conexão/QR fora da área central de Canais, contrariando D7.
- **Correção mínima:** registrar no F0 uma disposição única para a rota e cada chamador existente: ou declarar
  formalmente o legado fora de Agentes, sem link/entrada do redesign e com teste de não-regressão, ou encaminhar/
  retirar a superfície para o fluxo central `settings_inbox_new`. Enumerar também o tratamento do redirect de SSO,
  do menu e das fontes do Guia. O contrato novo deve continuar sem rota, QR, token, criação de caixa e `from` em
  Agentes; não basta declarar apenas a ausência de rotas novas.

### F0-ROUTE-02 — E2m recebe instruções incompatíveis sobre BE-05

- **Prova:** `F0-mapeamento.md:153-154` exige que E2m desvie antes de BE-05 e nunca chame `build_thread`,
  mas `:155` exige hidratação obrigatória por BE-05 antes de montar `PanelTune`; `:180` repete que o leitor deve
  ocorrer antes de qualquer fallback legado. A matriz de specs em `:160` simultaneamente pede E2m antes de BE-05
  e cobre o `422 manual_mode`.
- **Causa:** E2m é explicitamente manual sem instrução (`PRD.md:464,583` e `design/B2.md:152`), enquanto
  BE-05 só retoma modo guiado e devolve `422 manual_mode` para manual (`PRD.md:518`). A exceção de rota foi
  adicionada, mas o requisito geral de hidratação não foi separado por estado.
- **Efeito:** o implementador não consegue definir uma única entrada: seguir a hidratação obrigatória sempre
  recusa E2m; seguir a exceção monta `PanelTune` sem o leitor que o F0 declara obrigatório. A retomada manual
  fica bloqueada ou pode criar um fallback incompatível.
- **Correção mínima:** separar explicitamente os contratos. E2m deve ramificar antes de BE-05 e ir ao painel
  legado de Ajustes usando apenas o estado manual escopado já disponível, sem `build_thread`; E1–E4 guiados usam
  BE-05 antes do fallback e mantêm 401/404/ausência. A matriz deve ter casos distintos para E2m e para guided,
  sem esperar `422 manual_mode` no caminho que já foi definido como exceção.

### F0-D9-01 — o contrato do foco comum se contradiz dentro do próprio mapa

- **Prova:** na tabela D9, `F0-mapeamento.md:47-52` diz que `useModalFocus` preserva a API/exports atuais e
  inclui foco inicial, Escape, retorno ao gatilho e diálogo. O lifecycle em `:67-78`, porém, diz que o
  `SidePanel` é o dono dessas responsabilidades e que o composable terá apenas `activate/deactivate` para
  Tab/Shift+Tab, sem `close`, foco inicial ou restauração. A regra de não mudar props/exports atuais em `:75`
  também não define um adaptador para essa quebra.
- **Prova no código:** a implementação atual de
  `app/javascript/dashboard/components-next/CampaignJourney/useModalFocus.js:39-64` recebe
  `{ container, initial, onClose }`, captura/restaura o gatilho e trata Escape; `AudienceSidePanel.vue:93-97`
  chama exatamente essa API, enquanto `components-next/side-panel/SidePanel.vue:47-89` já controla abertura,
  Escape e restauração.
- **Causa:** “contrato preservado” mistura comportamento observável com ownership interna, sem declarar o
  contrato de migração da AudienceSidePanel.
- **Efeito:** a extração pode manter dois listeners e dois donos de Escape/foco, ou remover `onClose`/`initial`
  sem uma ponte para o consumidor atual. Isso quebra o D9 antes de F1 e pode causar fechamento duplicado ou foco
  devolvido duas vezes.
- **Correção mínima:** distinguir no mapa o baseline observado do contrato alvo. Fixar a API alvo
  (`activate/deactivate`, sem mover foco) e o adaptador/ordem de montagem da AudienceSidePanel dentro do
  `SidePanel`, ou documentar uma ponte temporária com remoção prevista. Declarar quais comportamentos observáveis
  permanecem e que somente o SidePanel pode abrir/fechar, tratar Escape, focar inicialmente e restaurar o gatilho.

## Pontos conferidos sem achado adicional

- **D9 etapas:** o mapa define adaptador de Campanhas com três itens, AgentSteps com quatro itens e Pronto fora
  da barra (`F0-mapeamento.md:49,54,81-93`); não há regressão normativa de Campanhas nesse ponto.
- **D4:** o inventário fixa 18 ocorrências em 12 caminhos do dashboard e nomeia a exceção pública separada
  (`:95-116`); a troca para `n-navy` está descrita como gate de implementação.
- **i18n:** o F0 exige catálogo fork em en/pt_BR, `AGENTS.V2.*` e `toLocaleTag`, além de listar os consumidores
  da migração (`:40-41,56-65`); não tratei a ausência atual do código novo como falha de desenho.
- **Guia/Central:** as fontes, comandos e regra de não editar os gerados estão explicitados (`:236-247`).
- **Acessibilidade e telas reais:** loopback, bloqueio de host externo, autenticação local e `@axe-core/playwright`
  estão definidos como pré-requisitos (`:190-212,257`); a dependência ainda ausente é um gate futuro declarado,
  não um motivo adicional desta checagem documental.

## Conclusão

O F0 continua **bloqueado** para implementação até resolver os três contratos acima em uma correção única e
submetê-la à checagem limitada prevista. Esta checagem não aprova o desenho, as telas, o protótipo ou qualquer
release.

## Validação desta revisão

- F0 relido no SHA informado; referências normativas e de código conferidas com `nl`/busca textual.
- Nenhuma edição em `F0-mapeamento.md`, produto ou fontes do protótipo.
- Nenhum teste, build, navegador, banco, serviço, commit, push, PR, merge ou deploy executado.
