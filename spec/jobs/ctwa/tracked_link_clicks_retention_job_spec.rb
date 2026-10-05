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

  # CA-3.5: os sinais da Meta seguem o card, não a idade do clique.
  describe 'Meta signals of an attributed click' do
    let(:conversation) { create(:conversation, account: account) }
    let(:pipeline) do
      account.crm_pipelines.create!(name: 'Viagem', created_by: create(:user, account: account, role: :administrator), status: :active)
    end
    let(:stage) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'S', position: 0) }
    let!(:old) { travel_to(40.days.ago) { click('EEEE6666', conversation: conversation) } }

    def card(status:, at: Time.current, conversation_id: conversation.id)
      travel_to(at) do
        account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', status: status, conversation_id: conversation_id)
      end
    end

    it 'keeps them while the conversation card is open (form and user agent still go)' do
      card(status: :open)

      described_class.perform_now

      expect(old.reload).to have_attributes(lead_data: {}, user_agent: nil, meta_signals: personal[:meta_signals])
    end

    it 'keeps them while a card linked to the conversation (not primary) is open' do
      linked = card(status: :open, conversation_id: create(:conversation, account: account).id)
      Crm::CardConversation.create!(account: account, card: linked, conversation: conversation)

      described_class.perform_now

      expect(old.reload.meta_signals).to eq(personal[:meta_signals])
    end

    it 'keeps them for a card won within the Meta send window' do
      card(status: :won, at: 2.days.ago)

      described_class.perform_now

      expect(old.reload.meta_signals).to eq(personal[:meta_signals])
    end

    it 'erases them once the card closed longer ago than the Meta send window' do
      card(status: :lost, at: (described_class::SIGNALS_AFTER_CLOSE + 1.day).ago)

      described_class.perform_now

      expect(old.reload.meta_signals).to eq({})
    end

    it 'erases them when the conversation never got a card, even with cards without conversation elsewhere' do
      card(status: :open, conversation_id: nil)

      described_class.perform_now

      expect(old.reload.meta_signals).to eq({})
    end
  end
end
