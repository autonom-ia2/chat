require 'rails_helper'

# Acesso por funil (#1148, parte C): os eventos de chamada de voz (status, SDP, quem ligou) vão só a quem vê a conversa,
# nunca ao canal da conta. Sem nenhuma linha de acesso, os specs de cada serviço (incoming_call_service_spec,
# call_service_spec, call_permission_reply_service_spec) conferem que tudo segue no canal da conta, como antes.
RSpec.describe 'Chamadas de voz com acesso por funil' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create(:user, account: account, role: :agent) }
  let(:sinistro_agent) { create(:user, account: account, role: :agent) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '15550001111') }
  let(:request_wamid) { 'wamid.permission_request_abc' }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open,
                          additional_attributes: { 'call_permission_requested_at' => Time.current.iso8601,
                                                   'call_permission_request_message_id' => request_wamid })
  end
  let(:broadcasts) { [] }

  before do
    account.enable_features!('channel_voice')
    channel.provider_config = channel.provider_config.merge('source' => 'embedded_signup', 'calling_enabled' => true)
    channel.save!
    [[vendas_agent, vendas], [sinistro_agent, sinistro]].each do |user, (pipeline, _stage)|
      create(:inbox_member, inbox: inbox, user: user)
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: pipeline)
    end
    account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'Sinistro', contact: contact, inbox: inbox,
                              primary_conversation: conversation)
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| broadcasts << [stream, payload[:event]] }
  end

  def streams(event)
    broadcasts.select { |_stream, name| name == event }.map(&:first)
  end

  def expect_only_who_sees(event)
    expect(streams(event)).to include(sinistro_agent.pubsub_token, admin.pubsub_token)
    expect(streams(event)).not_to include(vendas_agent.pubsub_token, "account_#{account.id}")
  end

  def whatsapp_call(status: 'ringing')
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: contact, provider: :whatsapp,
                  direction: :incoming, status: status, provider_call_id: 'wacid_abc')
  end

  it 'Call#broadcast_voice_call_event (Twilio e conferência)' do
    whatsapp_call.broadcast_voice_call_event(:ended, status: 'completed')

    expect_only_who_sees('voice_call.ended')
  end

  it 'Whatsapp::CallService (atender, recusar, desligar)' do
    call = whatsapp_call
    provider_service = instance_double(Whatsapp::Providers::WhatsappCloudService, reject_call: true)
    allow(channel).to receive(:provider_service).and_return(provider_service)
    allow(inbox).to receive(:channel).and_return(channel)
    allow(call).to receive(:inbox).and_return(inbox)

    Whatsapp::CallService.new(call: call, agent: sinistro_agent).reject

    expect_only_who_sees('voice_call.ended')
  end

  it 'Whatsapp::CallPermissionReplyService (cliente autorizou a ligação)' do
    conversation
    message = { from: '15550001111', type: 'interactive', context: { id: request_wamid },
                interactive: { type: 'call_permission_reply', call_permission_reply: { response: 'accept', is_permanent: false } } }

    Whatsapp::CallPermissionReplyService.new(inbox: inbox, params: { entry: [{ changes: [{ value: { messages: [message] } }] }] }).perform

    expect_only_who_sees('voice_call.permission_granted')
  end

  it 'Whatsapp::IncomingCallService: a chamada nova não toca para quem o funil esconde' do
    Crm::InboxAgentAccess.find_by(account: account, user: vendas_agent).update!(triage: true)
    params = { calls: [{ id: 'wacid_new', from: '15550002222', event: 'connect', session: { sdp: "v=0\r\n", sdp_type: 'offer' } }] }

    Whatsapp::IncomingCallService.new(inbox: inbox, params: params).perform

    # Conversa nova, sem card: só quem tem a triagem (e o administrador) ouve tocar.
    expect(streams('voice_call.incoming')).to include(vendas_agent.pubsub_token, admin.pubsub_token)
    expect(streams('voice_call.incoming')).not_to include(sinistro_agent.pubsub_token, "account_#{account.id}")
  end
end
