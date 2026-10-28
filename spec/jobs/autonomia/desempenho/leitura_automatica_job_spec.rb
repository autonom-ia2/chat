require 'rails_helper'

# O job diário da leitura automática (#2301): espalha só para as contas com o painel ligado e roda a rodada de cada
# agente com chave de leitura.
RSpec.describe Autonomia::Desempenho::LeituraAutomaticaJob do
  let(:ligada) { create(:account) }
  let(:sem_flag) { create(:account) }
  let(:orquestrador) { Autonomia::Desempenho::LeituraAutomatica::Orquestrador }

  def ficha_com_chave!(account, sujeito_id)
    ficha_da_loja!(account, sujeito_id: sujeito_id).tap { |ficha| ficha.update!(chave_de_leitura: 'Leia.') }
  end

  before do
    ligada.enable_features!('agentes_painel_desempenho')
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    ficha_com_chave!(ligada, 1)
    ficha_com_chave!(sem_flag, 2)
  end

  it 'com a ENV desligada (padrão), não faz nada' do
    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: nil) do
      expect { described_class.perform_now }.not_to have_enqueued_job(described_class)
    end
  end

  it 'espalha um job só para as contas com a flag' do
    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true') do
      expect { described_class.perform_now }.to have_enqueued_job(described_class).with(ligada.id).exactly(:once)
    end
  end

  it 'com a conta, roda a ficha vigente de cada agente que tem chave de leitura' do
    vigente = ficha_da_loja!(ligada, sujeito_id: 1, versao: 2).tap { |ficha| ficha.update!(chave_de_leitura: 'Leia a v2.') }
    ficha_da_loja!(ligada, sujeito_id: 3) # sem chave: fica de fora
    rodadas = []
    allow(orquestrador).to receive(:new) do |ficha|
      rodadas << ficha.id
      instance_double(orquestrador, call: nil)
    end

    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true') { described_class.perform_now(ligada.id) }

    expect(rodadas).to eq([vigente.id])
  end

  it 'a conta sem a flag não roda' do
    allow(orquestrador).to receive(:new)

    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true') { described_class.perform_now(sem_flag.id) }

    expect(orquestrador).not_to have_received(:new)
  end
end
