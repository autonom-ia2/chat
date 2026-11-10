require 'rails_helper'

# G67 (#2844, exemplo 17, passo 6: "a IA resume para a Júlia o que aconteceu durante as férias"): na execução, o
# "resumir" lê as mensagens desde o começo dela, nunca menos que as 5 de sempre, até o teto; passou do teto, ficam as
# mais recentes, e a IA sabe quantas ficaram de fora. O modelo é a OpenAI simulada no HTTP: nenhuma chamada paga.
RSpec.describe Autonomia::Automacao::PassoDeResumir, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, contact: create(:contact, account: account, name: 'Maria')) }
  let(:inicio) { Time.zone.parse('2026-11-02 10:00') }
  let(:corpos) { [] }
  let(:passos) do
    [esperar_passo('ferias', 10),
     { 'id' => 'conta', 'tipo' => 'resumir', 'le' => %w[mensagens_com_respostas], 'linhas' => 4, 'destino' => 'nota' }]
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: 'resp_1', output_text: { resumo: 'Maria pediu a proposta.' }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  after { Current.reset }

  def escreve(momento, texto)
    travel_to(momento) { create(:message, conversation: conversa, account: account, message_type: :incoming, content: texto) }
  end

  # Começa no `inicio`, as mensagens chegam durante a espera, e o resumo roda no fim dela.
  def rodar(durante: [])
    execucao = travel_to(inicio) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, passos), conversa) }
    end
    durante.each_with_index { |texto, dia| escreve(inicio + (dia + 1).days, texto) }
    travel_to(inicio + 11.days) { varrer }
    execucao
  end

  def entrada = JSON.parse(corpos.sole['input'].first['content'].first['text'])['conversa']

  def lidas = entrada['messages'].map { |linha| linha.delete_prefix('Customer: ') }

  it 'lê todas as mensagens da execução, desde a primeira, e nenhuma de antes dela', :aggregate_failures do
    escreve(inicio - 1.hour, 'Antes de começar')
    rodar(durante: (1..8).map { |dia| "Mensagem do dia #{dia}" })

    expect(lidas).to eq((1..8).map { |dia| "Mensagem do dia #{dia}" })
    expect(entrada).not_to have_key('omitted_older_messages')
  end

  it 'com poucas mensagens no período, lê as 5 de sempre, inclusive as de antes', :aggregate_failures do
    (1..6).each { |vez| escreve(inicio - (7 - vez).hours, "Antes #{vez}") }
    rodar(durante: ['Durante'])

    expect(lidas).to eq(['Antes 3', 'Antes 4', 'Antes 5', 'Antes 6', 'Durante'])
    expect(entrada).not_to have_key('omitted_older_messages')
  end

  it 'passou do teto: ficam as mais recentes, e a IA sabe quantas ficaram de fora', :aggregate_failures do
    stub_const("#{described_class}::MAX_MENSAGENS_DO_PERIODO", 6)
    rodar(durante: (1..8).map { |dia| "Mensagem do dia #{dia}" })

    expect(lidas).to eq((3..8).map { |dia| "Mensagem do dia #{dia}" })
    expect(entrada['omitted_older_messages']).to eq(2)
    expect(corpos.sole['instructions']).to include('omitted_older_messages')
  end

  it 'as mensagens além das 5 mais recentes vão cortadas no limite de caracteres', :aggregate_failures do
    longa = "Primeira #{'x' * 2_000} fim da longa"
    rodar(durante: [longa, *(1..5).map { |dia| "Depois #{dia}" }])

    expect(lidas.first).to start_with('Primeira ')
    expect(lidas.first.length).to eq(described_class::MAX_CARACTERES_ANTERIORES)
    expect(lidas.last(5)).to eq((1..5).map { |dia| "Depois #{dia}" })
  end
end
