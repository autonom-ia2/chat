# Checklist do card do funil (#1423) — nada se perdeu

Este é o checklist que acompanhou o redesenho do card do funil, do inventário da
gaveta antiga (cada função, onde estava e em que condição) até o card novo. Cada
linha diz onde a função mora agora, o print que a mostra e o spec que a protege.
Os prints citados (`01-resumo`, `13-agenda`…) foram tirados na demo local e ficam
fora do repositório; os finais estão listados no PR.

Abreviação: `K/` = `app/javascript/dashboard/routes/dashboard/crm/components/card/`.

## Rodada final (PR que troca o card antigo pelo novo)

| O que mudou | Onde · spec |
|---|---|
| O card novo virou o padrão; o `?gaveta=nova` saiu | `pages/CrmKanbanPage.vue` · `CrmKanbanPage.spec` |
| A gaveta antiga saiu (`CrmCardDrawer`, `CrmCardAiPanel`, `CrmCardSummaryPanel`, `calendar/CrmCardNextMeeting`, specs e story); os testes da linha do tempo foram para o composable que o card usa | `K/specs/useCardHistorico.spec.js` |
| **Janela do Google/Microsoft** virou tela do card ("Marcar reunião"): cartão-frase do convite por e-mail, o mesmo formulário (caixa, convidados, dia, hora, duração, sugestão de horário, lembrete de 15 min) e um botão azul. Com página de agendamento **e** Google/Microsoft, a tela deixa escolher (era a aba da janela). A janela do calendário continua igual, agora usando o mesmo formulário | `K/telas/TelaReuniaoNova.vue`, `calendar/CrmProviderMeetingForm.vue` (+ `CrmMeetingGuests`, `CrmMeetingAiTimes`, `useMeetingAi`, `meetingGuests`, `meetingDates`) · `CardGaveta.spec`, `CrmProviderMeetingForm.spec`, `CrmCalendarMeetingScheduler.spec` |
| **Link da agenda com página** virou tela do card ("Link da agenda"): cartão-frase (quem escolhe, página, até quando vale, estado do link), a mensagem editável, Copiar o link, Cancelar este link (com confirmação) e o azul Enviar na conversa (sem conversa: Copiar; link vencido: Gerar outro). O selo do último link aparece no cartão da Agenda. O botão do cabeçalho da conversa continua igual, com a mesma lógica | `K/telas/TelaLinkAgenda.vue`, `K/telas/TelaAgenda.vue`, `components-next/Booking/useBookingInvite.js` · `CardGaveta.spec`, `useBookingInvite.spec`, `BookingInviteButton.spec` |
| Enviando reunião ou link, Voltar/Fechar esperam a resposta | `K/CardGaveta.vue` (`ocupado`) · `CardGaveta.spec` |
| Densidade: o pior caso da demo (reunião hoje + retorno atrasado + cliente esperando + sugestão) rolava 44 px no 1440×900; agora cabe (0 px nos 5 cards da demo) | `K/CardHeroi.vue`, `K/CardCartao.vue`, `K/CardProximoPasso.vue`, `K/CardGaveta.vue` |
| Rótulo do topo no tema escuro com a mesma cor no card e nas telas de funil | `K/CardHeroi.vue`, `funil/FunilHeroi.vue` |
| Central de Ajuda e Guia descrevem o card novo | `lib/central_de_ajuda/10/*`, `lib/operator_guide/porques.md` |

