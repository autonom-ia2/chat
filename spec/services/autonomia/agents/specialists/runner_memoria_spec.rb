require 'rails_helper'

# #1755: o especialista (a Lia na cotação) lê a mesma memória do cliente que o principal, para não pedir de novo o que
# o cliente já deu. O "antes" e os fatos vão como dado (`user`, com cerca), o estado e a regra como `developer`, antes do
# pedido; os ids lidos ficam no Delivery para o `replied` do principal.
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
  let(:nome) { linha_da_memoria(id: 3, rotulo: 'nome', valor: 'Marcos Lima') }
  let(:placa) { linha_da_memoria(id: 9, rotulo: 'placa do pedido', valor: 'QTA4B21') }
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

  it 'o antes, o estado e os fatos entram antes do pedido, cada um no papel dele, e os ids ficam no Delivery' do
    chamadas = memoria_do_crm(leitura_da_memoria(antes: [nome], agora_fatos: [placa]))

    described_class.new(specialist: specialist, request: 'cotar o carro', delivery: delivery).call

    itens = papeis_e_textos
    pedido = itens.index { |_papel, texto| texto.start_with?('PEDIDO DO ATENDENTE') }
    antes = itens.index { |_papel, texto| texto.include?('Marcos Lima') }
    estado = itens.index { |_papel, texto| texto.start_with?('ESTADO DESTA CONVERSA') }
    fatos = itens.index { |_papel, texto| texto.include?('QTA4B21') }
    expect([itens[antes].first, itens[estado].first, itens[fatos].first]).to eq(%w[user developer user])
    expect([antes, estado, fatos].max).to be < pedido
    expect(chamadas.sole).to include(finalidade: :especialista, conversation: conversation, agent: agent)
    expect(delivery.memoria_fact_ids).to eq([3, 9])
  end

  it 'leitura vazia: a entrada fica como antes' do
    memoria_do_crm(Crm::Memoria::Leitor::Leitura.vazia)

    described_class.new(specialist: specialist, request: 'cotar o carro', delivery: delivery).call

    expect(papeis_e_textos.flatten.join).not_to include('REGISTRO#', 'ESTADO DESTA CONVERSA')
  end

  it 'fora de uma conversa (o Testar), nem com memória disponível o Leitor é chamado' do
    chamadas = memoria_do_crm(leitura_da_memoria(agora_fatos: [placa]))

    described_class.new(specialist: specialist, request: 'cotar o carro').call

    expect(chamadas).to be_empty
    expect(papeis_e_textos.flatten.join).not_to include('QTA4B21')
  end
end
