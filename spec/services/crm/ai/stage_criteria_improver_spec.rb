require 'rails_helper'

RSpec.describe Crm::Ai::StageCriteriaImprover do
  let(:account) { create(:account, custom_attributes: { 'industry' => 'Clínica odontológica' }) }
  let(:pipeline) { account.crm_pipelines.create!(name: 'Funil de teste', status: :active) }
  let(:stages) do
    [
      { 'name' => 'Novo', 'description' => 'Primeiro contato, antes da qualificação.' },
      { 'name' => 'Proposta', 'description' => 'Oferta apresentada; cliente está avaliando.' }
    ]
  end
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, resolve: credential) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:suggestion) { { 'description' => 'O cliente recebeu a oferta e está avaliando as condições.', 'note' => '' } }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .with(credential: credential, feature: 'classify', account: account, pipeline: pipeline).and_return(client)
  end

  def pedido_enviado(**args)
    enviado = nil
    allow(client).to receive(:create) do |request|
      enviado = request
      { text: suggestion.to_json }
    end
    described_class.new(pipeline: pipeline, stages: stages, stage_index: 1, language: 'pt_BR', **args).perform
    enviado
  end

  it 'uses the selected stage and unsaved context without changing either stage' do
    original = stages.deep_dup
    allow(client).to receive(:create).and_return({ text: suggestion.to_json })

    result = described_class.new(pipeline: pipeline, stages: stages, stage_index: 1, language: 'pt_BR').perform

    expect(result).to eq(suggestion)
    expect(stages).to eq(original)
  end

  # #1920: o tipo do funil, o "quando usar" e o ramo do negócio entram, e a tela vale por cima do salvo.
  it 'sends the funnel kind, when to use and line of business, preferring the unsaved form' do
    pipeline.update!(counts_as_sale: true, when_to_use: 'Pedidos de orçamento.')

    request = pedido_enviado(funil: { 'counts_as_sale' => 'false', 'when_to_use' => 'Cancelamento e renovação.' })

    expect(request).to include(model: 'gpt-6-luna', reasoning_effort: 'high', schema: described_class::SCHEMA)
    expect(JSON.parse(request[:input])).to eq(
      'pipeline' => { 'name' => 'Funil de teste', 'kind' => 'serve', 'when_to_use' => 'Cancelamento e renovação.' },
      'business' => { 'industry' => 'Clínica odontológica' },
      'stages' => stages, 'target_index' => 1, 'language' => 'pt_BR'
    )
  end

  it 'uses the saved funnel when the form sends nothing' do
    pipeline.update!(counts_as_sale: false, when_to_use: 'Suporte.')

    expect(JSON.parse(pedido_enviado[:input])['pipeline']).to eq('name' => 'Funil de teste', 'kind' => 'serve', 'when_to_use' => 'Suporte.')
  end

  it 'adds the real cases of the saved target stage, found by id, as evidence' do
    novo = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo', position: 0)
    proposta = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 1)
    caso = { signal: 'ficou_em_duvida', ai_chose: 'Proposta', messages: [{ role: 'customer', content: 'Vou pensar' }] }
    evidencia = instance_double(Crm::Ai::EvidenciaDaEtapa, casos: [caso])
    cards = account.crm_cards.none
    allow(Crm::Ai::EvidenciaDaEtapa).to receive(:new).with(stage: proposta, cards: cards).and_return(evidencia)
    stages.first['id'] = novo.id
    stages.last['id'] = proposta.id

    entrada = JSON.parse(pedido_enviado(cards: cards)[:input])

    expect(entrada['evidence']).to eq([caso.deep_stringify_keys])
    expect(entrada['stages'].map(&:keys)).to all(eq(%w[name description]))
  end

  # #1920: reordenar as etapas na tela não troca a etapa-alvo; etapa nova (sem id) não tem evidência.
  it 'finds the target by id after a reorder and has no evidence for a new stage' do
    novo = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo', position: 0)
    proposta = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 1)
    allow(Crm::Ai::EvidenciaDaEtapa).to receive(:new).and_return(instance_double(Crm::Ai::EvidenciaDaEtapa, casos: []))
    stages.replace([{ 'id' => proposta.id, 'name' => 'Proposta', 'description' => '' }, { 'id' => novo.id, 'name' => 'Novo', 'description' => '' }])

    pedido_enviado
    expect(Crm::Ai::EvidenciaDaEtapa).to have_received(:new).with(stage: novo, cards: nil)

    stages.last.delete('id')
    pedido_enviado
    expect(Crm::Ai::EvidenciaDaEtapa).to have_received(:new).once
  end

  it 'has no evidence for a draft pipeline' do
    rascunho = account.crm_pipelines.new(name: 'Rascunho')
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(client).to receive(:create).and_return({ text: suggestion.to_json })
    allow(Crm::Ai::EvidenciaDaEtapa).to receive(:new)

    described_class.new(pipeline: rascunho, stages: stages, stage_index: 0, language: 'pt_BR').perform

    expect(Crm::Ai::EvidenciaDaEtapa).not_to have_received(:new)
  end

  it 'tells the model to write the boundary, never a word list, and to drop robot instructions' do
    instructions = pedido_enviado[:instructions]

    expect(instructions).to include('immediately before and after the target')
    expect(instructions).to include('Never write a list of exact words or phrases to match.')
    expect(instructions).to include('Remove any instruction to a robot or')
    expect(instructions).not_to include('classify real cards')
  end

  it 'accepts a blank target description for drafting from its name and context' do
    stages.last['description'] = ''

    expect(described_class.valid_input?('stages' => stages, 'stage_index' => 1)).to be(true)
  end

  it 'rejects an index outside the supplied stages' do
    expect(described_class.valid_input?('stages' => stages, 'stage_index' => 2)).to be(false)
  end

  it 'rejects string indices instead of choosing a different target by coercion' do
    expect(described_class.valid_input?('stages' => stages, 'stage_index' => '1')).to be(false)
  end
end
