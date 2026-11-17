require 'rails_helper'

# E8 (#2901): a conversa em que a cotação da renovação fala com o segurado. Com "Lia responde", serve primeiro a conversa
# sem responsável (a Lia não responde conversa que está com alguém). A caixa que entrega toda conversa nova a alguém da
# equipe não abre outra conversa a cada envio: o envio segue na aberta e a equipe é avisada uma vez. Com "a equipe
# responde", nada muda. Tudo fictício; a Meta é dublê.
RSpec.describe Carteira::Cotacao::Envio do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent, name: 'Paula Exemplo') }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:quem_responde) { 'lia' }
  let(:distribui) { false }
  let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa, quem_cota: 'lia', quem_responde: quem_responde) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    caixa.update!(enable_auto_assignment: distribui)
    agente_de_cotacao(account)
    create(:inbox_member, user: atendente, inbox: caixa)
    aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
    por_em_renovacao(seguro, ajustes)
  end

  def envio
    described_class.new(seguro.reload, ajustes.reload)
  end

  def conversa_aberta(assignee: nil)
    create(:conversation, account: account, inbox: caixa, contact: marina, assignee: assignee, status: :open)
  end

  def avisos_da_caixa
    Crm::FollowUp.where(account_id: account.id).select { |tarefa| tarefa.metadata['motivo'] == 'caixa_distribui' }
  end

  describe 'Lia responde, numa caixa que não distribui' do
    it 'não usa a conversa que está com alguém da equipe: abre outra' do
      com_alguem = conversa_aberta(assignee: atendente)

      conversa = envio.conversa

      expect(conversa).not_to eq(com_alguem)
      expect(conversa).to have_attributes(inbox_id: caixa.id, contact_id: marina.id, assignee_id: nil)
      expect(com_alguem.reload.assignee).to eq(atendente)
      expect(avisos_da_caixa).to be_empty
    end

    it 'usa a conversa aberta sem responsável' do
      conversa_aberta(assignee: atendente)
      livre = conversa_aberta

      expect(envio.conversa).to eq(livre)
    end
  end

  describe 'Lia responde, numa caixa que passou a distribuir depois dos ajustes' do
    let(:distribui) { true }

    it 'a mensagem sai na conversa aberta, sem abrir outra, e a equipe é avisada uma vez com o nome do agente' do
      com_alguem = conversa_aberta(assignee: atendente)

      primeira = envio.modelo('renovacao_algo_mudou', Carteira::Cotacao::ETAPA_ALGO_MUDOU)
      envio.conversa

      expect(primeira.conversation).to eq(com_alguem)
      expect(Conversation.where(contact_id: marina.id, inbox_id: caixa.id).count).to eq(1)
      expect(avisos_da_caixa.size).to eq(1)
      expect(avisos_da_caixa.first.title).to include('Lia Exemplo')
      expect(com_alguem.reload.assignee).to eq(atendente)
    end
  end

  describe 'a equipe responde' do
    let(:quem_responde) { 'equipe' }
    let(:distribui) { true }

    it 'usa a conversa aberta mesmo com alguém da equipe, sem aviso' do
      com_alguem = conversa_aberta(assignee: atendente)

      expect(envio.conversa).to eq(com_alguem)
      expect(avisos_da_caixa).to be_empty
    end
  end
end
