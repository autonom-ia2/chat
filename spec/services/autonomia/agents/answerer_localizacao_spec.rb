require 'rails_helper'

# #1479 F2: com a flag `agentes_pedir_localizacao`, o Answerer pede o schema com o pedido de localização e acrescenta
# a regra dele; sem a flag, o pedido fica o da F1. A Lia fica fora.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: cloud.inbox) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: cloud.inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: nil) }
  let(:pedidos) { [] }
  let(:pede_localizacao) { { tipo: 'localizacao', header: nil, pergunta: 'Onde você está?', opcoes: [], botao: nil, link: nil } }

  def modelo_responde(interacao)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs|
      pedidos << kwargs
      { text: { reply: 'Certo.', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                answered_from_knowledge: false, interacao: interacao }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def atender
    described_class.new(agent: agent, query: 'qual a unidade mais perto?', trust_instruction: true, delivery: delivery).answer
  end

  it 'com a flag: schema com localização, a regra no fim e o pedido conferido' do
    account.enable_features!('agentes_pedir_localizacao')
    modelo_responde(pede_localizacao)
    resultado = atender
    expect(pedidos.last[:schema]).to eq(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA_COM_LOCALIZACAO)
    expect(pedidos.last[:instructions]).to end_with(
      "#{Autonomia::Agents::Interacao::INSTRUCAO}\n\n#{Autonomia::Agents::Interacao::PedidoDeLocalizacao::INSTRUCAO}"
    )
    expect(resultado.interacao).to eq('tipo' => 'localizacao', 'pergunta' => 'Onde você está?')
  end

  it 'sem a flag: o pedido ao modelo fica o da F1 (schema e instrução)' do
    modelo_responde(nil)
    atender
    expect(pedidos.last[:schema]).to equal(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA_COM_INTERACAO)
    expect(pedidos.last[:instructions]).to end_with(Autonomia::Agents::Interacao::INSTRUCAO)
    expect(pedidos.last[:instructions]).not_to include(Autonomia::Agents::Interacao::PedidoDeLocalizacao::INSTRUCAO)
  end

  it 'a Lia (insurance_quote) não recebe o pedido nem com a flag' do
    account.enable_features!('agentes_pedir_localizacao')
    lia = criar_principal(account, agent_type: 'insurance_quote')
    expect(Autonomia::Agents::Interacao.disponivel?(agent: lia, delivery: delivery, audience: :customer)).to be(false)
  end
end
