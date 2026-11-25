require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::BaseEmDiaJob do
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Desde 2010.' }
  end

  def contratado(versao)
    config = { 'contratado' => marca }
    config['contratado_base_versao'] = versao if versao
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato', config: config)
  end

  it 'enfileira só os contratados com a base de outra versão (ou nunca semeada)' do
    velho = contratado('0000000000000000')
    nunca = contratado(nil)
    em_dia = contratado(Autonomia::Agents::Contratados::Base::VERSAO)
    apagado = contratado(nil)
    apagado.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr')

    semear = Autonomia::Agents::Contratados::SemearBaseJob
    expect { described_class.perform_now }.to have_enqueued_job(semear).exactly(2)
    expect(semear).to have_been_enqueued.with(velho.id)
    expect(semear).to have_been_enqueued.with(nunca.id)
    [em_dia, apagado, comum].each { |fora| expect(semear).not_to have_been_enqueued.with(fora.id) }
  end

  it 'está no cron de hora em hora' do
    agenda = YAML.load_file(Rails.root.join('config/schedule.yml'))
    expect(agenda['autonomia_contratados_base_em_dia_job']).to eq(
      'cron' => '17 * * * *', 'class' => described_class.name, 'queue' => 'scheduled_jobs'
    )
  end
end
