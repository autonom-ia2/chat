require 'rails_helper'

# #855 — em 02/10/2026, na conta 18, o Guia leu as funções da conta para montar
# um acesso restrito a uma caixa, ficou inseguro sobre o que dava para fazer e
# o portão trocou a resposta inteira por "não tenho certeza suficiente". A
# pessoa ficou sem saber nem o que era possível.
#
# O Guia que leu ou mudou a conta responde pelo que viu e fez, mesmo inseguro.
# O agente de atendimento, sem `operador`, continua com o portão de sempre.
RSpec.describe Autonomia::Agents::Answerer do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Guia.', config: { 'with_knowledge' => false })
  end
  let(:inseguro) do
    { reply: 'Função personalizada não limita campanhas a uma caixa; consigo restringir as conversas e o CRM.',
      confidence: 0.4, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
      answered_from_knowledge: false }.to_json
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .and_return(instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: inseguro }))
  end

  def responder(operador: nil)
    described_class.new(agent: agente, query: 'crie a função Marketing', operador: operador).answer
  end

  it 'entrega a resposta do Guia que leu a conta, mesmo com confiança baixa', :aggregate_failures do
    guia = Autonomia::Guide::Contexto.new(account: conta, user: admin)
    guia.lido('[{"id":1,"name":"Atendimento"}]')

    resultado = responder(operador: guia)

    expect(resultado.handoff[:should]).to be(false)
    expect(resultado.reply).to include('consigo restringir')
  end

  # No teste real do mesmo pedido, o Guia criou a função e pediu handoff só para
  # registrar uma ressalva. A mudança já tinha acontecido: a resposta não some.
  it 'entrega a resposta do Guia que agiu, mesmo pedindo handoff', :aggregate_failures do
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(
      instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: {
                        text: JSON.parse(inseguro).merge('confidence' => 0.92, 'should_handoff' => true,
                                                         'handoff_reason' => 'restrição por caixa não confirmada').to_json
                      })
    )
    guia = Autonomia::Guide::Contexto.new(account: conta, user: admin)
    guia.lido('{"id":7,"name":"Marketing"}')

    resultado = responder(operador: guia)

    expect(resultado.handoff[:should]).to be(false)
    expect(resultado.reply).to be_present
  end

  it 'mantém o portão para o agente de atendimento' do
    expect(responder.handoff[:should]).to be(true)
  end

  it 'mantém o portão para o Guia que não leu nem fez nada' do
    guia = Autonomia::Guide::Contexto.new(account: conta, user: admin)

    expect(responder(operador: guia).handoff[:should]).to be(true)
  end
end
