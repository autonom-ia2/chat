require 'rails_helper'

# #1550 — o registro dos pacotes (config/fork_i18n.json) e o nicho da conta falam da mesma lista de tipos.
# Se um tipo novo entra no super admin sem entrar no registro, o checador do CI recusaria a pasta dele;
# se entra no registro sem entrar no nicho, a pasta nunca seria lida. Esta spec trava os dois juntos.
# rubocop:disable RSpec/DescribeClass -- é a configuração dos pacotes, não uma classe (mesmo padrão de spec/config)
RSpec.describe 'config/fork_i18n.json pacotes' do
  # rubocop:enable RSpec/DescribeClass
  let(:pacotes) { JSON.parse(Rails.root.join('config/fork_i18n.json').read).fetch('pacotes') }

  it 'lista os tipos de seguros na mesma ordem de Autonomia::Agents::Nicho::PERFIS' do
    expect(pacotes.dig('segmentos', 'seguros')).to eq(Autonomia::Agents::Nicho::PERFIS)
  end

  it 'aponta para as pastas que existem no repositório' do
    expect(Rails.root.join(pacotes.fetch('painel'))).to be_directory
    expect(Rails.root.join(pacotes.fetch('servidor'))).to be_directory
    expect(pacotes.fetch('idiomas')).to eq(%w[en pt_BR])
  end

  # Cada folha do pacote do servidor troca uma mensagem que o catálogo base já tem, no mesmo idioma.
  Rails.root.glob('config/pacotes/**/*.yml').sort.each do |arquivo|
    it "#{arquivo.relative_path_from(Rails.root)} só troca chaves que existem no catálogo base" do
      documento = YAML.safe_load_file(arquivo)
      locale = arquivo.basename('.yml').to_s
      expect(documento.keys).to eq([locale])

      folhas = ->(no, caminho) { no.is_a?(Hash) ? no.flat_map { |k, v| folhas.call(v, caminho + [k]) } : [caminho.join('.')] }
      folhas.call(documento[locale], []).each do |chave|
        expect(I18n.t(chave, locale: locale, raise: true)).to be_a(String), "#{locale}.#{chave}"
      end
    end
  end
end
