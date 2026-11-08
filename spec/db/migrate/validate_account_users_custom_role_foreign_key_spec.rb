require 'rails_helper'
require Rails.root.join('db/migrate/20261108490000_validate_account_users_custom_role_foreign_key.rb')

# #2219: a chave account_users.custom_role_id -> custom_roles sai de NOT VALID (#2208) para válida, e o down volta.
RSpec.describe ValidateAccountUsersCustomRoleForeignKey do
  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  def validated?
    ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT convalidated FROM pg_constraint
      WHERE conrelid = 'account_users'::regclass AND confrelid = 'custom_roles'::regclass AND contype = 'f'
    SQL
  end

  it 'validates the key and the down goes back to NOT VALID, still checking new writes', :aggregate_failures do
    described_class.new.down
    expect(validated?).to be(false)

    described_class.new.up
    expect(validated?).to be(true)

    described_class.new.down
    account_user = create(:account_user)
    expect(validated?).to be(false)
    expect { account_user.update_column(:custom_role_id, CustomRole.maximum(:id).to_i + 1) } # rubocop:disable Rails/SkipsModelValidations
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
