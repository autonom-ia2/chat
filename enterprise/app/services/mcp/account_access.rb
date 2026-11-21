# The accounts a connected app may act on: every active account the user administers (#3106).
# One connection covers them all, and the list is read on every call, so an account the user starts
# administering is in at once, and one they stop administering, or that gets suspended, is out at once.
class Mcp::AccountAccess
  def initialize(user)
    @user = user
  end

  def account_users
    return AccountUser.none if @user.nil?

    @user.account_users.administrator.joins(:account).merge(Account.active).includes(:account).order(:account_id)
  end

  def any?
    account_users.exists?
  end

  def find(account_id)
    account_users.find_by(account_id: account_id) if account_id.present?
  end
end
