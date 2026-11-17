require 'rails_helper'

# E8 (#2901): a conversa em que a cotação da renovação fala com o segurado. Com "Lia responde", só serve conversa sem
# responsável (a Lia não responde conversa que está com alguém); a conversa nova que a caixa der a alguém fica com a
# pessoa, o envio segue e a equipe é avisada. Com "a equipe responde", nada muda. Tudo fictício; a Meta é dublê.
RSpec.describe Carteira::Cotacao::Envio do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent, name: 'Paula Exemplo') }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:quem_responde) { 'lia' }
  let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa, quem_cota: 'lia', quem_responde: quem_responde) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
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

  def aviso_da_conversa
    Crm::FollowUp.where(account_id: account.id).find { |tarefa| tarefa.metadata['motivo'] == 'conversa_com_pessoa' }
  end

  describe 'Lia responde' do
    it 'não usa a conversa que está com alguém da equipe: abre outra' do
      com_alguem = conversa_aberta(assignee: atendente)

      conversa = envio.conversa

      expect(conversa).not_to eq(com_alguem)
      expect(conversa).to have_attributes(inbox_id: caixa.id, contact_id: marina.id, assignee_id: nil)
      expect(com_alguem.reload.assignee).to eq(atendente)
    end

    it 'usa a conversa aberta sem responsável' do
      conversa_aberta(assignee: atendente)
      livre = conversa_aberta

      expect(envio.conversa).to eq(livre)
    end

    it 'a conversa nova que a caixa deu a alguém: fica com a pessoa, a mensagem sai e a equipe é avisada com o nome dela' do
      allow_any_instance_of(ConversationBuilder).to receive(:perform).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        original.call(*args).tap { |nova| nova.update!(assignee: atendente) }
      end

      mensagem = envio.modelo('renovacao_algo_mudou', Carteira::Cotacao::ETAPA_ALGO_MUDOU)

      expect(mensagem).to be_persisted
      expect(mensagem.conversation.reload.assignee).to eq(atendente)
      expect(aviso_da_conversa.title).to include('Paula Exemplo', 'Lia Exemplo')
      expect(tipos_da_historia(seguro)).not_to include('algo_mudou_nao_saiu', 'proposta_nao_saiu')
    end
  end

  describe 'a equipe responde' do
    let(:quem_responde) { 'equipe' }

    it 'usa a conversa aberta mesmo com alguém da equipe, sem aviso' do
      com_alguem = conversa_aberta(assignee: atendente)

      expect(envio.conversa).to eq(com_alguem)
      expect(aviso_da_conversa).to be_nil
    end
  end
end
