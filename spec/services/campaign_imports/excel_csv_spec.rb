require 'rails_helper'

RSpec.describe CampaignImports::ExcelCsv do
  it 'turns a stored file into one Excel opens with accents and columns' do
    stored = "nome,cidade\n\"Flávia, a\",São Paulo\n".b

    expect(described_class.from_stored(stored)).to eq("﻿nome;cidade\nFlávia, a;São Paulo\n")
  end

  it 'keeps a stored BOM from doubling' do
    expect(described_class.from_stored("﻿nome\nAna\n")).to eq("﻿nome\nAna\n")
  end
end
