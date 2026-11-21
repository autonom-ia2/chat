# The accounts a connected app may act on: every active account the user administers (#3106).
# One connection covers them all, and the list is read on every call, so an account the user starts
# administering is in at once, and one they stop administering, or that gets suspended, is out at once.
#
# A connection made before #3106 promised one account, so it stays on that one: it does not reach the others without a
# new consent. The token's `all_accounts` says which promise the user accepted; without it, only `account_id` counts,
# and a missing `account_id` reaches nothing.
class Mcp::AccountAccess
  def initialize(user, all_accounts:, account_id:)
    @user = user
    @all_accounts = all_accounts == true
    @account_id = account_id
  end

  def account_users
    return AccountUser.none if @user.nil?

    scope = @user.account_users.administrator.joins(:account).merge(Account.active).includes(:account).order(:account_id)
    @all_accounts ? scope : scope.where(account_id: @account_id)
  end

  def any?
    account_users.exists?
  end

  def find(account_id)
    account_users.find_by(account_id: account_id) if account_id.present?
  end
end
