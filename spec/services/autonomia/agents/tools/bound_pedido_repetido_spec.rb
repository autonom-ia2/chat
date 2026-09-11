require 'rails_helper'

# "E AÍ, SAIU?" NÃO PODE ABRIR COTAÇÃO NOVA (entrega 10).
#
# Enquanto a cotação corre, o cliente pergunta se já saiu; o modelo chama a ferramenta de novo com os
# mesmos dados; até 10/09/2026 `ToolRun.open!` supersedia a viva e abria OUTRA cotação no portal do
# corretor. Agora o `Bound` compara a IDENTIDADE do pedido — digest da entrada como o adapter a
# entende, devolvida pelo `quote/validate` — com a da última consulta que ainda conta, e não abre.
#
# O que se prova aqui é DADO, nunca frase: nenhum destes exemplos passa texto do cliente para o
# código. "E aí?" e "quero mudar a franquia" chegam iguais — como argumentos da ferramenta —, e o
# código só sabe se os dados mudaram (termo 5). O caminho é o real: `Bound#execute` com a
# `InsuranceQuote` de verdade e o conector `mock`, que normaliza como o adapter.
#
# PROVA POR MUTAÇÃO (10/09/2026): `pedido_repetido` devolvendo sempre nil reprova "não abre";
# comparar o cru (`arguments`) em vez do digest reprova "o padrão escrito por extenso";
# `conta_como_pedido?` contando `failed` sem entrega reprova "tentativa nova"; sem `PEDIDO_VALE_POR`
# reprova "velha: abre".
RSpec.describe Autonomia::Agents::Tools::Bound do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:bound) { described_class.new(agent: agent, native: cotacao) }
  let(:runs) { Autonomia::Agents::ToolRun.for_conversation(conversation.id) }
  let(:auto) { { 'cpf' => '04297912678', 'vehicle' => { 'plate' => 'ABC1D23' }, 'cep' => '30130000' } }
  let(:bike_dados) do
    { 'segurado' => { 'nome' => 'Fulano', 'cpfCnpj' => '04297912678' },
      'configuracoes' => { 'marca' => 'Caloi', 'valorMercado' => 8000, 'numeroSerie' => 'SN-1' } }
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
  end

  # Cada mensagem do cliente é um turno com a sua origem: é o que separa "pediu de novo" de "retry".
  def mensagem(id)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: id)
  end

  def pedir(args, turno:)
    bound.execute({ 'name' => 'cotar_seguro', 'call_id' => "c#{turno}", 'arguments' => args.to_json }, delivery: mensagem(turno))
  end

  # A consulta que já existe: aberta numa mensagem anterior e promovida (o Responder faz isso no fim
  # do turno). `entregues` e `desfecho` levam a execução até o estado em que a próxima mensagem chega.
  def consulta_existente(args, entregues: 0, desfecho: nil)
    pedir(args, turno: 1)
    run = runs.order(:id).last
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    entregues.times { run.record_delivery! }
    run.finish!(desfecho) if desfecho
    run.reload
  end

  describe 'pergunta sobre andamento' do
    it 'nao abre execucao nova: o modelo recebe o estado da consulta, nao um erro' do
      # Arrange — a cotação está rodando desde a mensagem 1
      consulta_existente(auto)

      # Act — mensagem 2, mesmos dados (o modelo chamou de novo)
      saida = pedir(auto, turno: 2)

      # Assert
      expect(saida).to include('já está em andamento nesta conversa')
      expect(saida).not_to start_with('{')
      expect(runs.count).to eq(1)
      expect(runs.first.status).to eq('running')
    end

    it 'guarda a identidade do pedido na execucao, e a ferramenta nunca a ve' do
      run = consulta_existente(auto)

      expect(run.pedido).to be_a(String)
      expect(run.pedido.length).to eq(Autonomia::Insurance::Pedido::TAMANHO)
      expect(Autonomia::Agents::Tools::AsyncRunJob::MARCAS).to include(Autonomia::Agents::ToolRun::PEDIDO)
    end
  end

  describe 'mudanca de dado' do
    it 'qualquer dado diferente abre — inclusive um pequeno, como o numero do endereco' do
      consulta_existente(auto)

      saida = pedir(auto.merge('numero' => '10'), turno: 2)

      expect(saida).to eq(cotacao.accepted_message)
      expect(runs.count).to eq(2)
      expect(runs.order(:id).map(&:status)).to eq(%w[superseded pending])
    end
  end

  describe 'a comparacao e sobre a entrada normalizada, nao sobre o cru' do
    it 'o padrao escrito por extenso e o mesmo pedido que o padrao omitido (bike)' do
      # Arrange — o cru difere: a segunda chamada escreve o padrão que a primeira omitiu
      consulta_existente({ 'produto' => 'bike', 'dados' => bike_dados.to_json })
      com_padrao = bike_dados.deep_dup
      com_padrao['configuracoes']['assist24hs'] = 1

      # Act
      saida = pedir({ 'produto' => 'bike', 'dados' => com_padrao.to_json }, turno: 2)

      # Assert — o adapter normaliza os dois para a mesma entrada
      expect(saida).to include('já está em andamento')
      expect(runs.count).to eq(1)
    end

    it 'vale nos outros ramos: valor de mercado diferente na bike abre' do
      consulta_existente({ 'produto' => 'bike', 'dados' => bike_dados.to_json })
      outro = bike_dados.deep_dup
      outro['configuracoes']['valorMercado'] = 8001

      saida = pedir({ 'produto' => 'bike', 'dados' => outro.to_json }, turno: 2)

      expect(saida).to eq(cotacao.accepted_message)
      expect(runs.count).to eq(2)
    end
  end

  describe 'o que ainda conta como pedido feito' do
    it 'depois de falha sem entrega, o mesmo pedido e tentativa nova' do
      consulta_existente(auto, desfecho: 'failed')

      expect(pedir(auto, turno: 2)).to eq(cotacao.accepted_message)
      expect(runs.count).to eq(2)
    end

    it 'concluida com preco entregue ha pouco: barrada com o resumo; velha: abre' do
      run = consulta_existente(auto, entregues: 2, desfecho: 'done')

      saida = pedir(auto, turno: 2)
      expect(saida).to include('já terminou nesta conversa', 'concluída', '2 resultados encaminhados para publicação')
      expect(runs.count).to eq(1)

      # A janela conta do ENCERRAMENTO, não de `updated_at`: uma publicação adiada que sai depois do
      # fim mexe em `updated_at` e não pode renovar o pedido.
      encerrada_em = Autonomia::Agents::ToolRun::ENCERRADA_EM
      antiga = run.handle.merge(encerrada_em => (Autonomia::Agents::ToolRun::PEDIDO_VALE_POR + 1.hour).ago.iso8601)
      run.update_columns(handle: antiga, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      expect(pedir(auto, turno: 3)).to eq(cotacao.accepted_message)
      expect(runs.count).to eq(2)
    end

    it 'encerrada sem concluir, com preco parcial: o texto diz isso, nao "concluida"' do
      consulta_existente(auto, entregues: 1, desfecho: 'failed')

      saida = pedir(auto, turno: 2)

      expect(saida).to include('encerrada sem concluir', '1 resultado encaminhado para publicação')
      expect(saida).not_to include('concluída')
      expect(runs.count).to eq(1)
    end
  end

  # Dois turnos simultâneos com o mesmo pedido: a comparação, a abertura E a promoção ficam na mesma
  # seção crítica por (conversa, ferramenta) — o lock consultivo de transação, exclusivo entre sessões
  # por semântica do Postgres. Sem ele, os dois comparam com nada, um abre, o outro supersede; ou B lê
  # a `pending` de A (que não conta), A promove, e B supersede uma `running` já submetida ao portal.
  #
  # POR QUE A PROVA É POR RASTRO SQL, e não com duas conexões: a suíte roda com fixtures transacionais
  # e o pool fixa a conexão na thread — uma segunda sessão real não enxerga as linhas do exemplo. O que
  # se prova aqui é que os dois escritores tomam o MESMO lock, com a MESMA chave, dentro da transação
  # que escreve; a exclusão entre sessões é do banco.
  describe 'comparacao, abertura e promocao na mesma secao critica' do
    let(:escritas) { /pg_advisory_xact_lock|INSERT INTO "autonomia_agent_tool_runs"|UPDATE "autonomia_agent_tool_runs"/ }
    let(:chave) { Autonomia::Agents::ToolRun.chave_do_lock(conversation.id, 'cotar_seguro').to_s }

    def comandos_de
      comandos = []
      assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        comandos << payload[:sql] if payload[:sql].match?(escritas)
      end
      yield
      comandos
    ensure
      ActiveSupport::Notifications.unsubscribe(assinatura)
    end

    it 'toma o lock da conversa e da ferramenta antes de comparar, na transacao que abre' do
      comandos = comandos_de { pedir(auto, turno: 1) }

      lock = comandos.index { |sql| sql.include?('pg_advisory_xact_lock') }
      insercao = comandos.index { |sql| sql.include?('INSERT INTO "autonomia_agent_tool_runs"') }
      expect(lock).not_to be_nil
      expect(insercao).to be > lock
      expect(comandos[lock]).to include(chave)
    end

    it 'a promocao toma o mesmo lock, com a mesma chave, antes de escrever' do
      pedir(auto, turno: 1)
      run = runs.order(:id).last

      comandos = comandos_de { run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now) }

      lock = comandos.index { |sql| sql.include?('pg_advisory_xact_lock') }
      escrita = comandos.index { |sql| sql.include?('UPDATE "autonomia_agent_tool_runs"') }
      expect(lock).not_to be_nil
      expect(escrita).to be > lock
      expect(comandos[lock]).to include(chave)
      expect(run.reload.status).to eq('running')
    end

    it 'a chave e de 64 bits e cabe em bigint mesmo para conversa alem de 2^31' do
      chave_grande = Autonomia::Agents::ToolRun.chave_do_lock(2**40, 'cotar_seguro')
      expect(chave_grande).to be_between(-(2**63), (2**63) - 1)
      expect(chave_grande).not_to eq(Autonomia::Agents::ToolRun.chave_do_lock(2**40, 'outra'))
      expect { Autonomia::Agents::ToolRun.travar!(2**40, 'cotar_seguro') }.not_to raise_error
    end
  end

  describe 'sem identidade nao se barra' do
    it 'conferencia indisponivel: o pedido abre (o conferente nao e portao)' do
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_validate).and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'x'))
      consulta_existente(auto)

      expect(pedir(auto, turno: 2)).to eq(cotacao.accepted_message)
      expect(runs.count).to eq(2)
      expect(runs.map(&:pedido)).to all(be_nil)
    end
  end
end
