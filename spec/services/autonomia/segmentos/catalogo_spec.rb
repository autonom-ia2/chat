# frozen_string_literal: true

require 'rails_helper'

# Pacote do servidor no I18n do Rails (#1550), com os yml reais de config/pacotes.
RSpec.describe Autonomia::Segmentos::Catalogo do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:pacotes) { Autonomia::Segmentos::Pacotes }
  let(:won) { 'crm.export.statuses.won' }
  let(:lost) { 'crm.export.statuses.lost' }
  let(:corretora) { conta('seguros', 'corretora') }
  let(:saude) { conta('seguros', 'saude_beneficios') }

  around do |example|
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') { example.run }
  ensure
    ActiveSupport::IsolatedExecutionState.delete(AutonomiaPacotesI18nLookup::ESTADO)
  end

  def conta(nicho_escolhido, perfil = nil)
    create(:account, internal_attributes: { nicho::NICHO_KEY => nicho_escolhido, nicho::PERFIL_KEY => perfil }.compact)
  end

  it 'devolve o catálogo base fora de um with' do
    expect(I18n.t(won, locale: :pt_BR)).to eq('Ganho')
    expect(I18n.t(won, locale: :en)).to eq('Won')
  end

  it 'troca o texto pela camada seguros dentro do with' do
    pacotes.with(corretora) do
      expect(I18n.t(won, locale: :pt_BR)).to eq('Seguro ativo')
      expect(I18n.t(lost, locale: :pt_BR)).to eq('Não fechou')
      expect(I18n.t(won, locale: :en)).to eq('Active policy')
      expect(I18n.t(lost, locale: :en)).to eq('Not closed')
    end
  end

  it 'deixa a camada mais específica vencer e cai na camada seguros no que ela não tem' do
    pacotes.with(saude) do
      expect(I18n.t(won, locale: :pt_BR)).to eq('Plano ativo')
      expect(I18n.t(won, locale: :en)).to eq('Active plan')
      expect(I18n.t(lost, locale: :pt_BR)).to eq('Não fechou')
    end
  end

  it 'segue no base para chave que o pacote não tem' do
    pacotes.with(corretora) { expect(I18n.t('crm.export.statuses.open', locale: :pt_BR)).to eq('Aberto') }
  end

  it 'devolve a subárvore do base, sem misturar o pacote' do
    base = I18n.t('crm.export.statuses', locale: :pt_BR)

    pacotes.with(corretora) { expect(I18n.t('crm.export.statuses', locale: :pt_BR)).to eq(base) }
    expect(base[:won]).to eq('Ganho')
  end

  it 'aceita a chave em partes, com scope' do
    escopo = %i[crm export statuses]

    pacotes.with(corretora) { expect(I18n.t(:won, scope: escopo, locale: :pt_BR)).to eq('Seguro ativo') }
  end

  it 'devolve o base com o interruptor desligado' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'false') do
      pacotes.with(corretora) { expect(I18n.t(won, locale: :pt_BR)).to eq('Ganho') }
    end
  end

  it 'devolve o base para conta geral' do
    pacotes.with(conta('geral')) { expect(I18n.t(won, locale: :pt_BR)).to eq('Ganho') }
  end

  it 'não passa a camada para uma thread nova' do
    pacotes.with(corretora) do
      expect(Thread.new { I18n.t(won, locale: :pt_BR) }.value).to eq('Ganho')
      expect(I18n.t(won, locale: :pt_BR)).to eq('Seguro ativo')
    end
  end

  it 'mantém cada thread com o pacote da sua conta, mesmo intercaladas' do
    primeira_entrou = Queue.new
    segunda_leu = Queue.new
    contas = [corretora, saude]

    # Com prazo: se uma thread cair antes de avisar, a outra desiste e o exemplo falha em vez de travar a suíte.
    primeira = Thread.new do
      pacotes.with(contas.first) do
        primeira_entrou << true
        segunda_leu.pop(timeout: 5) && I18n.t(won, locale: :pt_BR)
      end
    end
    segunda = Thread.new do
      primeira_entrou.pop(timeout: 5) && pacotes.with(contas.last) do
        texto = I18n.t(won, locale: :pt_BR)
        segunda_leu << true
        texto
      end
    end

    expect([primeira.join(10)&.value, segunda.join(10)&.value]).to eq(['Seguro ativo', 'Plano ativo'])
  end

  it 'deixa o plural do base com o count, mesmo se o pacote trouxer texto na chave' do
    allow(described_class).to receive(:dados).and_return(
      'seguros' => { pt_BR: { crm: { export: { subtitle: 'Planos exportados' } } } }
    )
    base = I18n.t('crm.export.subtitle', locale: :pt_BR, date: '01/01', count: 2)

    pacotes.with(corretora) do
      expect(I18n.t('crm.export.subtitle', locale: :pt_BR, date: '01/01', count: 2)).to eq(base)
    end
    expect(base).to eq('Exportado em 01/01 · 2 cards')
  end

  it 'não cria chave que não existe no base' do
    allow(described_class).to receive(:dados).and_return('seguros' => { pt_BR: { crm: { so_no_pacote: 'órfã' } } })

    pacotes.with(corretora) { expect(I18n.t('crm.so_no_pacote', locale: :pt_BR, default: 'ausente')).to eq('ausente') }
  end

  describe '.procurar' do
    before do
      allow(described_class).to receive(:dados).and_return(
        'a' => { pt_BR: { x: { y: 'da camada a', z: 'só na a' } } },
        'a/b' => { pt_BR: { x: { y: 'da camada a/b', w: { fundo: 'texto' } } } }
      )
    end

    it 'procura da camada mais específica para a mais geral' do
      expect(described_class.procurar(:pt_BR, 'x.y', [], nil, %w[a a/b])).to eq('da camada a/b')
      expect(described_class.procurar(:pt_BR, 'x.z', [], nil, %w[a a/b])).to eq('só na a')
    end

    it 'não devolve subárvore nem atravessa texto' do
      expect(described_class.procurar(:pt_BR, 'x', [], nil, %w[a a/b])).to be_nil
      expect(described_class.procurar(:pt_BR, 'x.y.mais', [], nil, %w[a a/b])).to be_nil
    end

    it 'ignora camada ou idioma que não existe' do
      expect(described_class.procurar(:pt_BR, 'x.y', [], nil, %w[outra])).to be_nil
      expect(described_class.procurar(:en, 'x.y', [], nil, %w[a a/b])).to be_nil
    end
  end

  describe '.dados' do
    describe 'com um yml que não abre' do
      around do |example|
        anterior = described_class.instance_variable_get(:@dados)
        described_class.instance_variable_set(:@dados, nil)
        example.run
      ensure
        described_class.instance_variable_set(:@dados, anterior)
      end

      it 'fica no catálogo base, lê uma vez só e registra só a classe do erro' do
        allow(YAML).to receive(:safe_load_file).and_raise(Psych::SyntaxError.new('x.yml', 1, 1, 0, 'segredo no trecho', 'ctx'))
        allow(Rails.logger).to receive(:error)

        pacotes.with(corretora) do
          expect(I18n.t(won, locale: :pt_BR)).to eq('Ganho')
          expect(I18n.t(lost, locale: :pt_BR)).to eq('Perdido')
        end

        expect(YAML).to have_received(:safe_load_file).once
        registro = satisfy { |linha| linha.include?('Psych::SyntaxError') && linha.exclude?('segredo') }
        expect(Rails.logger).to have_received(:error).with(registro).once
      end
    end

    it 'lê os yml de config/pacotes com a camada pela pasta e a raiz no idioma' do
      dados = described_class.dados

      expect(dados).to be_frozen
      expect(dados.keys).to include('seguros', 'seguros/saude_beneficios')
      expect(dados.dig('seguros', :pt_BR, :crm, :export, :statuses, :won)).to eq('Seguro ativo')
      expect(dados.dig('seguros/saude_beneficios', :en, :crm, :export, :statuses, :won)).to eq('Active plan')
    end
  end
end
