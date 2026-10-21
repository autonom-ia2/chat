# #2054 — Conectar a conta de anúncios a partir do painel sem login (handoff 21/10/2026)

## Pedido do Rodrigo

O painel "Anúncios sem login" (#1960) não tem entrada para o módulo de conexão da conta de anúncios, que a conta 18
usa. Ele quer a conta 6 (Onze Onze) com o mesmo acesso da 18. A jornada deve ser tão simples que um usuário leigo
conecte sozinho, com design premium. O protótipo clicável numa tela real precisa da aprovação dele antes de o código
ser fechado.

Decisões dele nesta sessão:

- O caminho é **"Entrar com o Facebook"** (Login do Facebook para Empresas, já configurado em produção), e o cliente
  entra como **testador do app**. O app pode ter até 500 testadores com portfólio verificado, e foi assim que o
  Instagram foi testado.
- O compartilhamento como parceiro (BM 1455428945005668, "Autonom.ia") fica como segundo caminho. A mensagem pronta
  "outra pessoa cuida dos meus anúncios" é para agências.
- Rodrigo **não** tem acesso ao portfólio da Onze Onze: quem conecta é o cliente.

## Estado

Branch `feat/2054-conectar-anuncios`, em trabalho (WIP). Não há PR ainda; abrir só depois de o protótipo ser aprovado.

Feito no código:

- `Panel::Report` separa `ads` (levam ao WhatsApp: tiveram conversa pelo clique ou `conversations_started` da Meta)
  de `other_ads` (gasto, cliques e impressões). O gasto, o custo por conversa e o custo por venda saem só dos que
  levam ao WhatsApp. Novo campo `totals.other_spend`.
- `SemLogin.whatsapp_panel?` passa a valer sempre que não há conexão ativa com conta de anúncios. Uma conexão no meio
  do caminho (`choosing`) ou caída (`broken`) mantém o painel do WhatsApp com um aviso (`connection_state` e
  `connection_mode` no payload).
- Histórico que não encolhe ao conectar:
  - o `Linker` aceita o toque legado em `campaign`;
  - o `LinksBackfillJob` cobre 37 meses (`Period::MAX_MONTHS`);
  - o `Setup#save!` dispara o `LinksBackfillJob` na primeira conexão (em `start_loads`).
- FE:
  - cartão "Investimento — Ver quanto gastei" no caminho do painel sem login;
  - bloco "Outros anúncios";
  - `semLogin/ConectarAnuncios.vue` (uma ação por tela): Facebook primeiro, depois a mensagem para outra pessoa e o
    compartilhamento passo a passo, com desenho da tela da Meta em `MetaTelaGuia.vue`; nas telas de conferir, escolher
    e conectar, um sucesso leva de volta ao painel;
  - `MetaAdsPage`: com a flag `anuncios_sem_login`, avisar as vendas à Meta (passo 4) é opcional.
- i18n em en e pt_BR (`SEM_LOGIN.CONNECT`, `SEM_LOGIN.PENDING`, `PANEL.CONNECT_SPEND`, `PANEL.OTHER_ADS`).
- ESLint sem erro; o `--fix` só quebrou linhas no `MetaAdsPanel`, e isso foi conferido. Rubocop: 3 apontamentos
  corrigidos, sem nova rodada depois da correção.

## Protótipo no M2

- Snapshot: `/Users/Shared/maccluster-workspaces/chat2you/20261021-2054-conectar/src`
- Demo: `/Users/Shared/maccluster-demo-2054`, com `env.sh`, `subir.sh`, `seed.rb`, `fotos/`, chaves de criptografia
  só da demo e `meta_modo`.
- Rails na porta 3981, Vite na 3983, banco `chatwoot_demo_2054`, Redis db 14. Seed feito: conta 1 "Corretora
  Exemplo", 370 conversas de 6 anúncios.
- Simulação, só no snapshot e **nunca no commit**:
  - `config/initializers/zz_demo_2054.rb` faz o papel da Meta (login, contas, conexão e gasto de 120 dias com 3
    "outros anúncios");
  - `useMetaAdsFacebookLogin.js` fica no lugar da janela do Facebook.
  - Os originais estão no scratchpad da sessão, em `demo2054/`.
- `meta_modo` aceita: `uma` (padrão), `duas`, `nada`, `aos_poucos` e `recusa`.
- `subir.sh` foi disparado às 14h56 (hora local). Falta conferir se o painel subiu: `curl localhost:3981/app/login`
  no M2 e o `rails.log`.
- Túnel para o Rodrigo: `ssh -f -N -L 3981:127.0.0.1:3981 -L '3983:[::1]:3983' m2`.

## QA do protótipo (21/10, à tarde) — feito

Jornada inteira percorrida no Chrome: o cartão "Ver quanto gastei" leva a "Entrar com o Facebook" (simulado), depois
a "Achamos sua conta" e "Conectar". A tela "Pronto" leva ao painel com gasto. O histórico se manteve (142 conversas e
8 vendas, antes e depois) e o painel separa R$ 3.490 (WhatsApp) de R$ 1.494 (outros).

Também conferidos:
- os casos de duas contas (com o selo "Mais usada"), recusa do Facebook e "ainda não chegou" (conferiu sozinho e
  achou);
- a mensagem para outra pessoa e o compartilhamento em 3 passos com o desenho da Meta;
- os avisos `choosing` (Continuar retoma na escolha) e `broken`;
- celular (390 px) e tema claro e escuro.

Ajustes feitos no QA:
- nome do anúncio cai para o título do clique logo depois de conectar;
- CTA sólido no cartão "Investimento", que não quebra no celular;
- faixa "Entrar → Confirmar → Ver";
- a conexão abre no topo da tela.

ESLint e Rubocop limpos. Demo zerada (sem conexão, `meta_modo=uma`).

## Próxima ação

1. ~~Confirmar que o painel subiu e fazer o QA~~ (feito):
   - toda a jornada: Ver quanto gastei → Entrar com o Facebook → Conectar → Pronto → painel com gasto e "Outros
     anúncios";
   - os modos `duas`, `nada`, `recusa` e `aos_poucos`;
   - os avisos `choosing` e `broken`;
   - largura 390 px e tema claro/escuro.
2. Mandar o link ao Rodrigo e esperar a aprovação.
3. Depois de aprovado:
   - specs (Report, com os dois blocos e o custo só do WhatsApp; SemLogin, com `connection_state`; Linker, com o toque
     legado; LinksBackfillJob, com a janela; vitest de `ConectarAnuncios` e do painel);
   - `pnpm i18n:fork:check`;
   - revisor;
   - PR com `Refs #2054`;
   - parecer de Funções personalizadas;
   - vaga com a Orquestração.

## Depois da aprovação (21/10, fim da tarde)

Rodrigo aprovou o protótipo ("pode seguir com specs e PR"), aprovou a lista lateral fora do Resultado conectado
("é isso mesmo, pode implementar") e escolheu ler da Meta o destino do conjunto.

Feito:
- Painel conectado: a lista dos 4 passos só aparece na aba Conexão ou com um passo aberto.
- Destino do conjunto (`crm_meta_ad_objects.destination_type`, migration 20261108330000, versão reservada com a
  Orquestração):
  - lido por `Insights::Destinations` depois do gasto de hoje, com uma chamada a `act_<id>/adsets`, só quando
    falta destino;
  - `Panel::AdDestinations` põe em "Outros" só o anúncio que nunca trouxe conversa e cujo conjunto leva a um
    destino da lista OUTSIDE (site, vídeo, perfil…);
  - sem destino, o anúncio fica entre os que trazem conversa. Assim o anúncio novo de WhatsApp continua no custo
    por conversa e no consultor ("espere").
- O AdDetail abre também os outros anúncios, sem veredito.
- O relatório baixado mostra a linha "Outros anúncios (sem conversa)".
- Specs Ruby e vitest novos.

Validação no M2, snapshot `/Users/Shared/maccluster-workspaces/20261021-2054-merge/20261021-164420-818bf2be-…/src`
com a main mesclada:
- rspec de meta_ads: 539 exemplos, 0 falhas;
- vitest de metaAds: 201/201;
- Rubocop e ESLint sem erro;
- `i18n:fork:check` ok.

Falha que depende da ordem, fora do PR: `meta_advisor_action_spec` 65 e 74 falharam uma vez na suíte e passaram
sozinhos.

Depois do deploy:
- a conta 18 só passa o EUA para "Outros" quando a leitura de hoje gravar o destino, até 30 minutos depois de
  abrir a tela;
- teste real da conta 6 com a pessoa testadora (ver Riscos).

Limpeza extra: o snapshot `20261021-2054-merge` e o wrapper `rt2.sh` na pasta da demo.

## Riscos e pendências

- **Não provado:** o token de um **testador** lê a conta de anúncios dele com o app no nível "Limited"? A documentação
  só garante admin e desenvolvedor. Só o teste real responde: Rodrigo convida uma pessoa da Onze Onze como testadora,
  e ela conecta pela conta 6 depois do deploy. A Meta pede que o testador atue "em nome" do app, o que é um risco de
  política e fica como decisão do Rodrigo.
- O `Advisor` (consultor) usa `report.ads`. Com a separação, anúncio sem conversa sai do consultor. Isso muda a conta
  18 se ela tiver anúncio que não leva ao WhatsApp; conferir antes do PR.
- O compartilhamento como parceiro também não está provado; depende de a Onze Onze compartilhar.
- Na conta 6, conectar tira a conta do painel sem login e leva ao painel com gasto. O sem login volta sozinho se a
  conexão cair.

## Outros itens abertos da sessão

- O resultado do cron das fotos (tarefa `cron_check2`, 15h27 local) não foi lido.
- Confirmar que a foto é salva no primeiro clique real num anúncio sem foto.
- Confirmar que uma conta nova nasce com a flag `anuncios_sem_login`.

## Limpeza no fim da entrega

Worktree 2054, o snapshot do M2 `20261021-2054-conectar`, a demo `/Users/Shared/maccluster-demo-2054`, o banco
`chatwoot_demo_2054` e o Redis db 14.
