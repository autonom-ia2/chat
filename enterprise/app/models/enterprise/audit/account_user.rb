module Enterprise::Audit::AccountUser
  extend ActiveSupport::Concern

  included do
    audited only: [
      :availability,
      :role,
      :account_id,
      :inviter_id,
      :user_id,
      :custom_role_id
    ], on: [:create, :update, :destroy], associated_with: :account
  end
end
