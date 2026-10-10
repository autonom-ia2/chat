require 'rails_helper'

RSpec.describe Crm::Ai::AttributeExtractorApplier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:stage) { pipeline.stages.first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      contact: contact,
      primary_conversation: conversation,
      currency: 'BRL'
    )
  end

  def create_attribute(key:, model:, type:, values: nil)
    create(
      :custom_attribute_definition,
      account: account,
      attribute_key: key,
      attribute_model: model,
      attribute_display_type: type,
      attribute_values: values
    )
  end

  describe 'campos do card (#1146)' do
    let(:second_card) do
      account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'HB20', contact: contact, primary_conversation: conversation,
                                currency: 'BRL')
    end

    def extract(target_card, card_items: [], contact_items: [])
      described_class.new(card: target_card, extracted_attributes: { contact: contact_items, conversation: [], card: card_items },
                          prefix: '').perform
    end

    def item(key, value)
      { key: key, value: value, confidence: 0.9, evidence: value }
    end

    it 'dois cards da mesma conversa guardam valores diferentes no mesmo campo, sem um sobrescrever o outro' do
      create_attribute(key: 'placa', model: 'card_attribute', type: 'text')

      extract(card, card_items: [item('placa', 'ABC1D23')])
      # O segundo pedido vira o assunto atual da conversa, e a IA avalia o card dele.
      Crm::Cards::Focus.new(account: account, card: second_card, conversation: conversation).perform
      extract(second_card, card_items: [item('placa', 'XYZ9K87')])

      expect(card.reload.custom_attributes).to eq('placa' => 'ABC1D23')
      expect(second_card.reload.custom_attributes).to eq('placa' => 'XYZ9K87')
      expect(contact.reload.custom_attributes).not_to have_key('placa')
    end

    it 'dado da pessoa continua no contato, mesmo com a mesma chave existindo no card' do
      create_attribute(key: 'cidade', model: 'contact_attribute', type: 'text')
      create_attribute(key: 'cidade', model: 'card_attribute', type: 'text')

      result = extract(card, contact_items: [item('cidade', 'Campinas')], card_items: [item('cidade', 'Sorocaba')])

      expect(result.applied.pluck(:target)).to contain_exactly('contact', 'card')
      expect(contact.reload.custom_attributes['cidade']).to eq('Campinas')
      expect(card.reload.custom_attributes['cidade']).to eq('Sorocaba')
      expect(card.metadata.dig('ai', 'extracted_attributes').keys).to contain_exactly('cidade', 'card:cidade')
    end

    it 'card que não é o assunto atual da conversa não recebe campo de card' do
      create_attribute(key: 'placa', model: 'card_attribute', type: 'text')
      Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: 2.hours.ago)
      Crm::CardConversation.find_or_create_by!(account: account, card: second_card, conversation: conversation)
                           .update!(focused_at: 1.minute.ago)

      result = extract(card, card_items: [item('placa', 'XYZ9K87')])

      expect(card.reload.custom_attributes).to eq({})
      expect(result.rejected).to contain_exactly(hash_including(key: 'placa', reason: 'not_current_subject'))
    end

    it 'não sobrescreve campo do card já preenchido e recusa chave que não é de card' do
      create_attribute(key: 'placa', model: 'card_attribute', type: 'text')
      create_attribute(key: 'cpf_titular', model: 'contact_attribute', type: 'text')
      card.update!(custom_attributes: { 'placa' => 'ABC1D23' })

      result = extract(card, card_items: [item('placa', 'OUTRA99'), item('cpf_titular', '123')])

      expect(card.reload.custom_attributes).to eq('placa' => 'ABC1D23')
      expect(result.rejected).to contain_exactly(hash_including(key: 'placa', reason: 'already_filled'),
                                                 hash_including(key: 'cpf_titular', reason: 'unknown_key'))
    end
  end

  it 'fills empty contact and conversation attributes with coerced values and audit metadata' do
    create_attribute(key: 'sw_cidade', model: 'contact_attribute', type: 'text')
    create_attribute(key: 'sw_valor_conta_luz', model: 'contact_attribute', type: 'number')
    create_attribute(key: 'sw_decisor', model: 'contact_attribute', type: 'list', values: ['Sim, decide', 'Há outros decisores'])
    create_attribute(key: 'sw_agenda_confirmada', model: 'conversation_attribute', type: 'checkbox')

    result = described_class.new(
      card: card,
      prefix: 'sw_',
      extracted_attributes: {
        contact: [
          { key: 'sw_cidade', value: 'Guarapuava', confidence: 0.9, evidence: 'Sou de Guarapuava' },
          { key: 'sw_valor_conta_luz', value: '3000.0', confidence: 0.9, evidence: 'conta dá 3 mil' },
          { key: 'sw_decisor', value: 'Há outros decisores', confidence: 0.8, evidence: 'decido com meu sócio' }
        ],
        conversation: [
          { key: 'sw_agenda_confirmada', value: false, confidence: 0.9, evidence: 'ainda não confirmei agenda' }
        ]
      }
    ).perform

    expect(result.rejected).to be_empty
    expect(contact.reload.custom_attributes).to include(
      'sw_cidade' => 'Guarapuava',
      'sw_valor_conta_luz' => 3000,
      'sw_decisor' => 'Há outros decisores'
    )
    expect(conversation.reload.custom_attributes).to include('sw_agenda_confirmada' => false)
    expect(card.reload.metadata.dig('ai', 'extracted_attributes', 'sw_cidade')).to include(
      'target' => 'contact',
      'source' => 'ai',
      'evidence' => 'Sou de Guarapuava'
    )
  end

  it 'does not overwrite an already filled custom attribute' do
    create_attribute(key: 'sw_cidade', model: 'contact_attribute', type: 'text')
    contact.update!(custom_attributes: { 'sw_cidade' => 'Curitiba' })

    result = described_class.new(
      card: card,
      prefix: 'sw_',
      extracted_attributes: {
        contact: [{ key: 'sw_cidade', value: 'Guarapuava', confidence: 0.95, evidence: 'Sou de Guarapuava' }],
        conversation: []
      }
    ).perform

    expect(contact.reload.custom_attributes['sw_cidade']).to eq('Curitiba')
    expect(result.rejected).to include(hash_including(key: 'sw_cidade', reason: 'already_filled'))
  end

  it 'rejects unknown keys, non-whitelisted keys, low confidence, invalid numbers and invalid list values' do
    create_attribute(key: 'sw_valor_conta_luz', model: 'contact_attribute', type: 'number')
    create_attribute(key: 'sw_decisor', model: 'contact_attribute', type: 'list', values: ['Sim, decide'])
    create_attribute(key: 'other_city', model: 'contact_attribute', type: 'text')

    result = described_class.new(
      card: card,
      prefix: 'sw_',
      extracted_attributes: {
        contact: [
          { key: 'sw_inexistente', value: 'x', confidence: 0.9, evidence: 'x' },
          { key: 'other_city', value: 'Guarapuava', confidence: 0.9, evidence: 'cidade' },
          { key: 'sw_valor_conta_luz', value: 'tres mil', confidence: 0.9, evidence: 'valor' },
          { key: 'sw_decisor', value: 'Há outros decisores', confidence: 0.9, evidence: 'decisor' },
          { key: 'sw_valor_conta_luz', value: 3000, confidence: 0.4, evidence: 'valor' }
        ],
        conversation: []
      }
    ).perform

    expect(contact.reload.custom_attributes).to be_empty
    expect(result.rejected).to include(
      hash_including(key: 'sw_inexistente', reason: 'unknown_key'),
      hash_including(key: 'other_city', reason: 'not_whitelisted'),
      hash_including(key: 'sw_valor_conta_luz', reason: 'invalid_value'),
      hash_including(key: 'sw_decisor', reason: 'invalid_value'),
      hash_including(key: 'sw_valor_conta_luz', reason: 'low_confidence')
    )
  end

  it 'fills attributes without any prefix when the pipeline configures no prefix' do
    create_attribute(key: 'cpf', model: 'contact_attribute', type: 'text')
    create_attribute(key: 'tempo_de_conducao', model: 'contact_attribute', type: 'text')

    result = described_class.new(
      card: card,
      prefix: '',
      extracted_attributes: {
        contact: [
          { key: 'cpf', value: '123.456.789-00', confidence: 0.9, evidence: 'meu CPF é 123.456.789-00' },
          { key: 'tempo_de_conducao', value: 'desde 2009', confidence: 0.9, evidence: 'habilitado desde 2009' },
          { key: 'inexistente', value: 'x', confidence: 0.9, evidence: 'x' }
        ],
        conversation: []
      }
    ).perform

    expect(contact.reload.custom_attributes).to include(
      'cpf' => '123.456.789-00',
      'tempo_de_conducao' => 'desde 2009'
    )
    expect(result.rejected).to contain_exactly(hash_including(key: 'inexistente', reason: 'unknown_key'))
  end

  it 'rejects a key sent in the wrong contact/conversation group' do
    create_attribute(key: 'sw_cidade', model: 'contact_attribute', type: 'text')

    result = described_class.new(
      card: card,
      prefix: 'sw_',
      extracted_attributes: {
        contact: [],
        conversation: [{ key: 'sw_cidade', value: 'Guarapuava', confidence: 0.9, evidence: 'Sou de Guarapuava' }]
      }
    ).perform

    expect(conversation.reload.custom_attributes).to be_empty
    expect(result.rejected).to include(hash_including(target: 'conversation', key: 'sw_cidade', reason: 'unknown_key'))
  end
end
