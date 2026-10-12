require 'rails_helper'

# Envio do follow-up pelo WhatsApp API do Híbrido (chat#1349). Só a metadata gravada pelos runners de IA
# (delivery_transport) aciona o caminho novo; follow-up manual segue exatamente como antes.
RSpec.describe Crm::FollowUps::MessageSender do
  include CrmHybridHelpers

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { example.run } }

  let!(:scenario) { build_crm_hybrid_scenario }
  let(:ai_metadata) { { 'delivery_transport' => 'whatsapp_api', 'message_body' => 'Oi! Conseguiu ver o orçamento?' } }

  def sender_for(follow_up)
    described_class.new(follow_up: follow_up)
  end

  it 'envia como mensagem de sessão (sem template) quando o transporte é whatsapp_api e o Híbrido está pronto' do
    follow_up = create_crm_hybrid_follow_up(scenario, metadata: ai_metadata)

    result = nil
    expect { result = sender_for(follow_up).perform }.to change(Message, :count).by(1)

    expect(result.status).to eq(:sent)
    expect(result.message.content).to eq('Oi! Conseguiu ver o orçamento?')
    expect(result.message.content_attributes).to include('crm_follow_up_id' => follow_up.id, 'crm_follow_up_transport' => 'whatsapp_api')
    expect(result.message.content_attributes).not_to have_key('template_params')
    expect(follow_up.reload.metadata).to include('sent_message_id' => result.message.id, 'send_mode' => 'session')
    expect(WhatsappHybrid::Router.new(scenario[:conversation]).origin_of(result.message)).to eq('crm_follow_up')
  end

  it 'falha com whatsapp_api_unavailable, sem criar mensagem nem tentar template, quando o Híbrido caiu' do
    scenario[:connection].update!(status: 'disconnected')
    follow_up = create_crm_hybrid_follow_up(scenario, metadata: ai_metadata.merge('template_name' => 'retomada_orcamento'))

    result = nil
    expect { result = sender_for(follow_up).perform }.not_to change(Message, :count)

    expect(result.status).to eq(:failed)
    expect(result.error).to eq('whatsapp_api_unavailable')
    expect(follow_up.reload.metadata).not_to include('sent_message_id')
  end

  it 'falha com whatsapp_api_unavailable quando a origem crm_follow_up foi desligada depois da composição' do
    scenario[:connection].update!(disabled_origins: ['crm_follow_up'])
    follow_up = create_crm_hybrid_follow_up(scenario, metadata: ai_metadata)

    result = sender_for(follow_up).perform

    expect(result.status).to eq(:failed)
    expect(result.error).to eq('whatsapp_api_unavailable')
  end

  it 'se a janela oficial reabriu até o envio, manda a sessão normal sem marcar o transporte' do
    inside = build_crm_hybrid_scenario(last_inbound_ago: 1.hour.ago)
    follow_up = create_crm_hybrid_follow_up(inside, metadata: ai_metadata)

    result = sender_for(follow_up).perform

    expect(result.status).to eq(:sent)
    expect(result.message.content_attributes).to include('crm_follow_up_id' => follow_up.id)
    expect(result.message.content_attributes).not_to have_key('crm_follow_up_transport')
  end

  it 'sem delivery_transport, fora das 24h, o envio continua no caminho de template, mesmo com Híbrido pronto' do
    follow_up = create_crm_hybrid_follow_up(scenario, metadata: { 'message_body' => 'Olá' })

    result = nil
    expect { result = sender_for(follow_up).perform }.not_to change(Message, :count)

    expect(result.status).to eq(:failed)
    expect(result.error).to eq('template_name_required')
  end

  it 'follow-up manual fora das 24h continua exigindo template na criação, mesmo com Híbrido pronto' do
    expect { create_crm_hybrid_follow_up(scenario, source: 'manual', metadata: { 'message_body' => 'Olá' }) }
      .to raise_error(ActiveRecord::RecordInvalid, include('template fallback is required outside the messaging window'))
  end
end
