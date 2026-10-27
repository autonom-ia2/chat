# #2200: creating a Channel::FacebookPage reads and writes the Page's subscribed_apps (Crm::MetaAds::PageSubscription).
# Every spec answers it with "no app subscribed yet"; a spec that cares stubs the same URL again, and the later
# stub wins.
module MetaPageSubscriptionStub
  SUBSCRIBED_APPS = ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/subscribed_apps') }
end

RSpec.configure do |config|
  config.before do
    stub_request(:any, MetaPageSubscriptionStub::SUBSCRIBED_APPS)
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: [] }.to_json)
  end
end
