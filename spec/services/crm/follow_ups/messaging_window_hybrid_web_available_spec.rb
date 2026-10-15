require 'rails_helper'

# MessagingWindow#hybrid_web_available?: o texto livre do CRM pode sair pelo WhatsApp API (chat#1349)?
RSpec.describe Crm::FollowUps::MessagingWindow, '#hybrid_web_available?' do
  include CrmHybridHelpers

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { example.run } }

  let(:scenario) { build_crm_hybrid_scenario }
  let(:conversation) { scenario[:conversation] }

  it 'é verdadeiro fora das 24h com o Híbrido pronto e a origem crm_follow_up ligada' do
    window = described_class.new(conversation)

    expect(window.can_send_session_message?).to be(false)
    expect(window.requires_template?).to be(true)
    expect(window.hybrid_web_available?).to be(true)
  end

  it 'é falso dentro das 24h: ali a sessão oficial resolve e o Híbrido não entra' do
    inside = build_crm_hybrid_scenario(last_inbound_ago: 1.hour.ago)
    window = described_class.new(inside[:conversation])

    expect(window.can_send_session_message?).to be(true)
    expect(window.hybrid_web_available?).to be(false)
  end

  it 'é falso quando a origem crm_follow_up está desligada, mesmo com as outras ligadas' do
    scenario[:connection].update!(disabled_origins: ['crm_follow_up'])

    expect(described_class.new(conversation).hybrid_web_available?).to be(false)
  end

  it 'é falso quando a sessão não está conectada' do
    scenario[:connection].update!(status: 'disconnected')

    expect(described_class.new(conversation).hybrid_web_available?).to be(false)
  end

  it 'é falso com o WhatsApp API pausado na aba (#1487): o follow-up volta para o modelo aprovado' do
    scenario[:connection].update!(paused_at: Time.current)
    window = described_class.new(conversation)

    expect(window.hybrid_web_available?).to be(false)
    expect(window.requires_template?).to be(true)
  end

  it 'é falso quando o aceite de risco foi retirado' do
    scenario[:connection].update!(risk_accepted_at: nil)

    expect(described_class.new(conversation).hybrid_web_available?).to be(false)
  end

  it 'é falso quando o número conectado não é o da caixa' do
    scenario[:connection].update!(connected_phone: '5511000000000')

    expect(described_class.new(conversation).hybrid_web_available?).to be(false)
  end

  it 'é falso com o roteamento do Híbrido desligado na conexão ou no kill switch global' do
    expect(described_class.new(conversation).hybrid_web_available?).to be(true)

    scenario[:connection].update!(routing_enabled: false)
    expect(described_class.new(conversation).hybrid_web_available?).to be(false)

    scenario[:connection].update!(routing_enabled: true)
    with_modified_env(WHATSAPP_HYBRID_ROUTING_ENABLED: 'false') do
      expect(described_class.new(conversation).hybrid_web_available?).to be(false)
    end
  end

  it 'é falso para contato sem telefone' do
    scenario[:contact].update!(phone_number: nil)

    expect(described_class.new(conversation.reload).hybrid_web_available?).to be(false)
  end

  it 'é falso sem conexão híbrida na caixa' do
    plain = build_crm_hybrid_scenario(hybrid: false)

    expect(described_class.new(plain[:conversation]).hybrid_web_available?).to be(false)
  end

  it 'é falso para caixa que não é WhatsApp Oficial' do
    account, user = create_account_and_user
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511987654321')
    api_conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: api_conversation)
    api_conversation.messages.incoming.last.update!(created_at: 30.hours.ago)

    expect(described_class.new(api_conversation).hybrid_web_available?).to be(false)
  end

  it 'fora do piloto não consulta o banco além do que o Config já responde' do
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '999999') do
      expect(WhatsappHybrid::Connection).not_to receive(:exists?)
      expect(WhatsappHybrid::Connection).not_to receive(:find_by)

      expect(described_class.new(conversation).hybrid_web_available?).to be(false)
    end
  end
end
