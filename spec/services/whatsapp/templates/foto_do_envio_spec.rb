require 'rails_helper'

# #1717: todo envio de modelo com mensagem na conversa grava a foto do que saiu em template_params.enviado, num ponto só
# (o processamento do modelo). Cada caminho de envio é exercitado de ponta a ponta até o pedido à Meta (Graph falsa):
# conversa, fora da janela (Followup) e aviso do agendamento. A campanha está no spec do SentMessageRecorder.
RSpec.describe Whatsapp::Templates::FotoDoEnvio do
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:graph_messages) { ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/messages') } }
  let(:sent) { [] }

  before do
    stub_request(:post, graph_messages).to_return do |request|
      sent << JSON.parse(request.body)
      { status: 200, headers: json, body: { messages: [{ id: "wamid.#{sent.size}" }] }.to_json }
    end
  end

  def enviado_de(message)
    message.reload.additional_attributes.dig('template_params', 'enviado')
  end

  it 'fica por fora do SendComponents no processamento do modelo (o initializer prepende)' do
    ancestors = Whatsapp::TemplateProcessorService.ancestors

    expect(ancestors.index(described_class)).to be < ancestors.index(Whatsapp::Templates::SendComponents)
  end

  describe 'modelo mandado da conversa' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:template) do
      { 'name' => 'oferta_relampago', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
        'parameter_format' => 'POSITIONAL',
        'components' => [
          { 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => 'Só hoje!', 'has_expiration' => true } },
          { 'type' => 'BODY', 'text' => 'Oi {{1}}, aproveite.', 'example' => { 'body_text' => [['Ana']] } },
          { 'type' => 'BUTTONS', 'buttons' => [
            { 'type' => 'COPY_CODE', 'text' => 'Copiar código', 'example' => 'PROMO25' },
            { 'type' => 'URL', 'text' => 'Ver proposta', 'url' => 'https://loja.com.br/b/{{1}}', 'example' => ['https://loja.com.br/b/x'] }
          ] }
        ] }
    end
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                message_templates: [template])
    end
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: account, phone_number: '+5511987654321') }
    let(:conversation) do
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511987654321')
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    end
    let(:message) do
      params = { content: 'Oi Ana, aproveite.', private: false,
                 template_params: { name: 'oferta_relampago', language: 'pt_BR', category: 'MARKETING',
                                    processed_params: { body: { '1' => 'Ana' }, limited_time_offer: { expiration_time_ms: 1_798_761_600_000 },
                                                        buttons: [{ type: 'copy_code', parameter: 'SEGREDO9' },
                                                                  { type: 'url', parameter: 'AB3K' }] } } }
      Messages::MessageBuilder.new(agent, conversation, ActionController::Parameters.new(params)).perform
    end

    before { create(:inbox_member, user: agent, inbox: inbox) }

    it 'grava a foto na mensagem e o pedido à Meta continua o mesmo, com o cupom' do
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(enviado_de(message)).to eq(
        'versao' => 1, 'oferta' => { 'expira_em' => 1_798_761_600 },
        'botoes' => [{ 'tipo' => 'copy_code', 'texto' => 'Copiar código' },
                     { 'tipo' => 'url', 'texto' => 'Ver proposta', 'url' => 'https://loja.com.br/b/AB3K' }]
      )
      expect(enviado_de(message).to_json).not_to include('SEGREDO9')
      expect(message.reload.source_id).to eq('wamid.1')
      components = sent.sole.dig('template', 'components')
      expect(components.pluck('type')).to eq(%w[body limited_time_offer button button])
      expect(components[2]).to include('sub_type' => 'copy_code', 'parameters' => [{ 'type' => 'coupon_code', 'coupon_code' => 'SEGREDO9' }])
      expect(sent.to_json).not_to include('enviado', 'versao')
    end

    it 'se a foto falhar, o envio segue sem ela e o log só leva a classe do erro' do
      allow(Whatsapp::Templates::Enviado).to receive(:montar).and_raise(ArgumentError, 'Ana SEGREDO9')
      allow(Rails.logger).to receive(:error)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.source_id).to eq('wamid.1')
      expect(enviado_de(message)).to be_nil
      expect(Rails.logger).to have_received(:error)
        .with("[whatsapp][templates][enviado] foto_nao_gravada message_id=#{message.id} error=ArgumentError")
      expect(Rails.logger).not_to have_received(:error).with(a_string_including('SEGREDO9'))
    end

    it 'sem mensagem (campanha), o processamento não grava nada e a foto sai por foto_do_envio' do
      processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: message.additional_attributes['template_params'])

      expect(processor.foto_do_envio['botoes'].last['url']).to eq('https://loja.com.br/b/AB3K')
      expect { processor.call }.not_to(change { message.reload.additional_attributes })
      expect(enviado_de(message)).to be_nil
    end
  end

  describe 'fora da janela (EnvioForaDaJanela → MessageSender do Followup)' do
    let(:account_and_user) { create_account_and_user }
    let(:account) { account_and_user.first }
    let(:user) { account_and_user.last }
    let(:template) do
      { 'name' => 'retomar_conversa', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'parameter_format' => 'POSITIONAL',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, posso ajudar com {{2}}?', 'example' => { 'body_text' => [%w[Ana seguro]] } },
                         { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Sim, quero' }] }] }
    end
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                message_templates: [template]).inbox
    end

    # O metadata no formato que o `EnvioForaDaJanela::Despacho#metadata` devolve ao Followup.
    let(:metadata) do
      { 'template_name' => 'retomar_conversa', 'template_language' => 'pt_BR', 'template_category' => 'utility',
        'template_params_category' => 'UTILITY', 'template_processed_params' => { 'body' => { '1' => 'Ana', '2' => 'seguro' } },
        'message_body' => 'Oi Ana, posso ajudar com seguro?',
        'envio_fora_da_janela' => { 'tipo' => 'retomar', 'caminho' => 'modelo', 'modelo' => 'retomar_conversa' } }
    end

    # Conversa com a última mensagem do cliente há 30 horas: a janela fechou.
    def expired_conversation(contact)
      contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: '5511987654321').perform
      conversation = ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open', assignee_id: user.id),
                                             contact_inbox: contact_inbox).perform
      create_incoming_message(conversation: conversation)
      conversation.messages.incoming.last.update!(created_at: 30.hours.ago)
      conversation
    end

    def follow_up
      inbox.add_members([user.id])
      contact = account.contacts.create!(name: 'Ana', phone_number: '+5511987654321')
      conversation = expired_conversation(contact)
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact, primary_conversation: conversation,
                                       title: 'Lead')
      account.crm_follow_ups.create!(card: card, conversation: conversation, title: 'Retornar', due_at: 10.minutes.ago, timezone: 'UTC',
                                     automation_mode: :auto_send_message, created_by: user, metadata: metadata)
    end

    it 'a mensagem do Followup leva a foto com o botão de resposta rápida' do
      result = Crm::FollowUps::MessageSender.new(follow_up: follow_up).perform
      expect(result.status).to eq(:sent)

      Whatsapp::SendOnWhatsappService.new(message: result.message).perform

      expect(enviado_de(result.message)).to eq('versao' => 1, 'botoes' => [{ 'tipo' => 'quick_reply', 'texto' => 'Sim, quero' }])
      expect(sent.sole.dig('template', 'name')).to eq('retomar_conversa')
    end
  end

  describe 'aviso do agendamento (Crm::BookingV2::Notices::Sender)' do
    let(:account) { create(:account, locale: 'pt_BR') }
    let(:world) { build_booking_world(account: account) }
    let(:pronto) { Whatsapp::Templates::Finalidades.pronto(:agendamento_ao_marcar) }
    let(:v2) { pronto.corpo.deep_stringify_keys.merge('id' => '902', 'status' => 'APPROVED') }
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                                provider_config: { 'api_key' => 'k', 'phone_number_id' => 'p', 'business_account_id' => 'waba-1' },
                                message_templates: [v2])
    end
    let(:meeting) do
      create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                              metadata: { 'booking_profile_id' => world.profile.id })
    end
    let!(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }

    around do |example|
      with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
        travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
      end
    end

    before do
      account.enable_features('crm_booking_v2')
      account.save!
      world.profile.update!(notice_inbox: channel.inbox)
      allow(Whatsapp::Templates::MetaClient).to receive(:new).and_raise('a Meta não pode ser chamada')
    end

    it 'o aviso leva a foto com o link de gestão resolvido e o "Parar avisos"' do
      notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', status: :sending, attempts: 1,
                                          due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, 'booked'))
      Crm::BookingV2::Notices::Sender.new(notice).perform
      message = Message.find(notice.reload.message_id)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      botoes = enviado_de(message)['botoes']
      code = invite.url.split('/b/').last
      expect(botoes.pluck('tipo')).to eq(%w[url quick_reply])
      expect(botoes.first['url']).to start_with('https://').and end_with("/b/#{code}")
      expect(botoes.last).to eq('tipo' => 'quick_reply', 'texto' => v2['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].last['text'])
    end
  end
end
