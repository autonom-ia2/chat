require 'rails_helper'

# As páginas da suíte de fidelidade (#1099, entrega D): para cada modelo, o original limpo e o importado compilado, com
# toda imagem trocada pela mesma caixa cinza e nada vindo da rede, mais o manifest com a área editável contra a meta de
# 70%. Compila MJML com mjml-browser, então precisa de Node e das dependências do front, como o CI tem.
RSpec.describe EmailImportFidelity::Pages, :aggregate_failures do
  let(:out_dir) { Pathname(Dir.mktmpdir('fidelidade')) }

  after { FileUtils.rm_rf(out_dir) }

  it 'writes the original and the imported page of each model, images grey and offline, and the manifest' do
    manifest = described_class.call(out_dir, only: %w[promocional mailjet])

    expect(manifest[:goal]).to eq(0.7)
    expect(manifest[:widths]).to eq([600, 375])
    expect(manifest[:fixtures].pluck(:name)).to eq(%w[mailjet promocional])
    manifest[:fixtures].each do |entry|
      expect(entry[:editable_area_ratio]).to be >= 0.7
      expect(entry[:goal_met]).to be(true)
      expect(entry[:mjml_errors]).to eq(0)
      [entry[:original], entry[:imported]].each do |side|
        page = Nokogiri::HTML5(out_dir.join(side).read)
        expect(page.text).to be_present
        expect(page.css('img, link, script')).to be_empty
        expect(page.to_html).not_to include('https://fonts.')
      end
      expect(Nokogiri::HTML5(out_dir.join(entry[:imported]).read).css('[data-import-gray]')).to be_present
    end
    expect(JSON.parse(out_dir.join('manifest.json').read)['fixtures'].size).to eq(2)
  end
end
