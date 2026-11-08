require 'rails_helper'

# Pedido em uma frase (#2696): a IA da conta (credencial do Kanban CRM) preenche os campos; valor fora da tela sai.
RSpec.describe Autonomia::Prospecting::SearchInterpreter do
  let(:account) { create(:account) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:blank_answer) do
    { 'understood' => true, 'what' => nil, 'where' => nil, 'rating_min' => nil, 'rating_max' => nil, 'reviews_min' => nil,
      'has_website' => nil, 'has_photos' => nil, 'open_now' => nil, 'has_opening_hours' => nil, 'weak_presence' => false,
      'left_out' => nil }
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def answer_with(fields)
    allow(client).to receive(:create).and_return({ text: blank_answer.merge(fields).to_json, usage: {} })
  end

  def interpret(text = 'padarias perto da Paulista com nota boa')
    described_class.new(account: account, text: text).perform
  end

  it 'preenche o quê, onde e os ajustes, pela credencial da conta, numa tentativa só' do
    answer_with('what' => 'padarias', 'where' => 'Avenida Paulista, São Paulo', 'rating_min' => '4', 'has_website' => 'no',
                'left_out' => 'Não dá para escolher pelo horário que abre.')

    expect(interpret).to eq(
      status: 'understood', what: 'padarias', where: 'Avenida Paulista, São Paulo',
      advanced_filters: { 'rating_min' => '4', 'has_website' => 'no' }, score_mode: 'general',
      left_out: 'Não dá para escolher pelo horário que abre.'
    )
    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(credential: hash_including(api_key: 'chave-da-conta'), feature: 'prospeccao_frase', account: account, max_retries: 0)
    expect(client).to have_received(:create).with(hash_including(schema: described_class.schema, timeout: described_class::TIMEOUT))
  end

  it 'presença fraca vira o modo gbp' do
    answer_with('what' => 'restaurantes', 'weak_presence' => true)

    expect(interpret).to include(score_mode: 'gbp', where: nil)
  end

  it 'descarta valor e chave fora do conjunto da tela' do
    answer_with('what' => 'academias', 'rating_min' => '2', 'reviews_min' => '1000', 'open_now' => 'no', 'has_photos' => 'yes',
                'outside_top' => '10')

    expect(interpret[:advanced_filters]).to eq('has_photos' => 'yes')
  end

  it 'nota mínima e máxima juntas se contradizem: saem as duas' do
    answer_with('what' => 'clínicas', 'rating_min' => '4', 'rating_max' => '3.9')

    expect(interpret[:advanced_filters]).to eq({})
  end

  it '"não entendi" da IA não preenche nada' do
    answer_with('understood' => false, 'what' => 'oi')

    expect(interpret).to eq(status: 'not_understood', what: nil, where: nil, advanced_filters: {}, score_mode: 'general', left_out: nil)
  end

  it 'entendeu sem o quê nem o onde também é "não entendi"' do
    answer_with('rating_min' => '4')

    expect(interpret[:status]).to eq('not_understood')
  end

  it 'erro, tempo esgotado ou JSON quebrado da IA viram ai_failed' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('timeout', tempo_esgotado: true))
    expect { interpret }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('ai_failed') }

    allow(client).to receive(:create).and_return({ text: '["não é objeto"]', usage: {} })
    expect { interpret }.to raise_error(described_class::Error) { |error| expect(error.status).to eq(:service_unavailable) }
  end

  it 'conta sem a IA do Kanban CRM não chama ninguém' do
    account.hooks.destroy_all

    expect { interpret }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('ai_not_configured') }
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'recusa a frase vazia ou longa demais sem chamar a IA' do
    expect { interpret('   ') }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('text_blank') }
    expect { interpret('a' * 301) }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('text_too_long') }
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end
end
