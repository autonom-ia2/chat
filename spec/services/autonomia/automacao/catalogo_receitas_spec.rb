require 'rails_helper'

# As receitas prontas (#2498): cada uma passa no esquema e na Receita com as flags que pede ligadas, o gatilho existe no
# catálogo, a porta tem título, texto e nome em pt_BR e en, e a flag que a receita pede sai dos passos dela.
RSpec.describe Autonomia::Automacao::Catalogo, '.receitas' do
  let(:account) { create(:account) }
  let(:receitas) { described_class.receitas }
  let(:partes) { %w[TITULO TEXTO NOME] }

  before { account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_ia') }

  def frases(locale)
    JSON.parse(Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/automacaoLivre.json").read)
  end

  it 'monta as que o motor de hoje sabe fazer' do
    expect(receitas.pluck('chave')).to eq(%w[BOAS_VINDAS AGRADECER])
  end

  it 'cada receita passa no esquema e na Receita, então nenhuma quebrada chega à tela', :aggregate_failures do
    receitas.each do |item|
      expect(Autonomia::Automacao::Receita.esquema_valido?(item['receita'])).to be(true), item['chave']
      expect(Autonomia::Automacao::Receita.new(item['receita'], conta: account).problemas).to eq([]), item['chave']
    end
  end

  it 'o gatilho de cada receita existe no catálogo' do
    gatilhos = described_class.gerado['gatilhos'].pluck('tipo')

    expect(receitas.map { |item| item.dig('receita', 'gatilho', 'tipo') }).to all(be_in(gatilhos))
  end

  it 'a receita que manda mensagem pede automacao_mensagens' do
    expect(receitas.map { |item| item['requer'] }).to all(eq(['automacao_mensagens']))
  end

  it 'tem título, texto e nome em pt_BR e en', :aggregate_failures do
    %w[pt_BR en].each do |locale|
      textos = frases(locale)
      receitas.each do |item|
        partes.each do |parte|
          expect(textos.dig('AUTOMACAO_LIVRE', 'RECEITAS', item['chave'], parte)).to be_present, "#{locale} #{item['chave']} #{parte}"
        end
      end
    end
  end

  it 'o catálogo versionado traz as receitas' do
    expect(described_class.todos['receitas']).to eq(JSON.parse(receitas.to_json))
  end
end
