# De onde o card veio (G29, #2702), para a receita ler `card.origem` como escolha fechada. O `crm_cards.source` guarda o
# caminho exato que criou o card (o tipo da caixa da conversa, o formulário do anúncio, a prospecção, cada jeito de
# marcar pela agenda); a receita só precisa do grupo. O que não é de nenhum grupo (card feito à mão, pela API, origem
# nova) lê "outra".
module Autonomia::Automacao::OrigemDoCard
  module_function

  FORMULARIO_DO_ANUNCIO = 'formulario_do_anuncio'.freeze
  CONVERSA = 'conversa'.freeze
  PROSPECCAO = 'prospeccao'.freeze
  AGENDA = 'agenda'.freeze
  OUTRA = 'outra'.freeze
  OPCOES = [FORMULARIO_DO_ANUNCIO, CONVERSA, PROSPECCAO, AGENDA, OUTRA].freeze

  POR_SOURCE = {
    ::Crm::MetaAds::LeadForms::Importer::SOURCE => FORMULARIO_DO_ANUNCIO,
    'autonomia_prospecting' => PROSPECCAO,
    # A página pública (antiga e nova), o pedido de contato, o convite, a equipe pela agenda e a IA marcando.
    'public_booking' => AGENDA, 'contact_request' => AGENDA, 'public_link' => AGENDA, 'invite' => AGENDA,
    'panel' => AGENDA, 'ai' => AGENDA
  }.freeze

  # O card criado de uma conversa guarda o tipo da caixa (Crm::Cards::Creator): "Channel::Whatsapp", "Channel::Api"...
  def de(card)
    source = card.source.to_s
    return CONVERSA if source.start_with?('Channel::')

    POR_SOURCE.fetch(source, OUTRA)
  end
end
