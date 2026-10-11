require 'rails_helper'

RSpec.describe CampaignImports::XlsxDateFormats do
  describe '.kind_for_code' do
    it 'reads dates, times and both' do
      expect(described_class.kind_for_code('dd/mm/yyyy')).to eq(:date)
      expect(described_class.kind_for_code('mmm-yy')).to eq(:date)
      expect(described_class.kind_for_code('[$-416]d" de "mmmm" de "yyyy')).to eq(:date)
      expect(described_class.kind_for_code('hh:mm')).to eq(:time)
      expect(described_class.kind_for_code('h:mm AM/PM')).to eq(:time)
      expect(described_class.kind_for_code('dd/mm/yyyy hh:mm')).to eq(:datetime)
    end

    it 'tells when the format shows seconds' do
      expect(described_class.kind_for_code('hh:mm:ss')).to eq(:time_seconds)
      expect(described_class.kind_for_code('dd/mm/yyyy hh:mm:ss')).to eq(:datetime_seconds)
    end

    it 'leaves numbers, money, text and durations alone' do
      expect(described_class.kind_for_code('General')).to be_nil
      expect(described_class.kind_for_code('#,##0.00')).to be_nil
      expect(described_class.kind_for_code('[$R$-416] #,##0.00;[Red]-#,##0.00')).to be_nil
      expect(described_class.kind_for_code('0" dias"')).to be_nil
      expect(described_class.kind_for_code('@')).to be_nil
      expect(described_class.kind_for_code('[h]:mm:ss')).to be_nil
    end
  end

  it 'maps each cell style to the kind of its number format' do
    xml = <<~XML
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="&quot;R$&quot; #,##0.00"/></numFmts>
        <cellXfs count="5"><xf numFmtId="0"/><xf numFmtId="164"/><xf numFmtId="165"/><xf numFmtId="14"/><xf numFmtId="20"/></cellXfs>
      </styleSheet>
    XML
    formats = described_class.new(xml)

    expect([0, 1, 2, 3, 4, nil].map { |index| formats.kind_of(index) }).to eq([nil, :date, nil, :date, :time, nil])
  end

  it 'knows no date style in a file without styles' do
    expect(described_class.new(nil).kind_of(1)).to be_nil
  end

  it 'reads the built-in dates of the East Asian locales and the built-in times with seconds' do
    xml = '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cellXfs count="4">' \
          '<xf numFmtId="27"/><xf numFmtId="57"/><xf numFmtId="21"/><xf numFmtId="46"/></cellXfs></styleSheet>'

    expect((0..3).map { |index| described_class.new(xml).kind_of(index) }).to eq([:date, :date, :time_seconds, nil])
  end

  it 'leaves every number as it is when styles.xml cannot be read' do
    allow(Rails.logger).to receive(:warn)

    expect(described_class.new('<styleSheet><cellXfs><xf numFmtId="14"></cellXfs>').kind_of(0)).to be_nil
    expect(Rails.logger).to have_received(:warn).with(a_string_including('styles.xml unreadable'))
  end
end
