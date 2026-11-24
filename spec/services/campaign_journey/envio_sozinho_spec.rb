require 'rails_helper'

# A retomada dos adiados e o resto das duas versões não mandam ao mesmo tempo na mesma campanha: quem chega com a trava
# tomada não roda e devolve false; a trava sai mesmo se o envio quebrar.
RSpec.describe CampaignJourney::EnvioSozinho, :aggregate_failures do
  let(:campaign) { create(:campaign) }
  let(:conexao) { ActiveRecord::Base.connection }

  it 'roda o bloco com a trava e a solta no fim' do
    rodou = false

    expect(described_class.sozinho(campaign) { rodou = true }).to be(true)
    expect(rodou).to be(true)
    expect(described_class.sozinho(campaign) { nil }).to be(true)
  end

  it 'com a trava tomada por outro envio, não roda e devolve false' do
    allow(conexao).to receive(:select_value).and_call_original
    allow(conexao).to receive(:select_value).with(a_string_including('pg_try_advisory_lock')).and_return(false)
    rodou = false

    expect(described_class.sozinho(campaign) { rodou = true }).to be(false)
    expect(rodou).to be(false)
    expect(conexao).not_to have_received(:select_value).with(a_string_including('pg_advisory_unlock'))
  end

  it 'solta a trava mesmo quando o envio quebra' do
    allow(conexao).to receive(:select_value).and_call_original

    expect { described_class.sozinho(campaign) { raise StandardError, 'quebrou' } }.to raise_error(StandardError, 'quebrou')
    expect(conexao).to have_received(:select_value).with(a_string_including('pg_advisory_unlock'))
  end
end
