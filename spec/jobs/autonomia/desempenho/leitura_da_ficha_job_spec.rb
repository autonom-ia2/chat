require 'rails_helper'

# A rodada de um agente (#2301): um job por ficha, descartado se a rodada cair (cada tentativa pagaria IA de novo), sem
# segurar a rodada dos outros agentes da conta; reagendado quando outra rodada da conta está em andamento ou quando o
# erro veio antes de abrir a rodada (nada pago); uma por dia, em qualquer status.
RSpec.describe Autonomia::Desempenho::LeituraDaFichaJob do
  let(:account) { create(:account) }
  let(:orquestrador) { Autonomia::Desempenho::LeituraAutomatica::Orquestrador }
  let(:robo_a) { create(:agent_bot, account: account) }
  let(:ficha_a) { ficha_com_chave!(robo_a.id) }
  let(:ficha_b) { ficha_com_chave!(create(:agent_bot, account: account).id) }
  let(:rodadas) { [] }

  def ficha_com_chave!(sujeito_id, versao: 1)
    ficha_da_loja!(account, sujeito_id: sujeito_id, versao: versao).tap { |f| f.update!(chave_de_leitura: 'Leia.') }
  end

  def ligada(&)
    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true', &)
  end

  def rodada(status)
    Autonomia::Desempenho::Rodada.create!(account: account, sujeito_type: 'robo', sujeito_id: robo_a.id, corte_em: Time.current,
                                          piso_em: 1.day.ago, iniciada_em: Time.current, status: status, lote: 'spec')
  end

  # Cada rodada chamada fica em `rodadas`; a da ficha A cai (registrada como erro), a das outras devolve `status`.
  def rodadas_devolvem(status: 'ok', a_cai: false)
    allow(orquestrador).to receive(:new) do |ficha|
      rodadas << ficha.id
      raise orquestrador::RodadaComErro, 'NoMethodError' if a_cai && ficha.id == ficha_a.id

      instance_double(orquestrador, call: rodada(status))
    end
  end

  before do
    account.enable_features!('agentes_painel_desempenho')
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
  end

  after do
    Redis::Alfred.with { |redis| redis.scan_each(match: "autonomia:desempenho:leitura:rodou:#{account.id}:*").each { |chave| redis.del(chave) } }
  end

  it 'erro na rodada da ficha A é descartado, sem nova tentativa, e a ficha B roda' do
    rodadas_devolvem(a_cai: true)

    ligada do
      expect { described_class.perform_now(account.id, ficha_a.id) }.not_to raise_error
      described_class.perform_now(account.id, ficha_b.id)
    end

    expect(rodadas).to eq([ficha_a.id, ficha_b.id])
    expect(described_class).not_to have_been_enqueued
  end

  it 'pelo job da conta, o erro de A não impede B' do
    rodadas_devolvem(a_cai: true)
    [ficha_a, ficha_b]

    ligada do
      perform_enqueued_jobs(only: described_class) { Autonomia::Desempenho::LeituraAutomaticaJob.perform_now(account.id) }
    end

    expect(rodadas).to contain_exactly(ficha_a.id, ficha_b.id)
  end

  it 'com a conta ocupada por outra rodada, reagenda a ficha para mais tarde, sem descartar' do
    ocupada = instance_double(orquestrador)
    allow(ocupada).to receive(:call).and_raise(orquestrador::ContaOcupada)
    allow(orquestrador).to receive(:new).and_return(ocupada)

    ligada { described_class.perform_now(account.id, ficha_b.id) }

    expect(described_class).to have_been_enqueued.with(account.id, ficha_b.id)
    # A primeira execução conta como tentativa: são TENTATIVAS_DA_CONTA - 1 reagendamentos.
    expect((described_class::TENTATIVAS_DA_CONTA - 1) * described_class::ESPERA_DA_CONTA).to be >= orquestrador::TRAVA_POR
  end

  it 'uma rodada por agente por dia, em qualquer status: o job duplicado do mesmo dia não paga de novo' do
    rodadas_devolvem(status: 'erro')
    ligada { described_class.perform_now(account.id, ficha_a.id) }

    rodadas_devolvem(status: 'teto')
    ligada { 2.times { described_class.perform_now(account.id, ficha_a.id) } }
    expect(rodadas).to eq([ficha_a.id])

    travel_to(1.day.from_now) { ligada { described_class.perform_now(account.id, ficha_a.id) } }
    expect(rodadas).to eq([ficha_a.id, ficha_a.id])
  end

  it 'a rodada que caiu também marca o dia: a nova tentativa do job da conta não paga de novo' do
    rodadas_devolvem(a_cai: true)

    ligada { 2.times { described_class.perform_now(account.id, ficha_a.id) } }

    expect(rodadas).to eq([ficha_a.id])
  end

  it 'erro antes de abrir a rodada (nada pago) é logado com a conta e tenta de novo, sem marcar o dia' do
    allow(orquestrador).to receive(:new).and_raise(Redis::CannotConnectError)
    allow(Rails.logger).to receive(:error)

    ligada { described_class.perform_now(account.id, ficha_a.id) }

    expect(Rails.logger).to have_received(:error)
      .with("[desempenho][leitura] conta=#{account.id} ficha=#{ficha_a.id} antes_da_rodada=Redis::CannotConnectError")
    expect(described_class).to have_been_enqueued.with(account.id, ficha_a.id)
    expect(Redis::Alfred.with { |redis| redis.keys("autonomia:desempenho:leitura:rodou:#{account.id}:*") }).to be_empty
  end

  it 'erro ao marcar o dia depois da rodada (já paga) só fica no log: o job não tenta de novo' do
    rodadas_devolvem
    allow(Redis::Alfred).to receive(:set).and_call_original
    allow(Redis::Alfred).to receive(:set).with(start_with('autonomia:desempenho:leitura:rodou:'), anything, anything)
                                         .and_raise(Redis::CannotConnectError)
    allow(Rails.logger).to receive(:error)

    ligada { described_class.perform_now(account.id, ficha_a.id) }

    expect(Rails.logger).to have_received(:error)
      .with("[desempenho][leitura] conta=#{account.id} ficha=#{ficha_a.id} marca_rodou=Redis::CannotConnectError")
    expect(described_class).not_to have_been_enqueued
  end

  it 'com a ENV desligada, não roda' do
    allow(orquestrador).to receive(:new)

    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: nil) { described_class.perform_now(account.id, ficha_a.id) }

    expect(orquestrador).not_to have_received(:new)
  end

  it 'não roda a ficha que deixou de ser a vigente nem a de outra conta' do
    antiga = ficha_a
    ficha_com_chave!(antiga.sujeito_id, versao: 2)
    allow(orquestrador).to receive(:new)

    ligada do
      described_class.perform_now(account.id, antiga.id)
      described_class.perform_now(create(:account).id, ficha_b.id)
    end

    expect(orquestrador).not_to have_received(:new)
  end

  it 'confere de novo a conta e o agente, com o mesmo critério do job da conta' do
    allow(orquestrador).to receive(:new)
    ficha_do_apagado = ficha_a
    robo_a.destroy!

    ligada do
      described_class.perform_now(account.id, ficha_do_apagado.id)
      account.disable_features!('agentes_painel_desempenho')
      described_class.perform_now(account.id, ficha_b.id)
    end

    expect(orquestrador).not_to have_received(:new)
  end
end
