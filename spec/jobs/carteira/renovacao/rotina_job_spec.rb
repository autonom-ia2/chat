require 'rails_helper'

# E5 (#2898) — a rotina da renovação: um job por conta que já escolheu onde ficam as renovações.
RSpec.describe Carteira::Renovacao::RotinaJob do
  def conta_que_escolheu
    conta = conta_com_carteira
    funil, etapa = create_crm_pipeline(account: conta, user: create(:user, account: conta, role: :administrator), name: 'Renovação')
    create(:carteira_renovacao_config, account: conta, pipeline: funil, stage: etapa)
    conta
  end

  it 'enfileira um job para cada conta que escolheu, e nenhum para a que ainda não escolheu' do
    escolheram = [conta_que_escolheu, conta_que_escolheu]
    create(:carteira_renovacao_config, account: conta_com_carteira)

    expect { described_class.perform_now }.to have_enqueued_job(Carteira::Renovacao::DaContaJob).exactly(:twice)

    expect(enqueued_jobs.select { |job| job['job_class'] == 'Carteira::Renovacao::DaContaJob' }.map { |job| job['arguments'] })
      .to match_array(escolheram.map { |conta| [conta.id] })
  end
end
