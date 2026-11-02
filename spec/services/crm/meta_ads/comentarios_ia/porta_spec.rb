require 'rails_helper'

# #2469: a regra de quem escreve, uma só para o motor (Escrita, coberta em escrita_spec com cada motivo) e para a tela
# de Agentes. Aqui, o que só a tela usa: o agente da porta vem mesmo quando ele não escreve (a tela diz quem é e por
# quê), e nunca o de uma caixa de outra conta.
RSpec.describe Crm::MetaAds::ComentariosIa::Porta do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }

  def na_porta(caixa, **atributos)
    agente = Autonomia::Agents::Agent.create!(account: caixa.account, name: 'Porta', agent_type: 'custom', status: :active,
                                              enabled: true, **atributos)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente, inbox: caixa).perform(connect: true)
    agente
  end

  before do
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
  end

  it 'o agente da porta escreve: sem motivo' do
    agente = na_porta(inbox)

    porta = described_class.new(care: care, inbox: inbox)

    expect([porta.agente, porta.motivo]).to eq([agente, nil])
  end

  it 'a Lia na porta: o agente vem, com o motivo de não escrever' do
    agente = na_porta(inbox, agent_type: 'insurance_quote')

    porta = described_class.new(care: care, inbox: inbox)

    expect([porta.agente, porta.motivo]).to eq([agente, 'lia'])
  end

  it 'caixa de outra conta: nenhum agente, nem o que está na porta dela' do
    outra = create(:inbox)
    na_porta(outra)

    porta = described_class.new(care: care, inbox: outra)

    expect([porta.agente, porta.motivo]).to eq([nil, 'outra_conta'])
  end

  it 'sem caixa: nenhum agente' do
    porta = described_class.new(care: care, inbox: nil)

    expect([porta.agente, porta.motivo]).to eq([nil, 'sem_caixa'])
  end
end
