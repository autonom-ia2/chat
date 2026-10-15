require 'rails_helper'

# O consumo de IA é gravado UMA vez por ida ao modelo (#1656). A rodada final do laço de ferramentas era
# gravada duas vezes — no laço e de novo ao montar a resposta —, e o "Gasto com IA" saía dobrado nela.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:account) { create(:account) }
  let(:cliente) do
    described_class.new(credential: { api_key: 'chave-de-teste', source: 'spec' }, feature: 'agente_resposta', account: account)
  end
  let(:ferramentas) { [{ type: 'function', name: 'ler_da_conta' }] }
  let(:uso) { { 'input_tokens' => 10, 'output_tokens' => 5 } }

  def pedindo_ferramenta
    { 'usage' => uso,
      'output' => [{ 'type' => 'function_call', 'name' => 'ler_da_conta', 'call_id' => 'c1', 'arguments' => '{}' }] }
  end

  def respondendo
    { 'usage' => uso, 'output_text' => '{"reply":"pronto"}', 'output' => [] }
  end

  # O dublê fica no HTTP privado: o que se mede é quantas vezes cada ida vira registro.
  def responder_com(sequencia)
    allow(cliente).to receive(:post_responses) do |_body, **|
      instance_double(HTTParty::Response, success?: true, parsed_response: sequencia.shift || respondendo)
    end
  end

  def com_ferramentas(max_rodadas: 1)
    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil,
                                      tools: ferramentas, max_rodadas: max_rodadas) do |_calls|
      [{ type: 'function_call_output', call_id: 'c1', output: 'ok' }]
    end
  end

  before { allow(Crm::Ai::UsageRecorder).to receive(:record) }

  it 'sem ferramentas, grava uma vez' do
    responder_com([respondendo])

    cliente.create(model: 'm', instructions: 'i', input: 'oi')

    expect(Crm::Ai::UsageRecorder).to have_received(:record).once
  end

  it 'com ferramentas e resposta direta, grava uma vez' do
    responder_com([respondendo])

    com_ferramentas(max_rodadas: 4)

    expect(Crm::Ai::UsageRecorder).to have_received(:record).once
  end

  it 'com duas rodadas de ferramenta e depois a resposta, grava três' do
    responder_com([pedindo_ferramenta, pedindo_ferramenta, respondendo])

    com_ferramentas(max_rodadas: 4)

    expect(Crm::Ai::UsageRecorder).to have_received(:record).exactly(3).times
  end

  it 'pelo fechamento (as rodadas acabaram), grava uma por ida' do
    responder_com([pedindo_ferramenta, pedindo_ferramenta, respondendo])

    com_ferramentas(max_rodadas: 2)

    # Duas idas com ferramenta e a ida final sem ferramenta.
    expect(Crm::Ai::UsageRecorder).to have_received(:record).exactly(3).times
  end
end
