require 'rails_helper'

# #593 — o portão de confiança retinha a resposta certa do Guia. "Não encontrei
# o contato Pedro", dito DEPOIS de ler os contatos da conta, caía no piso do
# "não achei" (0.29) e a pessoa recebia "resposta retida". O que ancora a
# resposta do Guia é a leitura da conta, e o portão passou a saber disso.
#
# O piso continua valendo onde ele protege: agente de atendimento (sem
# `operador`) que diz "não achei a informação do frete" vai para um humano.
RSpec.describe Autonomia::Agents::Answerer do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Guia.', config: { 'with_knowledge' => false })
  end
  let(:nao_encontrei) do
    { reply: 'Não encontrei nenhum contato chamado Pedro nesta conta.', confidence: 0.95, should_handoff: false,
      handoff_reason: nil, used_snippet_ids: [], answered_from_knowledge: true }.to_json
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .and_return(instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: nao_encontrei }))
  end

  def responder(operador: nil)
    described_class.new(agent: agente, query: 'abre a ficha do Pedro', operador: operador).answer
  end

  it 'mantém o piso do "não achei" para o agente de atendimento' do
    expect(responder.handoff[:should]).to be(true)
  end

  it 'deixa passar o "não encontrei" do Guia que leu a conta', :aggregate_failures do
    guia = Autonomia::Guide::Contexto.new(account: conta, user: admin)
    guia.lido('[] [NOTA INTERNA, não repita: são 0 no total desta conta.]')

    resultado = responder(operador: guia)

    expect(resultado.handoff[:should]).to be(false)
    expect(resultado.reply).to include('Não encontrei')
  end

  # Sem leitura, o "não encontrei" não se apoia em nada: continua retido.
  it 'retém o "não encontrei" do Guia que não leu nada' do
    guia = Autonomia::Guide::Contexto.new(account: conta, user: admin)

    expect(responder(operador: guia).handoff[:should]).to be(true)
  end
end
