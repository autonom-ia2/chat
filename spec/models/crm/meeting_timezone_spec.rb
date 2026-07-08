require 'rails_helper'

# H4-booking: crm_meetings.timezone is a NOT-NULL column defaulting to 'UTC'.
# Presence alone let a garbage/non-IANA string persist and later collapse date
# math to UTC. We now require the value to be a real ActiveSupport::TimeZone.
RSpec.describe Crm::Meeting do
  # Isolate the timezone inclusion validation from the (many) association
  # validations by asserting only on the :timezone error key.
  def timezone_errors(value)
    meeting = described_class.new(timezone: value)
    meeting.valid?
    meeting.errors[:timezone]
  end

  it 'rejects a non-IANA timezone string' do
    expect(timezone_errors('Totally/Bogus')).to be_present
  end

  it 'rejects a blank timezone' do
    expect(timezone_errors('')).to be_present
  end

  it 'accepts a valid IANA timezone' do
    expect(timezone_errors('America/Sao_Paulo')).to be_empty
  end

  it 'accepts UTC' do
    expect(timezone_errors('UTC')).to be_empty
  end
end
