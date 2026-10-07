require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::MjmlSections, :aggregate_failures do
  include EmailAdjustFixture

  let(:sections) { described_class.parse(adjust_base_mjml) }

  it 'numbers the blocks the model may change and keeps the locked footer out of them' do
    expect(sections.editable.map(&:id)).to eq(%w[b1 b2])
    expect(sections.editable.map(&:mjml)).to eq([EmailAdjustFixture::HERO, EmailAdjustFixture::FAQ])
    expect(sections.editable.map(&:mjml).join).not_to include('footer-locked')
  end

  it 'gives the e-mail back unchanged when every block is kept' do
    expect(sections.assemble([{ 'keep' => 'b1', 'mjml' => '' }, { 'keep' => 'b2', 'mjml' => '' }])).to eq(sections.canonical)
  end

  it 'removes, rewrites and adds blocks and always ends with the same footer' do
    new_block = '<mj-section><mj-column><mj-text>Novo</mj-text></mj-column></mj-section>'
    result = sections.assemble([{ 'keep' => '', 'mjml' => new_block }, { 'keep' => 'b1', 'mjml' => '' }])

    expect(result).to include(new_block, EmailAdjustFixture::HERO)
    expect(result).not_to include('Perguntas frequentes')
    expect(result.index(new_block)).to be < result.index(EmailAdjustFixture::HERO)
    expect(result).to end_with("#{EmailCampaigns::LockedFooter::MJML}</mj-body></mjml>")
  end

  it 'leaves out unknown ids and reports them' do
    result = sections.assemble([{ 'keep' => 'b9', 'mjml' => '' }, { 'keep' => 'b2', 'mjml' => '' }])

    expect(sections.unknown_ids).to eq(['b9'])
    expect(result).to include(EmailAdjustFixture::FAQ)
  end

  it 'keeps the head and the mj-body attributes as they were' do
    mjml = "<mjml><mj-head><mj-title>Oi</mj-title></mj-head><mj-body background-color=\"#eeeeee\">#{EmailAdjustFixture::FAQ}" \
           "#{EmailCampaigns::LockedFooter::MJML}</mj-body></mjml>"

    result = described_class.parse(mjml).assemble([])

    expect(result).to start_with('<mjml><mj-head><mj-title>Oi</mj-title></mj-head><mj-body background-color="#eeeeee">')
  end

  it 'refuses MJML without a body' do
    expect(described_class.parse('<mj-section></mj-section>')).to be_nil
  end
end
