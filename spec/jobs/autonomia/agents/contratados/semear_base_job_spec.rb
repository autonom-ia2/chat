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

  before do
    enable_test_encryption!
    marcar_corretora!(account)
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                             'agente_ferramentas_prontas_consultas')
    allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!)
    allow(Rails.logger).to receive(:warn)
  end

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

  it 'conta com o modelo desligado: nada' do
    account.disable_features!('agente_seguro_viagem_universal')
    described_class.perform_now(contratado.id)
    expect(Autonomia::Agents::Contratados::Base).not_to have_received(:semear_se_preciso!)
  end

  # #3270: o embedding é pago; o agente pausado (7 dias grátis vencidos, sem a liberação) não ganha base nova.
  describe 'agente pausado' do
    before { contratado.update_columns(created_at: 8.days.ago) } # rubocop:disable Rails/SkipsModelValidations

    it 'não semeia' do
      described_class.perform_now(contratado.id)
      expect(Autonomia::Agents::Contratados::Base).not_to have_received(:semear_se_preciso!)
    end

    it 'não apaga a base que existe (nem chama a Base)' do
      base = Autonomia::Agents::Contratados::Base
      fonte = contratado.sources.create!(account_id: account.id, source_type: 'md', kind: :knowledge, reference: base::REFERENCIA,
                                         metadata: { base::MARCA_DA_FONTE => true }, status: :ready, review_status: 'accepted')
      described_class.perform_now(contratado.id)
      expect(Autonomia::Agents::Source.exists?(fonte.id)).to be(true)
    end

    it 'liberada a conta, semeia' do
      Autonomia::Agents::Contratados::Liberacao.atribuir(account, ['seguro_viagem_universal'])
      account.save!
      described_class.perform_now(contratado.id)
      expect(Autonomia::Agents::Contratados::Base).to have_received(:semear_se_preciso!).with(contratado)
    end
  end

  it 'falha do embedding: só o motivo curto no log, sem levantar' do
    allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!)
      .and_raise(Autonomia::Agents::EmbeddingService::EmbeddingError, 'ai_not_configured')

    expect { described_class.perform_now(contratado.id) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(a_string_including('motivo=ai_not_configured'))
  end

  it 'falha de rede que escapa do serviço: motivo rede, sem a exceção crua no log' do
    allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!)
      .and_raise(Faraday::ConnectionFailed, 'detalhe-interno-do-erro')

    expect { described_class.perform_now(contratado.id) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(a_string_including('motivo=rede'))
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including('detalhe-interno-do-erro'))
  end

  it 'conta sem a própria chave: o motivo no log' do
    allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!).and_return('sem_chave_da_conta')

    described_class.perform_now(contratado.id)

    expect(Rails.logger).to have_received(:warn).with(a_string_including('motivo=sem_chave_da_conta'))
  end

  describe 'a base pela metade (cada tentativa pagou o embedding inteiro)' do
    let(:base) { Autonomia::Agents::Contratados::Base }

    after { Redis::Alfred.delete(base.chave_das_parciais(contratado.id)) }

    it 'conta cada tentativa até o teto, com o motivo no log' do
      allow(base).to receive(:semear_se_preciso!).and_return(base::BASE_PARCIAL)

      (base::TETO_DE_PARCIAIS - 1).times { described_class.perform_now(contratado.id) }
      expect(base.parciais_esgotadas?(contratado.id)).to be(false)
      described_class.perform_now(contratado.id)

      expect(base.parciais_esgotadas?(contratado.id)).to be(true)
      expect(Rails.logger).to have_received(:warn).with(a_string_including('motivo=base_parcial'))
                                                  .exactly(base::TETO_DE_PARCIAIS).times
    end

    it 'só a base pela metade conta: sem a chave da conta, nada' do
      allow(base).to receive(:semear_se_preciso!).and_return(base::SEM_CHAVE_DA_CONTA)

      base::TETO_DE_PARCIAIS.times { described_class.perform_now(contratado.id) }

      expect(base.parciais_esgotadas?(contratado.id)).to be(false)
    end
  end

  describe 'com a Base de verdade e o embedding parado' do
    let(:pasta) { Pathname.new(Dir.mktmpdir) }
    let(:embedder) { instance_double(Autonomia::Agents::EmbeddingService) }

    before do
      pasta.join('base.md').write("### Bloco 1\nUm.\n### Bloco 2\nDois.\n### Bloco 3\nTrês.\n")
      stub_const('Autonomia::Agents::Contratados::Base::PASTA', pasta)
      stub_const('Autonomia::Agents::Contratados::Base::VERSAO', Autonomia::Agents::Contratados::Base.versao_de(pasta))
      allow(Autonomia::Agents::Contratados::Base).to receive(:semear_se_preciso!).and_call_original
      coluna = Autonomia::Agents::Config.embedding_column(Autonomia::Agents::Config.active_embedding_model)
      dimensao = coluna == Autonomia::Agents::Config::EMBEDDING_LARGE_COLUMN ? 3072 : 1536
      allow(embedder).to receive(:embed_batch) { |textos| textos.map { Array.new(dimensao, 0.01) } }
      allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)
    end

    after { FileUtils.remove_entry(pasta) }

    it 'semeia uma vez só, com a chave da conta' do
      allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
      create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                                 settings: { 'api_key' => 'chave-da-conta-teste' })

      2.times { described_class.perform_now(contratado.id) }

      expect(embedder).to have_received(:embed_batch).once
      expect(Autonomia::Agents::Contratados::Base.em_dia?(contratado.reload)).to be(true)
    end

    it 'sem a chave da conta e com a da instalação: nunca chama o provedor' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao-teste')

      described_class.perform_now(contratado.id)

      expect(Autonomia::Agents::EmbeddingService).not_to have_received(:new)
      expect(Autonomia::Agents::Contratados::Base.em_dia?(contratado.reload)).to be(false)
    end
  end
end
