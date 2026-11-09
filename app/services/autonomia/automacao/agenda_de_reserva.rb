# A página de agenda de reserva do link da agenda (G60, decisão 10 do Rodrigo, 09/11): quem monta a automação escolhe,
# no gatilho, uma página fixa (`agenda_de_reserva.pagina_id`, ex.: "Agenda do salão"). O link da agenda continua sendo a
# página de quem atende a conversa ou o card (LinkDaAgenda); só quando ninguém atende (o contato sem conversa na caixa
# escolhida, ou a conversa sem ninguém) vale a página fixa. Assim o parabéns do exemplo 6 sai com um link que funciona.
#
# Acesso: a página é da conta, das novas, e quem salva lê as páginas de agendamento (`agendamento_view`, ou o
# `agendamento_manage`, que o inclui). Ao rodar, a página precisa estar no ar e quem ligou ainda ler as páginas; senão o
# passo pula com o motivo próprio (`agenda_de_reserva_indisponivel`), nunca com outro link.
module Autonomia::Automacao::AgendaDeReserva
  INDISPONIVEL = 'agenda_de_reserva_indisponivel'.freeze
  ALVOS = [::Autonomia::Automacao::Gatilhos::CARD, ::Autonomia::Automacao::Gatilhos::CONTATO, 'Conversation'].freeze

  module_function

  def pagina_id(receita) = receita.to_h.dig('gatilho', 'agenda_de_reserva', 'pagina_id')

  def problemas_ao_salvar(conta, gatilho, account_user)
    id = gatilho.to_h.dig('agenda_de_reserva', 'pagina_id')
    return [] if id.nil?
    return [frase(:agenda_de_reserva_sem_alvo)] unless ALVOS.include?(::Autonomia::Automacao::Gatilhos.alvo(gatilho['tipo']))
    return [frase(:agenda_de_reserva_de_fora, id: id)] unless conta.crm_agent_booking_profiles.new_pages.exists?(id: id)
    return [] if account_user.nil? || le_paginas?(account_user)

    [frase(:agenda_de_reserva_sem_acesso, id: id)]
  end

  # O link da página fixa, para quando ninguém atende. Página desligada, apagada, sem quem atenda nela, ou quem ligou
  # que já não lê as páginas: vazio com o motivo próprio.
  def resultado(conta, pagina_id, quem)
    pagina = (pagina_no_ar(conta, pagina_id) if quem_ligou_le?(conta, quem))
    url = (::Crm::BookingV2::ShortLink.url_for(pagina) if pagina)
    ::Autonomia::Automacao::LinkDaAgenda::Resultado.new(url: url, por: (INDISPONIVEL unless url))
  end

  def quem_ligou_le?(conta, quem)
    account_user = quem && conta.account_users.find_by(user_id: quem.id)
    account_user.present? && le_paginas?(account_user)
  end

  def pagina_no_ar(conta, pagina_id)
    return unless ::Crm::Config.booking_v2_enabled?(conta)

    ::Crm::BookingV2::InvitePages.new(conta).usable.find { |item| item.id == pagina_id.to_i }
  end

  def le_paginas?(account_user) = %w[agendamento_view agendamento_manage].any? { |chave| account_user.permission_granted?(chave) }

  # O motivo do passo que pulou sem o link: o da página fixa fora do ar é próprio; o resto é o faltou_link_da_agenda.
  def motivo(por) = por == INDISPONIVEL ? INDISPONIVEL : 'faltou_link_da_agenda'

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
