# As sondas da página de agendamento (G44, G47): rodam o código de verdade e conferem o efeito. Ficam fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama as daqui.
module FechamentoAutomacao::SondasDaAgenda
  extend CrmHelpers
  extend BookingHelpers

  module_function

  # G44 (#2756): o texto do card com o link de uma página escolhida na receita (`agenda.<id da página>`) sai com o link
  # dessa página, lido com as permissões de quem ligou. Roda na transação do exemplo, que desfaz tudo.
  def link_da_pagina_escolhida?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') do
      account = FactoryBot.create(:account)
      account.enable_features!('crm_booking_v2')
      dono = FactoryBot.create(:user, account: account, role: :administrator)
      funil, etapa = create_crm_pipeline(account: account, user: dono)
      card = account.crm_cards.create!(pipeline: funil, stage: etapa, owner: dono, title: 'Sonda G44', currency: 'BRL')
      pagina = create_booking_profile(account: account, host: dono, title: 'Treinamento')
      valores = Autonomia::Automacao::Valores.new(alvo: card, quem: dono)
      texto = Autonomia::Automacao::Texto.new(['Marque: ', { '$valor' => "agenda.#{pagina.id}" }], valores).montar
      texto == "Marque: #{Crm::BookingV2::ShortLink.url_for(pagina)}"
    end
  end

  # G47 (#2755): a reserva pela página põe a reunião num card do contato, e o card nasce com a conversa dele no WhatsApp
  # dos avisos da página. Roda na transação do exemplo, que desfaz tudo.
  def card_da_pagina_ganha_a_conversa?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      caixa = FactoryBot.create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
      account = caixa.account
      dono = FactoryBot.create(:user, account: account, role: :administrator)
      funil, etapa = create_crm_pipeline(account: account, user: dono)
      contato = account.contacts.create!(name: 'Sonda G47', phone_number: '+5511900000047')
      no_whatsapp = FactoryBot.create(:contact_inbox, inbox: caixa, contact: contato, source_id: '5511900000047')
      conversa = FactoryBot.create(:conversation, account: account, inbox: caixa, contact: contato, contact_inbox: no_whatsapp)
      pagina = create_booking_profile(account: account, host: dono, pipeline: funil, stage: etapa, notice_inbox: caixa)
      card, = Crm::BookingV2::BookingCard.new(profile: pagina, contact: contato, target: { pipeline_id: funil.id, stage_id: etapa.id },
                                              host: dono, source: 'public_link', fallback_name: 'Sonda').perform
      card.conversation_id == conversa.id
    end
  end
end
