# Protótipos em tela real: automação no CRM (#2499 F6.3/F6.4/F6.5 e #2710)

> **Jornadas 1 e 2: implementadas de verdade** (F6.3/F6.5 da #2499, branch `feat/2414-f6-card-e-etapa`), sem mudar
> a jornada aprovada pelo Rodrigo em 12/11. **Jornada 3 (#2710): fora**, até o Rodrigo escolher a variante; o código de
> exemplo dela (selo "Já é cliente", "abrir a compra", `source` no quadro) saiu desta branch e continua só na
> `feat/2414-ft-prototipos`.

As partes têm flag própria, `automacao_no_crm` (decisão do Rodrigo em 12/11; nasce ligada em todas as contas), e
vêm com o motor e os gatilhos de card, como o resto da F6: `automacao_fundacao` + `automacao_motor` +
`automacao_gatilhos` (no servidor, `Motor.gatilhos?`). Sem `automacao_no_crm`, as três rotas dão 404 e as partes
somem. Quem não tem `automation_view` (nem `automation_manage`) não vê nada; sem o motor, a etapa mostra o cartão das
ações de hoje.

| Parte | De onde vem |
|---|---|
| Regras antigas da etapa ("Ligar no dia seguinte") | `crmKanban/fetchStageAutomations`; o interruptor salva na regra |
| Automações novas da etapa | `GET crm/stages/:stage_id/automacoes` (`Autonomia::Automacao::DaEtapa`): gatilho entrou, saiu ou parado nesta etapa, ligadas e desligadas. Ligar e desligar são os da própria automação (`autonomia/automacoes/:id/ligar` e `desligar`, "assumir e religar"), com a confirmação da lista de Automações quando ela manda mensagem, avisa a equipe ou usa IA (#2574) |
| O que roda no card (passo, espera, "O que já fez") | `GET crm/cards/:card_id/automacoes` (`Autonomia::Automacao::NoCard`): as execuções abertas com o card como alvo e os registros delas; as frases saem do `frases.js` com o catálogo real |
| "Parar para este card" | `POST crm/cards/:card_id/automacoes/:id/parar`: fecha as execuções abertas daquela automação neste card e as filhas delas em outro registro (P6: só o que está rodando; decisão de 12/11 para as filhas; sem tabela de exclusão, sem migration) |
| "Nova automação para esta etapa" e "Criar uma automação para quem entrar em…" | o editor abre com o gatilho da etapa já escolhido (`?gatilho=card.entrou_na_etapa&etapa=<id>`) |

Permissões (parecer de Funções): ver no card pede `automation_view` + `CardPolicy#show?`; parar pede
`automation_manage` + `CardPolicy#update?`; ver na etapa pede `automation_view` + a chave de funis
(`crm_manage_pipelines` ou `crm_admin`). Tudo no escopo da conta.

## Preparar a demo

No M4, de dentro da worktree (kit `bin/demo`, runbook `docs/runbooks/demo-tela-real.md`):

```sh
bin/demo up 2414-telas
bin/demo flag 2414-telas automacao_fundacao
bin/demo flag 2414-telas automacao_motor
bin/demo flag 2414-telas automacao_editor
bin/demo flag 2414-telas automacao_gatilhos
bin/demo flag 2414-telas automacao_no_crm
bin/demo seed 2414-telas docs/2414-prototipos/seed_demo.rb
bin/demo tunnel 2414-telas
```

Antes dos prints: copiar na demo as flags da conta 1 do hub (as de reunião/agenda do CRM incluídas, senão a Agenda
do card não aparece) e conferir pelo túnel que o Vite serve o texto novo (abrir a etapa e ver "Jeito antigo").

O seed cria o funil "Vendas (demo 2414)", a regra antiga "Ligar no dia seguinte" em "Proposta enviada" e o Pedro
Lima (card em "Proposta enviada"). As automações novas são de verdade: monte no editor (**Nova automação para esta
etapa**) as que a jornada usa, por exemplo "Lembrete de proposta" (Esperar 3 dias → Avisar o responsável) e "Mandar a
proposta de novo" (Mensagem → Esperar 2 dias → Avisar), ligue e mova o card de Pedro para "Proposta enviada" de novo.
Antes de criar as automações, o card e a etapa mostram o estado vazio.

## Jornada 1 — "Automações deste card" (F6.3)

1. Menu **CRM** → no topo, escolher o funil **Vendas (demo 2414)**.
2. Tocar no card **Pedro Lima** (coluna "Proposta enviada"). O card abre no resumo.
3. Rolar até **Automações deste card**, logo abaixo dos quatro cartões. Aparecem duas automações, cada uma com a
   espera, o passo atual e "O que já fez":
   - "Lembrete de proposta — espera até <entrada + 3 dias>", "Passo 1 de 2: Esperar 3 dias";
   - "Mandar a proposta de novo — espera até <entrada + 2 dias>", "Passo 2 de 3: Esperar 2 dias", e em "O que já
     fez" a mensagem que já foi.
4. Tocar **Parar para este card** na primeira: a linha vira a pergunta "Parar Lembrete de proposta neste card? O que ela começou em outro contato ou card por causa deste também para."
   com **Sim, parar** e **Voltar**.
5. **Sim, parar**: a linha some e aparece "Lembrete de proposta parou neste card. Os outros cards continuam."
6. Vazio (card sem automação rodando): "Nenhuma automação está cuidando deste card agora." e o botão **Criar uma automação para
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
7. **Alterar** em "Ligar no dia seguinte": abre a tela das ações da etapa (a de hoje). O das automações novas abre o
   editor dela.
8. Outra etapa do funil: "Esta etapa ainda não tem automação." e o botão (sem ajuda nem aviso).

Prints: 1440 e 390 nos passos 3/4, 5, 6 e 8.

## Jornada 3 — Reunião de quem já comprou (#2710): as duas variantes lado a lado

> **Não implementada nesta branch.** O Rodrigo ainda não escolheu a variante. O código e o seed de exemplo estão só na
> `feat/2414-ft-prototipos`; o roteiro abaixo descreve aquela demo.

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
- **API do motor**: feita na `feat/2414-f6-card-e-etapa` (ver a tabela no topo).
- **Receitas de etapa** (§8.4 do `docs/automacao/F6-F8-gatilhos.md`): o catálogo ainda não tem receita com gatilho
  de etapa; por isso "Criar uma automação…" abre o editor só com o gatilho, e não pelos modelos.
- **Flag**: F6.3/F6.5 têm a própria, `automacao_no_crm`, no fim do `config/features.yml`; o bit sai da ordem (47
  hoje, 48 com a `carteira_seguros` do #2910) e a Orquestração confirma antes do OK. As contas que já existem a
  Orquestração liga depois do deploy. A `automacao_passos_novos` é só dos passos novos (`passos-novos.md`).
- **Guia**: sem tela nova no painel; o bloco da etapa em `lib/operator_guide/porques.md` foi revisto e ganhou o do card
  (`ver_e_parar_automacoes_no_card`). O "parar" entrou em `Acoes::SEM_DESFAZER` (não reabre) e no porteiro da
  automação (`automation_manage`).
