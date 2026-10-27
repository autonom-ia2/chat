require 'rails_helper'

RSpec.describe Crm::MetaAds::PageSubscription do
  subject(:subscription) { described_class.new(page_id: page_id, access_token: token, api_version: 'v22.0') }

  let(:page_id) { '1234567890' }
  let(:token) { 'page-token-not-a-real-secret' }
  let(:app_id) { '544486745144318' }
  let(:url) { "https://graph.facebook.com/v22.0/#{page_id}/subscribed_apps" }

  before do
    stub_request(:get, 'https://graph.facebook.com/v22.0/app').with(headers: { 'Authorization' => "Bearer #{token}" })
                                                              .to_return(status: 200, body: { id: app_id }.to_json,
                                                                         headers: { 'Content-Type' => 'application/json' })
  end

  def stub_current(apps)
    stub_request(:get, url).with(headers: { 'Authorization' => "Bearer #{token}" })
                           .to_return(status: 200, body: { data: apps }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # Uma resposta por leitura, na ordem: antes da escrita e a releitura que confere.
  def stub_reads(*lists)
    stub_request(:get, url).with(headers: { 'Authorization' => "Bearer #{token}" })
                           .to_return(*lists.map do |fields|
                             { status: 200, body: { data: [{ id: app_id, subscribed_fields: fields }] }.to_json,
                               headers: { 'Content-Type' => 'application/json' } }
                           end)
  end

  def stub_post(fields)
    stub_request(:post, url).with(body: { subscribed_fields: fields.join(',') }, headers: { 'Authorization' => "Bearer #{token}" })
                            .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fields' do
    it 'returns only the fields of the app that owns the token, never another app of the page' do
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
      stub_reads(%w[messages feed], %w[messages feed leadgen])
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
      stub_reads(%w[messages leadgen feed], %w[messages feed])
      post = stub_post(%w[messages feed])

      subscription.remove!(%w[leadgen])

      expect(post).to have_been_requested
    end

    it 'removes the app from the page when no field remains' do
      stub_reads(%w[leadgen], [])
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

  it 'reads nothing from config: with no token app, it never writes another app fields over this one' do
    stub_request(:get, url).to_return(
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: [{ id: '999', subscribed_fields: %w[leadgen feed] }] }.to_json },
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: [{ id: '999', subscribed_fields: %w[leadgen feed] }, { id: app_id, subscribed_fields: %w[messages] }] }.to_json }
    )
    post = stub_post(%w[messages])

    subscription.add!(%w[messages])

    expect(post).to have_been_requested
  end

  describe 'concurrent writers on the same page (#2200)' do
    let(:lock_key) { described_class.lock_key(page_id) }

    it 'writes again when another writer dropped the field between the POST and the check' do
      stub_reads(%w[messages feed], %w[messages feed], %w[messages feed leadgen])
      post = stub_post(%w[messages feed leadgen])

      subscription.add!(%w[leadgen])

      expect(post).to have_been_requested.twice
    end

    it 'raises a transient error when the page never keeps the field' do
      stub_reads(%w[feed], %w[feed], %w[feed])
      stub_post(%w[feed leadgen])

      expect { subscription.add!(%w[leadgen]) }.to raise_error(described_class::Error, &:transient?)
    end

    it 'waits for the page lock and gives up with a transient error, without writing' do
      stub_const("#{described_class}::LOCK_WAIT", 0.3.seconds)
      Redis::LockManager.new.lock(lock_key, 10)
      stub_reads(%w[feed])

      expect { subscription.add!(%w[leadgen]) }.to raise_error(described_class::Error, &:transient?)
      expect(a_request(:post, url)).not_to have_been_made
    ensure
      Redis::LockManager.new.unlock(lock_key)
    end

    it 'releases the page lock after writing and after failing' do
      stub_reads(%w[feed], %w[feed leadgen])
      stub_post(%w[feed leadgen])
      subscription.add!(%w[leadgen])
      expect(Redis::LockManager.new.locked?(lock_key)).to be(false)

      stub_request(:get, url).to_return(status: 500, body: '{}')
      expect { described_class.new(page_id: page_id, access_token: token, api_version: 'v22.0').add!(%w[feed]) }
        .to raise_error(described_class::Error)
      expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
    end
  end

  it 'turns an unreadable answer into a transient error without the token' do
    stub_request(:get, url).to_return(status: 200, body: '{not json', headers: { 'Content-Type' => 'application/json' })

    expect { subscription.fields }.to raise_error(described_class::Error) { |error|
      expect(error).to be_transient
      expect(error.message).not_to include(token)
    }
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
