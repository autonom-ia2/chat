require 'rails_helper'

RSpec.describe BrandKits::Color do
  describe '.parse' do
    it 'normalizes hexadecimal notations' do
      expect(described_class.parse('#0B243F')).to eq('#0b243f')
      expect(described_class.parse('#fff')).to eq('#ffffff')
      expect(described_class.parse('#0ab9d1ff')).to eq('#0ab9d1')
    end

    it 'normalizes functional and named notations' do
      expect(described_class.parse('rgb(255, 31, 45)')).to eq('#ff1f2d')
      expect(described_class.parse('rgba(255,31,45,1)')).to eq('#ff1f2d')
      expect(described_class.parse('rgb(255 31 45 / 1)')).to eq('#ff1f2d')
      expect(described_class.parse('white')).to eq('#ffffff')
      expect(described_class.parse(' #ABC !important')).to eq('#aabbcc')
    end

    it 'refuses translucent, relative or malformed values' do
      ['#0ab9d180', 'rgba(255,31,45,.3)', 'lab(13% -1 -20)', 'var(--x)', '#12345', '#ggg', 'transparent', '', nil, 'rgb(300,0,0)']
        .each { |value| expect(described_class.parse(value)).to be_nil, value.inspect }
    end
  end

  describe 'WCAG math' do
    it 'computes the contrast ratio like the WCAG formula' do
      expect(described_class.contrast('#ffffff', '#000000')).to be_within(0.01).of(21)
      expect(described_class.contrast('#ffffff', '#ff1f2d')).to be_within(0.1).of(3.8)
    end

    it 'picks the readable ink for a background' do
      expect(described_class.readable_ink('#0b243f')).to eq('#ffffff')
      expect(described_class.readable_ink('#f4f6f8')).to eq(described_class::DARK_INK)
    end

    it 'chooses white text on the button only when it reaches 4.5:1, otherwise the ink, otherwise the darker choice' do
      expect(described_class.text_on('#0b243f', ink: '#111111')).to eq('#ffffff')
      expect(described_class.text_on('#ff1f2d', ink: '#111111')).to eq('#111111')
      expect(described_class.text_on('#ff1f2d', ink: '#ffffff')).to eq(described_class::DARK_INK)
    end

    it 'mixes two colors' do
      expect(described_class.composite('#000000', '#ffffff', 0.5)).to eq('#808080')
    end

    it 'tells neutral grays from brand colors' do
      expect(described_class.neutral?('#030b13')).to be(true)
      expect(described_class.neutral?('#0ab9d1')).to be(false)
    end
  end
end
