# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Segmentos::Pacotes do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:sem_escolha) { create(:account) }

  # O padrão da instalação passa pelo cache do GlobalConfig (Redis): limpar antes e depois para não vazar.
  around do |example|
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    example.run
  ensure
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    ActiveSupport::IsolatedExecutionState.delete(AutonomiaPacotesI18nLookup::ESTADO)
  end

  def conta(nicho_escolhido, perfil = nil, canal = nil)
    atributos = { nicho::NICHO_KEY => nicho_escolhido, nicho::PERFIL_KEY => perfil, nicho::CANAL_KEY => canal }.compact
    create(:account, internal_attributes: atributos)
  end

  def ligado(&)
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true', &)
  end

  describe '.enabled?' do
    it 'fica desligado sem a ENV' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) { expect(described_class.enabled?).to be(false) }
    end

    it 'liga com true e desliga com false' do
      ligado { expect(described_class.enabled?).to be(true) }
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'false') { expect(described_class.enabled?).to be(false) }
    end
  end

  # Revisão (#1550): valor digitado errado na stack não liga os pacotes.
  it 'só liga com true ou 1' do
    resultados = %w[true TRUE 1 lixo no yes 0 false].index_with do |valor|
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: valor) { described_class.enabled? }
    end

    expect(resultados).to eq('true' => true, 'TRUE' => true, '1' => true, 'lixo' => false, 'no' => false,
                             'yes' => false, '0' => false, 'false' => false)
  end

  describe '.camadas' do
    it 'devolve [] para conta de seguros com o interruptor desligado' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
        expect(described_class.camadas(conta('seguros', 'corretora'))).to eq([])
      end
    end

    it 'devolve [] para conta geral' do
      ligado { expect(described_class.camadas(conta('geral'))).to eq([]) }
    end

    it 'devolve seguros e seguros/<tipo> para a corretora' do
      ligado { expect(described_class.camadas(conta('seguros', 'corretora'))).to eq(%w[seguros seguros/corretora]) }
    end

    it 'devolve a camada de saúde e benefícios' do
      ligado do
        expect(described_class.camadas(conta('seguros', 'saude_beneficios'))).to eq(%w[seguros seguros/saude_beneficios])
      end
    end

    it 'não cria camada para o canal da insurtech' do
      ligado do
        expect(described_class.camadas(conta('seguros', 'insurtech', 'corretores'))).to eq(%w[seguros seguros/insurtech])
      end
    end

    it 'usa o padrão da instalação quando a conta não escolheu' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true', AUTONOMIA_NICHO_PADRAO: 'seguros:seguradora') do
        expect(described_class.camadas(sem_escolha)).to eq(%w[seguros seguros/seguradora])
      end
    end

    it 'devolve [] sem conta' do
      ligado { expect(described_class.camadas(nil)).to eq([]) }
    end

    it 'cai no geral e registra só a classe do erro quando a leitura do nicho falha' do
      account = conta('seguros', 'corretora')
      allow(nicho).to receive(:for).and_raise(ArgumentError, 'segredo da conta')
      allow(Rails.logger).to receive(:warn)

      ligado { expect(described_class.camadas(account)).to eq([]) }

      expect(Rails.logger).to have_received(:warn).with(
        a_string_including('[Autonomia::Segmentos::Pacotes]', "account=#{account.id}", 'ArgumentError')
      )
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('segredo da conta'))
    end
  end

  describe '.nome' do
    it 'devolve seguros.<tipo> ou nil' do
      ligado do
        expect(described_class.nome(conta('seguros', 'saude_beneficios'))).to eq('seguros.saude_beneficios')
        expect(described_class.nome(conta('geral'))).to be_nil
      end
      expect(described_class.nome(conta('seguros', 'corretora'))).to be_nil
    end
  end

  describe '.with' do
    it 'ativa as camadas só dentro do bloco e devolve o valor do bloco' do
      corretora = conta('seguros', 'corretora')

      ligado do
        resultado = described_class.with(corretora) { described_class.ativas }
        expect(resultado).to eq(%w[seguros seguros/corretora])
      end
      expect(described_class.ativas).to eq([])
    end

    it 'restaura a camada de fora depois de um with aninhado' do
      corretora = conta('seguros', 'corretora')
      saude = conta('seguros', 'saude_beneficios')

      ligado do
        described_class.with(corretora) do
          described_class.with(saude) { expect(described_class.ativas).to eq(%w[seguros seguros/saude_beneficios]) }
          expect(described_class.ativas).to eq(%w[seguros seguros/corretora])
        end
      end
      expect(described_class.ativas).to eq([])
    end

    it 'restaura mesmo quando o bloco lança erro' do
      corretora = conta('seguros', 'corretora')

      ligado do
        expect { described_class.with(corretora) { raise ArgumentError, 'falhou' } }
          .to(raise_error { |erro| expect(erro.class.name).to eq('ArgumentError') })
      end
      expect(described_class.ativas).to eq([])
    end
  end

  describe 'em jobs' do
    before do
      stub_const('PacotesQueFalhaJob', Class.new(ApplicationJob) do
        def perform(account)
          Autonomia::Segmentos::Pacotes.with(account) { raise ArgumentError, 'falhou no job' }
        end
      end)
      stub_const('PacotesLeituraJob', Class.new(ApplicationJob) do
        def perform
          [Autonomia::Segmentos::Pacotes.ativas, I18n.t('crm.export.statuses.won', locale: :pt_BR)]
        end
      end)
    end

    it 'não deixa a camada de um job que falhou para o próximo' do
      corretora = conta('seguros', 'corretora')

      ligado do
        expect { Rails.application.executor.wrap { PacotesQueFalhaJob.perform_now(corretora) } }
          .to(raise_error { |erro| expect(erro.class.name).to eq('ArgumentError') })
        expect(described_class.ativas).to eq([])

        resultado = Rails.application.executor.wrap { PacotesLeituraJob.perform_now }
        expect(resultado).to eq([[], 'Ganho'])
      end
    end

    it 'limpa no executor a camada que ficou solta na thread' do
      ActiveSupport::IsolatedExecutionState[AutonomiaPacotesI18nLookup::ESTADO] = %w[seguros seguros/corretora]

      resultado = Rails.application.executor.wrap { PacotesLeituraJob.perform_now }

      expect(resultado).to eq([[], 'Ganho'])
      expect(described_class.ativas).to eq([])
    end
  end
end
