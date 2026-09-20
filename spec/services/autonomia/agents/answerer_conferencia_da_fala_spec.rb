require 'rails_helper'

# A FALA DA LIA NÃO PROMETE PARA DEPOIS NEM CONTRADIZ A COTAÇÃO QUE FECHOU NO TURNO (#510, #511).
#
# O caminho é o real (agente do `Builder`, catálogo do `Answerer`, `ToolRun` no banco). Só o modelo é dublado:
# cada chamada devolve a próxima resposta da fila, e pode pedir uma ferramenta. O que se prova é o que o código
# garante: quando a reescrita é pedida, o que o pedido diz, e que a reescrita pode chamar ferramenta.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true,
                                            'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agente) do
    Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia',
                                                  nome_corretora: 'Seguros do Vale').call
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:delivery) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 78)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:chamada_da_cg) do
    { 'name' => 'consultar_condicoes_gerais', 'call_id' => 'cg1',
      'arguments' => { 'seguradora' => 'Zurich', 'pergunta' => 'Cobre enchente?', 'ramo' => 'Automóvel' }.to_json }
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    agente.update!(config: agente.config.merge('with_knowledge' => false))
    body = { 'answer_text' => 'Alagamento e enchente estão cobertos.', 'answer_status' => 'answered',
             'grounded' => true,
             'interpreted' => { 'insurers' => [{ 'sent' => 'Zurich', 'resolved' => ['Zurich'], 'did_you_mean' => [] }] } }
    stub_request(:post, 'https://agent.autonomia.site/query')
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def resposta_do_passo(passo)
    fala(passo[:texto], escala: passo[:escala] == true)
  end

  def fala(texto, escala: false)
    { reply: texto, confidence: 0.9, should_handoff: escala, handoff_reason: (escala ? 'cliente pediu' : nil),
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # Cada chamada ao modelo leva a próxima entrada da fila: { texto:, chamada: (opcional), antes: (opcional) }.
  # Guarda o `input` de cada chamada para o exemplo ler o pedido de reescrita.
  def stub_do_modelo(*fila)
    chamadas = []
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      passo = fila[chamadas.size]
      chamadas << kwargs
      raise Crm::Ai::ResponsesClient::Error, 'fora' if passo[:erro]

      passo[:antes]&.call
      executor.call([passo[:chamada]]) if passo[:chamada]
      { text: resposta_do_passo(passo) }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    chamadas
  end

  def responder
    described_class.new(agent: agente, query: 'a mais barata cobre enchente?', trust_instruction: true,
                        delivery: delivery).answer
  end

  def pedido_de_reescrita(chamada)
    chamada[:input].last[:content].first[:text]
  end

  # A execução ACEITA no turno, como o especialista a abre: `pending` até o Responder promovê-la no fim do
  # turno. É o estado em que uma cotação legítima está no momento da conferência.
  def cotacao_aberta_no_turno
    Autonomia::Agents::ToolRun.open!(
      agent: agente, slug: cotacao.slug, arguments: { 'produto' => 'auto', 'dados' => '{}' },
      scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id, origin_message_id: 77 }
    )
  end

  def cotacao_correndo
    run = cotacao_aberta_no_turno
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.reload
  end

  # O que o job da cotação faz quando o comparativo sai: fecha o portal e marca o PDF entregue.
  def fechar_com_comparativo(run)
    -> { run.reload.merge_handle!({ cotacao::FECHADO_KEY => true, cotacao::PDF_SENT_KEY => true }) }
  end

  describe 'promessa de consultar depois (#510)' do
    let(:promessa) { 'Vou confirmar nas condições da Zurich se a proposta cobre enchente.' }

    it 'sem ferramenta no turno, pede UMA reescrita, com ferramentas, e a reescrita pode consultar' do
      # Arrange
      chamadas = stub_do_modelo({ texto: promessa },
                                { texto: 'Pelas condições da Zurich, enchente está coberta.', chamada: chamada_da_cg })

      # Act
      resultado = responder

      # Assert
      expect(chamadas.size).to eq(2)
      expect(chamadas.last[:tools].map { |t| t[:name] || t['name'] }).to include('consultar_condicoes_gerais')
      expect(pedido_de_reescrita(chamadas.last)).to include('nenhuma ferramenta foi chamada')
      expect(resultado.reply).to eq('Pelas condições da Zurich, enchente está coberta.')
    end

    it 'com ferramenta chamada no turno, não pede reescrita' do
      chamadas = stub_do_modelo({ texto: 'Consultei e vou confirmar com você o resto depois.', chamada: chamada_da_cg })

      resultado = responder

      expect(chamadas.size).to eq(1)
      expect(resultado.reply).to eq('Consultei e vou confirmar com você o resto depois.')
    end

    it 'fala sem promessa sai como veio, sem reescrita' do
      chamadas = stub_do_modelo({ texto: 'A mais barata é a da Zurich. Quer que eu envie a proposta?' })

      resultado = responder

      expect(chamadas.size).to eq(1)
      expect(resultado.reply).to eq('A mais barata é a da Zurich. Quer que eu envie a proposta?')
    end

    it 'se a reescrita ainda promete, publica a reescrita (uma tentativa só)' do
      chamadas = stub_do_modelo({ texto: promessa }, { texto: 'Deixa eu verificar e já te retorno.' })

      resultado = responder

      expect(chamadas.size).to eq(2)
      expect(resultado.reply).to eq('Deixa eu verificar e já te retorno.')
    end

    it 'se a reescrita falha, publica a fala original' do
      chamadas = stub_do_modelo({ texto: promessa }, { erro: true })

      expect(responder.reply).to eq(promessa)
      expect(chamadas.size).to eq(2)
    end
  end

  describe 'cotação que fecha durante o turno (#511)' do
    let(:ainda_correndo) { 'A cotação continua correndo, e o comparativo chega por aqui quando terminar.' }

    it 'fechada durante o turno e fala "ainda correndo": pede reescrita dizendo que o comparativo já foi entregue' do
      run = cotacao_correndo
      chamadas = stub_do_modelo({ texto: ainda_correndo, antes: fechar_com_comparativo(run) },
                                { texto: 'O comparativo em PDF já está aí com você.' })

      resultado = responder

      expect(chamadas.size).to eq(2)
      expect(pedido_de_reescrita(chamadas.last)).to include('terminou enquanto você respondia')
      expect(pedido_de_reescrita(chamadas.last)).to include('comparativo em PDF já foi entregue')
      expect(resultado.reply).to eq('O comparativo em PDF já está aí com você.')
    end

    it 'cotação ainda correndo: não pede reescrita' do
      cotacao_correndo
      chamadas = stub_do_modelo({ texto: ainda_correndo })

      resultado = responder

      expect(chamadas.size).to eq(1)
      expect(resultado.reply).to eq(ainda_correndo)
    end

    # ANTES DA #547 este exemplo afirmava o contrário: sem cotação nenhuma a fala saía como veio, e era
    # exatamente o defeito medido na conversa 6983. Quem cobre o caso agora é o `:cotacao_prometida`.
    it 'sem cotação nenhuma: quem dispara é a promessa sem cotação, não o fechamento' do
      chamadas = stub_do_modelo({ texto: ainda_correndo }, { texto: 'Preciso do CEP para cotar.' })

      responder

      expect(chamadas.size).to eq(2)
      expect(pedido_de_reescrita(chamadas.last)).to include('não existe cotação correndo')
      expect(pedido_de_reescrita(chamadas.last)).not_to include('terminou enquanto você respondia')
    end
  end

  # PROMESSA DE COMPARATIVO SEM COTAÇÃO (#547). Medido em produção na conversa 6983, em 20/09/2026: o cliente
  # mandou tudo, a Lia disse que o comparativo chegava, e nenhuma execução foi criada. Vinte minutos depois,
  # cobrada, repetiu a promessa. O estado que desmente a fala aqui é a AUSÊNCIA de cotação.
  describe 'promessa de comparativo sem cotação (#547)' do
    let(:promessa) { 'Vou seguir com esses dados. O comparativo das seguradoras chega por aqui quando ficar pronto.' }

    it 'sem cotação nenhuma, pede UMA reescrita, com ferramentas, dizendo para acionar a cotação agora' do
      # Arrange
      chamadas = stub_do_modelo({ texto: promessa },
                                { texto: 'Estou cotando agora com as seguradoras.',
                                  antes: -> { cotacao_aberta_no_turno } })

      # Act
      resultado = responder

      # Assert
      expect(chamadas.size).to eq(2)
      expect(chamadas.last[:tools]).to be_present
      expect(pedido_de_reescrita(chamadas.last)).to include('não existe cotação correndo')
      expect(resultado.reply).to eq('Estou cotando agora com as seguradoras.')
    end

    it 'cotação aberta na própria reescrita: a reescrita publica e o sinal some' do
      chamadas = stub_do_modelo({ texto: promessa },
                                { texto: 'Já mandei cotar, o comparativo chega por aqui.',
                                  antes: -> { cotacao_aberta_no_turno } })

      resultado = responder

      expect(chamadas.size).to eq(2)
      expect(resultado.reply).to eq('Já mandei cotar, o comparativo chega por aqui.')
    end

    # O caso legítimo, e o motivo de a leitura ser refeita no momento da conferência: a execução aceita neste
    # turno ainda está `pending` (só o Responder a promove), e uma leitura que só olhasse `correndo?` a perderia.
    it 'cotação aceita neste turno (pending): promessa legítima, sem reescrita' do
      cotacao_aberta_no_turno
      chamadas = stub_do_modelo({ texto: promessa })

      resultado = responder

      expect(chamadas.size).to eq(1)
      expect(resultado.reply).to eq(promessa)
    end

    it 'cotação correndo desde antes do turno: promessa legítima, sem reescrita' do
      cotacao_correndo
      chamadas = stub_do_modelo({ texto: promessa })

      expect(responder.reply).to eq(promessa)
      expect(chamadas.size).to eq(1)
    end

    it 'sem promessa de cotação: fala normal sai como veio' do
      chamadas = stub_do_modelo({ texto: 'Me manda o CEP onde o carro dorme?' })

      responder

      expect(chamadas.size).to eq(1)
    end
  end

  # VOCABULÁRIO INTERNO NA FALA AO CLIENTE (#547). "Vou passar para o especialista de seguro auto" saiu na mesma
  # conversa 6983. Decisão do CEO em 20/09/2026: quem fala com o cliente é a Lia, e ele nunca ouve falar de
  # especialista. A régua é o que o CLIENTE lê, e é por isso que "o sistema da seguradora" continua passando.
  describe 'vocabulário interno na fala (#547)' do
    it 'fala citando o especialista pede reescrita' do
      chamadas = stub_do_modelo({ texto: 'Vou passar para o especialista de seguro auto seguir com os dados.' },
                                { texto: 'Alguém da equipe assume daqui, com o que você já mandou.' })

      resultado = responder

      expect(chamadas.size).to eq(2)
      expect(pedido_de_reescrita(chamadas.last)).to include('o cliente não conhece')
      expect(resultado.reply).to eq('Alguém da equipe assume daqui, com o que você já mandou.')
    end

    it 'fala citando o fluxo interno pede reescrita' do
      chamadas = stub_do_modelo({ texto: 'O fluxo de cotação não devolveu essa seguradora.' },
                                { texto: 'Essa seguradora não deu retorno nesta cotação.' })

      expect(responder.reply).to eq('Essa seguradora não deu retorno nesta cotação.')
      expect(chamadas.size).to eq(2)
    end

    # "ferramenta" e "agente" saíram da lista: são palavras do mundo do cliente numa conversa de auto.
    it 'fala de coleta com "ferramenta de trabalho" e "agente autorizado" sai como está' do
      legitima = 'O carro é usado como ferramenta de trabalho? E você é agente autorizado de alguma frota?'
      chamadas = stub_do_modelo({ texto: legitima })

      expect(responder.reply).to eq(legitima)
      expect(chamadas.size).to eq(1)
    end

    it '"sistema de rastreamento" e "sistema de alarme" saem como estão' do
      legitima = 'O carro tem sistema de rastreamento ou sistema de alarme instalado?'
      chamadas = stub_do_modelo({ texto: legitima })

      expect(responder.reply).to eq(legitima)
      expect(chamadas.size).to eq(1)
    end

    # O ACHADO DA REVISÃO: o pedido de reescrita leva só o texto, e o modelo devolve o schema inteiro. Sem
    # preservar a escalada, o cliente lia "alguém assume" e ninguém assumia — a mesma dor da conversa 6983.
    it 'reescrita de fala que escala não apaga a passagem para humano' do
      chamadas = stub_do_modelo({ texto: 'Vou passar para o especialista de seguro auto.', escala: true },
                                { texto: 'Alguém da equipe assume daqui.', escala: false })

      resultado = responder
      expect(resultado.reply).to eq('Alguém da equipe assume daqui.')
      expect(resultado.handoff[:should]).to be(true)
      expect(chamadas.size).to eq(2)
    end

    it '"o sistema da seguradora" não dispara: é coisa dela, não engrenagem nossa' do
      legitima = 'O sistema da seguradora ainda não devolveu o número da proposta.'
      chamadas = stub_do_modelo({ texto: legitima })

      expect(responder.reply).to eq(legitima)
      expect(chamadas.size).to eq(1)
    end

    it '"no nosso sistema" dispara' do
      chamadas = stub_do_modelo({ texto: 'Deixei registrado no nosso sistema.' },
                                { texto: 'Anotei aqui com você.' })

      expect(responder.reply).to eq('Anotei aqui com você.')
      expect(chamadas.size).to eq(2)
    end

    it '"modelo do veículo" não dispara: o falso positivo seria diário' do
      legitima = 'Me confirma o modelo do veículo, por favor?'
      chamadas = stub_do_modelo({ texto: legitima })

      expect(responder.reply).to eq(legitima)
      expect(chamadas.size).to eq(1)
    end
  end
end
