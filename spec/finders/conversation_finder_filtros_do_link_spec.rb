require 'rails_helper'

# Filtros pelo link na caixa de conversas (Números F2, #1883): `da_ia=1` traz só as conversas que um agente de IA passou
# para a equipe (registro de passagens); `esperando_min=N` traz só as que esperam alguém há mais de N minutos
# (waiting_since). Os dois restringem a lista e as contagens das abas. No Spam e na Lixeira, a pasta manda.
RSpec.describe ConversationFinder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:outra_inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    Current.account = account
  end

  def conversa(assignee: nil, caixa: inbox, waiting_since: nil)
    create(:conversation, account: account, inbox: caixa, assignee: assignee).tap do |conversation|
      conversation.update!(waiting_since: waiting_since)
    end
  end

  def passagem(conversation, de_type:, motivo:, para_type: 'User', de_id: 1)
    Crm::Passagem.create!(account: account, conversation: conversation, de_type: de_type, de_id: de_type && de_id,
                          para_type: para_type, para_id: agent.id, motivo: motivo, em: Time.current)
  end

  def perform(user, **params)
    described_class.new(user, ActionController::Parameters.new({ assignee_type: 'all' }.merge(params))).perform
  end

  describe 'da_ia=1' do
    let!(:do_agente) { conversa(assignee: agent).tap { |c| passagem(c, de_type: 'Autonomia::Agents::Agent', motivo: 'passar_para') } }
    let!(:do_robo_externo) { conversa.tap { |c| passagem(c, de_type: 'AgentBot', motivo: 'atribuicao') } }
    let!(:robo_sem_origem) { conversa.tap { |c| passagem(c, de_type: nil, motivo: 'robo_pediu') } }
    let!(:sem_passagem) { conversa }

    # Não entram: de pessoa, de ninguém sem motivo de robô, pessoa → IA e IA → IA.
    before do
      passagem(conversa, de_type: 'User', motivo: 'atribuicao')
      passagem(conversa, de_type: nil, motivo: 'atribuicao')
      passagem(conversa, de_type: 'User', motivo: 'passar_para_ia', para_type: 'Autonomia::Agents::Agent')
      passagem(conversa, de_type: 'AgentBot', motivo: 'robo_pediu', para_type: 'Autonomia::Agents::Agent')
    end

    it 'traz só as que a IA passou para uma pessoa da equipe, e as abas contam o mesmo' do
      result = perform(admin, da_ia: '1')

      expect(result[:conversations]).to contain_exactly(do_agente, do_robo_externo, robo_sem_origem)
      expect(result[:count]).to eq(mine_count: 0, assigned_count: 1, unassigned_count: 2, all_count: 3)
    end

    it 'conversa com várias passagens da IA aparece uma vez só' do
      passagem(do_agente, de_type: 'Autonomia::Agents::Agent', motivo: 'ia_crm')

      expect(perform(admin, da_ia: '1')[:conversations].to_a.count(do_agente)).to eq(1)
    end

    it 'não fura a visibilidade: o agente só vê as das caixas dele' do
      fora = conversa(caixa: outra_inbox).tap { |c| passagem(c, de_type: 'AgentBot', motivo: 'n8n') }

      expect(perform(agent, da_ia: '1')[:conversations]).not_to include(fora)
      expect(perform(admin, da_ia: '1')[:conversations]).to include(fora)
    end

    it 'não lê passagem de outra conta' do
      outra = create(:account)
      Crm::Passagem.create!(account: outra, conversation: sem_passagem, de_type: 'AgentBot', de_id: 1, para_type: 'User',
                            para_id: agent.id, motivo: 'n8n', em: Time.current)

      expect(perform(admin, da_ia: '1')[:conversations]).not_to include(sem_passagem)
    end

    it 'outro valor é ignorado' do
      expect(perform(admin, da_ia: 'sim')[:conversations].size).to eq(8)
    end
  end

  describe 'esperando_min' do
    let!(:ha_uma_hora) { conversa(waiting_since: 1.hour.ago) }
    let!(:ha_dez_minutos) { conversa(waiting_since: 10.minutes.ago) }

    before { conversa(waiting_since: nil) } # respondida

    it 'traz só as que esperam há mais de N minutos' do
      result = perform(admin, esperando_min: '30')

      expect(result[:conversations]).to contain_exactly(ha_uma_hora)
      expect(result[:count][:all_count]).to eq(1)
    end

    it 'valor fora de 1..1440 ou que não é inteiro é ignorado' do
      ['0', '1441', '-5', 'abc', '30.5', '0x1e', '', ' 30', '+30', '1_0'].each do |valor|
        expect(perform(admin, esperando_min: valor)[:conversations].size).to eq(3), "valor #{valor.inspect}"
      end
    end

    it 'junto com da_ia, valem os dois' do
      passagem(ha_uma_hora, de_type: 'AgentBot', motivo: 'n8n')
      passagem(ha_dez_minutos, de_type: 'AgentBot', motivo: 'n8n')

      expect(perform(admin, da_ia: '1', esperando_min: '30')[:conversations]).to contain_exactly(ha_uma_hora)
    end
  end

  describe 'com as pastas do e-mail ligadas' do
    let!(:no_spam) { conversa }
    let!(:na_entrada_da_ia) { conversa.tap { |c| passagem(c, de_type: 'AgentBot', motivo: 'n8n') } }
    let!(:spam_da_ia) { conversa.tap { |c| passagem(c, de_type: 'AgentBot', motivo: 'n8n') } }

    before do
      account.enable_features!('conversa_email_nova')
      ConversaCanal::PastaDoEmail.create!(account: account, conversation: no_spam, pasta: 'spam')
      ConversaCanal::PastaDoEmail.create!(account: account, conversation: spam_da_ia, pasta: 'spam')
    end

    it 'no Spam a pasta manda: o filtro da IA e o da espera não se aplicam' do
      expect(perform(admin, pasta: 'spam', da_ia: '1', esperando_min: '30')[:conversations]).to contain_exactly(no_spam, spam_da_ia)
    end

    it 'fora da pasta, o filtro da IA não traz de volta o que está no Spam' do
      expect(perform(admin, da_ia: '1')[:conversations]).to contain_exactly(na_entrada_da_ia)
    end
  end
end
