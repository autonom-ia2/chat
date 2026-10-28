require 'rails_helper'

# O job diário da leitura automática (#2301): espalha só para as contas com o painel ligado e roda a rodada de cada
# agente com chave de leitura que ainda existe e está ligado.
RSpec.describe Autonomia::Desempenho::LeituraAutomaticaJob do
  let(:ligada) { create(:account) }
  let(:sem_flag) { create(:account) }
  let(:robo) { create(:agent_bot, account: ligada) }
  let(:orquestrador) { Autonomia::Desempenho::LeituraAutomatica::Orquestrador }
  let(:rodadas) { [] }

  def ficha_com_chave!(account, sujeito_id, tipo: 'robo', versao: 1)
    ficha = ficha_da_loja!(account, sujeito_id: sujeito_id, versao: versao)
    ficha.update!(sujeito_type: tipo, chave_de_leitura: 'Leia.')
    ficha
  end

  def agente!(enabled: true)
    Autonomia::Agents::Agent.create!(account: ligada, name: 'Atendente', agent_type: 'custom', status: :active, enabled: enabled)
  end

  def registrar_rodadas
    allow(orquestrador).to receive(:new) do |ficha|
      rodadas << ficha.id
      instance_double(orquestrador, call: nil)
    end
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

  it 'com a conta, roda a ficha vigente de cada agente que tem chave de leitura' do
    vigente = ficha_com_chave!(ligada, robo.id, versao: 2)
    ficha_da_loja!(ligada, sujeito_id: create(:agent_bot, account: ligada).id) # sem chave: fica de fora
    registrar_rodadas

    rodar(ligada.id)

    expect(rodadas).to eq([vigente.id])
  end

  it 'pula o robô apagado e o agente apagado ou desligado' do
    ligado = agente!
    ficha_do_ligado = ficha_com_chave!(ligada, ligado.id, tipo: 'agente')
    ficha_com_chave!(ligada, agente!(enabled: false).id, tipo: 'agente')
    apagado = agente!
    ficha_com_chave!(ligada, apagado.id, tipo: 'agente')
    apagado.update!(deleted_at: Time.current)
    robo.destroy!
    registrar_rodadas

    rodar(ligada.id)

    expect(rodadas).to eq([ficha_do_ligado.id])
  end

  it 'a conta sem a flag não roda' do
    allow(orquestrador).to receive(:new)

    rodar(sem_flag.id)

    expect(orquestrador).not_to have_received(:new)
  end

  it 'erro na rodada é descartado, sem nova tentativa paga' do
    allow(orquestrador).to receive(:new).and_raise(ActiveRecord::StatementInvalid)

    expect { rodar(ligada.id) }.not_to raise_error
    expect(described_class).not_to have_been_enqueued
  end
end
