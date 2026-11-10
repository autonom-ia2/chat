# As sondas da página de agendamento (G44, G47, G60, G61): rodam o código de verdade e conferem o efeito. Ficam fora do
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

  # G60: a receita com a página de reserva da conta no gatilho sai do salvar sem problema.
  def reserva_no_gatilho_salva?
    numa_conta_de_teste do |conta, pessoa|
      gatilho = { 'tipo' => 'conversa.criada', 'agenda_de_reserva' => { 'pagina_id' => pagina_de_agendamento(conta, pessoa).id } }
      problemas_ao_salvar(conta, gatilho, { 'pessoas' => [pessoa.id] }) == []
    end
  end

  # G61: o "quem atende a reunião" num gatilho de conversa sai do salvar sem problema.
  def da_reuniao_em_qualquer_gatilho_salva?
    numa_conta_de_teste { |conta, _pessoa| problemas_ao_salvar(conta, { 'tipo' => 'conversa.criada' }, { 'da_reuniao' => true }) == [] }
  end

  # Os problemas que o salvar acusa (Receita#problemas, depois do esquema) numa receita de um "avisar" só, com o gatilho e
  # o `para` dados; nil fora do esquema (sondas G60 e G61). Sem pessoa: a sonda não confere a permissão de quem salva.
  def problemas_ao_salvar(conta, gatilho, para)
    receita = { 'gatilho' => gatilho, 'passos' => [{ 'id' => 'aviso', 'tipo' => 'avisar', 'para' => para, 'texto' => ['Oi'] }] }
    return unless Autonomia::Automacao::Receita.esquema_valido?(receita)

    Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: nil).problemas
  end

  # Uma conta com o passo "avisar" ligado e uma pessoa, desfeitas no fim (sondas G60 e G61).
  def numa_conta_de_teste
    resultado = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      conta = FactoryBot.create(:account)
      conta.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens')
      resultado = yield(conta, FactoryBot.create(:user, account: conta))
      raise ActiveRecord::Rollback
    end
    resultado
  end

  def pagina_de_agendamento(conta, pessoa)
    conta.crm_agent_booking_profiles.create!(
      page_version: Crm::AgentBookingProfile::NEW_PAGE, title: 'Agenda', duration_minutes: 30, timezone: 'America/Sao_Paulo',
      default_assignee: pessoa, locations: [{ 'type' => 'whatsapp_video' }], enabled: true, close_holidays: false
    )
  end
end
