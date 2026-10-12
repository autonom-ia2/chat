# O QUE AS FERRAMENTAS DA AGENDA DEVOLVEM EM CAMPOS (#1305, #1307), incluído pela `Native::Agenda`.
#
# Um formato só, JSON, para tudo o que a agenda devolve ao modelo:
# - Agenda que não marca: `agenda_disponivel: false`, o `motivo` e a `instrucao`.
# - Qualquer outra recusa (dado faltando, parâmetro inválido, pessoa não liberada, horário ocupado): o `motivo` (o
#   código da recusa sem o prefixo `agenda_`), a `instrucao` e, quando ajuda, `pessoas_liberadas` ou `horarios`.
#   `agendar_reuniao` soma `marcada: false` a toda recusa (`campos_da_recusa`).
# - Horários livres (`horarios_disponiveis`): cada um com `inicio`, `quando`, `pessoa_id` e `pessoa_nome`.
# - Reunião marcada (`agendar_reuniao`): o resumo para falar, o início no fuso da página, a duração, o local, a pessoa,
#   o link da reunião (link próprio, Meet, Teams) ou o endereço, e o link de gestão `/b/<código>` — sempre o convite
#   da reunião que é do contato DESTA conversa, nesta conta. A instrução diz o prazo para mudar ou cancelar quando a
#   página tem um (`cancel_until_minutes`, o mesmo que o link de gestão aplica) e, em Meet/Teams, que o convite do
#   calendário chega no e-mail do cliente (o provedor manda).
#
# FUSO É DADO, NÃO FALA (#1362): o fuso vai em `fuso` e no offset do `inicio`, nunca no texto pronto (`resumo`,
# `quando`, `instrucao`). Repetir o fuso a cada horário gasta token e não ajuda; citar o fuso (o cliente perguntou
# ou está em outro) é decisão do modelo, pela instrução "# Agenda".
#
# Usa o que a ferramenta já tem (`fuso`, `rotulo_do_local`, `contato`, `account`, `pagina`, `local_pede_email?`).
module Autonomia::Agents::Tools::Native::AgendaRespostas
  CONFIRMADO = 'Confirme ao cliente o dia, a hora, o local e com quem é. Mande o link_de_gestao: por ele o cliente ' \
               'confirma, muda ou cancela%<prazo>s. Se houver link_da_reuniao ou endereco, mande também.'.freeze
  SEM_CONVITE_POR_EMAIL = ' Não diga que mandou convite por e-mail.'.freeze
  CONVITE_DO_CALENDARIO = ' O convite do calendário vai para o e-mail do cliente: pode dizer que ele chega lá.'.freeze

  private

  # O que toda recusa desta ferramenta leva (a de marcar soma `marcada: false`).
  def campos_da_recusa
    {}
  end

  # A agenda não marca agora: o motivo em campo (`pagina_inexistente` | `pausada` | `sem_responsavel` |
  # `agenda_pausada` | `sem_horario`) e o que fazer.
  def indisponivel(motivo, instrucao)
    resposta(campos_da_recusa.merge(agenda_disponivel: false, motivo: motivo, instrucao: instrucao))
  end

  # As outras recusas, no mesmo formato.
  def recusa_em_campos(motivo, instrucao, **extra)
    resposta(campos_da_recusa.merge(motivo: motivo, instrucao: instrucao).merge(extra))
  end

  # Resposta em campos para o modelo. `JSON.generate` e não `to_json`, que escaparia `&`, `<` e `>` dos links e textos.
  def resposta(campos)
    JSON.generate(campos.compact)
  end

  def confirmar(reuniao)
    hora = reuniao.starts_at.in_time_zone(fuso)
    local = reuniao.metadata.to_h['location'].to_h
    minutos = ((reuniao.ends_at - reuniao.starts_at) / 60).round
    resposta(
      marcada: true, resumo: resumo(hora, minutos, local), **inicio_em_campos(hora), duracao_minutos: minutos,
      local: rotulo_do_local(local), link_da_reuniao: reuniao.online_meeting_url.presence, endereco: local['address'].presence,
      link_de_gestao: convite_do_cliente(reuniao)&.url, instrucao: instrucao_confirmada(local), **com_quem_e(reuniao)
    )
  end

  # O início com offset e o fuso da página como DADO (#1362): o texto (`resumo`) não cita o fuso.
  def inicio_em_campos(hora)
    { inicio: hora.iso8601, fuso: fuso.tzinfo.name }
  end

  # Quem recebe a reunião: o responsável que o Booker gravou nela.
  def com_quem_e(reuniao)
    { pessoa_id: reuniao.created_by_id, pessoa_nome: reuniao.created_by&.available_name }
  end

  def instrucao_confirmada(local)
    prazo = ::Autonomia::Agents::Tools::Native::AgendaInstrucao.prazo(pagina.cancel_until_minutes)
    convite = local_pede_email?(local['type']) ? CONVITE_DO_CALENDARIO : SEM_CONVITE_POR_EMAIL
    format(CONFIRMADO, prazo: prazo ? " (mudar ou cancelar, só #{prazo})" : '') + convite
  end

  def resumo(hora, minutos, local)
    dia = ::Autonomia::Agents::Tools::Native::Agenda::DIAS_DA_SEMANA[hora.wday]
    "Reunião marcada: #{dia}, #{hora.strftime('%d/%m, %H:%M')}, #{minutos} minutos, #{rotulo_do_local(local)}."
  end

  # O link de gestão é o convite da reunião que pertence ao contato DESTA conversa e nesta conta; nunca o de outro.
  def convite_do_cliente(reuniao)
    ::Crm::BookingInvite.where(account_id: account.id, meeting_id: reuniao.id, contact_id: contato.id, canceled_at: nil)
                        .order(:id).last
  end
end
