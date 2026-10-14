require 'rails_helper'

RSpec.describe Crm::Config do
  describe '.booking_v2_enabled?' do
    let(:account) { create(:account) }

    it 'fica desligada por padrão' do
      with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
        expect(described_class.booking_v2_enabled?(account)).to be(false)
      end
    end

    it 'liga só com a flag da conta e o calendário de reuniões da instalação' do
      account.enable_features('crm_booking_v2')
      account.save!

      with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
        expect(described_class.booking_v2_enabled?(account)).to be(true)
      end
      with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'false') do
        expect(described_class.booking_v2_enabled?(account)).to be(false)
      end
    end

    it 'não liga uma conta pela flag de outra' do
      account.enable_features('crm_booking_v2')
      account.save!

      with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
        expect(described_class.booking_v2_enabled?(create(:account))).to be(false)
        expect(described_class.booking_v2_enabled?(nil)).to be(false)
      end
    end
  end
end
