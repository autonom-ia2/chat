require 'rails_helper'

# #2067: o "Devolver para <agente>" só aparece quando a conversa está com uma pessoa que a recebeu de uma IA, e só com um
# robô para onde ela volta de verdade (Crm::Passagens::VeioDaIa).
RSpec.describe Crm::Passagens::VeioDaIa do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:n8n) { create(:agent_bot, account: account, name: 'Robô do n8n') }

  def conversa_com(pessoa)
    create(:conversation, account: account, inbox: inbox, status: :open).reload.tap do |conversation|
      conversation.update_columns(assignee_id: pessoa&.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def passou(conversation, origem:, para:, motivo: 'robo_pediu')
    Crm::Passagens.registrar!(conversation: conversation, de: origem, para: para, pedida_por: nil, motivo: motivo)
  end

  context 'with an external bot (n8n)' do
    before do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: n8n)
      [ana, bia].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    end

    it 'robô de outro sistema passou para a pessoa que está com a conversa: volta para ele' do
      conversation = conversa_com(ana)
      passou(conversation, origem: n8n, para: ana)

      expect(described_class.de(conversation)).to eq(id: n8n.id, name: 'Robô do n8n')
    end

    it 'a IA passou sem ponta gravada (motivo da IA): volta para o robô ativo da caixa' do
      conversation = conversa_com(ana)
      passou(conversation, origem: nil, para: ana)

      expect(described_class.de(conversation)).to eq(id: n8n.id, name: 'Robô do n8n')
    end

    # Pega o botão que não funcionaria: o robô saiu da caixa depois da passagem.
    it 'robô desligado da caixa: nada a oferecer' do
      conversation = conversa_com(ana)
      passou(conversation, origem: n8n, para: ana)
      AgentBotInbox.where(inbox: inbox).update_all(status: AgentBotInbox.statuses[:inactive]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(conversation)).to be_nil
    end

    {
      'veio de outra pessoa (IA → Ana → Bia)' => :de_pessoa,
      'a passagem foi para outra pessoa' => :outra_pessoa,
      'sem ninguém na conversa' => :sem_ninguem,
      'a passagem já foi devolvida' => :devolvida
    }.each do |caso, cenario|
      it "#{caso}: nada" do
        conversation = conversa_com(ana)
        case cenario
        when :de_pessoa
          passou(conversation, origem: n8n, para: ana)
          passou(conversation, origem: ana, para: bia, motivo: 'passar_para')
          conversation.update_columns(assignee_id: bia.id) # rubocop:disable Rails/SkipsModelValidations
        when :outra_pessoa then passou(conversation, origem: n8n, para: bia)
        when :sem_ninguem
          passou(conversation, origem: n8n, para: ana)
          conversation.update_columns(assignee_id: nil) # rubocop:disable Rails/SkipsModelValidations
        when :devolvida
          passou(conversation, origem: n8n, para: ana)
          Crm::Passagens.encerrar_aberta!(conversation, por: ana)
        end

        expect(described_class.de(conversation.reload)).to be_nil
      end
    end

    # Pega o N+1 na lista de conversas: o número de consultas não cresce com a página.
    it 'na lista, as consultas não crescem com o número de conversas', :aggregate_failures do
      contar = lambda do |conversas|
        total = 0
        contador = ->(*, payload) { total += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
        ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') { described_class.da_lista(conversas) }
        total
      end
      conversas = Array.new(4) { conversa_com(ana).tap { |conversation| passou(conversation, origem: n8n, para: ana) } }

      uma = contar.call(conversas.first(1))
      quatro = contar.call(conversas)

      expect(quatro).to eq(uma)
      expect(described_class.da_lista(conversas).values.pluck(:id).uniq).to eq([n8n.id])
    end
  end

  context 'with one of our AI agents' do
    include_context 'with crm responsible agent'

    it 'volta para o espelho do vínculo ativo dele nesta caixa, com o nome do agente' do
      passou(conversation, origem: porta, para: ana)
      conversation.update_columns(assignee_id: ana.id, assignee_agent_bot_id: nil, ai_assignee_type: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(conversation.reload)).to eq(id: porta.id, name: 'Porta')
    end

    it 'vínculo removido: nada' do
      passou(conversation, origem: espelho_area, para: ana)
      conversation.update_columns(assignee_id: ana.id) # rubocop:disable Rails/SkipsModelValidations
      area_sumiu!

      expect(described_class.de(conversation.reload)).to be_nil
    end
  end
end
