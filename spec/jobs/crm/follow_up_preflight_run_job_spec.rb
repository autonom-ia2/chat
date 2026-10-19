require 'rails_helper'

RSpec.describe Crm::FollowUpPreflightRunJob do
  it 'follow-up que sumiu: nada a fazer' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
