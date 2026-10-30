require 'rails_helper'

# Tema 6 (#1428), causa raiz de 22/10: o Testar e a prova rodavam o Answerer COM o portão de confiança, e o portão troca a
# resposta do modelo pela mensagem fixa (`fallback_message`). O atendimento roda sem portão (`trust_instruction`), então o
# dono testava um agente que o cliente nunca vê. Pelo HTTP de verdade do ResponsesClient (WebMock): a mesma resposta do
# modelo, com pouca confiança e pedido de passagem, sai igual no atendimento, no Testar e na prova. A Lia fica no portão.
RSpec.describe Autonomia::Agents::Playground do
  let(:account) { create(:account) }
  let(:fala_do_modelo) { 'Essa eu não sei de cabeça, vou chamar alguém da equipe para te responder, tá?' }
  let(:corpos) { [] }

  def agente(tipo)
    Autonomia::Agents::Agent.create!(account: account, name: 'Hubber', agent_type: tipo, status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', fallback_message: 'MENSAGEM FIXA DO DONO',
                                     config: { 'with_knowledge' => false })
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
    resposta = { reply: fala_do_modelo, confidence: 0.2, should_handoff: true, handoff_reason: 'nao_sei',
                 used_snippet_ids: [], answered_from_knowledge: false }.to_json
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      { status: 200, body: { output_text: resposta }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def atendimento(agent)
    Autonomia::Agents::Answerer.new(agent: agent, query: 'Vocês abrem no feriado?', trust_instruction: true).answer
  end

  it 'o Testar devolve a fala do modelo, a mesma do atendimento, e não a mensagem fixa', :aggregate_failures do
    agent = agente('support')

    testar = described_class.new(agent: agent, message: 'Vocês abrem no feriado?').run

    expect(testar.reply).to eq(fala_do_modelo)
    expect(testar.reply).to eq(atendimento(agent).reply)
    expect(testar.handoff[:should]).to be(true)
  end

  it 'a prova (sem ferramenta) também devolve a fala do modelo', :aggregate_failures do
    agent = agente('support')

    prova = Autonomia::Agents::Answerer.new(agent: agent, query: 'Vocês abrem no feriado?', prova: true,
                                            trust_instruction: described_class.como_no_atendimento?(agent)).answer

    expect(prova.reply).to eq(fala_do_modelo)
    expect(corpos.last).not_to have_key('tools')
  end

  it 'falha de IA no Testar volta como erro, sem texto (a tela mostra o aviso, não um balão vazio)', :aggregate_failures do
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 500, body: '{}')

    testar = described_class.new(agent: agente('support'), message: 'Oi').run

    expect(testar.reply).to be_nil
    expect(testar.error).to eq('ai_unavailable')
  end

  it 'a Lia (insurance_quote) segue no portão: a mensagem fixa no lugar da fala (D6, sem mexer na Lia)' do
    lia = agente('support')
    lia.update_column(:agent_type, 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.como_no_atendimento?(lia)).to be(false)
    expect(described_class.new(agent: lia, message: 'Vocês abrem no feriado?').run.reply).to eq('MENSAGEM FIXA DO DONO')
  end
end
