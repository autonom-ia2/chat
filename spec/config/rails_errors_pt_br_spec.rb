require 'rails_helper'

# #2110: as mensagens de validação do Rails em pt_BR vêm de config/locales/rails_errors.pt_BR.yml, cópia dos blocos de
# erro do pt-BR da rails-i18n (que o app não carrega: o código dele é pt_BR, e o módulo de locales da gem está desligado).
# rubocop:disable RSpec/DescribeClass -- é a configuração de locales, não uma classe (mesmo padrão de spec/config)
RSpec.describe 'config/locales/rails_errors.pt_BR.yml' do
  # rubocop:enable RSpec/DescribeClass
  def folhas(hash, caminho = [])
    hash.flat_map { |chave, valor| valor.is_a?(Hash) ? folhas(valor, caminho + [chave]) : [[(caminho + [chave]).join('.'), valor]] }
  end

  it 'monta a mensagem de validação em português' do
    resposta = I18n.with_locale(:pt_BR) { CannedResponse.new.tap(&:valid?).errors.full_messages }

    expect(resposta).to include('Content não pode ficar em branco')
  end

  it 'copia cada mensagem igual à do pt-BR da gem' do
    copia = folhas(YAML.load_file(Rails.root.join('config/locales/rails_errors.pt_BR.yml'))['pt_BR'])
    gem = folhas(YAML.load_file(File.join(Gem.loaded_specs.fetch('rails-i18n').gem_dir, 'rails/locale/pt-BR.yml'))['pt-BR']).to_h

    expect(copia).not_to be_empty
    expect(copia.reject { |chave, valor| gem[chave] == valor }).to be_empty
  end
end
