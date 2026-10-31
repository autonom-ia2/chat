require 'rails_helper'

# #1430, desenho D: a passada da consulta HTTP em segundo plano. Uma chamada, com a chave gravada na abertura e o tempo
# gravado na abertura; o resultado é gravado uma vez, higienizado, e só a desistência do turno faz o agente falar por
# evento. Cada exemplo cobre um modo de falha apontado na revisão.
RSpec.describe Autonomia::Agents::Tools::HttpAssincronaJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.',
                                     config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Consultar pedido', slug: 'consultar_pedido', timeout_seconds: 90,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      headers_config: [{ key: 'x-api-key', value: 'segredo-da-conta-123', secret: true }],
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:chaves) { [] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    agent_inbox
    ligar_consulta_em_segundo_plano
  end

  # A abertura de verdade (o turno que desiste sem o resultado): a linha nasce como em produção.
  def consulta_aberta(desistiu: true)
    relogio_do_turno
    entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77)
    Autonomia::Agents::Tools::ConsultaNoTurno.new(tool: tool, agente: agent, turno: entrega, args: { 'numero' => '42' }).tap do |consulta|
      desistiu ? consulta.resultado : consulta.disparar
    end
    runs.sole
  end

  it 'roda na fila propria agent_tools, sem retry do Sidekiq' do
    expect(described_class.new.queue_name).to eq('agent_tools')
    expect(described_class.get_sidekiq_options['retry']).to be(false)
  end

  describe 'sucesso' do
    it 'chama uma vez com a chave e o tempo da abertura, grava higienizado e a telemetria, fecha e dispara' do
      run = consulta_aberta
      sistema_responde('{"status":"enviado","eco":"segredo-da-conta-123"}', chaves: chaves)

      described_class.new.perform(run.id)

      expect(SafeFetch).to have_received(:fetch).once.with(tool.endpoint_url, hash_including(total_timeout: 90))
      expect(chaves).to eq([run.handle.fetch(runs::CHAVE_DA_CONSULTA)])
      run.reload
      expect(run.status).to eq('done')
      expect(run.resultado_da_consulta).to include('enviado').and include('[oculto]')
      expect(run.resultado_da_consulta).not_to include('segredo-da-conta-123')
      expect(run.handle).to include(runs::FILA_MS => a_kind_of(Integer), runs::API_MS => a_kind_of(Integer))
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end

    it 'o prazo da linha e renovado no comeco com o tempo gravado na abertura' do
      run = consulta_aberta
      tool.update!(timeout_seconds: 5) # mudar o cadastro depois da abertura não muda esta consulta
      sistema_responde('{}', antes: -> { chaves << runs.find(run.id).expires_at })

      freeze_time do
        described_class.new.perform(run.id)

        expect(chaves.last).to eq(90.seconds.from_now + described_class::FOLGA)
      end
    end

    it 'nao segura a conexao do banco durante a chamada HTTP' do
      run = consulta_aberta
      conexoes = []
      sistema_responde('{}', antes: -> { conexoes << ActiveRecord::Base.connection_pool.active_connection? })

      described_class.new.perform(run.id)

      expect(conexoes).to eq([nil])
      expect(run.reload.status).to eq('done')
    end
  end

  describe 'retry sem nova chamada' do
    it 'reentrada com a chamada feita e sem resultado nao chama de novo' do
      run = consulta_aberta
      run.merge_handle!({ runs::CHAMADA_FEITA => true })
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(run.reload.status).to eq('running')
    end

    it 'reentrada com o resultado gravado so fecha e dispara' do
      run = consulta_aberta
      run.merge_handle!({ runs::CHAMADA_FEITA => true })
      run.gravar_resultado!('{"ok":1}', sucesso: true, codigo: nil, api_ms: 5)
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(run.reload.status).to eq('done')
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end

    it 'o resultado e gravado uma vez so' do
      run = consulta_aberta

      expect(run.gravar_resultado!('primeiro', sucesso: true, codigo: nil, api_ms: 1)).to be(true)
      expect(run.gravar_resultado!('segundo', sucesso: true, codigo: nil, api_ms: 1)).to be(false)
      expect(run.reload.resultado_da_consulta).to eq('primeiro')
    end

    it 'chave ausente no handle falha alto, sem gerar outra' do
      run = consulta_aberta
      run.merge_handle!({}, remover: [runs::CHAVE_DA_CONSULTA])
      allow(SafeFetch).to receive(:fetch)

      expect { described_class.new.perform(run.id) }.to raise_error(KeyError)
      expect(SafeFetch).not_to have_received(:fetch)
    end
  end

  describe 'conferir antes de chamar' do
    it 'consulta superada antes de comecar nao chama' do
      run = consulta_aberta
      runs.where(id: run.id).update_all(status: 'superseded') # rubocop:disable Rails/SkipsModelValidations
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
    end

    it 'operador puxou o freio (agente desligado): bloqueia sem chamar e sem evento' do
      run = consulta_aberta
      agent.update!(enabled: false)
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(run.reload).to have_attributes(status: 'blocked', failure_code: 'nao_autorizado')
      expect(eventos_disparados(run)).to be_empty
    end

    it 'ferramenta desligada depois da abertura: falha ferramenta_indisponivel com evento, sem chamar' do
      run = consulta_aberta
      tool.update!(enabled: false)
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'ferramenta_indisponivel')
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end
  end

  describe 'falha' do
    it 'erro HTTP grava a saida de recusa do sincrono, fecha failed e dispara consulta_falhou' do
      run = consulta_aberta
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Service Unavailable', status: 503))

      described_class.new.perform(run.id)

      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'tool_http_error')
      expect(JSON.parse(run.resultado_da_consulta)).to eq('error' => 'tool_http_error: 503')
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end

    it 'erro de programacao sobe para o rastreador, sem virar consulta_falhou' do
      run = consulta_aberta
      allow(SafeFetch).to receive(:fetch).and_raise(NoMethodError, 'defeito')
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

      expect { described_class.new.perform(run.id) }.to raise_error(NoMethodError)
      expect(rastreador).to have_received(:capture_exception)
      expect(eventos_disparados(run)).to be_empty
    end
  end

  describe 'consulta superada' do
    it 'a superada que conclui 2xx grava o resultado e avisa o atendente em nota privada, sem falar' do
      run = consulta_aberta
      sistema_responde('{"status":"antigo"}', antes: lambda {
        runs.where(id: run.id).update_all(status: 'superseded') # rubocop:disable Rails/SkipsModelValidations
      })

      described_class.new.perform(run.id)

      expect(run.reload.status).to eq('superseded')
      expect(run.resultado_da_consulta).to eq('{"status":"antigo"}')
      expect(eventos_disparados(run)).to be_empty
      nota = conversation.messages.where(private: true).sole
      expect(nota.content).to include('trocada por uma mais nova', '{"status":"antigo"}')
    end
  end

  describe 'ponta a ponta' do
    it 'pessoa atribuida quando o resultado chega: nota privada com o resultado, e o agente nao fala' do
      run = consulta_aberta
      sistema_responde('{"status":"enviado"}')
      lia_responde('não deveria falar')
      conversation.update!(assignee: create(:user, account: account, role: :agent))

      described_class.new.perform(run.id)
      rodar_eventos

      nota = conversation.messages.reload.where(private: true).sole
      expect(nota.content).to include('{"status":"enviado"}', Autonomia::Agents::Tools::Recusa::AVISO_DE_DADO_EXTERNO)
      expect(conversation.messages.where(private: false, sender_type: 'AgentBot')).to be_empty
    end
  end
end
