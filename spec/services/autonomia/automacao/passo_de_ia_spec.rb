require 'rails_helper'

# A chamada de IA dos passos da F7 (#2500): a chave da conta, o custo só desta thread e os tipos de erro do executor.
RSpec.describe Autonomia::Automacao::PassoDeIa do
  let(:account) { create(:account) }
  let(:schema) do
    { name: 'teste', schema: { type: 'object', additionalProperties: false, required: %w[texto], properties: { texto: { type: 'string' } } } }
  end
  let(:ia) { described_class.new(conta: account, feature: 'automacao_resumir', modelo: Crm::Ai::Config::MODEL_SUMMARY) }

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
  end

  def openai_devolve(status: 200, texto: { texto: 'ok' }.to_json, &antes)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do
      antes&.call
      next { status: status, body: { error: { message: 'falhou' } }.to_json, headers: { 'Content-Type' => 'application/json' } } if status != 200

      payload = { id: 'resp_1', output_text: texto, usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def perguntar = ia.perguntar(instrucoes: 'Resuma.', entrada: { conversa: {} }, schema: schema)

  def falha
    perguntar
  rescue described_class::Falha => e
    [e.tipo, e.motivo]
  end

  it 'grava o uso na Gestão IA com a feature do passo e soma o custo no registro', :aggregate_failures do
    openai_devolve

    resposta, custo = perguntar

    expect(resposta).to eq('texto' => 'ok')
    expect(custo).to include('modelo' => Crm::Ai::Config::MODEL_SUMMARY, 'tokens_entrada' => 1000, 'tokens_saida' => 200)
    evento = Crm::AiUsageEvent.last
    expect([evento.feature, evento.account_id]).to eq(['automacao_resumir', account.id])
    expect(custo['custo_usd']).to eq(evento.cost_estimate.to_f.round(6))
  end

  # O evento de custo é global entre as threads do Sidekiq: sem o filtro, o custo de outro job entraria neste passo.
  it 'não soma o custo de outra thread que rodou ao mesmo tempo' do
    outro = Crm::AiUsageEvent.new(id: 0, feature: 'outro', model: 'x', reasoning_effort: 'low', cost_estimate: 9.99)
    openai_devolve { Thread.new { Crm::Ai::UsageRecorder.notify(outro, { input: 5, cached: 0, output: 5 }) }.join }

    _resposta, custo = perguntar

    expect(custo['custo_usd']).to be < 9
  end

  it 'erro passageiro (429, 5xx) é passageiro; chave recusada e outro 4xx são permanentes', :aggregate_failures do
    { 429 => [:passageiro, 'ia_indisponivel'], 503 => [:passageiro, 'ia_indisponivel'],
      401 => [:permanente, 'ia_chave_recusada'], 400 => [:permanente, 'ia_recusou'] }.each do |status, esperado|
      openai_devolve(status: status)
      expect(falha).to eq(esperado)
    end
  end

  it 'resposta que não é JSON, ou fora do schema, é permanente', :aggregate_failures do
    openai_devolve(texto: 'não é json')
    expect(falha).to eq([:permanente, 'resposta_fora_do_schema'])

    openai_devolve(texto: { outro: 1 }.to_json)
    expect(falha).to eq([:permanente, 'resposta_fora_do_schema'])
  end

  it 'chave desligada na conta conta como sem chave' do
    account.hooks.update_all(settings: { 'api_key' => 'chave-de-teste', 'enabled' => false }) # rubocop:disable Rails/SkipsModelValidations
    openai_devolve

    expect(falha).to eq([:permanente, 'ia_nao_configurada'])
  end
end
