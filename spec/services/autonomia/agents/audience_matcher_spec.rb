require 'rails_helper'

# #284 (Entrega 2a) — público-alvo do agente Autonom.ia: mesma semântica do Captain/segmentos.
RSpec.describe Autonomia::Agents::AudienceMatcher do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, :with_email, :with_phone_number, account: account,
                                                      additional_attributes: { 'country_code' => 'BR', 'city' => 'Curitiba' },
                                                      custom_attributes: { 'plan_tier' => 'paid' })
  end
  let(:conversation) do
    create(:conversation, account: account, contact: contact, additional_attributes: { 'browser_language' => 'pt' })
  end

  def leaf(attribute_key, filter_operator, values = nil)
    { 'attribute_key' => attribute_key, 'filter_operator' => filter_operator, 'values' => Array(values) }
  end

  def matches?(audience)
    described_class.new(audience).matches?(contact, conversation)
  end

  it 'matches everyone when the audience is blank' do
    expect(matches?(nil)).to be(true)
    expect(matches?({})).to be(true)
  end

  it 'matches contact standard, additional and custom attributes' do
    expect(matches?(leaf('country_code', 'equal_to', 'br'))).to be(true)
    expect(matches?(leaf('country_code', 'equal_to', 'us'))).to be(false)
    expect(matches?(leaf('plan_tier', 'equal_to', 'paid'))).to be(true)
    expect(matches?(leaf('email', 'contains', contact.email[2..5]))).to be(true)
    expect(matches?(leaf('city', 'starts_with', 'Cur'))).to be(true)
    expect(matches?(leaf('phone_number', 'equal_to', contact.phone_number.delete('+')))).to be(true)
    expect(matches?(leaf('identifier', 'is_not_present'))).to be(true)
  end

  it 'compares numeric custom attributes with UI strings' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                         attribute_display_type: :number, attribute_key: 'annual_spend')
    contact.update!(custom_attributes: contact.custom_attributes.merge('annual_spend' => 120.5))

    expect(matches?(leaf('annual_spend', 'equal_to', '120.5'))).to be(true)
    expect(matches?(leaf('annual_spend', 'equal_to', '120.6'))).to be(false)
  end

  it 'treats a missing checkbox attribute as false' do
    create(:custom_attribute_definition, account: account, attribute_key: 'newsletter_opt_in',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'checkbox')

    expect(matches?(leaf('newsletter_opt_in', 'equal_to', 'false'))).to be(true)
    expect(matches?(leaf('newsletter_opt_in', 'not_equal_to', 'true'))).to be(true)
  end

  it 'supports labels, days_before and browser language' do
    contact.update_labels(%w[vip])
    contact.update!(created_at: 40.days.ago)

    expect(matches?(leaf('labels', 'equal_to', %w[enterprise vip]))).to be(true)
    expect(matches?(leaf('labels', 'not_equal_to', %w[vip]))).to be(false)
    expect(matches?(leaf('created_at', 'days_before', '30'))).to be(true)
    expect(matches?(leaf('created_at', 'days_before', '60'))).to be(false)
    expect(matches?(leaf('browser_language', 'equal_to', 'pt'))).to be(true)
  end

  it 'evaluates OR inside AND with the right precedence' do
    audience = {
      'operator' => 'and',
      'conditions' => [
        leaf('country_code', 'equal_to', 'BR'),
        { 'operator' => 'or', 'conditions' => [leaf('plan_tier', 'equal_to', 'free'), leaf('plan_tier', 'equal_to', 'paid')] }
      ]
    }
    expect(matches?(audience)).to be(true)

    audience['conditions'][0] = leaf('country_code', 'equal_to', 'US')
    expect(matches?(audience)).to be(false)
  end
end
