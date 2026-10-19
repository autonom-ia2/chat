require 'rails_helper'
require Rails.root.join('db/migrate/20261108181000_add_campaign_send_to_custom_roles.rb')

# #1898 — quem já disparava campanhas pelo `campaign_manage` continua disparando depois da divisão.
RSpec.describe AddCampaignSendToCustomRoles do
  let(:account) { create(:account) }
  let!(:marketing) { create(:custom_role, account: account, permissions: %w[campaign_manage contact_view]) }
  let!(:leitor) { create(:custom_role, account: account, permissions: %w[campaign_view]) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  it 'dá campaign_send a quem tem campaign_manage, uma vez só' do
    2.times { described_class.new.up }

    expect(marketing.reload.permissions).to eq(%w[campaign_manage contact_view campaign_send])
    expect(leitor.reload.permissions).to eq(%w[campaign_view])
  end

  it 'o down tira a chave' do
    described_class.new.up
    described_class.new.down

    expect(marketing.reload.permissions).to eq(%w[campaign_manage contact_view])
  end
end
