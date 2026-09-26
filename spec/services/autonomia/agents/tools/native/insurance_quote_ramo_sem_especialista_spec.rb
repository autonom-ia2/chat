require 'rails_helper'

# A COTAÇÃO SÓ ABRE NO RAMO QUE TEM ESPECIALISTA NESTA CONTA (conversa 7150, 26/09/2026). A Lia disse que cotava seguro de
# vida, e o pedido chegaria a `cotar_seguro` pelo caminho genérico. O manual e a lista são a primeira porta; esta é a
# guarda no código. O que se prova:
#   no Agente de Cotação, ramo sem especialista é recusado na conferência e no envio, sem tocar no adapter;
#   o texto ao modelo manda encaminhar para a equipe, sem travessão nem crase, e dá os ramos que a IA cota;
#   o ramo que a corretora trabalha fica anotado para a nota da equipe; nome inventado, não;
#   auto, residencial e empresarial passam como antes, a conta que só tem auto também, e o agente comum não muda.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:lia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:comum) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:turno) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: nil)
  end
  let(:recentes) { Autonomia::Agents::Tools::RecusasRecentes }
  let(:todos) { %w[residencial condominio empresarial auto fianca_locaticia viagem acidentes_pessoais vida vida_global celular bike] }

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    recentes.retirar(conversation.id)
  end

  def conectar(produtos)
    lista = produtos.map { |produto| { 'product' => produto, 'enabled' => true } }
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                    .update!(status: 'ready', capabilities: { 'products' => lista })
  end

  def liberar(*ramos)
    ramos.each { |ramo| Autonomia::Insurance::Config.liberar_ramo!(account, ramo) }
  end

  def tool(produto, agente: lia, delivery: nil)
    described_class.new(agent: agente, params: { 'item' => 'Bem', 'produto' => produto, 'dados' => '{}' }, delivery: delivery)
  end

  describe 'no Agente de Cotação, com os três especialistas atendendo' do
    before do
      conectar(todos)
      liberar('residencial', 'empresarial')
    end

    it 'recusa vida na conferência, sem tocar no adapter, e manda encaminhar para a equipe' do
      expect(Autonomia::Insurance::Connector).not_to receive(:client)

      conferencia = tool('vida').precheck

      expect(conferencia.motivo).to eq('ramo_sem_especialista')
      expect(conferencia.faltando).to eq(['produto'])
      expect(conferencia.texto).to include('não é cotado pela IA nesta conta', '(auto, residencial, empresarial)',
                                           'fica com a equipe da corretora')
      expect(conferencia.texto).not_to include('—', '–', '`')
    end

    it 'recusa vida no envio também, e o evento é o de encaminhar para a equipe' do
      expect(Autonomia::Insurance::Connector).not_to receive(:client)

      handle = tool('vida').start
      progresso = tool('vida').poll(handle: handle, attempt: 0)
      fatos = described_class.fatos_do_evento(progresso.evento, Autonomia::Agents::ToolRun.new(handle: handle))

      expect(handle).to include('recusa' => 'ramo_sem_especialista', 'faltando' => ['produto'])
      expect(progresso.evento).to eq('falhou')
      expect(fatos).to include(described_class::FATOS_SEM_ESPECIALISTA)
      expect(fatos).to include('vai encaminhar para alguém da equipe')
      expect(fatos).not_to include('—', '–', '`')
    end

    it 'anota para a nota da equipe o ramo que a corretora trabalha, e não o nome inventado' do
      tool('vida', delivery: turno).precheck
      tool('drone', delivery: turno).precheck

      expect(tool('drone').precheck.motivo).to eq('ramo_sem_especialista')
      expect(recentes.retirar(conversation.id)).to eq(['ramo_pedido:vida'])
    end

    it 'o motivo tem frase no catálogo de recusas' do
      expect(Autonomia::Agents::Tools::Recusa::MOTIVOS).to have_key('ramo_sem_especialista')
    end

    # Regressão: os três ramos com especialista seguem o caminho de antes. A conferência pode recusar por outro motivo
    # (formulário, dado que falta), nunca por este.
    it 'auto, residencial e empresarial passam pela guarda, inclusive com maiúscula' do
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(Autonomia::Insurance::Connector::Mock.new)

      %w[auto Auto residencial empresarial].each do |produto|
        expect(tool(produto).precheck.try(:motivo)).not_to eq('ramo_sem_especialista'), produto
        expect(tool(produto).send(:recusa_do_envio).to_h['recusa']).not_to eq('ramo_sem_especialista'), produto
        expect(tool(produto).send(:ramo_sem_especialista?)).to be(false), produto
      end
    end

    # A conexão só de passagem (o healthcheck a cada 30 minutos, a sincronização) não tira nenhum dos três.
    it 'com a conexão autenticando ou descobrindo, os três seguem passando' do
      ramos = %w[auto residencial empresarial]
      %w[authenticating discovering].each do |status|
        Autonomia::Insurance::Connection.for_account(account).each { |conexao| conexao.update!(status: status) }

        expect(ramos.map { |produto| tool(produto).send(:ramo_sem_especialista?) }).to eq([false, false, false]), status
      end
    end

    # Com a conexão fora do ar, o motivo que a equipe precisa ler é a conexão, e não o ramo.
    it 'com a conexão fora do ar, a conferência diz que a conexão caiu' do
      Autonomia::Insurance::Connection.for_account(account).each { |conexao| conexao.update!(status: 'offline') }

      expect(tool('residencial').precheck.motivo).to eq('conexao_indisponivel')
    end
  end

  describe 'nas contas que só cotam auto' do
    it 'auto passa com a conexão só de auto' do
      conectar(%w[auto])

      expect(tool('auto').send(:ramo_sem_especialista?)).to be(false)
      expect(tool('residencial').send(:ramo_sem_especialista?)).to be(true)
    end

    # O mesmo que a Lia enxerga: sem a liberação do SuperAdmin, o especialista de residencial não atende, e a cotação
    # de residencial não abre pelo caminho genérico.
    it 'residencial sem liberação é ramo sem especialista, e auto segue cotando' do
      conectar(todos)

      expect(tool('residencial').send(:ramo_sem_especialista?)).to be(true)
      expect(tool('auto').send(:ramo_sem_especialista?)).to be(false)
    end
  end

  it 'o agente comum, com a ferramenta ligada direto, cota qualquer ramo como sempre' do
    conectar(todos)

    expect(tool('vida', agente: comum).send(:ramo_sem_especialista?)).to be(false)
    expect(tool('vida', agente: comum, delivery: turno).precheck.try(:motivo)).not_to eq('ramo_sem_especialista')
    expect(recentes.retirar(conversation.id)).to eq([])
  end
end
