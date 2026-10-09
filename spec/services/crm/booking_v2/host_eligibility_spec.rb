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

  it 'aceita função personalizada com CRM ou agendamento e recusa a que não tem nenhum' do
    with_crm = create(:user, account: account, role: :agent).tap { |user| grant(user, 'crm_view') }
    with_booking = create(:user, account: account, role: :agent).tap { |user| grant(user, 'agendamento_view') }
    unrelated = create(:user, account: account, role: :agent).tap { |user| grant(user, 'report_manage') }

    expect(described_class.eligible?(account: account, user: with_crm)).to be(true)
    expect(described_class.eligible?(account: account, user: with_booking)).to be(true)
    expect(described_class.eligible?(account: account, user: unrelated)).to be(false)
  end
end
