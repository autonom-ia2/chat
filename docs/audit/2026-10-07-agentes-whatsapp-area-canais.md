# Agentes de IA — conexão de WhatsApp permanece em Canais

## Decisão registrada

Em 07/10/2026, Rodrigo revisou D7: a área **Agentes de IA não cadastra nem conecta WhatsApp**. A conexão continua na área central de Canais/Caixas de entrada. Dentro de Agentes, a pessoa escolhe somente canais já conectados e elegíveis para associar ao agente e confirma essa escolha.

Quando não houver canal disponível, o agente continua salvo. A tela orienta a pessoa e oferece o atalho para `settings_inbox_new` somente quando a permissão da conta permitir. Agentes não pedem número, exibem QR ou token, fazem polling de conexão, criam caixa ou prometem retornar por uma origem `from` própria.

Esta decisão substitui o contrato anterior que motivou o achado `F0-FINAL-01`. O achado antigo continua preservado como histórico da revisão feita sob aquele contrato; ele deixa de exigir correção porque Rodrigo removeu o fluxo de conexão de Agentes. Isso não é uma aprovação retroativa da revisão antiga.

## Prova da área central existente

O destino do atalho foi conferido no código local:

- `app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js:18-35` declara a lista `settings_inbox_list` em `accounts/:accountId/settings/inboxes` e suas permissões de visualização;
- `app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js:53-63` declara `settings_inbox_new` em `accounts/:accountId/settings/inboxes/new`, com `administrator` ou `inbox_manage`;
- `app/javascript/dashboard/routes/dashboard/settings/inbox/Index.vue:114-117` usa `router-link` para `settings_inbox_new` no botão existente de nova caixa;
- `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue:25-38` lista as opções de WhatsApp/WhatsApp API no fluxo central.

`PanelChannels`/`channels` do painel de Agentes continua servindo para ler e associar caixas existentes. Ele não é o cadastro central e não é o destino do atalho de conexão.

## Fontes normativas ajustadas

O PRD foi alinhado em D7, §3, §6.2.4, §6.3, §6.4, BE-10/BE-13, §7.2, §8, §11, Apêndice A e §15.1e. As fontes agora registram que:

- não há rota, endpoint, tela, QR ou migração de conexão dentro de Agentes;
- Ligue e Onde atende exibem apenas canais existentes, ocupação, elegibilidade e associação;
- a ausência de canal preserva o agente e orienta para Canais/`settings_inbox_new`;
- `inviteConnection` e o fluxo de criação permanecem fora do kit novo de Agentes.

O mapeamento F0 foi alinhado com a mesma fronteira: não há linha de rota `autonomia_agents_connect_whatsapp`, nem contrato de `from`/QR; a matriz passou de 14 para 13 famílias, e o atalho central aparece apenas como saída de ausência de canal. A matriz continua em DRAFT e não autoriza implementação, merge ou deploy.

## Protótipo

As fontes em `docs/agentes-ia-redesign/mockup/src` foram alinhadas:

- a entrada `conectar` foi retirada do `MAP` e de `ROUTES`;
- `viewConectar`, seus estados de número/QR/código e seus handlers foram removidos;
- Ligue e Onde atende mostram “Abrir Canais” apontando para `/app/accounts/16/settings/inboxes/new` com a identificação `settings_inbox_new`, ou orientação para quem administra a conta;
- mensagens de ausência e falha passaram a descrever associação/abertura de Canais, sem simular conexão dentro de Agentes.

`docs/agentes-ia-redesign/mockup/jornada.html` ainda precisa ser regenerado pelo `mockup/build.sh`. Não foi gerado neste bloco, e nenhuma tela visual real foi declarada aprovada.

## Aceite e limites

O aceite de telas reais continua pendente e é apresentado uma tela por vez, começando pela lista. A jornada e seus cenários devem mostrar a orientação/atalho para Canais no lugar do antigo grupo de QR. O mockup é referência visual; a aprovação depende da implementação real em ambiente local isolado, dos quatro tamanhos/temas e dos cenários do aceite.

Este registro foi feito por inspeção estática local. Não houve execução de build, testes, navegador, serviço, banco, produção, commit, push, merge, fila ou deploy. Não há migration nesta alteração documental/prototípica.
