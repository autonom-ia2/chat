require 'rails_helper'

# #1755: o especialista (a Lia na cotação) lê a mesma memória do cliente que o principal, para não pedir de novo o que
# o cliente já deu. Os fatos vão como dado (`user`, com cerca), o estado do sistema como `developer`, antes do pedido.
RSpec.describe Autonomia::Agents::Specialists::Runner do
  let(:account) { conta_da_fase2 }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:specialist) do
    Autonomia::Agents::Specialist.create!(agent: agent, name: 'Cotação Auto', slug: 'auto', description: 'cotação de automóvel',
                                          instruction: 'Você cota automóvel.')
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 1) }
  let(:placa) { linha_da_memoria(id: 9, rotulo: 'placa do pedido', valor: 'QTA4B21') }
  let(:dono) { linha_da_memoria(chave: 'dono_previsto', rotulo: 'dono', valor: 'ninguem', origem: :sistema) }
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

  def papeis_e_textos
    entradas.sole.map { |item| [item[:role], item[:content].first[:text]] }
  end

  it 'com a memória ligada, o estado e os fatos entram antes do pedido, cada um no papel dele' do
    chamadas = memoria_do_crm(leitura_da_memoria(agora_do_sistema: [dono], agora_fatos: [placa]))

    described_class.new(specialist: specialist, request: 'cotar o carro', delivery: delivery).call

    itens = papeis_e_textos
    pedido = itens.index { |_papel, texto| texto.start_with?('PEDIDO DO ATENDENTE') }
    estado = itens.index { |_papel, texto| texto.start_with?('ESTADO DESTA CONVERSA') }
    fatos = itens.index { |_papel, texto| texto.include?('QTA4B21') }
    expect([itens[estado].first, itens[fatos].first]).to eq(%w[developer user])
    expect(estado).to be < pedido
    expect(fatos).to be < pedido
    expect(itens[estado].last).not_to include('QTA4B21')
    expect(chamadas.sole).to include(finalidade: :especialista, conversation: conversation, agent: agent)
  end

  it 'sem a flag (ou fora de uma conversa, como no Testar), a entrada fica como antes' do
    memoria_do_crm(leitura_da_memoria(agora_fatos: [placa]), ligada: false)

    described_class.new(specialist: specialist, request: 'cotar o carro', delivery: delivery).call
    described_class.new(specialist: specialist, request: 'cotar o carro').call

    expect(entradas.flatten.map { |item| item[:content].first[:text] }.join).not_to include('QTA4B21', 'MEMÓRIA')
  end
end
