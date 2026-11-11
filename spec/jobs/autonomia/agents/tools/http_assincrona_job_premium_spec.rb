require 'rails_helper'

# #2858 (F7): a consulta Premium em segundo plano cuja resposta se perdeu depois de a chamada sair (o worker morreu).
# A BigDataCorp pode ter cobrado: a telemetria ganha uma linha de falha por entrega incerta, sem cobrar o cliente, com
# o custo do dataset (para a conta da plataforma bater com a fatura da BigDataCorp). Zero chamada real.
RSpec.describe Autonomia::Agents::Tools::HttpAssincronaJob do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:certidoes) { incluir_pronta('certidoes_empresa', conta: account, agente: agent) }
  let(:chamada) do
    { 'name' => certidoes.slug, 'call_id' => 'c1',
      'arguments' => { consulta: 'divida_uniao', cnpj: '11.222.333/0001-81' }.to_json }
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { com_credencial_da_bigdatacorp { example.run } } }

  before do
    ligar_premium(account)
    agent_inbox
    ligar_consulta_em_segundo_plano
  end

  def abrir_consulta
    relogio_do_turno
    entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77)
    Autonomia::Agents::Tools::Bound.new(agent: agent, record: certidoes).execute(chamada, delivery: entrega)
    Autonomia::Agents::ToolRun.sole
  end

  it 'a resposta perdida depois da chamada vira falha por entrega incerta, sem cobrar o cliente, com o custo do dataset' do
    run = abrir_consulta
    run.marcar_chamada!(passada: 'job-que-morreu')

    described_class.incerta(run.reload)

    expect(JSON.parse(run.reload.resultado_da_consulta)['situacao']).to eq('nao_consegui_consultar')
    expect(Autonomia::FerramentasProntas::Premium::Registro.sole).to have_attributes(
      account_id: account.id, autonomia_agent_id: agent.id, fonte: 'certidoes_empresa', consulta: 'divida_uniao',
      dataset: 'ondemand_pgfn_company', resultado: 'falha', motivo: 'entrega_incerta', cobranca: 'sem_cobranca',
      numero: nil, do_cache: false, custo: BigDecimal('0.10'), preco: 0
    )
    expect(Autonomia::FerramentasProntas::Premium::Saldo.count).to eq(0)
    expect(chamou_a_bigdatacorp?).to be(false)
  end

  describe 'a linha já gravada pela execução (o worker morreu entre a telemetria e o resultado)' do
    let(:registros) { Autonomia::FerramentasProntas::Premium::Registro }
    let(:saldos) { Autonomia::FerramentasProntas::Premium::Saldo }
    let(:logs) { StringIO.new }

    before do
      cache_em_memoria
      token_da_bigdatacorp
      bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', [{ 'BaseStatus' => 'NEGATIVA' }])
      allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(logs))
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    end

    # A execução em segundo plano até a telemetria; depois, o SIGKILL: o resultado nunca chega à linha.
    def executar_e_morrer(run)
      Autonomia::FerramentasProntas.executor_para(certidoes, params: run.arguments, tool_run_id: run.id).call
      run.marcar_chamada!(passada: 'job-que-morreu')
    end

    it 'o job em segundo plano grava a execução na telemetria' do
      run = abrir_consulta

      rodar_consultas

      expect(registros.sole).to have_attributes(tool_run_id: run.id, resultado: 'encontrado', cobranca: 'gratis')
    end

    it 'a grátis vira sem cobrança e volta ao saldo, sem linha nova; o custo nosso fica' do
      run = abrir_consulta
      executar_e_morrer(run)
      expect(saldos.sole.contadas).to eq(1)

      described_class.incerta(run.reload)

      expect(registros.sole).to have_attributes(tool_run_id: run.id, resultado: 'encontrado', cobranca: 'sem_cobranca', numero: nil,
                                                preco: 0, custo: BigDecimal('0.10'), motivo: 'entrega_incerta')
      expect(saldos.sole.contadas).to eq(0)
    end

    it 'a cobrada vira sem cobrança com preço zero; o saldo não muda e o custo nosso fica' do
      saldo_premium!(account, 'certidoes_empresa', 20)
      run = abrir_consulta
      executar_e_morrer(run)

      described_class.incerta(run.reload)

      expect(registros.sole).to have_attributes(cobranca: 'sem_cobranca', preco: 0, custo: BigDecimal('0.10'), motivo: 'entrega_incerta')
      expect(saldos.sole.contadas).to eq(21)
    end

    it 'a execução viva que grava entre a busca e a inserção da entrega incerta: a linha dela vira sem cobrança e a grátis volta' do
      run = abrir_consulta
      run.marcar_chamada!(passada: 'job-que-morreu')
      allow(registros).to receive(:lock).and_wrap_original do |original, *args|
        relacao = original.call(*args)
        allow(relacao).to receive(:find_by).and_wrap_original do |busca, *criterios|
          achada = busca.call(*criterios)
          Autonomia::FerramentasProntas.executor_para(certidoes, params: run.arguments, tool_run_id: run.id).call if achada.nil?
          achada
        end
        relacao
      end

      described_class.incerta(run.reload)

      expect(registros.sole).to have_attributes(tool_run_id: run.id, resultado: 'encontrado', cobranca: 'sem_cobranca', numero: nil,
                                                preco: 0, custo: BigDecimal('0.10'), motivo: 'entrega_incerta')
      expect(saldos.sole.contadas).to eq(0)
    end

    it 'a execução que grava depois da entrega incerta não duplica: a linha dela não entra e o saldo volta atrás' do
      run = abrir_consulta
      run.marcar_chamada!(passada: 'job-que-morreu')
      described_class.incerta(run.reload)

      Autonomia::FerramentasProntas.executor_para(certidoes, params: run.arguments, tool_run_id: run.id).call

      expect(registros.sole).to have_attributes(motivo: 'entrega_incerta', cobranca: 'sem_cobranca')
      expect(saldos.sum(:contadas)).to eq(0)
      expect(logs.string).to include('já fechada como entrega incerta')
      expect(ChatwootExceptionTracker).not_to have_received(:new)
    end
  end

  it 'a falha do banco ao gravar a telemetria não segura o fechamento da linha' do
    run = abrir_consulta
    run.marcar_chamada!(passada: 'job-que-morreu')
    allow(Autonomia::FerramentasProntas::Premium::Registro).to receive(:create!).and_raise(ActiveRecord::StatementInvalid)

    described_class.incerta(run.reload)

    expect(JSON.parse(run.reload.resultado_da_consulta)['situacao']).to eq('nao_consegui_consultar')
  end

  it 'a pronta grátis que perde a resposta não escreve telemetria Premium' do
    cep = incluir_pronta('cep', conta: account, agente: agent)
    relogio_do_turno
    entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 78)
    Autonomia::Agents::Tools::Bound.new(agent: agent, record: cep)
                                   .execute({ 'name' => cep.slug, 'call_id' => 'c2', 'arguments' => { cep: '01001-000' }.to_json },
                                            delivery: entrega)
    run = Autonomia::Agents::ToolRun.sole
    run.marcar_chamada!(passada: 'job-que-morreu')

    described_class.incerta(run.reload)

    expect(Autonomia::FerramentasProntas::Premium::Registro.count).to eq(0)
  end
end
