# G29 (#2702): de onde o card veio, como escolha fechada da receita (`card.origem`). O `crm_cards.source` é gravado por
# quem cria o card e mistura formatos: o card que nasce de uma conversa grava o tipo do canal (`Channel::Whatsapp`,
# Crm::Cards::Creator#hydrate_from_conversation); os outros gravam um nome próprio. Aqui cada um vira um grupo que a
# pessoa reconhece. O que não tem grupo (card do quadro, da API, de uma regra, criado em grupo
# na lista de Relacionamentos) é "outro".
#
# Quem cria card está em QUEM_CRIA_CARD; o spec derruba a CI quando surge um lugar novo, para o source dele ganhar grupo.
module Autonomia::Automacao::OrigemDoCard
  FORMULARIO = 'formulario_de_anuncio'.freeze
  CONVERSA = 'conversa'.freeze
  AGENDA = 'agenda'.freeze
  PROSPECCAO = 'prospeccao'.freeze
  OUTRO = 'outro'.freeze
  GRUPOS = [FORMULARIO, CONVERSA, AGENDA, PROSPECCAO, OUTRO].freeze

  # O card do canal começa assim; o resto do nome é o canal.
  DO_CANAL = 'Channel::'.freeze
  # Reunião marcada pelo link público, pelo convite, pelo painel ou pela IA (Crm::BookingV2::Results::BOOKING_SOURCES),
  # o "me liga" da página (ContactRequest) e o agendamento antigo (Crm::Calendar::PublicBookingService).
  DA_AGENDA = %w[invite public_link ai panel contact_request public_booking].freeze
  POR_SOURCE = {
    'meta_lead_form' => FORMULARIO,
    'autonomia_prospecting' => PROSPECCAO,
    **DA_AGENDA.index_with { AGENDA }
  }.freeze

  QUEM_CRIA_CARD = %w[
    app/controllers/api/v1/accounts/crm/cards_controller.rb
    app/services/automation_rules/crm_actions.rb
    app/services/autonomia/automacao/card_novo.rb
    app/services/autonomia/prospecting/crm_card_converter.rb
    app/services/crm/booking_v2/booking_card.rb
    app/services/crm/booking_v2/contact_request.rb
    app/services/crm/calendar/public_booking_service.rb
    app/services/crm/cards/from_conversation_handler.rb
    app/services/crm/conversations/card_syncer.rb
    app/services/crm/meta_ads/lead_forms/importer.rb
    app/services/crm/subjects/acoes.rb
    app/services/crm/subjects/suggestion_responder.rb
    app/services/relacionamentos/criar_cards.rb
  ].freeze

  module_function

  def de(source)
    texto = source.to_s
    return CONVERSA if texto.start_with?(DO_CANAL)

    POR_SOURCE.fetch(texto, OUTRO)
  end
end
