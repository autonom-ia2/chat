# O QUE AS FERRAMENTAS DA AGENDA DEVOLVEM EM CAMPOS (#1305), incluído pela `Native::Agenda`.
#
# - Agenda que não marca: `agenda_disponivel: false`, o `motivo` e o que fazer.
# - Reunião marcada (`agendar_reuniao`): o resumo para falar, o início no fuso da página, a duração, o local, o link
#   da reunião (link próprio, Meet, Teams) ou o endereço, e o link de gestão `/b/<código>` — sempre o convite da
#   reunião que é do contato DESTA conversa, nesta conta.
#
# Usa o que a ferramenta já tem (`fuso`, `rotulo_do_local`, `contato`, `account`).
module Autonomia::Agents::Tools::Native::AgendaRespostas
  CONFIRMADO = 'Confirme ao cliente o dia, a hora e o local. Mande o link_de_gestao: por ele o cliente confirma, muda ' \
               'ou cancela. Se houver link_da_reuniao ou endereco, mande também. Não diga que mandou convite por e-mail.'.freeze

  private

  # A agenda não marca agora: o motivo em campo (`pagina_inexistente` | `pausada` | `sem_responsavel` |
  # `agenda_pausada` | `sem_horario`) e o que fazer.
  def indisponivel(motivo, instrucao)
    resposta(agenda_disponivel: false, motivo: motivo, instrucao: instrucao)
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
      marcada: true, resumo: resumo(hora, minutos, local), inicio: hora.iso8601, duracao_minutos: minutos,
      local: rotulo_do_local(local), link_da_reuniao: reuniao.online_meeting_url.presence, endereco: local['address'].presence,
      link_de_gestao: convite_do_cliente(reuniao)&.url, instrucao: CONFIRMADO
    )
  end

  def resumo(hora, minutos, local)
    dia = ::Autonomia::Agents::Tools::Native::Agenda::DIAS_DA_SEMANA[hora.wday]
    "Reunião marcada: #{dia}, #{hora.strftime('%d/%m, %H:%M')} (fuso #{fuso.tzinfo.name}), #{minutos} minutos, " \
      "#{rotulo_do_local(local)}."
  end

  # O link de gestão é o convite da reunião que pertence ao contato DESTA conversa e nesta conta; nunca o de outro.
  def convite_do_cliente(reuniao)
    ::Crm::BookingInvite.where(account_id: account.id, meeting_id: reuniao.id, contact_id: contato.id, canceled_at: nil)
                        .order(:id).last
  end
end
