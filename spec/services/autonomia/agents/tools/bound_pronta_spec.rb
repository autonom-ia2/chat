require 'rails_helper'

# #2858 (F0): a ferramenta pronta no turno do agente (`Tools::Bound`) e no caminho em segundo plano do #2749
# (`ConsultaNoTurno` + `HttpAssincronaJob`, fila `agent_tools`). Desligar a flag tira a pronta do turno; a Lia fica de
# fora; o cadastro manual não a enxerga.
RSpec.describe Autonomia::Agents::Tools::Bound do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_agente }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:manual) do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Estoque', slug: 'consultar_estoque', http_method: 'GET',
                                    endpoint_url: 'https://erp.exemplo.test/estoque')
  end
  let(:pronta) { incluir_pronta('cep', conta: account, agente: agent) }
  let(:brasilapi) { 'https://brasilapi.com.br/api/cep/v2/01001000' }
  let(:endereco) { { cep: '01001000', state: 'SP', city: 'São Paulo', neighborhood: 'Sé', street: 'Praça da Sé' } }
  let(:chamada) { { 'name' => 'pronta_cep', 'call_id' => 'c1', 'arguments' => { cep: '01001-000' }.to_json } }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def criar_agente(tipo: 'custom')
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: tipo, status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end

  def slugs_do_turno(agente = agent)
    described_class.for_agent(agente).map(&:slug)
  end

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
  end

  describe 'no catalogo do turno' do
    it 'entra com a flag, ao lado da manual, e sai quando a flag desliga' do
      manual
      pronta

      expect(slugs_do_turno).to eq(%w[consultar_estoque pronta_cep])

      account.disable_features!(Autonomia::FerramentasProntas::FLAG)
      expect(slugs_do_turno(agent.reload)).to eq(%w[consultar_estoque])
    end

    it 'nunca entra no turno da Lia, mesmo gravada no banco' do
      lia = criar_agente(tipo: 'insurance_quote')
      Autonomia::Agents::Tool.create!(account: account, agent: lia, name: 'CEP', slug: 'pronta_cep', fonte_pronta: 'cep',
                                      endpoint_url: '', http_method: 'GET')

      expect(slugs_do_turno(lia)).not_to include('pronta_cep')
    end

    it 'fonte que saiu do catalogo nao entra e nao derruba o turno' do
      pronta.update_column(:fonte_pronta, 'fonte_que_saiu') # rubocop:disable Rails/SkipsModelValidations

      expect(slugs_do_turno(agent.reload)).to be_empty
    end

    it 'desligada no agente (enabled false) nao entra' do
      pronta.update!(enabled: false)

      expect(slugs_do_turno).to be_empty
    end
  end

  it 'a fonte da F1 entra so com a flag das consultas, e as da F0 ficam' do
    account.enable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
    pronta
    incluir_pronta('ddd', conta: account, agente: agent)
    expect(slugs_do_turno).to eq(%w[pronta_cep pronta_ddd])

    account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
    expect(slugs_do_turno).to eq(%w[pronta_cep])
  end

  describe 'no turno sincrono' do
    it 'consulta a fonte do catalogo e o modelo le o dado enxuto' do
      fonte_responde(brasilapi, endereco)
      entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 7)

      saida = JSON.parse(described_class.new(agent: agent, record: pronta).execute(chamada, delivery: entrega))

      expect(saida).to include('situacao' => 'encontrado', 'dados' => include('cidade' => 'São Paulo', 'uf' => 'SP'))
    end

    it 'com as fontes fora, o modelo le "nao consegui consultar" e o turno segue' do
      fonte_lenta(brasilapi)
      fonte_fora('https://viacep.com.br/ws/01001000/json/')

      saida = JSON.parse(described_class.new(agent: agent, record: pronta).execute(chamada))

      expect(saida['situacao']).to eq('nao_consegui_consultar')
      expect(saida['orientacao']).to include('Não invente')
    end
  end

  describe 'no caminho em segundo plano do #2749 (fila agent_tools)' do
    before do
      agent_inbox
      ligar_consulta_em_segundo_plano
    end

    def abrir_consulta
      relogio_do_turno
      entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77)
      saida = described_class.new(agent: agent, record: pronta).execute(chamada, delivery: entrega)
      [saida, Autonomia::Agents::ToolRun.sole]
    end

    it 'a consulta lenta sai do turno: o modelo le "em andamento" e a execucao fica na fila agent_tools' do
      fonte_responde(brasilapi, endereco)

      saida, run = abrir_consulta

      expect(saida).to eq(Autonomia::Agents::Tools::ConsultaNoTurno::EM_ANDAMENTO)
      expect(run).to have_attributes(status: 'running', autonomia_agent_tool_id: pronta.id)
      expect(enqueued_jobs.map { |job| [job[:job], job[:queue]] }).to include([Autonomia::Agents::Tools::HttpAssincronaJob, 'agent_tools'])
    end

    it 'o job consulta a fonte do catalogo, grava o resultado e o evento fala' do
      fonte_responde(brasilapi, endereco)
      _saida, run = abrir_consulta

      expect(rodar_consultas).to eq(1)

      run.reload
      expect(run.status).to eq('done')
      expect(JSON.parse(run.resultado_da_consulta)).to include('situacao' => 'encontrado', 'dados' => include('cidade' => 'São Paulo'))
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
      expect(Autonomia::FerramentasProntas::Uso.sole.consultas).to eq(1)
    end

    it 'resposta perdida no meio (worker morreu) fecha como "nao consegui", sem incerteza nem aviso a quem atende' do
      _saida, run = abrir_consulta
      run.marcar_chamada!(passada: 'job-que-morreu')
      allow(Autonomia::Agents::Operate::AvisoAoAtendente).to receive(:consulta_incerta)

      Autonomia::Agents::Tools::HttpAssincronaJob.incerta(run.reload)

      run.reload
      expect(run.status).to eq('done')
      expect(JSON.parse(run.resultado_da_consulta)['situacao']).to eq('nao_consegui_consultar')
      expect(Autonomia::Agents::Operate::AvisoAoAtendente).not_to have_received(:consulta_incerta)
    end

    it 'com as fontes fora, o modelo le "nao consegui" e a linha guarda o desfecho da pronta' do
      fonte_fora(brasilapi)
      fonte_fora('https://viacep.com.br/ws/01001000/json/')
      _saida, run = abrir_consulta

      rodar_consultas

      run.reload
      expect(run.status).to eq('done')
      expect(JSON.parse(run.resultado_da_consulta)['situacao']).to eq('nao_consegui_consultar')
      expect(run.handle[Autonomia::Agents::ToolRun::CODIGO_DA_CONSULTA]).to eq('pronta_sem_resposta')
    end

    it 'a pronta superada no meio grava o resultado e nao avisa quem atende' do
      _saida, run = abrir_consulta
      stub_request(:get, brasilapi).to_return do
        Autonomia::Agents::ToolRun.where(id: run.id).update_all(status: 'superseded') # rubocop:disable Rails/SkipsModelValidations
        { status: 200, body: endereco.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      rodar_consultas

      expect(run.reload.status).to eq('superseded')
      expect(JSON.parse(run.resultado_da_consulta)['situacao']).to eq('encontrado')
      expect(conversation.messages.where(private: true)).to be_empty
    end

    it 'o CPF (calculado aqui) responde na hora e nao abre a linha da consulta, que guardaria o numero' do
      account.enable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
      cpf = incluir_pronta('cpf', conta: account, agente: agent)
      relogio_do_turno
      entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 78)
      chamada_cpf = { 'name' => 'pronta_cpf', 'call_id' => 'c2', 'arguments' => { cpf: '111.444.777-35' }.to_json }

      saida = JSON.parse(described_class.new(agent: agent, record: cpf).execute(chamada_cpf, delivery: entrega))

      expect(saida['dados']).to include('valido' => true)
      expect(Autonomia::Agents::ToolRun.count).to eq(0)
    end

    it 'a localizacao vai ao segundo plano com a coordenada ja arredondada no registro' do
      account.enable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
      local = incluir_pronta('localizacao', conta: account, agente: agent)
      relogio_do_turno
      entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 79)
      chamada_local = { 'name' => 'pronta_localizacao', 'call_id' => 'c3',
                        'arguments' => { latitude: -22.905612, longitude: -47.060831 }.to_json }

      described_class.new(agent: agent, record: local).execute(chamada_local, delivery: entrega)

      expect(Autonomia::Agents::ToolRun.sole.arguments).to eq('latitude' => -22.906, 'longitude' => -47.061)
    end

    it 'no job, com a flag das prontas desligada depois da abertura, nao consulta' do
      _saida, run = abrir_consulta
      account.disable_features!(Autonomia::FerramentasProntas::FLAG)

      rodar_consultas

      expect(JSON.parse(run.reload.resultado_da_consulta)['situacao']).to eq('nao_consegui_consultar')
      expect(a_request(:get, /brasilapi/)).not_to have_been_made
    end
  end

  describe 'no cadastro manual (API das ferramentas do agente)' do
    it 'o escopo manual nao enxerga a pronta' do
      manual
      pronta

      expect(agent.tools.manuais.pluck(:slug)).to eq(['consultar_estoque'])
    end
  end
end
