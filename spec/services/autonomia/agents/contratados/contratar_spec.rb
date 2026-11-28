require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::Contratar do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:embedder) { instance_double(Autonomia::Agents::EmbeddingService) }

  before do
    enable_test_encryption!
    marcar_corretora!(account)
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                             'agente_ferramentas_prontas_consultas')
    # Contratar exige a chave de IA da própria conta; a de mentira não passa pelo provedor.
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-conta-teste' })
    coluna = Autonomia::Agents::Config.embedding_column(Autonomia::Agents::Config.active_embedding_model)
    dimensao = coluna == Autonomia::Agents::Config::EMBEDDING_LARGE_COLUMN ? 3072 : 1536
    allow(embedder).to receive(:embed_batch) { |textos| textos.map { Array.new(dimensao, 0.01) } }
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)
  end

  def contratar(**mudancas)
    dados = { nome_agente: 'Bia', nome_corretora: 'Corretora Exemplo', sobre_corretora: 'Desde 2010.' }.merge(mudancas)
    described_class.new(account: account, user: user, modelo: 'seguro_viagem_universal', **dados)
  end

  it 'nasce sdr, rascunho, com a marca, as opções de conversa e as duas prontas' do
    agente = contratar.call
    expect(agente).to have_attributes(agent_type: 'sdr', status: 'draft', enabled: false, mode: 'guided', name: 'Bia')
    expect(agente.config['contratado']).to eq('modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia',
                                              'nome_corretora' => 'Corretora Exemplo', 'sobre_corretora' => 'Desde 2010.')
    expect(agente.config).to include('humanize_delivery' => true, 'voice_reply' => true)
    expect(agente.tools.pluck(:fonte_pronta)).to contain_exactly('cep', 'cpf')
    expect(Autonomia::FerramentasProntas.rodadas(agente)).to include(max_rodadas: 3, uma_escrita_por_turno: true)
  end

  it 'liga as opções de conversa do PR 1' do
    config = contratar.call.config
    chaves = %w[conversa_espera_a_fala conversa_em_fila conversa_entrega_inteira conversa_ritmo_do_canal
                humanize_delivery voice_reply]
    expect(config.slice(*chaves)).to eq(chaves.index_with(true))
  end

  it 'enfileira a base depois do commit' do
    expect { contratar.call }.to have_enqueued_job(Autonomia::Agents::Contratados::SemearBaseJob)
  end

  it 'recusa nome com marcador, com o campo (R14)' do
    expect { contratar(nome_corretora: '$nomeAgente').call }.to raise_error(described_class::Recusado) { |e|
      expect([e.motivo, e.campo]).to eq(%w[marcador nome_corretora])
    }
  end

  it 'nome grande demais: o campo é o motivo e o campo' do
    expect { contratar(nome_agente: 'a' * 121).call }.to raise_error(described_class::Recusado) { |e|
      expect([e.motivo, e.campo]).to eq(%w[nome_agente nome_agente])
    }
  end

  it 'conta sem a flag: indisponivel, sem campo, nada criado' do
    account.disable_features!('agente_seguro_viagem_universal')
    expect { contratar.call }.to raise_error(described_class::Recusado) { |e| expect([e.motivo, e.campo]).to eq(['indisponivel', nil]) }
    expect(Autonomia::Agents::Agent.count).to eq(0)
  end

  it 'conta sem a própria chave de IA: sem_chave_de_ia, sem campo, nada criado (a da instalação não vale)' do
    Integrations::Hook.where(account_id: account.id, app_id: 'crm_kanban_ai').delete_all
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao-teste')

    expect { contratar.call }.to raise_error(described_class::Recusado) { |e| expect([e.motivo, e.campo]).to eq(['sem_chave_de_ia', nil]) }
    expect(Autonomia::Agents::Agent.count).to eq(0)
    expect(Autonomia::Agents::Contratados::SemearBaseJob).not_to have_been_enqueued
  end

  it 'a versão da base vai por jsonb_set, sem regravar o resto do config' do
    pasta = Pathname.new(Dir.mktmpdir)
    pasta.join('base.md').write("### Bloco 1\nUm.\n### Bloco 2\nDois.\n### Bloco 3\nTrês.\n")
    agente = contratar.call
    copia = Autonomia::Agents::Agent.find(agente.id)
    agente.update!(config: agente.config.merge('greeting_extra' => 'x'))
    Autonomia::Agents::Contratados::Base.semear!(copia, pasta: pasta)
    expect(agente.reload.config).to include('greeting_extra' => 'x',
                                            'contratado_base_versao' => Autonomia::Agents::Contratados::Base.versao_de(pasta))
  ensure
    FileUtils.remove_entry(pasta) if pasta
  end

  it 'grava o retrato da instrução com os dados da corretora e quem contratou' do
    agente = contratar.call
    expect(agente.instruction).to include('Bia', 'Corretora Exemplo', 'Desde 2010.')
    expect(agente.instruction).not_to include('$nomeAgente', '$nomeCorretora', '$sobreCorretora')
    expect(agente).to have_attributes(created_by: user, with_knowledge: true)
    expect(agente.tools.find_by(fonte_pronta: 'cep').description).to eq(described_class::USAR_QUANDO['cep'])
  end

  it 'limpa os espaços das pontas antes de gravar' do
    agente = contratar(nome_agente: '  Bia  ', nome_corretora: ' Corretora Exemplo ').call
    expect(agente.name).to eq('Bia')
    expect(agente.config['contratado']).to include('nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo')
  end

  it 'nome só de espaços e apresentação grande demais: recusa com o campo' do
    expect { contratar(nome_corretora: '   ').call }.to raise_error(described_class::Recusado) { |e|
      expect([e.motivo, e.campo]).to eq(%w[nome_corretora nome_corretora])
    }
    expect { contratar(sobre_corretora: 'a' * 1001).call }.to raise_error(described_class::Recusado) { |e|
      expect([e.motivo, e.campo]).to eq(%w[sobre_corretora sobre_corretora])
    }
  end

  it 'apresentação vazia é aceita' do
    expect(contratar(sobre_corretora: '').call.config.dig('contratado', 'sobre_corretora')).to eq('')
  end

  it 'modelo fora do catálogo: indisponivel' do
    servico = described_class.new(account: account, user: user, modelo: 'outro', nome_agente: 'Bia',
                                  nome_corretora: 'Corretora Exemplo', sobre_corretora: '')
    expect { servico.call }.to raise_error(described_class::Recusado) { |e| expect(e.motivo).to eq('indisponivel') }
  end

  it 'várias cópias na mesma conta, uma por corretora' do
    contratar.call
    contratar(nome_agente: 'Rui', nome_corretora: 'Outra Corretora Exemplo').call
    expect(Autonomia::Agents::Agent.where(account: account).count).to eq(2)
  end

  it 'pronta recusada no meio: nada criado e indisponivel' do
    allow(Autonomia::FerramentasProntas::Incluir).to receive(:new).and_wrap_original do |original, **argumentos|
      servico = original.call(**argumentos)
      allow(servico).to receive(:call).and_raise(Autonomia::FerramentasProntas::Incluir::Recusado, 'desligada')
      servico
    end
    expect { contratar.call }.to raise_error(described_class::Recusado) { |e| expect(e.motivo).to eq('indisponivel') }
    expect(Autonomia::Agents::Agent.count).to eq(0)
    expect(Autonomia::Agents::Contratados::SemearBaseJob).not_to have_been_enqueued
  end
end
