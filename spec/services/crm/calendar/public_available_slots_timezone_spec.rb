require 'rails_helper'

# H4-booking regression: public booking slots must be anchored to the profile's
# resolved OPERATIONAL timezone, never a silent UTC. Before the fix,
# PublicAvailableSlots parsed the local day with `profile.resolved_timezone`,
# which collapsed to 'UTC' whenever the profile carried no timezone. In BR
# (UTC-3) an 09:00 local start then became 09:00 UTC == 06:00 BRT — offering
# slots three hours before the business day.
RSpec.describe Crm::Calendar::PublicAvailableSlots do
  # A duck-typed profile stand-in: the slots service only reads these methods, so
  # we avoid factory/DB/calendar-channel overhead and keep the timezone behavior
  # under a microscope.
  def profile_double(resolution:, start_hour: 9, end_hour: 17, weekdays: [1, 2, 3, 4, 5])
    inbox = instance_double(Inbox, id: 1, channel: nil)
    instance_double(
      Crm::AgentBookingProfile,
      account_id: 1,
      inbox: inbox,
      duration_minutes: 60,
      buffer_minutes: 0,
      booking_window_days: 30,
      start_hour: start_hour,
      end_hour: end_hour,
      weekdays: weekdays,
      timezone_resolution: resolution,
      resolved_timezone: resolution.zone.name
    )
  end

  def resolution_for(zone_name, source)
    TimeZoneResolver::Resolution.new(zone: ActiveSupport::TimeZone[zone_name], source: source)
  end

  before do
    # No provider busy intervals — isolate the timezone/window math.
    availability = instance_double(Crm::Meetings::AvailabilityService, busy_intervals: [])
    allow(Crm::Meetings::AvailabilityService).to receive(:new).and_return(availability)
    # No locally-scheduled meetings to subtract (dedicated mailbox, empty DB path).
    allow(Crm::Meeting).to receive(:where).and_return(Crm::Meeting.none)
  end

  describe 'BR profile lands slots in local business hours (not UTC-shifted)' do
    it 'anchors the first slot to 09:00 America/Sao_Paulo (== 12:00 UTC)' do
      # Freeze well before the booking day so the buffer/future guard never trims
      # the morning slots we assert on.
      travel_to(Time.utc(2026, 7, 6, 0, 0, 0)) do
        profile = profile_double(resolution: resolution_for('America/Sao_Paulo', :account))

        starts = described_class.new(profile: profile, date: '2026-07-08').perform

        expect(starts).not_to be_empty
        first = Time.iso8601(starts.first)
        # 09:00 in São Paulo is 12:00 UTC. If the tz silently fell back to UTC the
        # first slot would be 09:00 UTC (a full 3h early) and this would fail.
        expect(first.utc.hour).to eq(12)
        expect(first.in_time_zone('America/Sao_Paulo').hour).to eq(9)
      end
    end
  end

  describe 'fail-closed when the profile timezone does not resolve' do
    it 'returns NO slots instead of generating them in UTC (source :none)' do
      travel_to(Time.utc(2026, 7, 6, 0, 0, 0)) do
        profile = profile_double(resolution: resolution_for('UTC', :none))

        starts = described_class.new(profile: profile, date: '2026-07-08').perform

        expect(starts).to eq([])
      end
    end
  end
end
