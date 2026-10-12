require 'rails_helper'

# O resumo da lista (`GET crm/booking_pages`) leva a duração da reunião (#1371): a gaveta "Marcar reuniões" do agente
# de IA mostra quanto dura cada página sem pedir a página inteira. É o mesmo valor da página completa.
RSpec.describe Crm::BookingV2::PageSerializer do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before { account.enable_features!('crm_booking_v2') }

  it 'traz duration_minutes no resumo, o mesmo valor da página completa' do
    profile.update!(duration_minutes: 45)
    serializer = described_class.new(profile.reload)

    expect(serializer.summary[:duration_minutes]).to eq(45)
    expect(serializer.full[:duration_minutes]).to eq(45)
  end
end
