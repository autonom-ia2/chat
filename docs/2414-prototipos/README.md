# Protótipos em tela real: automação no CRM (#2499 F6.3/F6.4/F6.5 e #2710)

> **Esta branch é só da demo. Não vai para a main.** Depois do OK do Rodrigo no protótipo, ela é descartada e a
> implementação final sai em PRs próprios (com flag e bit reservados lá, não aqui).

Três jornadas montadas com os componentes reais do painel, encaixadas nas telas de verdade (o card do funil, a
etapa aberta no "Editar funil" e o quadro). Não há flag de produto: o protótipo só liga quando as duas coisas valem
ao mesmo tempo:

1. o painel roda no build de desenvolvimento (`import.meta.env.DEV`; no build de produção vira `false` e o ramo some);
2. o funil tem a marca que o seed da demo grava no banco da demo: `metadata.demo_prototipo_2414 = { etapa_id }`.

Fora do funil marcado, nada muda, nem na demo.

**Estado: código pronto para a demo, não conferido em tela.** A demo ainda não subiu, o seed não rodou e não houve
prints em 390 e 1440. Falta o passo "Preparar a demo" abaixo, olhar cada PNG e só então mandar ao Rodrigo.

O que é real e o que é ensaio:

| Parte | De onde vem |
|---|---|
| Regras antigas da etapa ("Ligar no dia seguinte") | real: `crmKanban/fetchStageAutomations`; o interruptor salva de verdade |
| Automações novas da etapa e do card (frase, passo atual, histórico, "Parar") | adaptador falso (`automacaoNoCrm/fonteDasAutomacoes.js`), no formato da receita da Automação livre; as frases saem do `frases.js` com o catálogo real |
| "Nova automação para esta etapa" e "Criar uma automação para quem entrar em…" | real: o editor abre com o gatilho da etapa já escolhido |
| Reuniões das jornadas do #2710 | reais: `Crm::Meeting` e a atividade `meeting_scheduled`, criadas pelo seed (a Agenda e a linha do tempo mostram o banco) |
| Selo "Já é cliente desde…" e "abrir a compra" | reais: `source` do card (`public_link`/`invite`), `customer_since` do contato e o card ganho pela API do perfil do contato |

## Preparar a demo

No M4, de dentro da worktree (kit `bin/demo`, runbook `docs/runbooks/demo-tela-real.md`):

```sh
bin/demo up 2414-telas
bin/demo flag 2414-telas automacao_editor
bin/demo flag 2414-telas automacao_gatilhos
bin/demo seed 2414-telas docs/2414-prototipos/seed_demo.rb
bin/demo tunnel 2414-telas
```

Antes dos prints: copiar na demo as flags da conta 1 do hub (as de reunião/agenda do CRM incluídas, senão a Agenda
do card não aparece) e conferir pelo túnel que o Vite serve o texto novo (abrir a etapa e ver "Jeito antigo").

O seed cria o funil "Vendas (demo 2414)" com a marca, a regra antiga "Ligar no dia seguinte" em "Proposta enviada",
o Pedro Lima (card em "Proposta enviada") e as duas variantes do #2710 (Maria Souza e Ana Costa). Salvar o funil
pelo "Editar funil" pode regravar o `metadata` sem a marca: se o protótipo sumir, rodar o seed de novo.

Estado vazio das automações: acrescentar `?demo=vazio` ao endereço do CRM e recarregar.

## Jornada 1 — "Automações deste card" (F6.3)

1. Menu **CRM** → no topo, escolher o funil **Vendas (demo 2414)**.
2. Tocar no card **Pedro Lima** (coluna "Proposta enviada"). O card abre no resumo.
3. Rolar até **Automações deste card**, logo abaixo dos quatro cartões. Aparecem duas automações, cada uma com a
   espera, o passo atual e "O que já fez":
   - "Lembrete de proposta — espera até <entrada + 3 dias>", "Passo 1 de 2: Esperar 3 dias";
   - "Mandar a proposta de novo — espera até <entrada + 2 dias>", "Passo 2 de 3: Esperar 2 dias", e em "O que já
     fez" a mensagem que já foi.
4. Tocar **Parar para este card** na primeira: a linha vira a pergunta "Parar Lembrete de proposta só neste card?"
   com **Sim, parar** e **Voltar**.
5. **Sim, parar**: a linha some e aparece "Lembrete de proposta parou neste card. Os outros cards continuam."
6. Vazio (`?demo=vazio`): "Nenhuma automação está cuidando deste card agora." e o botão **Criar uma automação para
   quem entrar em Proposta enviada**.

Só card aberto mostra a parte: card ganho, perdido ou arquivado não tem automação rodando. Quem não tem
`automation_view` (nem `automation_manage`) não vê a parte.

Prints: 1440 e 390 nos passos 3, 4, 5 e 6.

## Jornada 2 — "Automações desta etapa" (F6.5 e o aviso da F6.4)

