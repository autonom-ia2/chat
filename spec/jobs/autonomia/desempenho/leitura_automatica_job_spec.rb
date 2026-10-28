require 'rails_helper'

# O job diário da leitura automática (#2301): espalha só para as contas com o painel ligado e enfileira um
# LeituraDaFichaJob por agente com chave de leitura que ainda existe e está ligado.
RSpec.describe Autonomia::Desempenho::LeituraAutomaticaJob do
  let(:ligada) { create(:account) }
  let(:sem_flag) { create(:account) }
  let(:robo) { create(:agent_bot, account: ligada) }

  def ficha_com_chave!(account, sujeito_id, tipo: 'robo', versao: 1)
    ficha = ficha_da_loja!(account, sujeito_id: sujeito_id, versao: versao)
    ficha.update!(sujeito_type: tipo, chave_de_leitura: 'Leia.')
    ficha
  end

  def agente!(enabled: true)
    Autonomia::Agents::Agent.create!(account: ligada, name: 'Atendente', agent_type: 'custom', status: :active, enabled: enabled)
  end

  # [account_id, ficha_id] de cada LeituraDaFichaJob enfileirado.
  def fichas_enfileiradas
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == 'Autonomia::Desempenho::LeituraDaFichaJob' }
                   .map { |job| job['arguments'] }
  end

  def rodar(account_id = nil)
    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true') { described_class.perform_now(account_id) }
  end

  before do
    ligada.enable_features!('agentes_painel_desempenho')
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    ficha_com_chave!(ligada, robo.id)
    ficha_com_chave!(sem_flag, create(:agent_bot, account: sem_flag).id)
  end

  it 'com a ENV desligada (padrão), não faz nada' do
    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: nil) do
      expect { described_class.perform_now }.not_to have_enqueued_job(described_class)
    end
  end

  it 'espalha um job só para as contas com a flag' do
    expect { rodar }.to have_enqueued_job(described_class).with(ligada.id).exactly(:once)
  end

  it 'com a conta, enfileira um job para a ficha vigente de cada agente que tem chave de leitura' do
    vigente = ficha_com_chave!(ligada, robo.id, versao: 2)
    ficha_da_loja!(ligada, sujeito_id: create(:agent_bot, account: ligada).id) # sem chave: fica de fora

    rodar(ligada.id)

    expect(fichas_enfileiradas).to eq([[ligada.id, vigente.id]])
  end

  it 'enfileira um job por agente, cada um com a sua ficha' do
    outro = ficha_com_chave!(ligada, create(:agent_bot, account: ligada).id)

    rodar(ligada.id)

    expect(fichas_enfileiradas).to contain_exactly([ligada.id, Autonomia::Desempenho::Ficha.vigente(ligada, 'robo', robo.id).id],
                                                   [ligada.id, outro.id])
  end

  it 'quem leu há mais tempo vai primeiro, e os jobs saem espaçados para a ordem valer' do
    outro = ficha_com_chave!(ligada, create(:agent_bot, account: ligada).id)
    Autonomia::Desempenho::Rodada.create!(account: ligada, sujeito_type: 'robo', sujeito_id: robo.id, corte_em: 1.hour.ago, piso_em: 1.day.ago,
                                          iniciada_em: 1.hour.ago, status: 'ok', lote: 'spec')

    rodar(ligada.id)

    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == 'Autonomia::Desempenho::LeituraDaFichaJob' }
    expect(jobs.map { |job| job['arguments'].second }).to eq([outro.id, Autonomia::Desempenho::Ficha.vigente(ligada, 'robo', robo.id).id])
    expect(jobs.second[:at] - jobs.first[:at]).to be_within(1).of(described_class::VEZ_A_VEZ)
  end

  it 'pula o robô apagado e o agente apagado ou desligado' do
    ligado = agente!
    ficha_do_ligado = ficha_com_chave!(ligada, ligado.id, tipo: 'agente')
    ficha_com_chave!(ligada, agente!(enabled: false).id, tipo: 'agente')
    apagado = agente!
    ficha_com_chave!(ligada, apagado.id, tipo: 'agente')
    apagado.update!(deleted_at: Time.current)
    robo.destroy!

    rodar(ligada.id)

    expect(fichas_enfileiradas).to eq([[ligada.id, ficha_do_ligado.id]])
  end

  it 'a conta sem a flag não enfileira nada' do
    rodar(sem_flag.id)

    expect(fichas_enfileiradas).to be_empty
  end

  it 'listar as fichas não engole erro: fica com as novas tentativas padrão (não paga nada)' do
    allow(Autonomia::Desempenho::Ficha).to receive(:vigente).and_raise(ActiveRecord::StatementInvalid)

    expect { rodar(ligada.id) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(described_class.rescue_handlers.map(&:first)).not_to include('StandardError')
  end
end
