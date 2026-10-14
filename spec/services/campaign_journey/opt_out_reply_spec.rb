require 'rails_helper'

# #1449: a primeira resposta do cliente a uma mensagem de campanha do WhatsApp pedindo para parar marca o contato
# (origem campaign_reply). Quem decide é o modelo (simulado aqui, sem chamada paga); o spec prova quando ele é chamado,
# o que é gravado em cada decisão e que o texto do cliente nunca vai ao log.
RSpec.describe CampaignJourney::OptOutReply do
  let(:account) { create(:account) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511987650001') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:campaign_text) { 'Oi! Temos condição especial de renovação este mês.' }

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    Redis::Alfred.scan_each(match: 'campaign_journey:opt_out_reply:*') { |key| Redis::Alfred.delete(key) }
  end

  def outgoing(content, attributes: {}, at: 1.hour.ago, to: conversation)
    to.messages.create!(account_id: account.id, inbox_id: to.inbox_id, message_type: :outgoing, content: content,
                        additional_attributes: attributes, created_at: at, updated_at: at)
  end

  def campaign_message(attributes: { 'campaign_id' => 7 }, at: 1.hour.ago, to: conversation)
    outgoing(campaign_text, attributes: attributes, at: at, to: to)
  end

  def incoming(content, at: Time.current, to: conversation, content_attributes: {})
    to.messages.create!(account_id: account.id, inbox_id: to.inbox_id, message_type: :incoming, content: content,
                        sender: to.contact, content_attributes: content_attributes, created_at: at, updated_at: at)
  end

  def model_answers(decision, motivo)
    allow(client).to receive(:create).and_return(text: { pediu_para_parar: decision, motivo: motivo }.to_json)
  end

  it '"sim": marca o contato com a origem campaign_reply, sem autor' do
    campaign_message
    model_answers('sim', 'pedido_explicito_de_parar')

    described_class.new(incoming('Por favor, não me mandem mais isso')).perform

    contact.reload
    expect(contact).to be_opted_out
    expect(contact.opt_out_source).to eq('campaign_reply')
    expect(contact.opted_out_by_id).to be_nil
  end

  it 'pergunta pela feature própria, com a campanha como contexto, e loga só ids e códigos' do
    campaign_message
    reply = incoming('Por favor, não me mandem mais isso')
    model_answers('sim', 'pedido_explicito_de_parar')
    allow(Rails.logger).to receive(:info)

    described_class.new(reply).perform

    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'campanha_opt_out', account: account))
    expect(client).to have_received(:create) do |args|
      expect(JSON.parse(args[:input])).to eq('reply' => 'Por favor, não me mandem mais isso', 'previous_message' => campaign_text)
    end
    expect(Rails.logger).to have_received(:info).with(
      "[campaign_journey][opt_out_reply] account=#{account.id} conversation=#{conversation.id} message=#{reply.id} " \
      'decisao=sim motivo=pedido_explicito_de_parar'
    )
    expect(Rails.logger).not_to have_received(:info).with(a_string_including('não me mandem'))
  end

  it '"nao" e "nao_se_aplica" não marcam o contato' do
    campaign_message
    model_answers('nao', 'ambigua')
    described_class.new(incoming('agora não, obrigado')).perform
    expect(contact.reload).not_to be_opted_out

    other = create(:contact, account: account, phone_number: '+5511987650002')
    other_conversation = create(:conversation, account: account, inbox: inbox, contact: other)
    campaign_message(to: other_conversation)
    model_answers('nao_se_aplica', 'sem_texto_interpretavel')
    described_class.new(incoming('👍', to: other_conversation)).perform
    expect(other.reload).not_to be_opted_out
  end

  it 'aceita a marca da campanha da WhatsApp API (whatsapp_api_campaign_id) numa caixa API' do
    api_inbox = create(:channel_api, account: account).inbox
    api_conversation = create(:conversation, account: account, inbox: api_inbox, contact: contact)
    campaign_message(attributes: { 'whatsapp_api_campaign_id' => 3 }, to: api_conversation)
    model_answers('sim', 'recusa_de_contato')

    described_class.new(incoming('SAIR', to: api_conversation)).perform

    expect(contact.reload.opt_out_source).to eq('campaign_reply')
  end

  it 'reconhece a mensagem da campanha gravada depois, na resposta, com a data do envio (SentMessageRecorder#record_at_reply)' do
    reply = incoming('parem de mandar')
    campaign_message(at: 2.hours.ago)
    model_answers('sim', 'pedido_explicito_de_parar')

    described_class.new(reply).perform

    expect(contact.reload).to be_opted_out
    expect(client).to have_received(:create) do |args|
      expect(JSON.parse(args[:input])['previous_message']).to eq(campaign_text)
    end
  end

  it 'foto sem texto antes do pedido não conta como a primeira resposta' do
    campaign_message
    incoming(nil, at: 5.minutes.ago)
    model_answers('sim', 'pedido_explicito_de_parar')

    described_class.new(incoming('SAIR')).perform

    expect(contact.reload.opt_out_source).to eq('campaign_reply')
  end

  it 'sem vaga no dia, a tentativa seguinte também não chama o modelo' do
    stub_const("#{described_class}::DAILY_LIMIT", 0)
    campaign_message
    reply = incoming('para de mandar')
    model_answers('sim', 'pedido_explicito_de_parar')

    2.times { described_class.new(reply).perform }

    expect(client).not_to have_received(:create)
  end

  describe 'quando o modelo não é chamado' do
    before { model_answers('sim', 'pedido_explicito_de_parar') }

    def expect_untouched(reply)
      described_class.new(reply).perform
      expect(client).not_to have_received(:create)
      expect(contact.reload).not_to be_opted_out
    end

    it 'segunda resposta depois da mesma campanha' do
      campaign_message
      incoming('Quanto custa?', at: 30.minutes.ago)
      expect_untouched(incoming('para de mandar'))
    end

    it 'a última mensagem antes da resposta não é de campanha (alguém da equipe escreveu depois)' do
      campaign_message(at: 2.hours.ago)
      outgoing('Posso ajudar?', at: 1.hour.ago)
      expect_untouched(incoming('para de mandar'))
    end

    it 'conversa sem campanha' do
      outgoing('Bom dia!')
      expect_untouched(incoming('para de mandar'))
    end

    it 'campanha mais antiga que a janela' do
      campaign_message(at: (described_class::WINDOW + 1.hour).ago)
      expect_untouched(incoming('para de mandar'))
    end

    it 'resposta de botão (content_attributes.selected_option): o botão tem o caminho dele, sem IA' do
      campaign_message
      expect_untouched(incoming('Parar avisos', content_attributes: { selected_option: { id: 'stop_notices' } }))
    end

    it 'mensagem sem texto (só mídia)' do
      campaign_message
      expect_untouched(incoming(nil))
    end

    it 'caixa que não é WhatsApp' do
      email_inbox = create(:channel_email, account: account).inbox
      email_conversation = create(:conversation, account: account, inbox: email_inbox, contact: contact)
      campaign_message(to: email_conversation)
      expect_untouched(incoming('para de mandar', to: email_conversation))
    end

    it 'contato que já recusou, por qualquer origem: a origem fica como estava' do
      contact.opt_out!(source: 'manual')
      campaign_message
      described_class.new(incoming('para de mandar')).perform
      expect(client).not_to have_received(:create)
      expect(contact.reload.opt_out_source).to eq('manual')
    end

    it 'teto diário da conta atingido: não chama, não marca e loga o motivo' do
      stub_const("#{described_class}::DAILY_LIMIT", 0)
      campaign_message
      reply = incoming('para de mandar')
      allow(Rails.logger).to receive(:warn)

      expect_untouched(reply)
      expect(Rails.logger).to have_received(:warn).with(
        "[campaign_journey][opt_out_reply] account=#{account.id} conversation=#{conversation.id} message=#{reply.id} limite_diario"
      )
    end
  end

  it 'a decisão fica guardada por mensagem: rodar de novo não paga outra chamada nem conta no teto' do
    campaign_message
    reply = incoming('não quero mais')
    model_answers('nao', 'ambigua')

    2.times { described_class.new(reply).perform }

    expect(client).to have_received(:create).once
    expect(Redis::Alfred.get(described_class.counter_key(account.id)).to_i).to eq(1)
  end

  it 'o custo aparece na Gestão IA, em Campanhas' do
    expect(Crm::Reports::AiUsage.resource_for_feature(described_class::FEATURE)).to eq('Campanhas')
  end

  describe '#applicable?' do
    it 'é verdadeiro só para a primeira resposta a uma campanha recente' do
      campaign_message
      first = incoming('oi', at: 10.minutes.ago)
      second = incoming('tudo bem?')

      expect(described_class.new(first)).to be_applicable
      expect(described_class.new(second)).not_to be_applicable
    end
  end
end
