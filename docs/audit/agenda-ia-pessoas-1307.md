# Agenda da IA: pessoas liberadas (#1307)

Base: `origin/fix/1305-agenda-ia-completa` (PR #1347, ainda não mesclado). Branch `feat/1307-pessoas-liberadas`. Sem migration: a liberação mora no jsonb `config` do agente.

## Contrato

- **Config do agente:** `booking_agent_ids`, uma lista de ids de usuário, ao lado de `booking_page_id`. Só a chave ausente, `null` ou `[]` quer dizer todas as pessoas da página. Um valor gravado que não dá para ler vale como ninguém. O PATCH e o POST conferem a lista no servidor (`AgendaPessoas.liberacao_conferida`). Quando o pedido muda a liberação, ficam só os ids que são pessoas da página escolhida, nesta conta, como inteiros únicos (base 10) e na ordem recebida. Um pedido que não deixa ninguém, seja porque só traz ids de fora ou porque o valor não é lista, recebe 422 com `autonomia.agents.booking_agent_ids_invalid`. Assim a restrição nunca vira "todas" em silêncio. Reenviar a liberação salva, mesmo com ids que saíram da página, não mexe nela e não recusa. Trocar a página não reescreve a liberação salva: quem não é da página nova não vale, e a agenda fica sem responsável até o dono escolher de novo. Mudar a liberação pede `agendamento_view`, a mesma permissão de escolher a página. A comparação é feita sobre o pedido cru, como conjunto, e sair de uma restrição para "todas" conta como mudança. O jbuilder do agente passa a expor `booking_agent_ids` como gravado.
- **`GET crm/booking_pages`:** cada página traz `pessoas: [{ id, nome, ai_status }]`, com `ai_status` igual a `ativa` ou `agenda_pausada`. A ordem é a fixa do #1305 (`InvitePages#people`): no responsável fixo, só ele; no modo por pessoa, os links ativos de quem pode atender, por id. Sai só o nome de exibição. O spec confere que 1 e 4 páginas fazem o mesmo número de consultas.
- **`horarios_disponiveis`:** aceita `pessoa_id` (opcional). O id precisa ser de uma pessoa liberada; senão a resposta é `{motivo: 'pessoa_nao_liberada' | 'pessoa_pausada', pessoas_liberadas}`. Sem `pessoa_id`, a ferramenta junta as liberadas que podem atender. Quando duas pessoas têm o mesmo início, fica a primeira na ordem da página. A resposta agora é JSON: `{agenda_disponivel, fuso, duracao_minutos, aviso?, horarios: [{inicio, quando, pessoa_id, pessoa_nome}], locais: [{tipo, rotulo, pede_email_do_cliente}], quem_atende_esta_conversa?, instrucao}`.
- **`agendar_reuniao`:** recebe `pessoa_id`, obrigatório quando mais de uma liberada pode atender (`motivo: 'pessoa_obrigatoria'`). O servidor confere se a pessoa está liberada, se é pessoa da página e se a agenda dela está aberta. O `Booker` confere o horário livre dela, usando o link dela no modo por pessoa e o responsável no modo fixo. Toda recusa vem em JSON com `marcada: false`. A confirmação traz `pessoa_id` e `pessoa_nome`.
- **Instrução "# Agenda":** lista as liberadas pelo nome e com o `pessoa_id` de cada uma. Diz para seguir a instrução do dono; sem ela, preferir quem atende a conversa, se estiver liberado; senão, oferecer os horários das liberadas. Quem decide é o modelo. O código só lista quem pode e confere números.
- **`recebe`** do #1305 continua igual.

## Decisões

- **Liberação que perdeu todas as pessoas:** se ninguém liberado ainda é pessoa da página (saiu da conta, link desligado, id forjado no banco), a agenda do agente fica `sem_responsavel`. Ela não volta a valer para todas. Todas as liberadas pausadas deixam a agenda em `agenda_pausada`. Os valores são os mesmos de `ai_status`, nenhum vocabulário novo.
- **Quem atende a conversa:** antes, no modo por pessoa, o código escolhia o link de quem estava atribuído. Agora isso vai ao modelo como dado (`quem_atende_esta_conversa`), e quem decide é o modelo.
- **`agenda_pausada` com um sentido só:** o código de recusa da página despublicada era `agenda_pausada`, o mesmo nome do `ai_status` "quem atende pausou Meus horários". O código virou `agenda_pagina_pausada`. Os valores de `ai_status` e do campo `motivo` não mudaram.
- **Precedência:** a instrução "# Agenda" vale sobre regras antigas que mandem encaminhar remarcação e cancelamento à equipe. Para remarcar ou cancelar, a IA manda o link de gestão. O `booking_context` do Construtor diz o mesmo.
- **Prazo:** com `cancel_until_minutes`, a instrução e a confirmação dizem "só até N horas (ou minutos) antes do horário", o mesmo prazo que o link aplica (`too_late`).
- **Meet/Teams:** a confirmação diz que o convite do calendário vai para o e-mail do cliente. Nos outros locais continua "não diga que mandou convite por e-mail".
- **De quem é o aviso:** chegou a ser feito ("Mensagem de <nome da conta>" no texto livre) e foi retirado por decisão do Rodrigo em 12/10/2026: conversar por um canal e receber o aviso por outro é normal, e se o dono quiser avisar o cliente, ele põe na instrução do agente que a confirmação chega pelo WhatsApp. O texto dos avisos não muda neste PR.
- **Memória do turno:** `AgendaDoTurno.no_turno`, aberto em `Answerer#answer`, calcula o estado uma vez por agente. Antes eram três vezes por turno (gate das duas ferramentas e instrução), cada uma com as consultas de página, elegibilidade e pausas. Quando rodam, as ferramentas leem tudo de novo.

## Medições

- **Estado por turno:** o spec conta `InvitePages.new`. Dentro do turno, o gate das duas ferramentas mais o `estado` constroem um. Fora do turno, o gate sozinho constrói dois. A instrução, com a página ativa, monta mais um para a lista de pessoas.
- **Listener `booked_in_conversation_id` (#1305):** a consulta roda a cada mensagem de saída pública. Ela parte de `crm_meeting_notices` pendentes do tipo `booked` na conta (o índice usado é `status, due_at`), junta `crm_meetings` pela chave e filtra `metadata->>'booked_in_conversation_id'`. O custo cresce com os avisos pendentes da instância, não com as reuniões. Hoje é baixo, e por isso não criei índice. Se crescer, há duas saídas: um índice parcial em `crm_meeting_notices (account_id) WHERE status = pending AND kind = 'booked'`, que é migration, ou pular a consulta quando a mensagem não contém o endereço `/b/` do nosso link (comparação de string, sem regex).

## Revisão independente

`caveman:cavecrew-reviewer`, duas passadas:

- **Primeira:** quatro caminhos em que a liberação caía em "todas". Um pedido só com ids de fora, ou com um valor que não é lista, gravava `[]`. A troca de página também gravava `[]`. Um valor gravado ilegível virava todas. E quem não tinha permissão conseguia mandar `[]` sobre uma lista que tinha ficado velha, porque a comparação era feita depois da conferência. Vieram também o `Integer` sem base, a página sem preload e um comentário inexato do jbuilder. Corrigi todos.
- **Segunda:** dois HIGH sobre as correções. O 422 disparava ao reenviar uma lista que tinha ficado velha, e a troca de página ainda gravava `[]`. Corrigi os dois: reenviar não mexe, e a troca de página mantém a restrição.

## Pendências

- Os modelos aprovados da Meta não dizem de quem é o aviso. Mudar isso exige uma versão nova do modelo e uma nova aprovação.
- A tela que grava `booking_agent_ids` é da sessão Agentes IA.

## Validação

Os specs focados rodaram no banco isolado da worktree, e a saída de cada rodada foi lida inteira. Rodaram as ferramentas da agenda, as recusas, o construtor, o Answerer, o PromptBuilder, `spec/services/crm/booking_v2/`, as requests do agente, das páginas, dos convites e da reserva pública: 1534 exemplos, 0 falhas. Os 27 pendentes faltam por libvips na máquina. O rubocop passou sem ofensas. `autonomia:guia:formatos` foi regerado (só números de linha) e o `:check` está em dia. `guia:build` e `guia:check` estão em dia, `central:check` só deu avisos que já existiam, e `i18n:fork:check` passou. Nada foi testado em agente real nem em produção.
