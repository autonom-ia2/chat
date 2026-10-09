class AddCustomerSinceToContacts < ActiveRecord::Migration[7.2]
  def change
    add_column :contacts, :customer_since, :datetime
  end
end
