require 'rails_helper'

# Retenção do dado pessoal dos cliques de página (#1011, docs/crm/ponte-lp-atribuicao.md).
RSpec.describe Ctwa::TrackedLinkClicksRetentionJob do
  let(:account) { create(:account) }
  let(:tracked_link) { create(:ctwa_tracked_link, account: account, usage: 'website', allowed_origins: ['https://placement.com.br']) }
  let(:personal) do
    { lead_data: { 'fields' => [{ 'key' => 'nome', 'label' => 'Nome', 'value' => 'Maria' }] },
      meta_signals: { 'fbc' => 'fb.1.1759650000000.IwAR123', 'client_ip_address' => '200.1.2.3' }, user_agent: 'iPhone' }
  end

  def click(token, **attributes)
    create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: token,
                                     params: { 'utm_campaign' => 'Viagem' }, campaign_key: 'c:1', **personal, **attributes)
  end

  it 'apaga formulário e sinais de clique expirado sem conversa, mantendo a linha e a campanha' do
    expired = click('AAAA2222', expires_at: 1.minute.ago)

    described_class.perform_now

    expect(expired.reload).to have_attributes(lead_data: {}, meta_signals: {}, user_agent: nil, campaign_key: 'c:1',
                                              params: { 'utm_campaign' => 'Viagem' })
  end

  it 'mantém o clique ainda ativo intacto' do
    active = click('BBBB3333')

    described_class.perform_now

    expect(active.reload).to have_attributes(personal)
  end

  it 'apaga os dados do clique atribuído só depois da janela de retenção' do
    conversation = create(:conversation, account: account)
    recent = click('CCCC4444', conversation: conversation)
    old = travel_to((described_class::ATTRIBUTED_RETENTION + 1.day).ago) { click('DDDD5555', conversation: conversation) }

    described_class.perform_now

    expect(recent.reload).to have_attributes(personal)
    expect(old.reload).to have_attributes(lead_data: {}, meta_signals: {}, user_agent: nil, conversation_id: conversation.id)
  end
end
