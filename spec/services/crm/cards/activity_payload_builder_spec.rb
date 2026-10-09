require 'rails_helper'

RSpec.describe Crm::Cards::ActivityPayloadBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }

  # A timeline mostra "Reunião passou para <nome>": o nome de quem recebeu vem resolvido em labels.to_user_id.
  it 'resolve o nome de quem recebeu a reunião reatribuída' do
    activity = Crm::Activity.create!(account: account, card: world.card, actor_type: 'system', event_type: 'meeting_host_reassigned',
                                     payload: { 'meeting_id' => 1, 'from_user_id' => 999_999, 'to_user_id' => world.host.id })

    payload = described_class.new(account: account, user: admin, account_user: admin.account_users.first, activities: [activity]).perform

    expect(payload.first[:labels]).to eq('to_user_id' => world.host.name)
  end
end
