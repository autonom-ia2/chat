require 'rails_helper'

# Sugestão do modelo de cada aviso (#1272): só candidatos que o envio aceita, a IA escolhe (simulada, sem chamada
# paga), "nenhum serve" e falha da IA.
RSpec.describe Crm::BookingV2::NoticeTemplates::Suggester do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:good) { template('lembrete_horario', 'Oi {{1}}, seu horário é {{2}}. Gerencie em {{3}} quando quiser.') }
  let(:list) do
    [
      good,
      template('sem_link', 'Oi {{1}}, seu horário é {{2}}.'),
      template('quatro_variaveis', 'Oi {{1}}, {{2}} com {{4}}: {{3}} ok.'),
      template('pendente', 'Oi {{1}}, {{2}}: {{3}} ok.', status: 'PENDING'),
      template('autenticacao', 'Código {{1}} {{2}} {{3}} ok.', category: 'AUTHENTICATION'),
      template('topo_imagem', 'Oi {{1}}, {{2}}: {{3}} ok.', components: [{ 'type' => 'HEADER', 'format' => 'IMAGE' }])
    ]
  end

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  def template(name, body, status: 'APPROVED', category: 'UTILITY', components: [])
    { 'name' => name, 'language' => 'pt_BR', 'status' => status, 'category' => category,
      'components' => [{ 'type' => 'BODY', 'text' => body }] + components }
  end

  before do
    channel.update_columns(message_templates: list) # rubocop:disable Rails/SkipsModelValidations
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def answer(choices)
    allow(client).to receive(:create).and_return(text: { choices: choices }.to_json)
  end

  def suggest(kinds = %w[booked day_before])
    described_class.new(account: account, inbox: inbox, kinds: kinds).perform
  end

  it 'manda à IA só os modelos que o envio aceita e devolve a escolha com o motivo' do
    answer([{ kind: 'booked', index: 0, reason: 'Fala do horário marcado.' }, { kind: 'day_before', index: 0, reason: 'Serve de lembrete.' }])

    result = suggest

    expect(result).to eq(
      'booked' => { name: 'lembrete_horario', language: 'pt_BR', reason: 'Fala do horário marcado.' },
      'day_before' => { name: 'lembrete_horario', language: 'pt_BR', reason: 'Serve de lembrete.' }
    )
    expect(client).to have_received(:create) do |args|
      sent = JSON.parse(args[:input])
      expect(sent['candidates'].pluck('name')).to eq(['lembrete_horario'])
      expect(sent['notices'].pluck('kind')).to eq(%w[booked day_before])
      expect(args[:schema][:schema][:properties][:choices][:items][:properties][:kind][:enum]).to eq(%w[booked day_before])
    end
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'aviso_modelo', account: account, max_retries: 0))
  end

  it 'aceita "nenhum serve" (índice -1) e ignora índice fora da lista' do
    answer([{ kind: 'booked', index: -1, reason: 'Nenhum fala de horário.' }, { kind: 'day_before', index: 7, reason: 'x' }])

    expect(suggest).to eq('booked' => nil, 'day_before' => nil)
  end

  it 'sem candidato que sirva, não pergunta à IA' do
    channel.update_columns(message_templates: list.drop(1)) # rubocop:disable Rails/SkipsModelValidations
    allow(client).to receive(:create)

    expect(suggest).to eq('booked' => nil, 'day_before' => nil)
    expect(client).not_to have_received(:create)
  end

  it 'escolhe direto o modelo da plataforma já aprovado, sem IA para esse aviso' do
    platform = template('agendamento_ao_marcar_v1', Crm::BookingV2::NoticeTemplates::Catalog.body_for('booked'))
    channel.update_columns(message_templates: [platform]) # rubocop:disable Rails/SkipsModelValidations
    answer([{ kind: 'day_before', index: -1, reason: 'Não é lembrete.' }])

    result = suggest

    expect(result['booked']).to include(name: 'agendamento_ao_marcar_v1', language: 'pt_BR')
    expect(result['day_before']).to be_nil
    expect(client).to have_received(:create) { |args| expect(JSON.parse(args[:input])['notices'].pluck('kind')).to eq(['day_before']) }
  end

  it 'falha da IA vira Unavailable' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    expect { suggest }.to raise_error(described_class::Unavailable)
  end

  it 'resposta que não é JSON vira Unavailable' do
    allow(client).to receive(:create).and_return(text: 'nada')

    expect { suggest }.to raise_error(described_class::Unavailable)
  end

  it 'IA desligada na instalação vira Unavailable' do
    with_modified_env('CRM_AI_ENABLED' => 'false') do
      expect { suggest }.to raise_error(described_class::Unavailable, 'ai_disabled')
    end
  end
end
