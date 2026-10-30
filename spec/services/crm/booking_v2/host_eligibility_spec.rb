require 'rails_helper'

RSpec.describe Crm::BookingV2::HostEligibility do
  let(:account) { create(:account) }

  def grant(user, *permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
  end

  it 'aceita agente comum e administrador' do
    agent = create(:user, account: account, role: :agent)
    admin = create(:user, account: account, role: :administrator)

    expect(described_class.eligible?(account: account, user: agent)).to be(true)
    expect(described_class.eligible?(account: account, user: admin)).to be(true)
  end

  it 'recusa quem não é da conta ou quem saiu dela' do
    stranger = create(:user, account: create(:account), role: :agent)
    leaver = create(:user, account: account, role: :agent)
    leaver.account_users.find_by(account: account).destroy!

    expect(described_class.eligible?(account: account, user: stranger)).to be(false)
    expect(described_class.eligible?(account: account, user: leaver)).to be(false)
    expect(described_class.eligible?(account: account, user: nil)).to be(false)
  end

  it 'recusa membro de integração (token de API), mesmo sem função' do
    bot = create(:user)
    create(:account_user, account: account, user: bot, integration: true)

    expect(described_class.eligible?(account: account, user: bot)).to be(false)
  end

  # Mesmo critério de quem vê card (Enterprise::Crm::CardPolicy#index?): crm_view ou crm_admin.
  it 'com função personalizada, aceita só quem vê card (crm_view ou crm_admin)' do
    with_view = create(:user, account: account, role: :agent).tap { |user| grant(user, 'crm_view') }
    with_admin = create(:user, account: account, role: :agent).tap { |user| grant(user, 'crm_admin') }
    expect(described_class.eligible?(account: account, user: with_view)).to be(true)
    expect(described_class.eligible?(account: account, user: with_admin)).to be(true)

    { 'agendamento_view' => %w[agendamento_view], 'agendamento_manage' => %w[agendamento_manage],
      'crm_view_reports' => %w[crm_view_reports], 'sales_value_view' => %w[sales_value_view],
      'report_manage' => %w[report_manage] }.each do |label, keys|
      user = create(:user, account: account, role: :agent).tap { |member| grant(member, *keys) }
      expect(described_class.eligible?(account: account, user: user)).to be(false), "#{label} não deveria bastar"
    end
  end

  # #2124: chave de editar o CRM grava crm_view junto, então quem edita cards também atende.
  it 'aceita quem tem só uma chave de editar o CRM' do
    CustomRole::CRM_EDITING_KEYS.each do |key|
      user = create(:user, account: account, role: :agent).tap { |member| grant(member, key) }
      expect(described_class.eligible?(account: account, user: user)).to be(true), "#{key} deveria bastar"
      expect(described_class.eligible_user_ids(account: account)).to include(user.id)
    end
  end

  # #1305: a mesma regra numa consulta, para a lista de páginas não perguntar pessoa por pessoa.
  it 'eligible_user_ids dá o mesmo resultado de eligible? para cada pessoa da conta' do
    agent = create(:user, account: account, role: :agent)
    admin = create(:user, account: account, role: :administrator)
    sem_cards = create(:user, account: account, role: :agent)
    com_cards = create(:user, account: account, role: :agent)
    grant(sem_cards, 'agendamento_manage')
    grant(com_cards, 'crm_view')
    create(:user, account: create(:account), role: :agent)
    create(:account_user, account: account, user: create(:user), integration: true)

    ids =described_class.eligible_user_ids(account: account)

    expect(ids).to eq(Set[agent.id, admin.id, com_cards.id])
    [agent, admin, sem_cards, com_cards].each do |user|
      expect(ids.include?(user.id)).to eq(described_class.eligible?(account: account, user: user))
    end
  end
end
