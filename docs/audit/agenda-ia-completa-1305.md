# Agenda da IA completa (#1305)

Base: `origin/main` 17c94d3974. Branch `fix/1305-agenda-ia-completa`. Sem migration.

## O que se confirmou no código

| Lacuna | Situação antes | Onde |
|---|---|---|
| 1. A IA não agendava avisos | Confirmada. `agendar_reuniao` criava a reunião e o convite `channel: 'ai'` (o link de gestão existia), mas não chamava `Notices::Scheduler#schedule!`. Só a página pública e o painel chamavam, cada um com a sua cópia. | `agendar_reuniao.rb:133-141`, `public/api/v2/booking_controller.rb:127-135`, `panel_booking.rb:119-129` |
| 2. Link de gestão e local não chegavam ao modelo | Confirmada. O retorno era prosa sem link. | `agendar_reuniao.rb:191-197` |
| 3. Página apagada ou pausada com `booking_page_id` gravado | Confirmada. `disponivel?` só olhava o id e as flags. A IA recebia as ferramentas e a instrução, prometia horário e só então caía em `SEM_PAGINA` ou `PAUSADA`. | `agenda.rb:60-62`, `agenda.rb:101-106` |
| 4. Confirmação só no prompt | Confirmada. | `agenda.rb:80-82` |
| 5. Remarcar e cancelar | Confirmada: só no esqueleto `scheduler`. | `builder.rb:668-671` |
| `Results` | Já classificava `source: 'ai'` como origem `ai` ("Pela IA"). O convite da IA nasce agendado e sem `sent_at`, então não conta como enviado nem aberto. Nada mudou. | `results.rb:26-35` |

A issue dizia que o link de gestão "nunca é criado". Não procede: ele era criado, só não chegava ao modelo nem ao cliente.

## Decisões

- **Um ponto só para os avisos:** `Crm::BookingV2::BookingNotices#schedule`. A página pública, o painel e a IA chamam o mesmo serviço. Ele faz o agendamento, calcula o `notice_will_send` e trata o erro: rastreador, log e `false`, sem desfazer a reunião.
- **Aviso repetido na mesma conversa:** quando a conversa da IA é da mesma caixa de avisos da página, o aviso "ao marcar" vence 5 minutos depois (`CONFIRMATION_GRACE`). No envio (`Notices::Sender` → `BookingNotices.already_told?`), ele só sai se a conversa não recebeu nenhuma mensagem de saída desde a reserva. Com a resposta da IA lá, vira `skipped: told_in_conversation`, sem chamar o responsável. Se o turno morreu antes de a IA responder, o cliente recebe o aviso com o link. A decisão olha só dados (caixa, conversa, mensagens de saída e horário), nunca texto. Os lembretes seguem normais. Se a caixa de avisos é outra (IA no Instagram, avisos no WhatsApp), o aviso sai na hora. A tela mostra o motivo como "a IA já confirmou na conversa". Na primeira versão o aviso nascia pulado; a revisão apontou que, se o turno morresse depois da reserva, o cliente ficava sem confirmação nenhuma.
- **Consentimento:** a reunião da IA grava `notify_client: true` (aviso ligado por padrão), `notice_basis: 'pedido_na_conversa_com_ia'`, `booked_by_agent_id` e `booked_in_conversation_id`.
- **Retorno em campos (JSON):** `marcada`, `resumo`, `inicio`, `duracao_minutos`, `local`, `link_da_reuniao` (link próprio, Meet ou Teams), `endereco`, `link_de_gestao` e `instrucao`. O link de gestão é sempre o convite da reunião que pertence ao contato da conversa, na conta do agente.
- **Regra única "esta página marca?":** `InvitePages#status` devolve `ativa`, `pausada`, `sem_responsavel` ou `agenda_pausada` (o responsável fixo pausou Meus horários, ou todos os links por pessoa são de quem pausou). Quem lê essa regra: a IA (`Native::Agenda.estado`, que soma `pagina_inexistente` para id apagado ou de outra conta), a tela de páginas (`ai_status`) e o convite e o painel (`usable?`, que continuam aceitando `ativa` e `agenda_pausada`, como antes).
- **Página que não marca:** as ferramentas saem do turno (`pode_marcar?`). A instrução "# Agenda" diz que a agenda está indisponível, com o motivo, e manda passar para uma pessoa. O `booking_page_id` não é apagado. Se a página mudar no meio do turno, a ferramenta devolve `{agenda_disponivel: false, motivo}`. O motivo é `pagina_inexistente`, `pausada`, `sem_responsavel`, `agenda_pausada` ou `sem_horario`.
- **Vocabulário:** um só para a tela e para a IA. O pedido citava `sem_atendente`; ficou `sem_responsavel`, o valor de `ai_status`, para não haver dois nomes para o mesmo estado.
- **Confirmação:** `cliente_confirmou` é um booleano obrigatório no schema. Só `true` marca, e o código não lê o texto do cliente. O spec sem regex cobre os arquivos novos.
- **Ordem dos links por pessoa:** `has_many :agent_booking_links, -> { order(:id) }`. "Quem recebe sem ninguém atribuído" é `InvitePages#link_for(page, nil)`: o primeiro link ativo, pulando quem pausou a agenda. A IA e o `recebe` da tela usam esse mesmo método. Na IA, quem está atribuído à conversa e pausou a agenda conta como "ninguém atribuído" (achado da revisão). O convite e o painel continuam usando o link da própria pessoa.
- **Remarcar e cancelar pela conversa:** não foi implementado. A IA manda o link de gestão. As ferramentas foram para a #1309 por três motivos: o aviso `rescheduled` repetiria na mesma conversa, o responsável dos horários diverge em página por pessoa, e falta escolher a reunião do contato.
- **Elegibilidade em lote:** `HostEligibility.eligible_user_ids` aplica a mesma regra numa consulta. `InvitePages` lê a elegibilidade e as pausas uma vez por instância, e a lista de páginas passa uma instância só.

## Contrato para a tela de páginas (`GET crm/booking_pages`, cada página)

- `ai_status`: `"ativa" | "pausada" | "sem_responsavel" | "agenda_pausada"`
- `recebe`: `{ "modo": "fixo" | "por_pessoa", "nome": <nome de exibição> | null }`. No fixo, é o responsável da página. Por pessoa, é o primeiro link ativo de quem não pausou. Vem `null` quando ninguém pode atender.
- `timezone`: o mesmo valor da página completa.

## Validação

Os specs focados rodaram no banco isolado da worktree, e a saída de cada rodada foi lida inteira:

- rspec das ferramentas, das recusas, do registro, do construtor, do booking v2, dos avisos, do job de avisos, dos resultados, das páginas, dos convites e da reserva pública: 0 falhas.
- rubocop nos arquivos Ruby tocados: sem ofensas.
- vitest (`meetingNotices`, `CrmMeetingDetail`) e eslint passaram, `pnpm i18n:fork:check` está em dia.
- `autonomia:guia:formatos`: regerado (só números de linha do controller), e `:check` e `formatos_spec` passaram.
- `scripts/guide-map/build.mjs`, `check.mjs` e `central-de-ajuda/conferir.mjs`: em dia.

Nada foi testado em agente real nem em produção.
