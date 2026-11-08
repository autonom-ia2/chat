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

  # stub_catalogo remonta o índice; cada exemplo termina com o índice real de novo.
  after do
    described_class.instance_variable_set(:@indice, nil)
    described_class::ACHADOS.clear
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
      expect(I18n.t(won, locale: :pt_BR)).to eq('Implantado')
      expect(I18n.t(won, locale: :en)).to eq('Implemented')
      expect(I18n.t(lost, locale: :pt_BR)).to eq('Não fechou')
      expect(I18n.t('crm.export.columns.lost_reason', locale: :pt_BR)).to eq('Por que não fechou')
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

    expect([primeira.join(10)&.value, segunda.join(10)&.value]).to eq(['Seguro ativo', 'Implantado'])
  end

  # Troca os yml do pacote no teste e remonta o índice de verdade (com o filtro contra o base); devolve o original no fim.
  def stub_catalogo(dados)
    allow(described_class).to receive(:carregar).and_return(dados)
    described_class.instance_variable_set(:@indice, nil)
    described_class::ACHADOS.clear
  end

  it 'deixa o plural do base com o count, mesmo se o pacote trouxer texto na chave' do
    stub_catalogo(
      'seguros' => { pt_BR: { crm: { export: { subtitle: 'Planos exportados' } } } }
    )
    base = I18n.t('crm.export.subtitle', locale: :pt_BR, date: '01/01', count: 2)

    pacotes.with(corretora) do
      expect(I18n.t('crm.export.subtitle', locale: :pt_BR, date: '01/01', count: 2)).to eq(base)
    end
    expect(base).to eq('Exportado em 01/01 · 2 cards')
  end

  it 'não cria chave que não existe no base' do
    stub_catalogo('seguros' => { pt_BR: { crm: { so_no_pacote: 'órfã' } } })

    pacotes.with(corretora) { expect(I18n.t('crm.so_no_pacote', locale: :pt_BR, default: 'ausente')).to eq('ausente') }
  end

  describe '.procurar' do
    before do
      stub_catalogo(
        'a' => { pt_BR: { crm: { export: { statuses: { won: 'da camada a', lost: 'só na a' } }, so_no_pacote: 'órfã' } } },
        'a/b' => { pt_BR: { crm: { export: { statuses: { won: 'da camada a/b' }, subtitle: 'plural vira texto' } } } }
      )
    end

    it 'procura da camada mais específica para a mais geral' do
      expect(described_class.procurar(:pt_BR, 'crm.export.statuses.won', [], nil, %w[a a/b])).to eq('da camada a/b')
      expect(described_class.procurar(:pt_BR, 'crm.export.statuses.lost', [], nil, %w[a a/b])).to eq('só na a')
      expect(described_class.procurar(:pt_BR, :lost, 'crm.export.statuses', nil, %w[a a/b])).to eq('só na a')
    end

    it 'não devolve subárvore, não atravessa texto e descarta o que no base não é texto' do
      expect(described_class.procurar(:pt_BR, 'crm.export.statuses', [], nil, %w[a a/b])).to be_nil
      expect(described_class.procurar(:pt_BR, 'crm.export.statuses.won.mais', [], nil, %w[a a/b])).to be_nil
      expect(described_class.procurar(:pt_BR, 'crm.so_no_pacote', [], nil, %w[a a/b])).to be_nil
      expect(described_class.procurar(:pt_BR, 'crm.export.subtitle', [], nil, %w[a a/b])).to be_nil
    end

    it 'ignora camada ou idioma que não existe' do
      expect(described_class.procurar(:pt_BR, 'crm.export.statuses.won', [], nil, %w[outra])).to be_nil
      expect(described_class.procurar(:en, 'crm.export.statuses.won', [], nil, %w[a a/b])).to be_nil
    end

    it 'descarta folha de plural e yml que desce por baixo de um texto do base, sem quebrar' do
      export = { subtitle: { one: 'um', other: 'vários' }, statuses: { won: { extra: 'por baixo de texto' } } }
      stub_catalogo('a' => { pt_BR: { crm: { export: export } } })

      expect(described_class.procurar(:pt_BR, 'crm.export.subtitle.other', [], nil, %w[a])).to be_nil
      expect(described_class.procurar(:pt_BR, 'crm.export.statuses.won.extra', [], nil, %w[a])).to be_nil
      expect(described_class.planas.fetch('a')).to eq({})
    end

    it 'aceita separador de vários caracteres e chave com separador sobrando' do
      expect(described_class.procurar(:pt_BR, 'crm::export::statuses::won', [], '::', %w[a a/b])).to eq('da camada a/b')
      expect(described_class.procurar(:pt_BR, '.crm.export.statuses.won', [], nil, %w[a a/b])).to eq('da camada a/b')
      expect(described_class.procurar(:pt_BR, 'crm..export.statuses.won', [], nil, %w[a a/b])).to eq('da camada a/b')
    end

    it 'guarda a resposta e responde igual na segunda vez, inclusive a ausência' do
      2.times do
        expect(described_class.procurar(:pt_BR, 'crm.export.statuses.won', [], nil, %w[a a/b])).to eq('da camada a/b')
        expect(described_class.procurar(:pt_BR, 'crm.export.statuses.won', [], nil, %w[a])).to eq('da camada a')
        expect(described_class.procurar(:pt_BR, 'crm.export.statuses.open', [], nil, %w[a a/b])).to be_nil
      end
    end
  end

  describe '.dados' do
    describe 'com um yml que não abre' do
      around do |example|
        anterior = described_class.instance_variable_get(:@indice)
        described_class.instance_variable_set(:@indice, nil)
        example.run
      ensure
        described_class.instance_variable_set(:@indice, anterior)
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
      expect(dados.dig('seguros/saude_beneficios', :en, :crm, :export, :statuses, :won)).to eq('Implemented')
    end
  end

  # Achados da revisão (#1550): o lookup roda em toda tradução de quem está num pacote.
  describe 'custo e imutabilidade' do
    it 'devolve na hora a chave cujo nome final não está em pacote nenhum, sem montar o caminho' do
      allow(I18n).to receive(:normalize_keys).and_call_original

      expect(described_class.procurar(:pt_BR, 'crm.export.statuses.open', [], nil, %w[seguros seguros/corretora])).to be_nil
      expect(I18n).not_to have_received(:normalize_keys)
    end

    it 'congela o catálogo inteiro, até as folhas' do
      texto = described_class.procurar(:pt_BR, 'crm.export.statuses.won', [], nil, %w[seguros])

      expect(texto).to eq('Seguro ativo')
      expect(texto).to be_frozen
      expect(described_class.dados.dig('seguros', :pt_BR, :crm)).to be_frozen
    end
  end

  # #1802: a camada seguros/corretora troca as frases da IA do Vendas e dos funis antigos; o resto segue de cima.
  describe 'camada da corretora' do
    let(:criterio) { 'crm.stage_criteria' }

    it 'troca as frases do Vendas e dos funis antigos só para a corretora' do
      base = I18n.t("#{criterio}.vendas.e2", locale: :pt_BR)

      pacotes.with(corretora) do
        expect(I18n.t("#{criterio}.vendas.e2", locale: :pt_BR)).to include('a equipe disse que está cotando')
        expect(I18n.t("#{criterio}.legado.em_atendimento", locale: :pt_BR)).to include('CEP de pernoite')
        expect(I18n.t("#{criterio}.vendas.e2", locale: :en)).to include('the team said it is quoting')
      end
      # A saúde tem a Venda de plano dela (#2083) e não herda o legado da corretora.
      pacotes.with(saude) do
        expect(I18n.t("#{criterio}.vendas.e2", locale: :pt_BR)).to include('quantas vidas')
        expect(I18n.t("#{criterio}.legado.em_atendimento", locale: :pt_BR)).not_to include('CEP de pernoite')
      end
      expect(I18n.t("#{criterio}.vendas.e2", locale: :pt_BR)).to eq(base)
    end

    it 'deixa o perdido dos funis antigos com o texto da camada seguros (F1) e os modelos novos com a base' do
      seguros = described_class.dados.dig('seguros', :pt_BR, :crm, :stage_criteria, :legado, :perdido)

      pacotes.with(corretora) do
        expect(I18n.t("#{criterio}.legado.perdido", locale: :pt_BR)).to eq(seguros)
        expect(I18n.t("#{criterio}.renovacao.e1", locale: :pt_BR)).to include('renovação do seguro que vai vencer')
      end
    end
  end
end
