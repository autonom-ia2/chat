require 'rails_helper'

# Números do consultor formatados pelo servidor (#1110, F5, D5.1): cada tipo da tabela §2 em pt_BR e en, e o
# render que volta nil (texto da regra) quando um marcador não tem valor ou está malformado.
RSpec.describe Crm::MetaAds::Advisor::Format do
  def value(type, raw, locale, currency: 'BRL')
    described_class.value(type, raw, locale: locale, currency: currency)
  end

  describe '.value' do
    it 'dinheiro na moeda da conta, com centavos só quando existem' do
      expect(value(:money, 842, 'pt_BR')).to eq('R$ 842')
      expect(value(:money, 1234.5, 'pt_BR')).to eq('R$ 1.234,50')
      expect(value(:money, '163.51', 'pt_BR')).to eq('R$ 163,51')
      expect(value(:money, 99.999, 'pt_BR')).to eq('R$ 100')
      expect(value(:money, 1234.5, 'en', currency: 'USD')).to eq('US$ 1,234.50')
      expect(value(:money, 1500, 'en')).to eq('R$ 1,500')
      expect(value(:money, 10, 'en', currency: 'GBP')).to eq('GBP 10')
    end

    it 'contagem e dias: inteiro com separador de milhar' do
      expect(value(:count, 12_345, 'pt_BR')).to eq('12.345')
      expect(value(:count, 12_345, 'en')).to eq('12,345')
      expect(value(:count, '7', 'pt_BR')).to eq('7')
      expect(value(:days, 30, 'pt_BR')).to eq('30')
      expect(value(:days, 3, 'en')).to eq('3')
    end

    it 'porcentagem guardada em fração vira inteiro com %' do
      expect(value(:percent, 0.33, 'pt_BR')).to eq('33%')
      expect(value(:percent, 0.2, 'en')).to eq('20%')
      expect(value(:percent, 0.666, 'en')).to eq('67%')
    end

    it 'decimal com uma casa no separador do idioma' do
      expect(value(:decimal1, 4.6, 'pt_BR')).to eq('4,6')
      expect(value(:decimal1, '4.64', 'en')).to eq('4.6')
      expect(value(:decimal1, 3, 'pt_BR')).to eq('3,0')
    end

    it 'duração arredondada para baixo: menos de 1 min, minutos, horas e minutos, dias' do
      expect(value(:duration, 30, 'pt_BR')).to eq('menos de 1 min')
      expect(value(:duration, 360, 'pt_BR')).to eq('6 min')
      expect(value(:duration, 419, 'pt_BR')).to eq('6 min')
      expect(value(:duration, 4800, 'pt_BR')).to eq('1 h 20 min')
      expect(value(:duration, 7200, 'pt_BR')).to eq('2 h')
      expect(value(:duration, (47 * 3600) + 3599, 'pt_BR')).to eq('47 h 59 min')
      expect(value(:duration, 48 * 3600, 'pt_BR')).to eq('2 dias')
    end

    it 'duração em inglês' do
      expect(value(:duration, 30, 'en')).to eq('less than 1 min')
      expect(value(:duration, 4800, 'en')).to eq('1 h 20 min')
      expect(value(:duration, 3 * 86_400, 'en')).to eq('3 days')
    end

    it 'texto sai como veio, com dígitos (nome de anúncio)' do
      expect(value(:text, 'Promo 10/10', 'pt_BR')).to eq('Promo 10/10')
    end

    it 'idioma sem catálogo do consultor cai no inglês' do
      expect(value(:money, 1234.5, 'es')).to eq('R$ 1,234.50')
      expect(value(:duration, 7200, 'xx')).to eq('2 h')
    end
  end

  describe '.render' do
    let(:facts) do
      { count: 2, value: 3000.0, days: 3, ad_name: 'Promo 10/10', median_seconds: 1500, ctr_drop_pct: 0.33,
        frequency_7d: 4.6, window_days: 7 }
    end

    def render(template, locale: 'pt_BR', with: facts)
      described_class.render(template, with, locale: locale, currency: 'BRL')
    end

    it 'troca cada marcador pelo valor formatado, em pt_BR e en' do
      template = 'São {{count}} propostas paradas há mais de {{days}} dias, somando {{value}}.'

      expect(render(template)).to eq('São 2 propostas paradas há mais de 3 dias, somando R$ 3.000.')
      expect(render(template, locale: 'en')).to eq('São 2 propostas paradas há mais de 3 dias, somando R$ 3,000.')
    end

    it 'aceita fatos com chave string (vindos do jsonb) e espaços dentro do marcador' do
      template = '{{ ad_name }} caiu {{ctr_drop_pct}}; cada pessoa viu {{frequency_7d}} vezes em {{window_days}} dias, metade em {{median_seconds}}'

      expect(render(template, with: facts.stringify_keys))
        .to eq('Promo 10/10 caiu 33%; cada pessoa viu 4,6 vezes em 7 dias, metade em 25 min')
    end

    it 'texto sem marcador sai igual; nil continua nil' do
      expect(render('Responda rápido.')).to eq('Responda rápido.')
      expect(render('')).to eq('')
      expect(render(nil)).to be_nil
    end

    it 'marcador sem valor atual (nil, vazio, ausente ou chave sem tipo) devolve nil' do
      expect(render('Gasto {{spend}}')).to be_nil
      expect(render('{{ad_name}} parou', with: facts.merge(ad_name: nil))).to be_nil
      expect(render('{{ad_name}} parou', with: facts.merge(ad_name: ''))).to be_nil
      expect(render('Veja {{campanha}}', with: facts.merge(campanha: 'X'))).to be_nil
    end

    it 'marcador malformado devolve nil' do
      expect(render('São {{count propostas')).to be_nil
      expect(render('São count}} propostas')).to be_nil
      expect(render('São {{count}} propostas}}')).to be_nil
      expect(render('São {{}} propostas')).to be_nil
      expect(render('São {{ }} propostas')).to be_nil
      expect(render('São {{count {{days}} propostas')).to be_nil
    end
  end

  it 'toda chave da tabela §2 tem um tipo conhecido' do
    known = %i[money count percent decimal1 duration days text]

    expect(described_class::TYPES.values - known).to be_empty
    expect(described_class::TYPES.keys).to include('value', 'median_seconds', 'identified_pct', 'frequency_7d', 'max_increase_pct',
                                                   'cpm_change_pct', 'missing_conversations', 'cooldown_days')
  end
end
