require 'rails_helper'

# The cases live in a fixture shared with the editor's JS port (citationLinks.js, #1079), so the
# server (generation) and the editor (opening old drafts) link citations the same way.
RSpec.describe EmailCampaigns::Ai::CitationLinks do
  cases = JSON.parse(
    Rails.root.join(
      'app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/specs/fixtures/citationLinks.json'
    ).read
  )

  cases['text'].each do |example|
    it "text: #{example['name']}" do
      expect(described_class.new(example['input']).link).to eq(example['expected'])
    end
  end

  cases['mjml'].each do |example|
    it "mjml: #{example['name']}" do
      expect(described_class.call(example['input'])).to eq(example['expected'])
    end
  end
end
