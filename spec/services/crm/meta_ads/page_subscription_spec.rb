require 'rails_helper'

RSpec.describe Crm::MetaAds::PageSubscription do
  subject(:subscription) { described_class.new(page_id: page_id, access_token: token, app_id: app_id, api_version: 'v22.0') }

  let(:page_id) { '1234567890' }
  let(:token) { 'page-token-not-a-real-secret' }
  let(:app_id) { '544486745144318' }
  let(:url) { "https://graph.facebook.com/v22.0/#{page_id}/subscribed_apps" }

  def stub_current(apps)
    stub_request(:get, url).with(headers: { 'Authorization' => "Bearer #{token}" })
                           .to_return(status: 200, body: { data: apps }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_post(fields)
    stub_request(:post, url).with(body: { subscribed_fields: fields.join(',') }, headers: { 'Authorization' => "Bearer #{token}" })
                            .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fields' do
    it 'returns only the fields of this app' do
      stub_current([{ id: '1', subscribed_fields: ['feed'] }, { id: app_id, subscribed_fields: %w[messages leadgen] }])

      expect(subscription.fields).to eq(%w[messages leadgen])
    end

    it 'returns an empty list when the app is not subscribed to the page' do
      stub_current([])

      expect(subscription.fields).to eq([])
    end
  end

  describe '#add!' do
    it 'posts the union of the current fields and the new ones' do
      stub_current([{ id: app_id, subscribed_fields: %w[messages feed] }])
      post = stub_post(%w[messages feed leadgen])

      subscription.add!(%w[leadgen])

      expect(post).to have_been_requested
    end

    it 'does not post when every field is already subscribed' do
      stub_current([{ id: app_id, subscribed_fields: %w[leadgen feed] }])

      subscription.add!(%w[leadgen])

      expect(a_request(:post, url)).not_to have_been_made
    end
  end

  describe '#remove!' do
    it 'posts the fields that remain' do
      stub_current([{ id: app_id, subscribed_fields: %w[messages leadgen feed] }])
      post = stub_post(%w[messages feed])

      subscription.remove!(%w[leadgen])

      expect(post).to have_been_requested
    end

    it 'removes the app from the page when no field remains' do
      stub_current([{ id: app_id, subscribed_fields: %w[leadgen] }])
      delete = stub_request(:delete, url).with(headers: { 'Authorization' => "Bearer #{token}" })
                                         .to_return(status: 200, body: { success: true }.to_json)

      subscription.remove!(%w[leadgen])

      expect(delete).to have_been_requested
      expect(a_request(:post, url)).not_to have_been_made
    end

    it 'does nothing when the fields are not subscribed' do
      stub_current([{ id: app_id, subscribed_fields: %w[feed] }])

      subscription.remove!(%w[leadgen])

      expect(a_request(:post, url)).not_to have_been_made
      expect(a_request(:delete, url)).not_to have_been_made
    end
  end

  describe '.for_instagram' do
    subject(:subscription) { described_class.for_instagram(instagram_id: '1784', access_token: token, api_version: 'v22.0') }

    let(:url) { 'https://graph.instagram.com/v22.0/1784/subscribed_apps' }

    it 'keeps the Direct fields when adding comments on graph.instagram.com' do
      stub_current([{ subscribed_fields: %w[messages message_reactions] }])
      post = stub_post(%w[messages message_reactions comments])

      subscription.add!(%w[comments])

      expect(post).to have_been_requested
    end
  end

  it 'raises with the Meta error code and never the token' do
    stub_request(:get, url).to_return(
      status: 400, headers: { 'Content-Type' => 'application/json' },
      body: { error: { code: 190, message: "Invalid OAuth access token #{token}abcdefghij" } }.to_json
    )

    expect { subscription.fields }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq(190)
      expect(error).not_to be_transient
      expect(error.message).not_to include(token)
    }
  end

  it 'marks a usage limit as transient' do
    stub_request(:get, url).to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                                      body: { error: { code: 4, message: 'Application request limit reached' } }.to_json)

    expect { subscription.fields }.to raise_error(described_class::Error, &:transient?)
  end

  it 'marks a network failure as transient' do
    stub_request(:get, url).to_timeout

    expect { subscription.fields }.to raise_error(described_class::Error) { |error| expect(error).to be_transient }
  end

  it 'marks a missing permission as a refusal' do
    stub_request(:get, url).to_return(status: 403, headers: { 'Content-Type' => 'application/json' },
                                      body: { error: { code: 200, message: 'Permissions error' } }.to_json)

    expect { subscription.fields }.to raise_error(described_class::Error) { |error| expect(error).not_to be_transient }
  end
end
