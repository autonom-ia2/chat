require 'rails_helper'

RSpec.describe Relationships::CompanyMediaQuery do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { create(:company, account: account) }
  let(:contact) { create(:contact, account: account, company: company) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let!(:attachment) do
    message.attachments.create!(account: account, file: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png'))
  end

  it 'uses the real current company association, preserving attachment occurrences' do
    query = described_class.new(company, admin, {})
    expect(query.scope.pluck(:id)).to include(attachment.id)
    contact.update!(company_id: nil, additional_attributes: { company_name: company.name })
    expect(described_class.new(company, admin, {}).scope).to be_empty
  end

  it 'searches filenames in the database and bounds pages' do
    expect(described_class.new(company, admin, { 'q' => 'sample' }).scope.pluck(:id)).to include(attachment.id)
    expect(described_class.new(company, admin, { 'q' => 'absent' }).scope).to be_empty
    expect { described_class.new(company, admin, { 'per_page' => '1000' }) }.to raise_error(Relationships::Configuration::Invalid)
  end

  it 'excludes inaccessible conversations before counts' do
    agent = create(:user, account: account, role: :agent)
    expect(described_class.new(company, agent, {}).scope.count).to eq(0)
  end
end
