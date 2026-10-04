require 'rails_helper'

RSpec.describe 'Super Admin Instagram account feature', type: :request do
  let(:account) { create(:account, internal_attributes: { 'unrelated' => 'preserved' }) }
  let(:path) { "/super_admin/accounts/#{account.id}" }
  let(:marker) { Instagram::Automation::AccountRollout::MARKER }
  let(:feature_params) do
    if ChatwootApp.enterprise?
      { enabled_features: account.all_features.transform_keys { |key| "feature_#{key}" }.transform_values(&:to_s)
                                 .merge('feature_instagram_assisted_onboarding' => 'false') }
    else
      { account: { feature_instagram_assisted_onboarding: '0' } }
    end
  end

  before do
    sign_in(create(:super_admin), scope: :super_admin)
    account.enable_features!('channel_instagram', 'instagram_assisted_onboarding', 'labels')
  end

  it 'shows exactly one native checkbox using the edition account form' do
    get "#{path}/edit"
    expect(response).to have_http_status(:ok)
    name = ChatwootApp.enterprise? ? 'enabled_features[feature_instagram_assisted_onboarding]' : 'account[feature_instagram_assisted_onboarding]'
    inputs = Nokogiri::HTML(response.body).css('input[type="checkbox"]').select { |input| input['name'] == name }
    expect(inputs.size).to eq(1)
    expect(inputs.first['checked']).to be_present
  end

  { 'en' => 'Instagram assisted onboarding', 'pt_BR' => 'Conexão assistida do Instagram' }.each do |locale, accessible_name|
    it "associates the edition checkbox with its readable #{locale} label" do
      I18n.with_locale(locale) { get "#{path}/edit" }
      expect(response).to have_http_status(:ok)
      name = ChatwootApp.enterprise? ? 'enabled_features[feature_instagram_assisted_onboarding]' : 'account[feature_instagram_assisted_onboarding]'
      document = Nokogiri::HTML(response.body)
      inputs = document.css('input[type="checkbox"]').select { |input| input['name'] == name }
      expect(inputs.size).to eq(1)
      checkbox = inputs.first
      expect(checkbox['id']).to be_present
      labels = document.css('label[for]').select { |label| label['for'] == checkbox['id'] }
      expect(labels.size).to eq(1)
      expect(labels.first.text.squish).to eq(accessible_name)
      expect(labels.first['class'].split).to include('min-h-11', 'min-w-11') if ChatwootApp.enterprise?
    end

    # Keep DOM accessibility and the saved OFF decision verified in the same request flow.
    # rubocop:disable RSpec/MultipleExpectations
    it "keeps the OFF checkbox labelled in #{locale} and preserves its rollout marker" do
      patch path, params: feature_params.deep_merge(account: { name: account.name })
      expect(response).to have_http_status(:redirect)
      I18n.with_locale(locale) { get "#{path}/edit" }
      expect(response).to have_http_status(:ok)
      name = ChatwootApp.enterprise? ? 'enabled_features[feature_instagram_assisted_onboarding]' : 'account[feature_instagram_assisted_onboarding]'
      document = Nokogiri::HTML(response.body)
      checkbox = document.css('input[type="checkbox"]').find { |input| input['name'] == name }
      expect(checkbox).to be_present
      expect(checkbox['checked']).to be_nil
      label = document.css('label[for]').find { |element| element['for'] == checkbox['id'] }
      expect(label).to be_present
      expect(label.text.squish).to eq(accessible_name)
      expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be false
      expect(account.internal_attributes).to eq('unrelated' => 'preserved', marker => true)
    end
    # rubocop:enable RSpec/MultipleExpectations
  end

  it 'atomically saves a manual OFF and marker before rollout, preserving other features and attributes' do
    previous_bits = account.feature_flags
    patch path, params: feature_params.deep_merge(account: { name: account.name })
    expect(response).to have_http_status(:redirect)
    expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be false
    expect(account.feature_flags).to eq(previous_bits)
    expect(account.internal_attributes).to eq('unrelated' => 'preserved', marker => true)

    rollout = Instagram::Automation::AccountRollout.new
    expect(rollout.call[:processed]).to eq(1)
    expect(rollout.call(dry_run: false, confirmation: 'instagram_assisted_onboarding')[:processed]).to eq(1)
    expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be false
  end

  it 'does not persist either the marker or feature on an invalid account edit' do
    patch path, params: feature_params.deep_merge(account: { name: '' })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be true
    expect(account.internal_attributes).not_to have_key(marker)
  end

  it 'keeps the marker and OFF through later unrelated account edits' do
    patch path, params: feature_params.deep_merge(account: { name: account.name })
    patch path, params: { account: { name: 'Renamed account' } }
    expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be false
    expect(account.internal_attributes[marker]).to be true
  end

  it 'does not mark an unrelated edit as an Instagram rollout decision' do
    patch path, params: { account: { name: 'Renamed account' } }
    expect(account.reload.internal_attributes).not_to have_key(marker)
  end

  it 'does not grant the denied channel when enabling assisted onboarding' do
    account.disable_features!('channel_instagram', 'instagram_assisted_onboarding')
    on_params = if ChatwootApp.enterprise?
                  { enabled_features: { feature_instagram_assisted_onboarding: 'true', feature_channel_instagram: 'false' } }
                else
                  { account: { feature_instagram_assisted_onboarding: '1' } }
                end
    patch path, params: on_params.deep_merge(account: { name: account.name })
    expect(response).to have_http_status(:redirect)
    expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be true
    expect(account.feature_enabled?('channel_instagram')).to be false
    expect(account.internal_attributes[marker]).to be true
  end

  it 'rejects unauthenticated flag edits' do
    sign_out(:super_admin)
    patch path, params: feature_params.deep_merge(account: { name: account.name })
    expect(response).to have_http_status(:redirect)
    expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be true
    expect(account.internal_attributes).not_to have_key(marker)
  end
end
