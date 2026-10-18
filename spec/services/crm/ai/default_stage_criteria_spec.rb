require 'rails_helper'

RSpec.describe Crm::Ai::DefaultStageCriteria do
  it 'returns criteria for default stage names' do
    expect(described_class.criteria_for('Novo')).to include('Primeiro contato')
    expect(described_class.criteria_for('Perdido')).to include('sem conversão')
  end

  it 'builds metadata for known stages' do
    expect(described_class.metadata_for('Proposta')).to eq(
      'ai_criteria' => described_class.criteria_for('Proposta')
    )
  end

  it 'knows the stages of the ready-made Sales pipeline, in plain words' do
    names = ['Novo contato', 'Em conversa', 'Proposta enviada', 'Negociação', 'Fechado']

    expect(names.map { |name| described_class.criteria_for(name) }).to all(be_present)
    expect(described_class.criteria_for('  NEGOCIAÇÃO ')).to include('acertando detalhes')
  end

  it 'knows the stages of the ready-made Service and Appointments pipelines' do
    names = ['Novo pedido', 'Em atendimento', 'Esperando o cliente', 'Resolvido',
             'Novo contato', 'Horário marcado', 'Atendido', 'Não veio']

    expect(names.map { |name| described_class.criteria_for(name) }).to all(be_present)
  end

  # #1498
  it 'knows the stages of the After-sales, Collections and Appointment templates only in a Serve pipeline' do
    names = ['Compra feita', 'Acompanhando', 'Tudo certo', 'A vencer', 'Atrasado', 'Prometeu pagar', 'Pago',
             'Pediu horário', 'Precisa remarcar']

    expect(names.map { |name| described_class.criteria_for(name, atender: true) }).to all(be_present)
    expect(names.map { |name| described_class.criteria_for(name) }).to all(be_nil)
  end

  it 'reads "Em atendimento" as service in a Serve pipeline and keeps the sale meaning otherwise' do
    expect(described_class.criteria_for('Em atendimento', atender: true)).to include('cuidando do pedido')
    expect(described_class.criteria_for('Em atendimento')).to include('proposta')
    expect(described_class.metadata_for('Novo', atender: true)['ai_criteria']).to include('pedir ajuda')
  end

  # #1548: o pacote de textos por tipo de conta (#1545) troca o nome da etapa; o critério segue o modelo e a posição.
  describe 'by template and position' do
    it 'finds the criteria even when the stage name changed' do
      criteria = I18n.with_locale(:pt_BR) do
        described_class.criteria_for('Sinistro em análise', atender: true, template: 'ATENDIMENTO', position: '2')
      end

      expect(criteria).to eq(I18n.t('crm.stage_criteria.atendimento.e2', locale: :pt_BR))
      expect(criteria).to include('cuidando do pedido')
    end

    it 'answers in the language of the person' do
      %i[en pt_BR].each do |locale|
        criteria = I18n.with_locale(locale) { described_class.criteria_for('Fechado', template: 'VENDAS', position: 5) }
        expect(criteria).to eq(I18n.t('crm.stage_criteria.vendas.e5', locale: locale))
      end
      expect(I18n.t('crm.stage_criteria.vendas.e5', locale: :en)).not_to eq(I18n.t('crm.stage_criteria.vendas.e5', locale: :pt_BR))
    end

    it 'reads the position in base 10 only' do
      expect(described_class.criteria_for('Etapa nova', atender: true, template: 'COBRANCA', position: '0x2')).to be_nil
      expect(described_class.criteria_for('Etapa nova', atender: true, template: 'COBRANCA', position: '02')).to be_present
    end

    it 'falls back to the name when the template or the position is unknown' do
      expect(described_class.criteria_for('Pago', atender: true, template: 'SEGUROS', position: 4)).to include('comprovante')
      expect(described_class.criteria_for('Pago', atender: true, template: 'COBRANCA', position: 9)).to include('comprovante')
      expect(described_class.criteria_for('Pago', atender: true, template: 'COBRANCA', position: 'x')).to include('comprovante')
      expect(described_class.criteria_for('Etapa nova', atender: true, template: 'COBRANCA', position: 0)).to be_nil
    end

    it 'never gives a Sell pipeline a Serve phrase, nor the other way around' do
      sell = described_class.criteria_for('Etapa nova', template: 'COBRANCA', position: 2)
      serve = described_class.criteria_for('Etapa nova', atender: true, template: 'VENDAS', position: 1)
      sell_by_name = I18n.with_locale(:pt_BR) { described_class.criteria_for('Em atendimento', template: 'ATENDIMENTO', position: 2) }

      expect(sell).to be_nil
      expect(serve).to be_nil
      expect(sell_by_name).to include('proposta')
      expect(sell_by_name).not_to include('cuidando do pedido')
    end

    # #1802: Renovação é de Vender; Sinistro e Alteração na apólice, de Atender. Achados só por modelo e posição.
    it 'knows the broker templates by template and position, each in its own kind' do
      expect(described_class.criteria_for('A vencer', template: 'RENOVACAO', position: 1)).to eq(I18n.t('crm.stage_criteria.renovacao.e1'))
      expect(described_class.criteria_for('Aberto', atender: true, template: 'SINISTRO', position: 1)).to eq(I18n.t('crm.stage_criteria.sinistro.e1'))
      expect(described_class.criteria_for('Feito', atender: true, template: 'ALTERACAO', position: 4))
        .to eq(I18n.t('crm.stage_criteria.alteracao.e4'))
      expect(described_class.criteria_for('Etapa', atender: true, template: 'RENOVACAO', position: 1)).to be_nil
      expect(described_class.criteria_for('Etapa', template: 'SINISTRO', position: 1)).to be_nil
    end

    it 'does not map the broker stage names: without the template they have no criteria' do
      %w[Cotando Aberto Renovado].each { |name| expect(described_class.criteria_for(name)).to be_nil }
      expect(described_class::SELL_TEMPLATES).to contain_exactly('VENDAS', 'RENOVACAO')
    end

    it 'builds metadata from the template' do
      expect(described_class.metadata_for('Outro nome', atender: true, template: 'COBRANCA', position: 1)).to eq(
        'ai_criteria' => I18n.t('crm.stage_criteria.cobranca.e1')
      )
    end
  end

  # As etapas de cada modelo vêm do i18n do painel (CRM_FUNIL.MODELOS.<X>.E<n>); cada uma precisa da sua frase no back,
  # em inglês e português, para o funil novo não nascer sem critério em silêncio.
  describe 'i18n catalog' do
    let(:locales) { %w[en pt_BR] }
    let(:model_stages) do
      catalog = JSON.parse(Rails.root.join('app/javascript/dashboard/i18n/locale/pt_BR/crm.json').read)
      catalog.dig('CRM_FUNIL', 'MODELOS').slice(*Crm::Pipeline::TEMPLATES).transform_values do |model|
        model.keys.count { |key| key.start_with?('E') && key.delete_prefix('E').to_i.positive? }
      end
    end

    it 'has a phrase for every stage of every template, in every language' do
      expect(model_stages.keys).to match_array(Crm::Pipeline::TEMPLATES)

      model_stages.each do |template, total|
        expect(total).to be_positive
        locales.each do |locale|
          (1..total).each do |position|
            key = "crm.stage_criteria.#{template.downcase}.e#{position}"
            expect(I18n.t(key, locale: locale, default: '')).to be_present, "#{locale}: #{key}"
          end
          expect(I18n.exists?("crm.stage_criteria.#{template.downcase}.e#{total + 1}", locale)).to be(false)
        end
      end
    end

    it 'has a phrase for every name of the fallback, in every language' do
      keys = described_class::NAME_KEYS.values + described_class::ATENDER_NAME_KEYS.values

      keys.product(locales).each do |key, locale|
        expect(I18n.t("crm.stage_criteria.#{key}", locale: locale, default: '')).to be_present, "#{locale}: #{key}"
      end
    end
  end
end
