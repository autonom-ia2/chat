require 'rails_helper'

# #2414 review: one rule for the contact data of any audience, the contact base's own (ContactPolicy#index?).
RSpec.describe ConversationAudience::Access do
  let(:account) { create(:account) }

  def account_user_with(role: :agent, permissions: nil)
    user = create(:user, account: account, role: role)
    account_user = user.account_users.find_by(account: account)
    account_user.update!(custom_role: create(:custom_role, account: account, permissions: permissions)) if permissions
    account_user
  end

  describe '.hides_contact_data?' do
    it 'hides from a custom role without contact_view and from nobody' do
      expect(described_class.hides_contact_data?(account_user_with(permissions: %w[campaign_view campaign_manage]))).to be(true)
      expect(described_class.hides_contact_data?(nil)).to be(true)
    end

    it 'shows to a custom role with contact_view or contact_manage, the administrator and a plain agent, like the contact base' do
      [account_user_with(permissions: %w[campaign_view contact_view]), account_user_with(permissions: %w[contact_manage]),
       account_user_with(role: :administrator), account_user_with].each do |account_user|
        expect(described_class.hides_contact_data?(account_user)).to be(false)
      end
    end
  end
end
