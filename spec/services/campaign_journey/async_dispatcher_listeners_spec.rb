require 'rails_helper'

# #1002: the reply-mark listener is on the async dispatcher whatever the initializer order.
RSpec.describe CampaignJourney::AsyncDispatcherListeners do
  let(:listener) { CampaignJourney::ReplyMarkListener.instance }

  def registrations_of(async)
    async.send(:local_registrations).count { |registration| registration.try(:listener).equal?(listener) }
  end

  it 'is subscribed exactly once on the booted dispatcher' do
    expect(registrations_of(Rails.configuration.dispatcher.async_dispatcher)).to eq(1)
  end

  it 'subscribes when listeners are loaded after the prepend (initializer before event_handlers)' do
    async = AsyncDispatcher.new
    async.load_listeners

    expect(registrations_of(async)).to eq(1)
  end

  it 'adds the listener to a dispatcher that loaded its listeners before the prepend' do
    without_journey = Class.new(BaseDispatcher) { def listeners = [CampaignListener.instance] }.new
    without_journey.load_listeners
    dispatcher = instance_double(Dispatcher, async_dispatcher: without_journey)

    expect(described_class.ensure_subscribed!(dispatcher)).to be(true)
    expect(described_class.ensure_subscribed!(dispatcher)).to be(false)
    expect(registrations_of(without_journey)).to eq(1)
  end

  it 'does not subscribe twice when ensure_subscribed! ran before load_listeners' do
    async = AsyncDispatcher.new
    described_class.ensure_subscribed!(instance_double(Dispatcher, async_dispatcher: async))
    async.load_listeners

    expect(registrations_of(async)).to eq(1)
  end

  it 'does nothing before the dispatcher exists' do
    expect(described_class.ensure_subscribed!(nil)).to be(false)
  end
end
