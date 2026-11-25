require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::SemearBaseJob do
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Desde 2010.' }
  end
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => marca })
  end

  before { allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!) }

  it 'semeia o contratado (a conferência de em dia é da Base, sob a trava)' do
    described_class.perform_now(contratado.id)
    expect(Autonomia::Agents::Contratados::Base).to have_received(:semear_se_preciso!).with(contratado)
  end

  it 'agente apagado: nada' do
    contratado.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    described_class.perform_now(contratado.id)
    expect(Autonomia::Agents::Contratados::Base).not_to have_received(:semear_se_preciso!)
  end

  it 'agente que não é contratado, ou que não existe: nada' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr')
    described_class.perform_now(comum.id)
    described_class.perform_now(0)
    expect(Autonomia::Agents::Contratados::Base).not_to have_received(:semear_se_preciso!)
  end

  it 'falha do embedding: só o motivo curto no log, sem levantar' do
    allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!)
      .and_raise(Autonomia::Agents::EmbeddingService::EmbeddingError, 'ai_not_configured')
    allow(Rails.logger).to receive(:warn)

    expect { described_class.perform_now(contratado.id) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(a_string_including('motivo=ai_not_configured'))
  end

  it 'com o embedding de verdade parado, semeia a base inteira do modelo uma vez' do
    allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!).and_call_original
    embedder = instance_double(Autonomia::Agents::EmbeddingService)
    coluna = Autonomia::Agents::Config.embedding_column(Autonomia::Agents::Config.active_embedding_model)
    dimensao = coluna == Autonomia::Agents::Config::EMBEDDING_LARGE_COLUMN ? 3072 : 1536
    allow(embedder).to receive(:embed_batch) { |textos| textos.map { Array.new(dimensao, 0.01) } }
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)

    2.times { described_class.perform_now(contratado.id) }

    expect(embedder).to have_received(:embed_batch).once
    expect(Autonomia::Agents::Contratados::Base.em_dia?(contratado.reload)).to be(true)
  end
end