**Fora deste PR:** lembretes com recorrência (#1460), lembrete sem card (#1461) e
quem recebe o lembrete (#1462). Os roteiros de vídeo da Central (10.02, 10.03, 10.04,
10.05, 10.08) apontam para a gaveta antiga e estão marcados para regravar.

---

## v5 — correção da auditoria (o checklist v4 dizia "0 perdidos" e não era verdade)

Por que o v4 não pegou: ele conferia se o item **existia em algum lugar do código**, não se
estava **visível, com o nome que a pessoa espera e no mesmo número de toques**. Três furos:
(1) RL-01..RL-12 marcados em bloco porque o painel inteiro foi embutido numa tela "Cliente",
misturando contato, empresa e status; (2) o status de cliente (`contact_type`/`customer_since`,
selo "Cliente" da base de clientes) **não estava no inventário**: ele veio só da gaveta antiga,
e o selo vive no card do quadro e na ficha do contato; (3) RT-03 contou os modos existentes no
formulário, mas o "Lembrete" ficou escondido atrás de "Marcar um retorno" e com o nome padrão
"Falar com o cliente".

| Faltava ou estava escondido | v5 | Onde · print · spec |
|---|---|---|
| Contato, Empresa e Cliente misturados numa tela "Cliente" | Cartão **Contato e empresa**: linha da pessoa (Alterar → tela Contato) e linha da empresa (Alterar → tela Empresa); telas separadas pelo mesmo painel (`parte` pessoa/empresa) | `K/CardResumo.vue`, `K/telas/TelaCliente.vue`, `CrmCardRelationshipPanel.vue` (`parte`) · `01`, `07`, `45` · spec "Contato e empresa" |
| Empresa sumia quando o negócio não tinha pessoa | A linha da empresa aparece mesmo sem pessoa | `49-empresa-sem-pessoa` · spec |
| Status de cliente ausente | Selo **"Cliente desde mm/aaaa"** no topo e no cartão; **Marcar como cliente / Desfazer** com confirmação, mesma rota e permissão da ficha (`contacts/setCustomer`) | `46-resumo-cliente`, `47-marcar-cliente` · specs |
| Topo dizia "Cliente no funil" para quem não comprou | Topo mostra a **etapa**; a palavra cliente só no selo | `01` · spec |
| Lembrete simples escondido | Agenda com **"Marcar algo novo"** sempre à vista: Lembrete (só equipe, no calendário, com exemplos), Mensagem no dia, Marcar reunião, Mandar link; "Chamar de volta sozinho" na mesma tela; azul do rodapé = **Novo lembrete** | `K/telas/TelaAgenda.vue` · `13`, `40`, `41` · specs |
| Nome padrão "Falar com o cliente" | Nome **primeiro, vazio**, com "Ex.: Ligar dia 30 às 10h · Aniversário do cliente"; título da tela pelo tipo (Novo lembrete / Mensagem no dia) | `K/telas/TelaRetornoNovo.vue` · `43` · spec |
| Adiar retorno só no calendário | **Adiar** na linha do retorno (data e hora ali mesmo, `crmKanban/rescheduleFollowUp`) | `K/telas/TelaRetornos.vue` · `44` · spec |
| Sem página de agendamento: só descobria depois de abrir o modal antigo | A Agenda pergunta antes (`useJeitoDeMarcar`): com página → **tela "Marcar reunião" na própria gaveta** (mesmo formulário do calendário); só Google/Microsoft → janela de sempre; nada → aviso simples com **Criar minha página** (com permissão) e **Só um lembrete** | `K/useJeitoDeMarcar.js`, `K/telas/TelaReuniaoNova.vue` · `40`, `41`, `42` · specs |
| Mudar etapa exigia abrir a tela Etapa | **Um toque na coluna** do quadro "Onde está no funil", com confirmação curta (FunilQuadro ganhou `clicavel`, desligado nas telas de funil) | `48-mover-pelo-quadro` · specs (gaveta e FunilQuadro) |
| Quem cuida no cartão do contato | Foi para o **Negócio** (é o dono do negócio) | `01` |
| Atendente de cada conversa | Continua na tela Conversas ("Conversa nº 3: Ana Souza atende") | `09` |
| Arquivar | Direto no fim de "Mais detalhes", com a confirmação | `38` |

**Fora da v5 (exige back novo, não inventado):** lembrete sem card; repetição anual
(aniversário); responsável do retorno diferente de quem cria. Ver relatório: propostas de Issue.

**Limites da v5 (resolvidos na rodada final, acima):** a janela do Google/Microsoft e o
diálogo do link de agenda com página existente continuavam no visual de antes.

---

# (v4, mantido para histórico)

Base: worktree `1423-card-funil`, HEAD = origin/main 29bb4a8 (merge fast-forward, sem commit nosso).
Código novo em `app/javascript/dashboard/routes/dashboard/crm/components/card/` (abreviado `K/`).
Prints: `<largura>-<nome>.png` (1440 e 390), na demo local. Demo: snapshot
`20261013-092444-29bb4a83-82634bc424-69273a7f` no M2 (Rails 3386, Vite 3387, banco `chatwoot_dev_1423`).

## A estrutura nova (pedido do Rodrigo: "tripa de coisas enorme")

Resumo do card, de cima para baixo, **sem nada repetido na mesma tela**:

1. Topo como estava: herói (funil, nome, pessoa · negócio) e a faixa com o selo e Ganhou/Perdeu.
   A etapa saiu da migalha e da faixa (fica no quadro e no cartão Negócio).
2. **Próximo passo**: o único destaque, com **um** botão azul. Embaixo, no máximo 2 linhas "Depois disso".
   Sem botão cinza ao lado (abrir conversa, agenda e histórico têm lugar nos cartões); a única
   exceção é "Deixar como está" da sugestão, que não existe em outro lugar.
3. **Quatro cartões**, sempre na mesma ordem, dois por linha a partir de 1280 px:
   - **Cliente**: nome, telefone, empresa; linha "Fulano cuida deste cliente ›" abre a troca de dono.
   - **Negócio**: nome, valor, urgência; linha "Etapa X, a 2ª de 5 ›" (abre a etapa); a sugestão
     do assistente vira uma linha (só quando não está no Próximo passo).
   - **Agenda**: reunião e retornos juntos, por data, o atrasado em vermelho; **sem o que já está
     no Próximo passo** ("Nada mais marcado." quando tudo já está lá).
   - **Conversa**: "N conversas ›" (lista), o resumo da conversa em 2 linhas e **o único**
     "Abrir a conversa". Quando o Próximo passo é "Responder agora", o cartão não repete o botão.
4. **Mais detalhes**, recolhido numa linha: De onde veio, O que já aconteceu, Mais do negócio
   (atenção, deve fechar até, informações extras) e Arquivar.
5. Direita: **só** "Onde está no funil", o `FunilQuadro` das telas de funil (#1414) reaproveitado,
   com rolagem para o lado, setas, "mais N etapas" e a coluna do cliente rolada até o meio.
   O "Em resumo" e os "Últimos acontecimentos" saíram (estão no cartão Conversa e em Mais detalhes).
   O resumo também perdeu o rodapé "Fechar" (repetia o X do topo; Esc também fecha).

Meta de densidade: no 1440×900 o resumo cabe sem rolar, **inclusive no pior caso da demo**
(reunião hoje + retorno atrasado + cliente esperando + sugestão) — medido pelo script de print
(`01-resumo-inteiro` com rolagem extra 0 px).

Telas internas: "Reunião" e "Retornos" viraram **uma tela Agenda** (reunião do dia, retornos
combinados, "Chamar de volta sozinho", feitos/cancelados e os dois jeitos de marcar reunião).
O azul da tela é "Marcar retorno", no rodapé. Na direita das telas internas, só prévia de
verdade (negócio, quem cuida, retorno novo, criação, quem participa da reunião); o resto mostra o
quadro, nunca uma cópia do que está à esquerda (saíram "Ficha rápida", "O primeiro da fila",
"Quando chegou" e "O que a conversa diz").

Decisões já tomadas e implementadas: (a) trocar quem cuida na própria gaveta, com a lista do
acesso por funil (`owner_options`) e o CardGuard no servidor; (b) protótipo em `?gaveta=nova` (na rodada final o card novo virou o padrão).

Legenda: onde está · print · spec.

## Cabeçalho
- [x] CAB-01 — `K/CardHeroi.vue`: herói escuro; migalha só com o funil; título empresa > pessoa > negócio · `01-resumo`
- [x] CAB-02 — subtítulo pessoa · "Negócio: X" · `01-resumo`, `21-resumo-vazio`
- [x] CAB-03 — criação "Passo 1 de 2"/"Passo 2 de 2" · `23-criar-1`, `24-criar-2` · `CrmOpportunityForm.spec`
- [x] CAB-04 — "Voltar ao contato" no herói, pela guarda · *código*
- [x] CAB-05 — X de 44 px pela guarda; **é o único fechar do resumo** · todos · `CardGaveta.spec` ("fechar fica no X")
- [x] CAB-06 — dialog, aria, transição, RTL, 80 rem · todos

## Status
- [x] ST-01 — selo na faixa · `01-resumo`, `20-resumo-ganho`
- [x] ST-02 / ST-03 — Ganhou/Perdeu na faixa em qualquer largura · `01-resumo`, `390-01-resumo` · spec
- [x] ST-04 — Reabrir é o azul do Próximo passo · `20-resumo-ganho` · spec
- [x] ST-05 — `K/DialogoGanhou.vue` · `16-ganhou` · spec
- [x] ST-06 — `K/DialogoPerdeu.vue` · `17-perdeu`
- [x] ST-07 — página recarrega e avisa (sem mudança) · *código da página*
- [x] ST-08 — Esc e clique fora fecham os diálogos · `16`, `17`

## Conversão Meta Ads
- [x] MT-01 — `K/origem/OrigemAviso.vue` na tela De onde veio; no resumo, a frase da origem fica em Mais detalhes · `14-origem`, `38-mais-detalhes-aberto`

## Abas (deixam de existir)
- [x] AB-01 — viraram os 4 cartões + Mais detalhes + telas próprias · spec "não tem abas"
- [x] AB-02 — `initialTab`: followups→**agenda**, contact→cliente, conversations→conversas, timeline→histórico · spec (calendário abre na Agenda)
- [x] AB-03 — "Carregando…" na faixa · *código* (`CardFaixa`)
- [x] AB-04 — uma coluna no celular · prints 390

## Resumo — campos
- [x] RS-01 — reunião: no Próximo passo quando é hoje, senão na linha do cartão Agenda; tela Agenda com `CrmMeetingDayActions` (número, Chamar no WhatsApp, Lembrar, outro horário) e selo da resposta ("Confirmou") · `01-resumo`, `13-agenda`
- [x] RS-02 — `TelaEtapa` pela linha "Etapa … ›" do cartão Negócio; muda na hora · `02-etapa`, `34c-etapa-8-etapas` · spec (move)
- [x] RS-03 a RS-06 — `TelaNegocio` (nome obrigatório, observações, quanto vale com moeda, urgência) · `03-negocio`
- [x] RS-07 — "Mais detalhes" do negócio (atenção, deve fechar até) · `04-negocio-mais`; resumo disso em Mais detalhes › Mais do negócio · `38-mais-detalhes-aberto`
- [x] RS-08 — Salvar no rodapé, volta ao resumo atualizado · spec (salvar)

## Sugestão e leitura da conversa
- [x] IA-01 — sugestão no Próximo passo (Mover / Deixar como está) ou, quando não cabe lá, linha no cartão Negócio; `TelaEtapa` com Ler de novo etc. · `01-resumo`, `02-etapa` · spec (PM-08)
- [x] IA-02 — resumo da conversa no cartão Conversa (2 linhas) e completo na tela Conversas (Atualizar, "Atualizado há X") · `01-resumo`, `09-conversas`
- [x] IA-03 — ator "Sistema, lendo a conversa" · `15-historico`

## Vínculos do card
- [x] VC-01 — `TelaOrigem` "Como X chegou" + "Ligado a", por Mais detalhes › De onde veio · `14-origem`
- [x] VC-02 — Abrir a conversa: **um lugar no resumo** (cartão Conversa, ou "Responder agora" quando o cliente espera), mais a tela Conversas e a Origem · `01-resumo`, `19-resumo-espera` · spec ("abre por um lugar só")
- [x] VC-03 — vários toques (`K/origem/OrigemCaminho.vue`) · `14-origem`
- [x] VC-04 — origem única · `29b-origem-unica` · spec (data-toques=1)
- [x] VC-05 — formulário da página · `14-origem`
- [x] VC-06 — Ligado a: pessoa, caixa, conversa · `14-origem`

## Campos do card
- [x] CF-01 / CF-02 — `CrmCardCustomFields` em `TelaNegocio`; a contagem aparece em Mais detalhes › Mais do negócio · `03-negocio`, `27-negocio-leitura`, `38-mais-detalhes-aberto`

## Dono
- [x] DN-01 — criação com o filtro do funil · `24-criar-2`
- [x] DN-02 — **decisão (a) implementada**: `TelaQuemCuida` troca o dono (ChoiceSelect da casa), lista sem quem não cuida do funil (`getOwnerOptions` por card), o dono atual sempre aparece; Salvar no rodapé, prévia à direita muda para "Prévia"; sem permissão, só leitura · `06-quem-cuida`, `37-quem-cuida-lista`, `37b-quem-cuida-trocado` · spec (troca, sem permissão)
- [x] DN-03 — quem atende cada conversa em Quem cuida e Conversas · `06-quem-cuida`, `09-conversas`
- [x] DN-04 — servidor recusa dono sem funil (`crm.owner_without_funnel`), a página traduz · *servidor/página*

## Etapa
- [x] ET-01 — etapas do funil do card, no quadro e na tela Etapa · `02-etapa`, `34-resumo-8-etapas`
- [x] ET-02 — servidor sem mudança · *servidor*

## Valor e venda
- [x] VV-01 — valor no cartão Negócio, no ganho e "achado na conversa" · `01`, `16`
- [x] VV-02 — `countsAsSale` · spec

## Agenda
- [x] AG-01 — "Eu escolho o horário" na tela Agenda, que abre pelo cartão Agenda **em qualquer estado** (sempre visível) e pelo "Ver a reunião" · `13-agenda`, `30b-agenda-sem-reuniao`, `31-agenda-negocio-fechado` · spec it.each (atrasado, esperando, fechado)
- [x] AG-02 — "O cliente escolhe pelo link" (`BookingInviteButton`, régua `useBookingInviteAvailable`); se o servidor desligar, some e a gaveta lembra até trocar de card · `13-agenda`, `32b-agenda-sem-link` · spec (sem link, só link, servidor desligou)
- [x] AG-03 — = RS-01
- [x] AG-04 — reunião recarrega com o card · *código*

## Retornos
- [x] RT-01 — carregando (dentro da Agenda) · *código*
- [x] RT-02 — "Retornos combinados" na Agenda: atrasado em vermelho, Feito e Cancelar de 44 px · `10-retornos` (= tela Agenda)
- [x] RT-03 — `TelaRetornoNovo` pelo azul "Marcar retorno" da Agenda (e do Próximo passo em dia) · `11-retorno-novo`
- [x] RT-04 — esconder/mensagem desligados sem conversa · *código*
- [x] RT-05 / RT-06 — janela no dia escolhido e avisos · `12-retorno-mensagem`, `25-retorno-so-pronta`
- [x] RT-07 — mensagem obrigatória · `25`
- [x] RT-08 / RT-09 — mensagens prontas em cartões · `25-retorno-so-pronta`
- [x] RT-10 — outra caixa: nome digitado e **idioma com a lista inteira do WhatsApp** (nome pelo navegador, en/pt_BR) + **"Outro idioma" com campo livre** para qualquer código; valor fora da lista abre no campo; prévia sem balão livre enquanto falta o nome; rodapé diz o que falta · `28-retorno-outra-caixa`, `35-retorno-falta-pronta`, `33-retorno-idioma-lista` (lista aberta), `36-retorno-idioma-outro` · `CampoIdioma.spec`, spec (falta)
- [x] RT-11 — mesma validação e payload · spec (template_name/template_language)
- [x] RT-12 — `refreshMessagingWindow` exposto · *código*
- [x] RT-13 — `CrmCardAutoFollowupStatus` dentro da Agenda · `13-agenda`
- [x] RT-14 — feitos/cancelados recolhidos · `13-agenda`
- [x] RT-15 — vazio · *código*
- [x] RT-16 — rascunho pede "Sair sem salvar?" · `05-sair-sem-salvar`

## Conversas
- [x] CV-01 — tela Conversas pelo "N conversas ›" do cartão · `09-conversas`
- [x] CV-02 — vazio no cartão ("Nenhuma conversa ligada") · `21-resumo-vazio`
- [x] CV-03 — resumo no topo da tela Conversas · `09-conversas`

## Histórico
- [x] HS-01 a HS-05 — `TelaHistorico` por Mais detalhes › O que já aconteceu (contagem e "o último foi há X" na linha) · `15-historico`, `38-mais-detalhes-aberto` · `timeline.spec`

## Relacionamento
- [x] RL-01 a RL-12 — `CrmCardRelationshipPanel` inteiro em `TelaCliente` (cartão Cliente › Alterar) · `07-cliente`, `08-cliente-editar`, `22-cliente-vazio`

## Criação
- [x] CR-01 a CR-04 — sem mudança nesta rodada; a prévia da direita usa o FunilQuadro com o cliente chegando na etapa escolhida · `23-criar-1`, `23b`, `23c`, `24-criar-2`, `24b`

## Arquivar e rodapé
- [x] RD-01 — Arquivar em Mais detalhes, com confirmação · `38-mais-detalhes-aberto`, `18-arquivar` · spec
- [x] RD-02 / RD-03 — rodapé por tela, no máximo 2 botões, um azul; o resumo não tem rodapé · todos · spec
- [x] RD-04 — rodapé some durante o vínculo · *código*

## Descarte
- [x] DS-01 — "Sair sem salvar?" também para a troca de dono · `05-sair-sem-salvar` · spec
- [x] DS-02 — atualização do mesmo card não apaga o que se digita · *código*

## Teclado
- [x] TK-01 a TK-05 — Esc, foco preso, 44 px, painel fixo · spec

## Tempo real
- [x] TR-01 a TR-06 — página sem mudança · *código/servidor*

## Permissões
- [x] PM-01 / PM-02 — mesmas props · `26-resumo-leitura`, `27-negocio-leitura`
- [x] PM-03 / PM-04 / PM-05 / PM-07 — servidor sem mudança · *servidor*
- [x] PM-06 — `canManageRelationshipRecords` · `07`
- [x] PM-08 — botões da sugestão pedem `canManageAi` e `can_edit` · spec

## Estados
- [x] ES-01 — carregando · *código*
- [x] ES-02 — vazios · `21-resumo-vazio`, `22-cliente-vazio`, `20-resumo-ganho`
- [x] ES-03 — erros · *código*

## Celular
- [x] CEL-01 — uma coluna: Próximo passo, 4 cartões, Mais detalhes e o quadro no fim · `390-01-resumo-inteiro`
- [x] CEL-02 — rodapé com no máximo 2 botões; resumo sem rodapé · prints 390

## Dívidas
- [x] OB-01 a OB-06 — como na v3 (CampoQuando, TextArea, Arquivar com confirmação, aceitar recarrega, sem jargão, moeda por escolha)
- [x] OB-07 — = DN-02, **implementado**

## Repetições que existiam na v3 e onde ficaram
| Repetido na v3 | v4 |
|---|---|
| Reunião no Próximo passo e no cartão Reunião | só no Próximo passo; o cartão Agenda omite o que já está lá |
| Retorno atrasado em "Depois disso" e no cartão Retornos | idem |
| Cartão Etapa com barra + quadro da direita + faixa + migalha | quadro à direita e uma linha no Negócio |
| "Abrir a conversa" 2× + cartão Conversas | um só no cartão Conversa (ou "Responder agora") |
| "Últimos acontecimentos" + "O que já aconteceu" | uma linha em Mais detalhes |
| Rodapé "Fechar" + X | só o X |
| Ficha rápida / primeiro da fila / quando chegou / resumo na direita das telas | quadro do funil |
