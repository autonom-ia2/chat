require 'rails_helper'

RSpec.describe Crm::Ai::HandoffMemberSelector do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:busy_agent) { create(:user, account: account) }
  let(:outsider) { create(:user, account: account) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: busy_agent)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
  end

  it 'uses the inbox member pool by default and balances round-robin by open conversation count' do
    create(:conversation, account: account, inbox: inbox, assignee: busy_agent)

    selected = described_class.new(inbox: inbox, account_id: account.id).perform

    expect(selected).to eq(agent)
  end

  it 'restricts the eligible pool to a valid user member id' do
    selected = described_class.new(
      inbox: inbox,
      account_id: account.id,
      pool_type: 'user',
      pool_id: busy_agent.id
    ).perform

    expect(selected).to eq(busy_agent)
  end

  it 'falls back to inbox members when user pool id is not an inbox member' do
    selected = described_class.new(
      inbox: inbox,
      account_id: account.id,
      pool_type: 'user',
      pool_id: outsider.id
    ).perform

    expect(selected).to be_present
    expect([agent, busy_agent]).to include(selected)
    expect(selected).not_to eq(outsider)
  end

  it 'respects require_online gating for a single-user pool' do
    selector = described_class.new(
      inbox: inbox,
      account_id: account.id,
      require_online: true,
      pool_type: 'user',
      pool_id: agent.id
    )

    expect(selector.perform).to be_nil
    expect(selector.held_for_online?).to be(true)
  end

  # Desempate do rodízio (#1140, decisão 10): empatados em conversas abertas, recebe quem recebeu há mais tempo (pelo
  # registro de passagens); depois, o menor id. A ordem de inbox.members (sem ORDER BY) não decide mais.
  describe 'empate em conversas abertas' do
    let(:conversa) { create(:conversation, account: account, inbox: inbox) }

    def recebeu(user, atras:, motivo: 'atribuicao')
      Crm::Passagem.create!(account: account, conversation: conversa, para_type: 'User', para_id: user.id, motivo: motivo,
                            em: atras.ago, created_at: atras.ago)
    end

    def escolhido(*fila)
      described_class.new(inbox: inbox, account_id: account.id, members: fila).perform
    end

    # Pega: o primeiro da lista recebia sempre, quase sempre a mesma pessoa.
    it 'recebe quem recebeu há mais tempo, qualquer que seja a ordem', :aggregate_failures do
      recebeu(agent, atras: 1.hour)
      recebeu(busy_agent, atras: 3.hours)

      expect(escolhido(agent, busy_agent)).to eq(busy_agent)
      expect(escolhido(busy_agent, agent)).to eq(busy_agent)
    end

    # Pega: quem nunca recebeu ficar atrás de quem acabou de receber.
    it 'quem nunca recebeu vem primeiro', :aggregate_failures do
      recebeu(agent, atras: 5.minutes)

      expect(escolhido(agent, busy_agent)).to eq(busy_agent)
      expect(escolhido(busy_agent, agent)).to eq(busy_agent)
    end

    # Pega: o convite (não recebeu a conversa) contar como recebida.
    it 'convite não conta como recebida' do
      recebeu(agent, atras: 3.hours)
      recebeu(busy_agent, atras: 1.hour, motivo: Crm::Passagens::CONVITE)

      expect(escolhido(agent, busy_agent)).to eq(busy_agent)
    end

    # Pega: empate total decidido pela ordem física dos membros (não determinístico).
    it 'empate total: o menor id', :aggregate_failures do
      primeiro, segundo = [agent, busy_agent].sort_by(&:id)

      expect(escolhido(segundo, primeiro)).to eq(primeiro)
      expect(escolhido(primeiro, segundo)).to eq(primeiro)
    end

    # Pega: o desempate passar por cima da carga (menos conversas abertas continua vencendo).
    it 'menos conversas abertas vence antes do desempate' do
      recebeu(busy_agent, atras: 10.hours)
      create(:conversation, account: account, inbox: inbox, assignee: busy_agent)

      expect(escolhido(busy_agent, agent)).to eq(agent)
    end
  end
end
