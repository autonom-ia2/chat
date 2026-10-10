require 'rails_helper'

RSpec.describe CampaignImports::PhoneNormalizer do
  it 'normalizes Brazilian mobile phones to E.164' do
    expect(described_class.normalize!('11987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('5511987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('+5511987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('(11) 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'rejects Brazilian landlines' do
    expect { described_class.normalize!('(11) 3456-4321') }.to raise_error(
      described_class::Error,
      'invalid_brazilian_mobile_number'
    )
  end

  it 'keeps refusing the legacy eight-digit mobile without the national formats' do
    expect { described_class.normalize!('(11) 8765-4321') }.to raise_error(described_class::Error, 'invalid_brazilian_mobile_number')
  end

  describe 'with the national formats (customer_base reading)' do
    def normalize(value)
      described_class.normalize!(value, national_formats: true)
    end

    def refused(value)
      normalize(value)
      false
    rescue described_class::Error
      true
    end

    it 'reads the modern mobile as before, without flagging a ninth digit' do
      result = normalize('(11) 98765-4321')

      expect(result.phone_number).to eq('+5511987654321')
      expect(result.ninth_digit_added).to be(false)
    end

    it 'drops the long-distance trunk 0 and the international 00 prefix' do
      expect(normalize('011 98765-4321').phone_number).to eq('+5511987654321')
      expect(normalize('0055 11 98765-4321').phone_number).to eq('+5511987654321')
      expect(normalize('(0xx21) 98765-4321').phone_number).to eq('+5521987654321')
    end

    it 'restores the ninth digit of a legacy mobile written the Brazilian way' do
      ['(11) 8765-4321', '11 8765-4321', '1187654321', '551187654321', '+55 11 8765-4321', '011 8765-4321', '5511 8765-4321'].each do |value|
        result = normalize(value)
        expect(result.phone_number).to eq('+5511987654321'), value
        expect(result.ninth_digit_added).to be(true), value
      end
    end

    it 'adds the ninth digit only to mobile ranges (6 to 9), never to a landline (2 to 5)' do
      %w[6 7 8 9].each do |first|
        expect(normalize("(21) #{first}543-2109").phone_number).to eq("+55219#{first}5432109"), first
      end
      %w[2 3 4 5].each do |first|
        expect(refused("(21) #{first}543-2109")).to be(true), first
      end
    end

    it 'keeps 55 as the DDD of Rio Grande do Sul when nothing else can be the DDD' do
      expect(normalize('(55) 8765-4321').phone_number).to eq('+5555987654321')
    end

    it 'never turns a number written in another country grouping into a Brazilian mobile' do
      expect(refused('917 555 1234')).to be(true)
      expect(refused('(917) 755-1234')).to be(true)
      expect(refused('917-755-1234')).to be(true)
    end

    it 'never reads a number with another country code as Brazilian' do
      expect(refused('+1 917 755 1234')).to be(true)
      expect(refused('+91 7555-1234')).to be(true)
      expect(refused('+351 912 345 678')).to be(true)
      expect(refused('Tel: +34 912 345 678')).to be(true)
    end

    it 'never takes the country code 55 as the DDD' do
      expect(refused('+55 8765-4321')).to be(true)
      expect(refused('+55 98765-4321')).to be(true)
    end

    it "refuses an area code that is not one of Anatel's" do
      expect(refused('(20) 8765-4321')).to be(true)
      expect(refused('(10) 98765-4321')).to be(true)
    end

    it 'still refuses landlines' do
      expect(refused('(11) 3456-4321')).to be(true)
      expect(refused('551134564321')).to be(true)
    end
  end
end
