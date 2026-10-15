require 'rails_helper'

# Tema 14 (#1434), decisão (c) do Rodrigo: só um agente CRIADO como "Ajuda outros agentes" pode ser ajudante. A marca de
# origem (`config['papel'] = 'ajudante'`) só nasce pelo início do Construtor com `papel: 'ajudante'`.
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }

  def rascunho_da_abertura(**opcoes)
    thread = Autonomia::Agents::BuildThread.new(account: account)
    thread.persist_start_options!(type: 'custom', **opcoes)
    thread.save!
    thread.append_message!('user', 'Quero um agente que conheça as regras do produto Auto')
    builder = described_class.new(account: account, build_thread: thread)
    client = instance_double(Crm::Ai::ResponsesClient,
                             create: { text: { 'needs_more_info' => true, 'next_question' => 'Qual o nome?' }.to_json })
    allow(builder).to receive(:client).and_return(client)
    builder.run!(thread.begin_build!)
    thread.reload.agent
  end

  it 'a abertura "Ajuda outros agentes" cria o rascunho interno e com a marca de origem' do
    agente = rascunho_da_abertura(papel: 'ajudante')

    expect(agente).to be_actuation_internal
    expect(agente).to be_ajudante_de_origem
    expect(agente.config['papel']).to eq('ajudante')
  end

  it 'a marca vence a atuação pedida: o ajudante é sempre interno' do
    expect(rascunho_da_abertura(papel: 'ajudante', actuation: 'external')).to be_actuation_internal
  end

  it 'sem a abertura do ajudante, o rascunho nasce sem a marca (o Copiloto interno inclusive)' do
    expect(rascunho_da_abertura(actuation: 'internal')).not_to be_ajudante_de_origem
    expect(rascunho_da_abertura(papel: 'outra_coisa')).not_to be_ajudante_de_origem
  end
end
