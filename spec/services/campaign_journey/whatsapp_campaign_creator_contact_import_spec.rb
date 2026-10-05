require 'rails_helper'

# #1006: a saved contact import (flow "contacts") has contacts, but it is not an audience and a
# campaign can never be linked to it, even when the caller reaches the creator directly.
RSpec.describe CampaignJourney::WhatsappCampaignCreator, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:channel) { journey_cloud_channel(account) }

  it 'refuses a contact import as the audience of a campaign' do
    contact_import = saved_audience(account: account, user: account_and_user.last, content: "Nome,Celular\nAna,11987654321\n")
    contact_import.update!(options: contact_import.options.merge('flow' => CampaignImport::CONTACTS_FLOW))
    expect(contact_import).to have_attributes(status: 'completed', imported_contacts_count: 1)

    creator = described_class.new(
      account: account, campaign_import: contact_import, channel: 'whatsapp_cloud',
      attributes: { title: 'Renovação', inbox_id: channel.inbox.id, template_params: journey_template_params,
                    variable_bindings: { '1' => { source: 'contact', value: 'first_name' } } }
    )

    expect { creator.perform }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('not_an_audience') }
    expect(account.campaigns.count).to eq(0)
    expect(CampaignAudienceLink.count).to eq(0)
    expect(account.campaign_imports.campaign_flows).not_to include(contact_import)
  end
end