1. Menu **CRM** → funil **Vendas (demo 2414)** → botão de configurar do quadro → **Editar funil**.
2. No resumo do funil, abrir **Etapas** e tocar na etapa **Proposta enviada**.
3. A parte **Automações desta etapa** mostra uma lista só, na mesma linha da lista de Automações (frase, **Alterar**
   e o interruptor Ligada/Desligada):
   - "Ligar no dia seguinte", com o selo **Jeito antigo**: Quando o card entra nesta etapa → Criar o retorno
     "Ligar para o cliente" (regra real; o interruptor salva);
   - "Lembrete de proposta" e "Mandar a proposta de novo": card entrou em Proposta enviada → os passos;
   - "Avisar se o cliente sumir" (Desligada): card parado 5 dias em Proposta enviada → avisar o responsável.
4. Embaixo, **Nova automação para esta etapa** e o aviso "Ainda não contam como entrar ou sair desta etapa:
   arquivar vários cards de uma vez, apagar a etapa e mover cards pela integração." O aviso só aparece quando há
   automação de entrar ou sair.
5. **Nova automação para esta etapa**: o editor abre com o gatilho "card entrou na etapa" de **Proposta enviada**.
6. Mudar o nome da etapa sem salvar e tocar **Nova automação para esta etapa**: aparece "Sair sem salvar? O que você
   mudou no funil não fica guardado." com **Sair sem salvar** e **Ficar**.
7. **Alterar** em "Ligar no dia seguinte": abre a tela das ações da etapa (a de hoje). O das automações novas abre a
   lista de Automações (no ensaio elas não existem no motor).
8. Outra etapa do funil: "Esta etapa ainda não tem automação." e o botão (sem ajuda nem aviso).

Prints: 1440 e 390 nos passos 3/4, 5, 6 e 8.

## Jornada 3 — Reunião de quem já comprou (#2710): as duas variantes lado a lado

A #2710 pede uma decisão de produto que ainda não foi tomada. A tela mostra as duas saídas que dá para implementar,
cada uma com uma pessoa, para o Rodrigo escolher (a 3ª opção, deixar como está, é o que acontece hoje):

| | Variante 1: o card ganho recebe a reunião | Variante 2: card novo, casado pelo contato |
|---|---|---|
| Na demo | Maria Souza: "Plano anual" (ganho) com a reunião na Agenda e na linha do tempo; nenhum card novo | Ana Costa: "Plano mensal" (ganho) e o card novo "Ana Costa - Agenda" com a reunião; o selo "Já é cliente desde…" abre o ganho |
| Ganha | um card só por cliente; a reunião fica no histórico da compra | o funil de vendas conta a oportunidade nova (recompra, upgrade) |
| Perde | a reunião fica num card fechado (coluna "Venda fechada"); quem olha só os cards abertos não a vê | dois cards da mesma pessoa; a ligação entre eles é só o contato |
| Muda no backend | a página de agendamento reaproveita o card ganho (hoje `BookingCard#open_card` só olha card ativo) | nada na reserva; a tela casa pelo contato (o que o protótipo faz) |

Passos:

1. Menu **CRM** → funil **Vendas (demo 2414)**. Na coluna "Novo contato", o card **Ana Costa - Agenda** tem o selo
   **Já é cliente desde <data>** no lugar do selo "Cliente" (só nesse card: os outros clientes seguem com o selo de
   sempre).
2. Tocar no selo (não no card): abre o card ganho **Plano mensal** da Ana.
3. Abrir o card **Ana Costa - Agenda**: no topo, o selo "Cliente desde…" vira botão com a seta e abre a compra; a
   reunião está na **Agenda** do card e em **Mais detalhes** → **O que já aconteceu** ("Reunião marcada").
4. Abrir o card ganho **Plano anual** da Maria (coluna "Venda fechada"): a reunião está na **Agenda** e na linha do
   tempo do próprio card ganho; não existe card novo da Maria.

A tela não diz por qual canal o link chegou: a reserva grava só a origem (`public_link` ou `invite`), não se o link
foi por e-mail ou WhatsApp.

Prints: 1440 e 390 nos passos 1, 3 e 4.

## Pendências

- **Decisão do #2710** (variante 1 ou 2): registrar na Issue depois que o Rodrigo escolher. O protótipo não decide.
- **API do motor**: o que roda num card (passo atual e espera), o histórico de execuções por card, parar uma
  automação só num card, e ligar e desligar pela etapa. Cada endpoint leva o parecer de Funções
  (`automation_view` + `CardPolicy#show?` para ver; `automation_manage` + `CardPolicy#update?` para parar).
- **Receitas de etapa** (§8.4 do `docs/automacao/F6-F8-gatilhos.md`): o catálogo ainda não tem receita com gatilho
  de etapa; por isso "Criar uma automação…" abre o editor só com o gatilho, e não pelos modelos.
- **Flag e bit**: só no PR da implementação final. Avisar a Orquestração que nenhuma flag deste protótipo existe.
- **Guia**: nenhuma rota nova, então não precisa de `guia:build`, de formatos nem de `porques.md`/`central:check`
  neste protótipo. Quando a F6.5 virar tela final, revisar o bloco da etapa em `lib/operator_guide/porques.md`.
