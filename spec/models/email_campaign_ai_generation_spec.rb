require 'rails_helper'

# EmailCampaign#ai_succeed! takes the draft as a hash (#1076). Its only caller is
# EmailCampaigns::Ai::PollJob#succeed (spec/jobs/email_campaigns/ai/poll_job_quality_spec.rb runs it for real).
RSpec.describe EmailCampaign, :aggregate_failures do
  let(:campaign) { create(:email_campaign, subject: 'Antigo') }
  let(:draft) { { subject: ' Novo ', preheader: 'Prévia', body_mjml: '<mjml></mjml>', subject_variants: %w[a b c] } }

  it 'writes the draft, the identity used and the warnings of the active generation' do
    token = campaign.ai_begin!

    won = campaign.ai_succeed!(token, draft, brand_identity: { 'kit_id' => 1, 'name' => 'Hub2You', 'mode' => 'light' },
                                             quality_warnings: [{ 'check' => 'contrast', 'detail' => 'x' }])

    expect(won).to be(true)
    expect(campaign.reload).to have_attributes(
      subject: 'Novo', preheader: 'Prévia', body_mjml: '<mjml></mjml>', ai_subject_variants: %w[a b c], ai_status: 'ready',
      brand_identity: { 'kit_id' => 1, 'name' => 'Hub2You', 'mode' => 'light' },
      ai_quality_warnings: [{ 'check' => 'contrast', 'detail' => 'x' }]
    )
  end

  it 'keeps the old subject when the draft has none and defaults identity and warnings to empty' do
    token = campaign.ai_begin!

    campaign.ai_succeed!(token, draft.merge(subject: ''))

    expect(campaign.reload).to have_attributes(subject: 'Antigo', brand_identity: {}, ai_quality_warnings: [])
  end

  it 'writes nothing for a superseded generation' do
    old = campaign.ai_begin!
    campaign.ai_begin!

    expect(campaign.ai_succeed!(old, draft)).to be(false)
    expect(campaign.reload).to have_attributes(subject: 'Antigo', ai_status: 'processing')
  end
end
