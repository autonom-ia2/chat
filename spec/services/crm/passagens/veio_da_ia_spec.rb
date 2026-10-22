require 'rails_helper'

# #2067: o "Devolver para <agente>" só aparece quando a conversa está com uma pessoa que a recebeu de uma IA, e só com
# para onde ela volte de verdade (Crm::Passagens::VeioDaIa): agente nosso atendendo (pelo "Passar para", com a Fase 2) ou
# robô ainda ligado na caixa (pela atribuição de robô).
RSpec.describe Crm::Passagens::VeioDaIa do
  def passou(conversation, origem:, para:, motivo: 'robo_pediu')
    Crm::Passagens.registrar!(conversation: conversation, de: origem, para: para, pedida_por: nil, motivo: motivo)
  end

  def contar_consultas(&)
    total = 0
    contador = ->(*, payload) { total += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(contador, 'sql.active_record', &)
    total
  end

  context 'with an external bot (n8n)' do
    let(:account) { create(:account) }
    let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
    let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let(:n8n) { create(:agent_bot, account: account, name: 'Robô do n8n') }

    before do
      allow(Crm::Config).to receive(:enabled?).and_return(true)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: n8n)
      [ana, bia].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    end

    def conversa_com(pessoa)
      create(:conversation, account: account, inbox: inbox, status: :open).reload.tap do |conversation|
        # A pessoa no nome, sem robô junto (como a atribuição deixa).
        conversation.update_columns(assignee_id: pessoa&.id, assignee_agent_bot_id: nil, ai_assignee_type: nil) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    it 'robô de outro sistema passou para a pessoa que está com a conversa: volta para ele, pela atribuição de robô' do
      conversation = conversa_com(ana)
      passou(conversation, origem: n8n, para: ana)

      expect(described_class.de(conversation)).to eq(tipo: 'robo', id: n8n.id, name: 'Robô do n8n')
    end

    it 'o nome é o de agora, não o gravado na passagem' do
      conversation = conversa_com(ana)
      passou(conversation, origem: n8n, para: ana)
      n8n.update!(name: 'Atendente virtual')

      expect(described_class.de(conversation)[:name]).to eq('Atendente virtual')
    end

    it 'robô sem nome: sai sem nome (a tela diz "a IA")' do
      conversation = conversa_com(ana)
      passou(conversation, origem: n8n, para: ana)
      n8n.update_columns(name: '') # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(conversation)).to eq(tipo: 'robo', id: n8n.id, name: nil)
    end

    it 'a IA passou sem ponta gravada (motivo da IA): volta para o robô ativo da caixa' do
      conversation = conversa_com(ana)
      passou(conversation, origem: nil, para: ana)

      expect(described_class.de(conversation)).to eq(tipo: 'robo', id: n8n.id, name: 'Robô do n8n')
    end

    # Pega o botão que não funcionaria: o robô saiu da caixa depois da passagem.
    it 'robô desligado da caixa: nada a oferecer' do
      conversation = conversa_com(ana)
      passou(conversation, origem: n8n, para: ana)
      AgentBotInbox.where(inbox: inbox).update_all(status: AgentBotInbox.statuses[:inactive]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(conversation)).to be_nil
    end

    it 'sem o CRM: nada (nem consulta)', :aggregate_failures do
      conversation = conversa_com(ana)
      passou(conversation, origem: n8n, para: ana)
      allow(Crm::Config).to receive(:enabled?).and_return(false)

      expect(contar_consultas { expect(described_class.da_lista([conversation])).to eq({}) }).to eq(0)
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
      conversas = Array.new(4) { conversa_com(ana).tap { |conversation| passou(conversation, origem: n8n, para: ana) } }

      uma = contar_consultas { described_class.da_lista(conversas.first(1)) }
      quatro = contar_consultas { described_class.da_lista(conversas) }

      expect(quatro).to eq(uma)
      expect(described_class.da_lista(conversas).values.pluck(:id).uniq).to eq([n8n.id])
    end
  end

  context 'with one of our AI agents' do
    include_context 'with crm responsible agent'

    let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }

    def com_a_ana!(conversa = conversation)
      conversa.update_columns(assignee_id: ana.id, assignee_agent_bot_id: nil, ai_assignee_type: nil) # rubocop:disable Rails/SkipsModelValidations
      conversa.reload
    end

    it 'com a Fase 2: volta para o agente pelo "Passar para", com o nome dele' do
      passou(conversation, origem: porta, para: ana)

      expect(described_class.de(com_a_ana!)).to eq(tipo: 'ia', id: agente_da_porta.id, name: 'Porta')
    end

    it 'o nome é o do agente agora; o espelho sem nome não importa', :aggregate_failures do
      passou(conversation, origem: porta, para: ana)
      agente_da_porta.update_columns(name: 'Gabriela') # rubocop:disable Rails/SkipsModelValidations
      porta.update_columns(name: '') # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(com_a_ana!)[:name]).to eq('Gabriela')
    end

    # Pega o botão para um agente que não atenderia: ele recusaria com `nao_atende_cliente`.
    it 'agente pausado: nada' do
      passou(conversation, origem: porta, para: ana)
      agente_da_porta.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(com_a_ana!)).to be_nil
    end

    it 'agente desligado: nada' do
      passou(conversation, origem: porta, para: ana)
      agente_da_porta.update_columns(enabled: false) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(com_a_ana!)).to be_nil
    end

    it 'os Agentes desligados na conta: nada' do
      passou(conversation, origem: porta, para: ana)
      allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(false)

      expect(described_class.de(com_a_ana!)).to be_nil
    end

    # Sem a Fase 2 não há "Passar para": a devolução é a atribuição de robô, para o espelho do vínculo na caixa.
    it 'sem a Fase 2: volta pela atribuição de robô, para o espelho do agente nesta caixa' do
      passou(conversation, origem: porta, para: ana)
      Autonomia::Agents::Fase2.desligar!(account)

      expect(described_class.de(com_a_ana!)).to eq(tipo: 'robo', id: porta.id, name: 'Porta')
    end

    it 'vínculo removido: nada' do
      passou(conversation, origem: espelho_area, para: ana)
      area_sumiu!

      expect(described_class.de(com_a_ana!)).to be_nil
    end

    it 'a IA passou sem ponta gravada: o primeiro robô ativo da caixa que atende, pela regra do agente' do
      passou(conversation, origem: nil, para: ana)

      expect(described_class.de(com_a_ana!)).to eq(tipo: 'ia', id: agente_da_porta.id, name: 'Porta')
    end

    it 'sem ponta gravada e o agente da caixa pausado: nada (o mesmo filtro do agente)' do
      passou(conversation, origem: nil, para: ana)
      Autonomia::Agents::Agent.where(account: account).update_all(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.de(com_a_ana!)).to be_nil
    end

    # Pega o N+1 no caminho do agente nosso: vínculos e agentes numa leitura só.
    it 'na lista, o caminho do agente nosso não cresce com o número de conversas', :aggregate_failures do
      conversas = Array.new(4) do
        create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload.tap do |conversa|
          passou(conversa, origem: porta, para: ana)
          com_a_ana!(conversa)
        end
      end

      uma = contar_consultas { described_class.da_lista(conversas.first(1)) }
      quatro = contar_consultas { described_class.da_lista(conversas) }

      expect(quatro).to eq(uma)
      expect(described_class.da_lista(conversas).values.uniq).to eq([{ tipo: 'ia', id: agente_da_porta.id, name: 'Porta' }])
    end

    # Decisão 3 do Rodrigo (22/10): a Lia (Agente de Cotação) é IA como as outras, sem mexer na estrutura dela.
    it 'a Lia (insurance_quote) é IA: a conversa que veio dela oferece "Devolver para Lia"' do
      lia = criar_agente('Lia', agent_type: 'insurance_quote')
      espelho_da_lia = Autonomia::Agents::Areas.vincular!(agent: lia, inbox: inbox).agent_bot
      passou(conversation, origem: espelho_da_lia, para: ana)

      expect(described_class.de(com_a_ana!)).to eq(tipo: 'ia', id: lia.id, name: 'Lia')
    end
  end
end
