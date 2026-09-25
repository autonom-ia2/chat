require 'rails_helper'

# A FALA COM PREÇO SAI CONFERIDA MESMO SEM LEITURA NO TURNO (revisão adversarial de 24/09/2026).
#
# Até aqui a `ConferenciaDePrecos` só rodava quando o especialista tinha chamado `ver_resultado_da_cotacao` naquele
# turno. Se a Lia escrevesse valor em reais sem essa leitura, a fala saía sem conferência nenhuma, e um preço
# inventado chegava ao cliente. Desde a chat#692 o evento `valores_guardados` manda a Lia buscar os valores e mandá-los,
# o que deixava o furo mais perto. Agora, sem leitura no turno, a referência é o resultado guardado que a ferramenta
# leria: o da cotação do evento, quando o turno é de evento; senão, o da cotação mais nova de cada bem da conversa.
#
# Dublados: o modelo da Lia (a fala e, quando pedida, a reescrita). O resto é o caminho real. Dados sintéticos.
# Valor em reais que não é preço de seguradora nenhuma (revisão da frente 4).
VALORES_SOLTOS = {
  'danos materiais' => 'Posso refazer com danos materiais de R$ 200.000,00.',
  'valor a segurar perguntado' => 'Se você segurar R$ 300 mil, eu refaço a cotação com esse valor.',
  'franquia da entrada' => 'A cotação foi feita com a franquia de R$ 3.500,00 que você pediu.',
  'teto informado' => 'O teto para incêndio nesse tipo de imóvel é de R$ 1.500.000,00.',
  'prêmio da apólice atual' => 'Hoje você paga R$ 3.100,00 na apólice atual.'
}.freeze

