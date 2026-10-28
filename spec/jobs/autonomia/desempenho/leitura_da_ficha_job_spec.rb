require 'rails_helper'

# A rodada de um agente (#2301): um job por ficha, descartado se cair (cada tentativa pagaria IA de novo), sem segurar
# a rodada dos outros agentes da conta.
RSpec.describe Autonomia::Desempenho::LeituraDaFichaJob do
  let(:account) { create(:account) }
  let(:orquestrador) { Autonomia::Desempenho::LeituraAutomatica::Orquestrador }
  let(:ficha_a) { ficha_com_chave!(create(:agent_bot, account: account).id) }
  let(:ficha_b) { ficha_com_chave!(create(:agent_bot, account: account).id) }
  let(:rodadas) { [] }

  def ficha_com_chave!(sujeito_id, versao: 1)
    ficha_da_loja!(account, sujeito_id: sujeito_id, versao: versao).tap { |f| f.update!(chave_de_leitura: 'Leia.') }
  end

  def ligada(&)
    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true', &)
  end

  # A rodada da ficha A cai com um erro; a da B roda.
  def a_cai
    allow(orquestrador).to receive(:new) do |ficha|
      rodadas << ficha.id
      raise ActiveRecord::StatementInvalid if ficha.id == ficha_a.id

      instance_double(orquestrador, call: nil)
    end
  end

  it 'erro na rodada da ficha A é descartado, sem nova tentativa, e a ficha B roda' do
    a_cai

    ligada do
      expect { described_class.perform_now(account.id, ficha_a.id) }.not_to raise_error
      described_class.perform_now(account.id, ficha_b.id)
    end

    expect(rodadas).to eq([ficha_a.id, ficha_b.id])
    expect(described_class).not_to have_been_enqueued
  end

  it 'pelo job da conta, o erro de A não impede B' do
    a_cai
    account.enable_features!('agentes_painel_desempenho')
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    [ficha_a, ficha_b]

    ligada do
      perform_enqueued_jobs(only: described_class) { Autonomia::Desempenho::LeituraAutomaticaJob.perform_now(account.id) }
    end

    expect(rodadas).to contain_exactly(ficha_a.id, ficha_b.id)
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
end
