require 'rails_helper'

# #1335: no disparo, quem falou com a caixa nas últimas 24 h (conferido AGORA) recebe a mensagem escrita; os outros, o
# modelo. A Meta nunca é chamada de verdade (stub_graph_messages).
RSpec.describe CampaignJourney::ConversaAberta::Envio, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:content) do
    "Nome,Celular,Link da oferta\nAna Souza,11987654321,https://x.com/ana\nBia Lima,21987654321,https://x.com/bia\n" \
      "Caio Reis,31987654321,\n"
  end
  let(:audience) { saved_audience(account: account, user: user, content: content) }
  let(:texto) { 'Oi, {{cliente.primeiro_nome}}! Suas peças: {{publico.Link_da_oferta}}. Quer ver?' }

  before { account.enable_features!(:campaign_open_window_text) }

  def contato(nome)
    audience.campaign_import_rows.includes(:contact).map(&:contact).find { |contact| contact.name == nome }
  end

  def falou(nome, at: 1.hour.ago)
    contact = contato(nome)
    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) { |ci| ci.source_id = contact.phone_number.delete('+') }
    conversation = Conversation.find_by(contact_inbox: contact_inbox) ||
                   create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming, created_at: at)
    conversation
  end

  def campanha(free_text: texto)
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], message: 'Olá {{1}}, sua apólice vence em {{2}}. {{3}}',
                                 template_params: journey_template_params)
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, variable_defaults: {},
                                 variable_bindings: { '1' => { 'source' => 'contact', 'value' => 'first_name' },
                                                      '2' => { 'source' => 'fixed', 'value' => '10/2026' },
                                                      '3' => { 'source' => 'fixed', 'value' => 'Equipe' } })
    CampaignFreeText.create!(account: account, campaign: campaign, content: free_text) if free_text
    campaign
  end

  def disparar(campaign)
    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
  end

  def por_numero(sent)
    sent.index_by { |body| body['to'] }
  end

  it 'quem falou nas últimas 24 h recebe a mensagem escrita com os campos dela; os outros, o modelo' do
    sent = stub_graph_messages
    conversa = falou('Ana Souza')
    falou('Bia Lima', at: 30.hours.ago)
    campaign = campanha

    disparar(campaign)

    envios = por_numero(sent)
    expect(envios['+5511987654321']).to include('type' => 'text', 'text' => { 'body' => 'Oi, Ana! Suas peças: https://x.com/ana. Quer ver?' })
    expect(envios['+5521987654321']['type']).to eq('template')
    expect(envios['+5531987654321']['type']).to eq('template')
    ana = CampaignRecipient.find_by(campaign: campaign, contact: contato('Ana Souza'))
    expect(ana).to have_attributes(status: 'sent', message_content: 'Oi, Ana! Suas peças: https://x.com/ana. Quer ver?')
    expect(CampaignFreeTextDelivery.find_by(campaign_recipient_id: ana.id)).to have_attributes(source_id: ana.source_id, fell_back_at: nil)
    registrada = conversa.messages.outgoing.last
    expect(registrada.content).to eq('Oi, Ana! Suas peças: https://x.com/ana. Quer ver?')
    expect(registrada.additional_attributes).to eq('campaign_id' => campaign.id, 'campaign_free_text' => true)
  end

  it 'falta o valor de um campo: vai o modelo, nunca texto pela metade' do
    sent = stub_graph_messages
    falou('Caio Reis')

    disparar(campanha)

    expect(por_numero(sent)['+5531987654321']['type']).to eq('template')
    expect(CampaignFreeTextDelivery.count).to eq(0)
  end

  it 'sem a flag da conta, todos recebem o modelo' do
    sent = stub_graph_messages
    falou('Ana Souza')
    account.disable_features!(:campaign_open_window_text)

    disparar(campanha)

    expect(sent.pluck('type').uniq).to eq(['template'])
  end

  it 'sem mensagem escrita, todos recebem o modelo' do
    sent = stub_graph_messages
    falou('Ana Souza')

    disparar(campanha(free_text: nil))

    expect(sent.pluck('type').uniq).to eq(['template'])
  end

  it 'a Meta recusa o texto na hora: a pessoa recebe o modelo no mesmo disparo' do
    sent = stub_graph_messages(failing: ['+5511987654321'])
    falou('Ana Souza')

    disparar(campanha)

    expect(sent.select { |body| body['to'] == '+5511987654321' }.pluck('type')).to eq(%w[text template])
  end

  it 'erro ao montar o texto: vai o modelo, nunca falha a pessoa' do
    sent = stub_graph_messages
    falou('Ana Souza')
    allow(CampaignJourney::ConversaAberta::Texto).to receive(:preencher).and_raise(ArgumentError)
    allow(Rails.logger).to receive(:error)

    disparar(campanha)

    expect(por_numero(sent)['+5511987654321']['type']).to eq('template')
  end

  it 'a Meta aceitou o texto e o registro falhou: a pessoa fica sent, sem modelo extra' do
    sent = stub_graph_messages
    falou('Ana Souza')
    campaign = campanha
    allow(CampaignFreeTextDelivery).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    allow(Rails.logger).to receive(:error)

    disparar(campaign)

    expect(sent.select { |body| body['to'] == '+5511987654321' }.pluck('type')).to eq(%w[text])
    expect(CampaignRecipient.find_by(campaign: campaign, contact: contato('Ana Souza'))).to be_sent
  end

  describe 'aviso 131047 da Meta (janela fechada depois do envio)' do
    def aviso(source_id, code)
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: {
        phone_number: channel.phone_number, object: 'whatsapp_business_account',
        entry: [{ changes: [{ field: 'messages', value: { statuses: [{
          id: source_id, status: 'failed', recipient_id: '5511987654321', timestamp: Time.current.to_i.to_s,
          errors: [{ code: code, title: 'Re-engagement message' }]
        }] } }] }]
      }.with_indifferent_access).perform
    end

    it 'manda o modelo uma vez só para quem o texto não alcançou' do
      sent = stub_graph_messages
      falou('Ana Souza')
      campaign = campanha
      disparar(campaign)
      ana = CampaignRecipient.find_by(campaign: campaign, contact: contato('Ana Souza'))
      texto_id = ana.source_id

      perform_enqueued_jobs { 2.times { aviso(texto_id, 131_047) } }

      para_ana = sent.select { |body| body['to'] == '+5511987654321' }
      expect(para_ana.pluck('type')).to eq(%w[text template])
      expect(ana.reload).to be_sent
      expect(ana.source_id).not_to eq(texto_id)
      expect(CampaignFreeTextDelivery.find_by(source_id: texto_id).fell_back_at).to be_present
    end

    it 'campanha parada: o modelo não sai, e a pessoa fica com o motivo' do
      sent = stub_graph_messages
      falou('Ana Souza')
      campaign = campanha
      disparar(campaign)
      ana = CampaignRecipient.find_by(campaign: campaign, contact: contato('Ana Souza'))
      CampaignPauses::Pauser.new(campaign, source: 'manual', reason_code: 'manual').perform

      perform_enqueued_jobs { aviso(ana.source_id, 131_047) }

      expect(sent.select { |body| body['to'] == '+5511987654321' }.pluck('type')).to eq(%w[text])
      expect(ana.reload).to be_failed
      expect(ana.error_message).to eq(described_class::PAUSADA)
    end

    it 'outro erro da Meta não troca para o modelo' do
      sent = stub_graph_messages
      falou('Ana Souza')
      campaign = campanha
      disparar(campaign)
      texto_id = CampaignRecipient.find_by(campaign: campaign, contact: contato('Ana Souza')).source_id

      perform_enqueued_jobs { aviso(texto_id, 131_026) }

      expect(sent.select { |body| body['to'] == '+5511987654321' }.pluck('type')).to eq(%w[text])
    end
  end
end
