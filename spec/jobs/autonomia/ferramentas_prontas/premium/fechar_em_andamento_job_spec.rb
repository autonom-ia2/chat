require 'rails_helper'

# #2858 (F7, revisor 12/11): o Experimente Premium roda em segundo plano, num job próprio, fora do `ToolRun` do agente.
# Para o worker que morre no meio da chamada não sumir com o custo da BigDataCorp, a execução grava uma linha "em
# andamento" ANTES de chamar e a atualiza ao terminar. A linha "em andamento" mais velha que o prazo máximo da consulta
# (mais a folga) vira entrega incerta, pela mesma regra do `entrega_incerta!`: o custo fica na telemetria e nada conta
# para o cliente. Quem fecha é o `FecharEmAndamentoJob`. BigDataCorp do WebMock: nenhuma chamada real.
RSpec.describe Autonomia::FerramentasProntas::Premium::FecharEmAndamentoJob do
  let(:account) { create(:account) }
  let(:premium) { Autonomia::FerramentasProntas::Premium }
  let(:ferramenta) { Autonomia::Agents::Tool.new(account: account, fonte_pronta: 'certidoes_empresa') }
  let(:pgfn) { { 'consulta' => 'divida_uniao', 'cnpj' => '11.222.333/0001-81' } }
  let(:certidao_negativa) do
    [{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA', 'AdditionalOutputData' => { 'EmissionDate' => '2026-11-10 10:00:00Z' } }]
  end

  def consultar(em_andamento: true)
    JSON.parse(Autonomia::FerramentasProntas.executor_para(ferramenta, params: pgfn, em_andamento: em_andamento).call)
  end

  def em_andamento!(criada_em)
    travel_to(criada_em) do
      fonte = Autonomia::FerramentasProntas::Catalogo.buscar('certidoes_empresa')
      premium::Cobranca.em_andamento!(tool: ferramenta, fonte: fonte, consulta: fonte.consulta('divida_uniao'))
    end
  end

  around { |example| com_credencial_da_bigdatacorp { example.run } }

  before do
    ligar_premium(account)
    cache_em_memoria
    token_da_bigdatacorp
    Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: account.id, fonte: 'certidoes_empresa')
  end

  it 'a linha "em andamento" existe enquanto a BigDataCorp responde; ao terminar, a MESMA linha vira o resultado' do
    vistas = []
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return do
      vistas << registros_premium.pluck(:resultado)
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: corpo_da_bigdatacorp('ondemand_pgfn_company', 'OnlineCertificates', certidao_negativa).to_json }
    end

    expect(consultar['situacao']).to eq('encontrado')
    expect(vistas).to eq([%w[em_andamento]])
    expect(registros_premium.sole).to have_attributes(resultado: 'encontrado', cobranca: 'gratis', numero: 1, custo: BigDecimal('0.10'))
  end

  it 'sem `em_andamento` (o agente), nada muda: uma linha só, gravada no fim' do
    bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', certidao_negativa)

    consultar(em_andamento: false)

    expect(registros_premium.sole).to have_attributes(resultado: 'encontrado', numero: 1)
  end

  it 'o worker que morre: a linha "em andamento" velha vira entrega incerta, com o custo e sem contar para o cliente' do
    linha = em_andamento!(10.minutes.ago)

    described_class.perform_now(account.id)

    expect(linha.reload).to have_attributes(resultado: 'falha', motivo: 'entrega_incerta', cobranca: 'sem_cobranca', numero: nil,
                                            custo: BigDecimal('0.10'), preco: 0)
    expect(premium::Saldo.count).to eq(0)
  end

  it 'a linha dentro do prazo da consulta não é fechada, nem a de outra conta' do
    nova = em_andamento!(10.seconds.ago)
    outra = create(:account)
    de_outra = premium::Registro.create!(account: outra, fonte: 'certidoes_empresa', consulta: 'divida_uniao', dataset: 'ondemand_pgfn_company',
                                         dia: Time.zone.today, resultado: 'em_andamento', cobranca: 'sem_cobranca',
                                         created_at: 10.minutes.ago)

    described_class.perform_now(account.id)

    expect(nova.reload.resultado).to eq('em_andamento')
    expect(de_outra.reload.resultado).to eq('em_andamento')
  end

  it 'a execução que termina depois do varredor não conta nem cobra: a linha fica como entrega incerta, e o caso vai ao log' do
    allow(Rails.logger).to receive(:warn)
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return do
      travel_to(10.minutes.from_now) { described_class.perform_now(account.id) }
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: corpo_da_bigdatacorp('ondemand_pgfn_company', 'OnlineCertificates', certidao_negativa).to_json }
    end

    expect(consultar['situacao']).to eq('encontrado')
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'entrega_incerta', cobranca: 'sem_cobranca',
                                                      custo: BigDecimal('0.10'))
    expect(premium::Saldo.count).to eq(0)
    expect(Rails.logger).to have_received(:warn).with(a_string_including('já fechada como entrega incerta'))
  end

  it 'a execução com `em_andamento` agenda o varredor da conta para depois do prazo' do
    freeze_time
    bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', certidao_negativa)

    expect { consultar }.to have_enqueued_job(described_class).with(account.id).at(described_class::ESPERA.from_now)
  end

  it 'a execução sem `em_andamento` (o agente) não agenda o varredor' do
    bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', certidao_negativa)

    expect { consultar(em_andamento: false) }.not_to have_enqueued_job(described_class)
  end

  context 'without a conta: a varredura periódica do config/schedule.yml' do
    def em_andamento_de(conta, criada_em)
      premium::Registro.create!(account: conta, fonte: 'certidoes_empresa', consulta: 'divida_uniao', dataset: 'ondemand_pgfn_company',
                                dia: Time.zone.today, resultado: 'em_andamento', cobranca: 'sem_cobranca', created_at: criada_em)
    end

    it 'fecha a linha órfã de todas as contas, pela mesma regra, e deixa a que ainda está no prazo' do
      outra = create(:account)
      orfa = em_andamento!(10.minutes.ago)
      orfa_de_outra = em_andamento_de(outra, 10.minutes.ago)
      nova = em_andamento_de(outra, 10.seconds.ago)

      described_class.perform_now

      expect(orfa.reload).to have_attributes(resultado: 'falha', motivo: 'entrega_incerta', custo: BigDecimal('0.10'))
      expect(orfa_de_outra.reload).to have_attributes(resultado: 'falha', motivo: 'entrega_incerta', custo: BigDecimal('0.10'))
      expect(nova.reload.resultado).to eq('em_andamento')
      expect(premium::Saldo.count).to eq(0)
    end

    it 'está agendada no config/schedule.yml, sem conta nos argumentos' do
      schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
      entrada = schedule.values.find { |item| item['class'] == described_class.name }

      expect(entrada).to include('queue' => 'scheduled_jobs')
      expect(entrada['cron']).to be_present
      expect(entrada['args']).to be_nil
    end
  end

  it 'o prazo do varredor cobre a consulta mais lenta (sob demanda) com folga' do
    expect(described_class::LIMITE).to be > (premium::Dataset::PRAZO_SOB_DEMANDA + premium::ConsultaPaga::FOLGA).seconds
  end
end
