require 'rails_helper'

RSpec.describe Instagram::RefreshTokensJob do
  let(:refresh_url) { 'https://graph.instagram.com/refresh_access_token' }

  def stub_refresh(status:, body: {})
    stub_request(:get, refresh_url).with(query: hash_including(grant_type: 'ig_refresh_token'))
                                   .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # The factory subscribes the channel on create, which reads the token. Create it fresh (not eligible
  # for refresh yet) and age it afterwards so the refresh happens inside the job.
  def channel_expiring_in(duration, token_age:)
    create(:channel_instagram, updated_at: Time.current).tap do |channel|
      channel.update_columns(expires_at: duration.from_now, updated_at: token_age.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'refreshes a token expiring within the refresh window' do
    channel = channel_expiring_in(5.days, token_age: 55.days)
    stub_refresh(status: 200, body: { access_token: 'renewed-token', expires_in: 60.days.to_i })

    described_class.perform_now

    channel.reload
    expect(channel[:access_token]).to eq('renewed-token')
    expect(channel.expires_at).to be > 59.days.from_now
  end

  it 'does not touch a token that expires later' do
    channel = channel_expiring_in(40.days, token_age: 20.days)
    stub = stub_refresh(status: 200, body: { access_token: 'renewed-token', expires_in: 60.days.to_i })

    described_class.perform_now

    expect(stub).not_to have_been_requested
    expect(channel.reload[:access_token]).not_to eq('renewed-token')
  end

  it 'ignores expired or revoked tokens' do
    channel_expiring_in(-1.hour, token_age: 61.days)
    stub = stub_refresh(status: 200, body: { access_token: 'renewed-token', expires_in: 60.days.to_i })

    described_class.perform_now

    expect(stub).not_to have_been_requested
  end

  it 'flags the inbox for reconnection when the refresh fails close to expiry' do
    channel = channel_expiring_in(1.day, token_age: 59.days)
    stub_refresh(status: 400, body: { error: { message: 'invalid token' } })

    described_class.perform_now

    expect(channel.reload.reauthorization_required?).to be true
  end

  it 'does not flag a record updated in the last 24 hours, which Meta would not refresh yet' do
    channel = channel_expiring_in(1.day, token_age: 2.hours)
    stub = stub_refresh(status: 200, body: { access_token: 'renewed-token', expires_in: 60.days.to_i })

    described_class.perform_now

    expect(stub).not_to have_been_requested
    expect(channel.reload.reauthorization_required?).to be false
  end

  it 'clears a previous reconnection flag after a successful refresh' do
    channel = channel_expiring_in(1.day, token_age: 59.days)
    channel.prompt_reauthorization!
    stub_refresh(status: 200, body: { access_token: 'renewed-token', expires_in: 60.days.to_i })

    described_class.perform_now

    expect(channel.reload.reauthorization_required?).to be false
  end

  it 'keeps the inbox connected when the refresh fails with time left to retry' do
    channel = channel_expiring_in(6.days, token_age: 54.days)
    stub_refresh(status: 400, body: { error: { message: 'temporary' } })

    described_class.perform_now

    expect(channel.reload.reauthorization_required?).to be false
  end
end
