require 'rails_helper'

describe ApplicationHelper do
  describe '#available_locales_with_name' do
    it 'does not offer European Portuguese, which is served as Brazilian Portuguese' do
      codes = helper.available_locales_with_name.pluck(:iso_639_1_code)

      expect(codes).to include('pt_BR', 'en')
      expect(codes).not_to include('pt')
    end
  end
end
