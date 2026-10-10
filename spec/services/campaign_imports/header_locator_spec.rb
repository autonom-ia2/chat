require 'rails_helper'

RSpec.describe CampaignImports::HeaderLocator, :aggregate_failures do
  def parsed(content)
    CampaignImports::Parser.new(StringIO.new(content), filename: 'base.csv').perform
  end

  let(:customer_base) { CampaignImports::ContactReading::CUSTOMER_BASE }
  # A person without phone or email in the middle of a file without a header.
  let(:headless) { "Ana,11987654321\nBeto,\nCaio,21987654321\n" }

  context 'with the customer_base reading' do
    it 'never takes a line after the first data row as the header and reads the file whole' do
      candidate = described_class.new(parsed(headless), reading: customer_base).perform

      expect(candidate.untitled).to be(true)
      expect(candidate.header_row_number).to eq(0)
      expect(candidate.rows.size).to eq(3)
    end

    it 'reopens the untitled reading when the user pinned header row 0' do
      candidate = described_class.new(parsed(headless), reading: customer_base).perform(header_row: 0, table_index: 0)

      expect(candidate.untitled).to be(true)
      expect(candidate.rows.size).to eq(3)
    end
  end

  context 'with the classic reading' do
    it 'keeps taking the line without contact data as the header, as before' do
      candidate = described_class.new(parsed(headless)).perform

      expect(candidate.untitled).to be(false)
      expect(candidate.header_row_number).to eq(2)
      expect(candidate.rows.size).to eq(1)
    end

    it 'finds no header in a file where every line has contact data' do
      expect(described_class.new(parsed("Ana,11987654321\nBia,21987654321\n")).perform).to be_nil
    end
  end
end
