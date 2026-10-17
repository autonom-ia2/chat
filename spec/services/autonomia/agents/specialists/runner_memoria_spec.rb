require 'rails_helper'

# #1755: a memória do cliente é só do agente PRINCIPAL (decisão do Rodrigo, 17/10/2026). O especialista (a cotação da
# Lia, o ajudante) recebe o que o principal manda a ele e nunca lê a memória: a entrada dele fica como antes.
RSpec.describe Autonomia::Agents::Specialists::Runner do
  let(:account) { conta_da_fase2 }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:specialist) do
    Autonomia::Agents::Specialist.create!(agent: agent, name: 'Cotação Auto', slug: 'auto', description: 'cotação de automóvel',
                                          instruction: 'Você cota automóvel.')
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 1) }
  let(:entradas) { [] }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(cliente).to receive(:create_with_tool_executor) do |**kwargs|
      entradas << kwargs[:input]
      { text: { resposta: 'ok', dados_faltando: [] }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  it 'mesmo com memória disponível na conversa, o especialista não lê a memória' do
    chamadas = memoria_do_crm(leitura_da_memoria(agora_fatos: [linha_da_memoria(id: 9, rotulo: 'placa', valor: 'QTA4B21')]))

    described_class.new(specialist: specialist, request: 'cotar o carro', delivery: delivery).call

    expect(chamadas).to be_empty
    expect(entradas.sole.map { |item| item[:content].first[:text] }.join).not_to include('QTA4B21', 'REGISTRO#')
  end
end
