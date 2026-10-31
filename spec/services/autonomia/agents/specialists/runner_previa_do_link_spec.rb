require 'rails_helper'

# #1775: o ajudante (tema 14) lê a conversa do principal, que pode trazer a linha da prévia do link (texto de uma página
# pública). A regra da prévia chega a ele porque o Runner passa o PRINCIPAL à Materia (`agent: @specialist.agent`), que
# decide por `PreviaDoLink.aplica?`. Sem esse argumento, o gate fecha em silêncio e o ajudante lê a página sem a regra.
RSpec.describe Autonomia::Agents::Specialists::Runner do
  let(:account) { conta_da_fase2 }
  let(:principal) { criar_principal(account) }
  let(:vinculo) { vincular(principal, criar_ajudante(account)) }
  let(:conversation) { create(:conversation, account: account) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 1) }
  let(:previa) { Autonomia::Agents::Operate::PreviaDoLink }
  let(:codigo) { previa.codigo(conversation) }
  let(:historico) do
    [{ role: 'user', content: "esse tem seguro?\n#{previa.cabecalho(codigo)} Prévia do link que o cliente mandou (...): {}" }]
  end
  let(:entradas) { [] }

  before do
    account.enable_features!(previa::FLAG)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(cliente).to receive(:create_with_tool_executor) do |**kwargs|
      entradas << kwargs[:input]
      { text: { resposta: 'ok', dados_faltando: [] }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def regras_da_previa
    entradas.sole.select { |item| item[:role] == 'developer' && item[:content].first[:text] == previa.regra(codigo) }
  end

  it 'o ajudante recebe a regra da prévia quando a conversa do principal traz a linha' do
    described_class.new(specialist: vinculo, request: 'esse imóvel tem seguro?', delivery: delivery, history: historico).call

    expect(regras_da_previa.size).to eq(1)
  end

  it 'com o principal na Lia, o ajudante não recebe a regra' do
    allow(vinculo.agent).to receive(:agent_type).and_return('insurance_quote')

    described_class.new(specialist: vinculo, request: 'esse imóvel tem seguro?', delivery: delivery, history: historico).call

    expect(regras_da_previa).to be_empty
  end
end
