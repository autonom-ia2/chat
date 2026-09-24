require 'rails_helper'

RSpec.describe Autonomia::Prospecting::PhoneContract do
  describe '.e164 com a tabela compartilhada' do
    ProspectingPhoneContractCases.all.each do |item|
      it "#{item['caso']}: #{item['raw'].inspect} (#{item['region'].inspect}) vira #{item['e164'].inspect}" do
        expect(described_class.e164(item['raw'], region: item['region'])).to eq(item['e164'])
      end
    end
  end

  describe '.parse' do
    it 'devolve E.164, dígitos e país' do
      phone = described_class.parse('(55) 99988-7766', region: 'BR')

      expect(phone.e164).to eq('+5555999887766')
      expect(phone.digits).to eq('5555999887766')
      expect(phone.country_iso2).to eq('BR')
    end

    it 'devolve nil para número inválido' do
      expect(described_class.parse('1234', region: 'BR')).to be_nil
      expect(described_class.parse(nil, region: 'BR')).to be_nil
    end
  end

  describe '.chat_id' do
    it 'monta o chat do WhatsApp a partir dos dígitos' do
      expect(described_class.chat_id('+55 41 99999-0001', region: 'BR')).to eq('5541999990001@c.us')
      expect(described_class.chat_id('1234', region: 'BR')).to be_nil
    end
  end

  describe '.region_for' do
    let(:account) { create(:account) }

    it 'usa BR quando a conta não escolheu país' do
      expect(described_class.region_for(account)).to eq('BR')
    end

    it 'usa o search_country das configurações da conta' do
      setting = Autonomia::Prospecting::Setting.for_account(account)
      setting.update!(metadata: setting.metadata.to_h.merge('search_country' => 'pt'))

      expect(described_class.region_for(account)).to eq('PT')
    end

    it 'volta para BR quando o país guardado é desconhecido' do
      ProspectingPhoneContractCases.apply_region!(account, 'XX')

      expect(described_class.region_for(account)).to eq('BR')
    end
  end
end