RSpec.describe Autonomia::Agents::Answerer do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agente) do
    Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Seguros do Vale').call
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:delivery) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 91)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:conferencia) { Autonomia::Agents::ConferenciaDePrecos }
  let(:porto) { cotou('8', 'Porto Seguro', 2119.18) }
  let(:allianz) { cotou('5', 'Allianz', 2402.55) }
  # A mesma seguradora no residencial, com outro preço: é o que separa a cotação certa da errada.
  let(:porto_residencial) { cotou('8', 'Porto Seguro', 412.37) }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true',
                      AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    agente.update!(config: agente.config.merge('with_knowledge' => false))
  end

  def cotou(code, name, amount, coverage = nil)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' }, 'coverage' => coverage }.compact
  end

  def cotacao_da_conversa(ofertas, faixa: 'auto:carro abc1d23', criada: 5.minutes.ago, handle: {})
    Autonomia::Agents::ToolRun.create!(
      account: account, agent: agente, slug: cotacao.slug, status: 'done', conversation_id: conversation.id,
      agent_inbox_id: agent_inbox.id, execution_key: SecureRandom.uuid, arguments: {}, created_at: criada, faixa: faixa,
      handle: { 'quote_id' => "q-#{SecureRandom.hex(3)}:1",
                cotacao::RESULTADO_KEY => Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas) }.merge(handle)
    )
  end

  def fala(texto)
    { reply: texto, confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # A Lia responde `texto` sem consultar ninguém (nenhuma leitura no turno). `reescrita`: o Hash que ela devolve
  # quando a conferência pede, ou a exceção da chamada. -> as reescritas pedidas.
  def modelo(texto, reescrita: nil)
    reescritas = []
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'c'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor).and_return({ text: fala(texto) })
    allow(client).to receive(:create) do |**kwargs|
      reescritas << kwargs
      raise reescrita if reescrita.is_a?(Class)

      { text: reescrita.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    reescritas
  end

  def responder(com: delivery)
    described_class.new(agent: agente, query: 'e aí, quanto deu?', trust_instruction: true, delivery: com).answer
  end

  def pedido(reescritas)
    reescritas.first[:input].last[:content].first[:text]
  end

  describe 'turno de mensagem, sem leitura' do
    it 'o preço certo sai como está, sem reescrita' do
      cotacao_da_conversa([porto, allianz])
      certa = 'A Porto Seguro ficou em R$ 2.119,18 no total, e a Allianz em R$ 2.402,55 no total.'
      reescritas = modelo(certa)

      expect(responder.reply).to eq(certa)
      expect(reescritas).to be_empty
      expect(delivery.resultado_do_turno).to be_nil
    end

    it 'o preço inventado volta para reescrever, com o resultado guardado como dados, e sai a reescrita conferida' do
      cotacao_da_conversa([porto, allianz])
      certa = 'A Porto Seguro ficou em R$ 2.119,18 no total.'
      reescritas = modelo('A Porto Seguro ficou em R$ 1.999,00 no total.',
                          reescrita: { 'reply' => certa, 'reply_sem_valores' => 'Vou encaminhar os valores.' })

      expect(responder.reply).to eq(certa)
      expect(reescritas.size).to eq(1)
      expect(pedido(reescritas)).to include('Porto Seguro fez proposta: R$ 2.119,18 no total')
    end

    it 'o valor certo posto na seguradora errada também volta' do
      cotacao_da_conversa([porto, allianz])
      reescritas = modelo('A Allianz ficou em R$ 2.119,18 no total.', reescrita: Crm::Ai::ResponsesClient::Error)

      expect(responder.reply).not_to include('2.119,18')
      expect(reescritas.size).to eq(1)
    end

    it 'a reescrita que falha, sem o PDF: sai o recuo, que não manda a pessoa pedir de novo' do
      cotacao_da_conversa([porto])
      modelo('A Porto Seguro ficou em R$ 1.999,00 no total.', reescrita: Crm::Ai::ResponsesClient::Error)

      expect(responder.reply).to eq(conferencia::RECUO_SEM_COMPARATIVO)
      expect(conferencia::RECUO_SEM_COMPARATIVO).not_to include('de novo')
      expect(conferencia::RECUO_SEM_COMPARATIVO).to include('encaminhar para alguém da equipe')
    end

    it 'a franquia que a seguradora cotou pode ser citada sem leitura, como pode com ela' do
      cotacao_da_conversa([cotou('20', 'Suhai', 2890.73, { 'deductible_amount' => 5795 })])
      certa = 'A franquia da Suhai é de R$ 5.795,00.'
      reescritas = modelo(certa)

      expect(responder.reply).to eq(certa)
      expect(reescritas).to be_empty
    end

    it 'fala sem valor em reais não é tocada' do
      cotacao_da_conversa([porto])
      texto = 'A Porto Seguro trouxe proposta. Quer que eu mande a proposta dela?'
      reescritas = modelo(texto)

      expect(responder.reply).to eq(texto)
      expect(reescritas).to be_empty
    end

    it 'conversa sem cotação com preço: a fala sai como antes (não há referência)' do
      texto = 'O valor que você paga hoje, R$ 3.100,00, entra na comparação quando a cotação sair.'
      reescritas = modelo(texto)

      expect(responder.reply).to eq(texto)
      expect(reescritas).to be_empty
    end

    it 'agente que não é de cotação não passa pela referência guardada' do
      cotacao_da_conversa([porto])
      agente.update_column(:agent_type, 'custom') # rubocop:disable Rails/SkipsModelValidations
      texto = 'A Porto Seguro ficou em R$ 1.999,00 no total.'
      reescritas = modelo(texto)

      expect(responder.reply).to eq(texto)
      expect(reescritas).to be_empty
    end
  end

  # VALOR SOLTO NÃO É PREÇO (revisão adversarial da frente 4, 25/09/2026). Sem leitura no turno, só o valor posto numa
  # seguradora da cotação é conferido: danos materiais, valor a segurar, franquia pedida, teto informado e prêmio da
  # apólice atual passam, em auto e em residencial, e o preço inventado para uma seguradora continua voltando.
  {
    'auto' => { faixa: 'auto:carro abc1d23', preco: 2119.18, escrito: 'R$ 2.119,18' },
    'residencial' => { faixa: 'residencial:apartamento', preco: 412.37, escrito: 'R$ 412,37' }
  }.each do |ramo, caso|
    describe "#{ramo}: depois de uma cotação com preço, sem leitura no turno" do
      let!(:cotada) { cotacao_da_conversa([cotou('8', 'Porto Seguro', caso[:preco]), allianz], faixa: caso[:faixa]) }

      VALORES_SOLTOS.each do |assunto, texto|
        it "#{assunto} passa" do
          reescritas = modelo(texto)

          expect(responder.reply).to eq(texto)
          expect(reescritas).to be_empty
        end
      end

      it 'o turno que aceita a recotação passa, com a execução nova ainda pendente' do
        Autonomia::Agents::ToolRun.create!(
          account: account, agent: agente, slug: cotacao.slug, status: 'pending', conversation_id: conversation.id,
          agent_inbox_id: agent_inbox.id, execution_key: SecureRandom.uuid, arguments: {}, faixa: caso[:faixa], handle: {}
        )
        texto = 'Comecei a nova cotação com danos materiais de R$ 200.000,00. Assim que sair, te mando aqui.'
        reescritas = modelo(texto)

        expect(responder.reply).to eq(texto)
        expect(reescritas).to be_empty
      end

      it 'Porto com preço inventado continua voltando' do
        reescritas = modelo('A Porto Seguro ficou em R$ 1.999,00 no total.', reescrita: Crm::Ai::ResponsesClient::Error)

        expect(responder.reply).to eq(conferencia::RECUO_SEM_COMPARATIVO)
        expect(pedido(reescritas)).to include(caso[:escrito])
      end

      it 'o preço certo com o nome certo passa' do
        texto = "A Porto Seguro ficou em #{caso[:escrito]} no total."
        reescritas = modelo(texto)

        expect(responder.reply).to eq(texto)
        expect(reescritas).to be_empty
        expect(cotada).to be_persisted
      end
    end
  end

  # A LEITURA DA REFERÊNCIA QUE FALHA NÃO DERRUBA O TURNO (revisão da frente 4): a fala sai como saía antes.
  it 'falha de banco ao ler a referência guardada: a fala sai como veio, sem reescrita' do
    cotacao_da_conversa([porto])
    allow(Autonomia::Agents::Tools::Native::InsuranceQuoteResult).to receive(:referencia_guardada)
      .and_raise(ActiveRecord::StatementInvalid, 'conexão perdida')
    texto = 'A Porto Seguro ficou em R$ 1.999,00 no total.'
    reescritas = modelo(texto)

    expect(responder.reply).to eq(texto)
    expect(reescritas).to be_empty
  end

  describe 'duas cotações na conversa' do
    let!(:residencial) { cotacao_da_conversa([porto_residencial], faixa: 'residencial:apartamento', criada: 2.minutes.ago) }

    before { cotacao_da_conversa([porto, allianz], faixa: 'auto:carro abc1d23', criada: 10.minutes.ago) }

    it 'no turno de mensagem, o preço de cada bem passa, e o inventado volta' do
      texto = 'No carro, a Porto Seguro ficou em R$ 2.119,18 no total. No apartamento, R$ 412,37 no total.'
      expect(modelo(texto)).to be_empty
      expect(responder.reply).to eq(texto)

      reescritas = modelo('No carro, a Porto Seguro ficou em R$ 2.000,00 no total.', reescrita: Crm::Ai::ResponsesClient::Error)
      expect(responder.reply).not_to include('2.000,00')
      expect(pedido(reescritas)).to include('R$ 2.119,18', 'R$ 412,37')
    end

    it 'a cotação mais nova do mesmo bem é a referência, e não a anterior' do
      cotacao_da_conversa([cotou('8', 'Porto Seguro', 1888.88)], faixa: 'auto:carro abc1d23', criada: 1.minute.ago)
      reescritas = modelo('A Porto Seguro ficou em R$ 2.119,18 no total.', reescrita: Crm::Ai::ResponsesClient::Error)

      expect(responder.reply).not_to include('2.119,18')
      expect(pedido(reescritas)).to include('R$ 1.888,88')
    end

    describe 'no turno do evento valores_guardados' do
      def delivery_do_evento(run)
        Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                               evento: 'valores_guardados', execucao_do_evento: run)
      end

      it 'a referência é a cotação do evento: o preço do outro bem volta' do
        reescritas = modelo('A Porto Seguro ficou em R$ 2.119,18 no total.', reescrita: Crm::Ai::ResponsesClient::Error)

        expect(responder(com: delivery_do_evento(residencial)).reply).to eq(conferencia::RECUO_SEM_COMPARATIVO)
        expect(pedido(reescritas)).to include('R$ 412,37')
        expect(pedido(reescritas)).not_to include('2.119,18')
      end

      it 'o preço da cotação do evento sai como está' do
        texto = 'A Porto Seguro ficou em R$ 412,37 no total.'
        reescritas = modelo(texto)

        expect(responder(com: delivery_do_evento(residencial)).reply).to eq(texto)
        expect(reescritas).to be_empty
      end

      it 'o turno de evento leva a cotação do evento ao contexto de entrega' do
        evento = Autonomia::Agents::Tools::Evento.new(run: residencial, tipo: 'valores_guardados')
        turno = Autonomia::Agents::Operate::ResponderAoEvento.new(conversation: conversation, agent_inbox: agent_inbox, evento: evento)

        expect(turno.send(:delivery).execucao_do_evento).to eq(residencial)
        expect(turno.send(:delivery).evento).to eq('valores_guardados')
      end
    end
  end

  describe 'com leitura no turno, nada muda' do
    before do
      cotacao_da_conversa([porto], faixa: 'auto:carro abc1d23', criada: 10.minutes.ago)
      cotacao_da_conversa([porto_residencial], faixa: 'residencial:apartamento', criada: 2.minutes.ago)
    end

    # A leitura do turno foi só a do carro: o preço do apartamento não está nela, e volta, como sempre voltou. O
    # resultado guardado não entra quando há leitura.
    it 'a referência é só o que a ferramenta devolveu no turno' do
      lido = conferencia::Dados.new(texto: 'Porto Seguro fez proposta: R$ 2.119,18 no total.', seguradoras: ['Porto Seguro'],
                                    comparativo: true, coberturas: [])
      delivery.registrar_resultado(lido)
      reescritas = modelo('A Porto Seguro ficou em R$ 412,37 no total.', reescrita: Crm::Ai::ResponsesClient::Error)

      expect(responder.reply).to eq(conferencia::RECUO_COM_COMPARATIVO)
      expect(pedido(reescritas)).not_to include('412,37')
    end

    # Com leitura, o valor solto que não está nos dados continua voltando, como sempre voltou: o modo que deixa
    # passar valor solto é só o da referência guardada.
    it 'o valor solto fora dos dados continua voltando' do
      lido = conferencia::Dados.new(texto: 'Porto Seguro fez proposta: R$ 2.119,18 no total.', seguradoras: ['Porto Seguro'],
                                    comparativo: true, coberturas: [])
      delivery.registrar_resultado(lido)
      reescritas = modelo('Posso refazer com danos materiais de R$ 200.000,00.', reescrita: Crm::Ai::ResponsesClient::Error)

      expect(responder.reply).to eq(conferencia::RECUO_COM_COMPARATIVO)
      expect(reescritas.size).to eq(1)
    end

    it 'e o preço que ela leu sai como está' do
      lido = conferencia::Dados.new(texto: 'Porto Seguro fez proposta: R$ 2.119,18 no total.', seguradoras: ['Porto Seguro'],
                                    comparativo: false, coberturas: [])
      delivery.registrar_resultado(lido)
      texto = 'A Porto Seguro ficou em R$ 2.119,18 no total.'
      reescritas = modelo(texto)

      expect(responder.reply).to eq(texto)
      expect(reescritas).to be_empty
    end
  end
end
