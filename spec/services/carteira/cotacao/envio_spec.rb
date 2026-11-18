require 'rails_helper'

# E8 (#2901): a conversa em que a cotação da renovação fala com o segurado. É a conversa aberta mais recente do contato
# na caixa, com ou sem responsável; conversa nova só quando não há nenhuma aberta, e nunca uma por envio. Vale para "Lia
# responde" e para "a equipe responde". Tudo fictício; a Meta é dublê.
RSpec.describe Carteira::Cotacao::Envio do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent, name: 'Paula Exemplo') }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa, quem_cota: 'lia', quem_responde: 'lia') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    caixa.update!(enable_auto_assignment: false)
    agente_de_cotacao(account)
    create(:inbox_member, user: atendente, inbox: caixa)
    aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
    por_em_renovacao(seguro, ajustes)
  end

  def envio
    described_class.new(seguro.reload, ajustes.reload)
  end

  def conversas_da_marina
    Conversation.where(contact_id: marina.id, inbox_id: caixa.id)
  end

  it 'Lia responde: a conversa aberta com alguém da equipe é usada, sem abrir outra e sem tirar a pessoa' do
    com_alguem = create(:conversation, account: account, inbox: caixa, contact: marina, assignee: atendente, status: :open)

    mensagem = envio.modelo('renovacao_algo_mudou', Carteira::Cotacao::ETAPA_ALGO_MUDOU)
    envio.conversa

    expect(mensagem.conversation).to eq(com_alguem)
    expect(conversas_da_marina.count).to eq(1)
    expect(com_alguem.reload.assignee).to eq(atendente)
  end

  it 'sem nenhuma conversa aberta: abre uma, e os envios seguintes usam a mesma' do
    primeira = envio.conversa
    primeira.update!(assignee: atendente)

    expect(envio.conversa).to eq(primeira)
    expect(conversas_da_marina.count).to eq(1)
  end
end
