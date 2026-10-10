require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::ShortSentence, :aggregate_failures do
  it 'keeps a short text, on one line' do
    expect(described_class.call("Troquei o título.\n\nE o botão.", 200)).to eq('Troquei o título. E o botão.')
  end

  it 'cuts a long text at the end of a sentence' do
    text = "Troquei o título e deixei o botão verde. #{'Depois revisei tudo com calma ' * 10}"

    expect(described_class.call(text, 60)).to eq('Troquei o título e deixei o botão verde.')
  end

  it 'cuts at a word with an ellipsis when no sentence ends in time' do
    result = described_class.call('palavra ' * 40, 50)

    expect(result.length).to be <= 50
    expect(result).to end_with('palavra…')
  end
end
