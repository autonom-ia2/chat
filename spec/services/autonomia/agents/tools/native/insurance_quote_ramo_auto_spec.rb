require 'rails_helper'

# A primeira ferramenta ASSÍNCRONA de verdade. O que estes exemplos travam é o CONTRATO com o
# cliente: o que ele lê, o que ele nunca lê, e por que a segunda mensagem se anuncia como
# complemento em vez de parecer uma cotação nova.
#
# ESCRITOS PARA `InsuranceAutoQuote`, e mantidos PALAVRA POR PALAVRA quando as duas ferramentas
# viraram uma em 08/09/2026. São eles que provam que a unificação não perdeu comportamento — um
# spec afrouxado para caber no código novo não provaria nada.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  # A placa vai no bloco `vehicle`, como o adapter lê (entrega 2); CPF e CEP pelos atalhos comuns.
  let(:params) { { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'vehicle' => { 'plate' => 'TYV8I74' } } }
  let(:tool) { described_class.new(agent: agent, params: params) }

  # A ferramenta CONFERE a entrada antes de submeter, e a conferência não toca no portal. Os dublês
  # abaixo precisam conhecê-la; o que cada exemplo assegura — o payload que sobe, o texto que desce
  # — continua palavra por palavra o que era quando a ferramenta de auto era um arquivo à parte.
  before { enable_test_encryption! }

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  # A conferência que a ferramenta faz antes de submeter, e que não toca no portal.
  def sem_problema
    { 'valido' => true, 'problemas' => [] }
  end

  # A consulta de placa que a cotação faz antes de conferir (entrega 2): o tipo liga as regras.
  def consulta_de_placa
    { 'plate' => 'TYV8I74', 'model' => 'Gol', 'model_year' => 2016, 'vehicle_type' => 'v' }
  end

  # O conector que confere sem problema e responde a placa; o resto cada exemplo diz.
  def conector_pronto(**respostas)
    instance_double(Autonomia::Insurance::Connector::Mock, quote_validate: sem_problema,
                                                           vehicle_lookup: consulta_de_placa, **respostas)
  end

  # Com o schema de auto guardado, como a sincronização deixa: o conector daqui é um dublê e não
  # responde `quote_schema` — sem o schema, a ferramenta recusaria auto por `formulario_indisponivel`.
  def ready_connection
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com',
                                                      password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def offer(code, name, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status }
    # `basis` acompanha todo prêmio que o adapter devolve hoje (critério 5.5): sem ele o valor é um
    # número sem unidade. O caso `unknown` tem exemplos próprios mais abaixo.
    return base unless amount

    base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' })
  end

  it 'is asynchronous, because a quote takes minutes and the turn cannot wait' do
    expect(described_class.async?).to be(true)
  end

  describe '#start' do
    it 'submits and keeps the quote id for the polling that follows' do
      # Arrange
      ready_connection
      connector = conector_pronto(quote_start: { 'quote_id' => 'abc:1', 'status' => 'queued' })
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)

      # Act
      handle = tool.start

      # Assert
      expect(handle['quote_id']).to eq('abc:1')
      expect(handle[described_class::DELIVERED_KEY]).to eq([])
      expect(connector).to have_received(:quote_start).with(
        hash_including(product: 'auto',
                       input: hash_including('insured' => { 'document' => '04297912678' },
                                             # o tipo vem da consulta de placa, antes de enviar (entrega 2, termo 5)
                                             'vehicle' => hash_including('plate' => 'TYV8I74', 'vehicleType' => 'v')))
      )
    end

    # RENOVAÇÃO. O portal cobra menos de quem já tem seguro, e a conta sai destes três campos. Sem
    # eles a renovação era cotada como primeira apólice — mais cara, e o comparativo perdia para o
    # preço que o cliente já paga.
    context 'when o cliente está renovando' do
      it 'não manda `quotation` numa cotação nova, para o adapter usar os próprios padrões' do
        # Arrange
        ready_connection
        connector = conector_pronto(quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)

        # Act
        tool.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]).not_to have_key('quotation')
        end
      end

      it 'manda bônus e sinistros quando o cliente está renovando' do
        # Arrange
        ready_connection
        connector = conector_pronto(quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        renovacao = described_class.new(agent: agent,
                                        params: params.merge('quotation' => { 'isRenewal' => true, 'bonusClass' => 7,
                                                                              'previousClaimsCount' => 1 }))

        # Act
        renovacao.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]['quotation'])
            .to eq('isRenewal' => true, 'bonusClass' => 7, 'previousClaimsCount' => 1)
        end
      end

      # Zero sinistro é a resposta MAIS COMUM numa renovação, e é diferente de "não sei". Com
      # `blank?` no lugar de `nil?` o zero informado viraria omissão silenciosa.
      it 'preserva zero sinistros, que é resposta e não ausência' do
        # Arrange
        ready_connection
        connector = conector_pronto(quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        sem_sinistro = described_class.new(agent: agent,
                                           params: params.merge('quotation' => { 'isRenewal' => true, 'bonusClass' => 5,
                                                                                 'previousClaimsCount' => 0 }))

        # Act
        sem_sinistro.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]['quotation']['previousClaimsCount']).to eq(0)
        end
      end

      # String vazia é o modelo dizendo "não sei", não "zero". O portal recebe 0 nos dois casos (o
      # adapter tem `.default(0)`), então isto fixa a INTENÇÃO do payload, não o efeito no portal —
      # é o que impede alguém de "simplificar" o método e passar a afirmar um dado que o cliente
      # não deu no dia em que o default do adapter mudar.
      it 'omite sinistros quando vem string vazia, que é ausência e não zero' do
        # Arrange
        ready_connection
        connector = conector_pronto(quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        sem_resposta = described_class.new(agent: agent,
                                           params: params.merge('quotation' => { 'isRenewal' => true,
                                                                                 'previousClaimsCount' => '' }))

        # Act
        sem_resposta.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]['quotation']).to eq('isRenewal' => true)
        end
      end

      # `false` é resposta ("não estou renovando"), e vai como veio: o bloco chega ao adapter, que
      # aplica os padrões dele. O tipo é booleano no schema da função — o modelo não manda "false".
      it 'leva isRenewal false como resposta, e não como ausência' do
        # Arrange
        ready_connection
        connector = conector_pronto(quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        nova = described_class.new(agent: agent, params: params.merge('quotation' => { 'isRenewal' => false }))

        # Act
        nova.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]['quotation']).to eq('isRenewal' => false)
        end
      end
    end

    describe 'aviso de renovação sem bônus' do
      it 'sai junto do primeiro preço, uma vez só' do
        # Arrange
        ready_connection
        resultado = { 'status' => 'running',
                      'offers' => [{ 'status' => 'quoted', 'insurer' => { 'code' => '1', 'name' => 'Ezze' },
                                     'premium' => { 'amount' => 2050.4 } }] }
        connector = conector_pronto(quote_result: resultado)
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => [],
                   described_class::SEM_BONUS_KEY => true }

        # Act
        primeira = tool.poll(handle: handle, attempt: 1)

        # Assert
        expect(primeira.deliveries.first).to include('Ezze')
        expect(primeira.deliveries.first).to include('classe de bônus')
      end

      it 'marca no handle que saiu, para não repetir' do
        # Arrange
        ready_connection
        resultado = { 'status' => 'running',
                      'offers' => [{ 'status' => 'quoted', 'insurer' => { 'code' => '1', 'name' => 'Ezze' },
                                     'premium' => { 'amount' => 2050.4 } }] }
        connector = conector_pronto(quote_result: resultado)
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => [],
                   described_class::SEM_BONUS_KEY => true }

        # Act
        primeira = tool.poll(handle: handle, attempt: 1)

        # Assert
        expect(primeira.handle[described_class::AVISO_SENT_KEY]).to be(true)
      end

      it 'não repete depois de já ter saído' do
        # Arrange — segunda leva, com a sentinela do aviso já marcada
        ready_connection
        resultado = { 'status' => 'running',
                      'offers' => [{ 'status' => 'quoted', 'insurer' => { 'code' => '2', 'name' => 'Mapfre' },
                                     'premium' => { 'amount' => 2582.76 } }] }
        connector = conector_pronto(quote_result: resultado)
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['1'],
                   described_class::SEM_BONUS_KEY => true,
                   described_class::AVISO_SENT_KEY => true }

        # Act
        segunda = tool.poll(handle: handle, attempt: 2)

        # Assert
        expect(segunda.deliveries.first).to include('Mapfre')
        expect(segunda.deliveries.first).not_to include('classe de bônus')
      end

      # `deliver` roda ANTES de `record_attempt!`: uma entrega bloqueada avança o handle com os
      # códigos das ofertas mesmo assim. Com a regra antiga (só na primeira entrega) o aviso se
      # perdia para sempre nessa janela. Com sentinela própria, ele sai na leva seguinte.
      it 'sai numa entrega posterior quando a primeira não chegou a sair' do
        # Arrange — já há oferta entregue, mas o aviso nunca foi marcado
        ready_connection
        resultado = { 'status' => 'running',
                      'offers' => [{ 'status' => 'quoted', 'insurer' => { 'code' => '2', 'name' => 'Mapfre' },
                                     'premium' => { 'amount' => 2582.76 } }] }
        connector = conector_pronto(quote_result: resultado)
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['1'],
                   described_class::SEM_BONUS_KEY => true }

        # Act
        segunda = tool.poll(handle: handle, attempt: 2)

        # Assert
        expect(segunda.deliveries.first).to include('classe de bônus')
        expect(segunda.handle[described_class::AVISO_SENT_KEY]).to be(true)
      end

      it 'não avisa quando a renovação veio com bônus' do
        # Arrange
        ready_connection
        resultado = { 'status' => 'running',
                      'offers' => [{ 'status' => 'quoted', 'insurer' => { 'code' => '1', 'name' => 'Ezze' },
                                     'premium' => { 'amount' => 1800.0 } }] }
        connector = conector_pronto(quote_result: resultado)
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => [],
                   described_class::SEM_BONUS_KEY => false }

        # Act
        progresso = tool.poll(handle: handle, attempt: 1)

        # Assert
        expect(progresso.deliveries.first).not_to include('classe de bônus')
      end
    end

    it 'strips the formatting the customer typed, because the portal wants digits' do
      # Arrange
      ready_connection
      captured = nil
      connector = conector_pronto
      allow(connector).to receive(:quote_start) do |**kwargs|
        captured = kwargs[:input]
        { 'quote_id' => 'a:1' }
      end
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)

      # Act
      tool.start

      # Assert
      expect(captured['address']['zipCode']).to eq('31110210')
      expect(captured['commissionPercent']).to eq(10.0)
    end
  end

  describe '#poll' do
    let(:connector) { conector_pronto }

    before do
      ready_connection
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_proposal)
        .and_return({ 'url' => 'https://exemplo.test/comparativo.pdf' })
    end

    def result(status, offers)
      { 'quote_id' => 'abc:1', 'status' => status, 'offers' => offers }
    end

    it 'says nothing while no insurer has answered' do
      # Arrange
      allow(connector).to receive(:quote_result).and_return(result('running', []))

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 0)

      # Assert — silêncio é melhor que "ainda estou consultando" a cada 5 segundos
      expect(progress).to be_running
      expect(progress.deliveries).to be_empty
    end

    it 'delivers the first prices as soon as they arrive, cheapest first' do
      # Arrange
      allow(connector).to receive(:quote_result).and_return(
        result('running',
               [offer('3', 'Mapfre', 'quoted', 2582.76), offer('43', 'Ezze', 'quoted', 2050.40)])
      )

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => [] },
                           attempt: 1)

      # Assert
      # A ORDEM É O QUE ESTE EXEMPLO GUARDA — mais barata primeiro. O texto exato mudou de forma em
      # 08/09/2026 (marcador, negrito do WhatsApp, milhar) e a asserção passou a olhar a ordem, não
      # a redação: prender o texto inteiro aqui é o que faz melhorar o layout parecer regressão.
      texto = progress.deliveries.first
      expect(texto.index('Ezze')).to be < texto.index('Mapfre')
      expect(texto).to include('*Ezze* — R$ 2.050,40 no total')
      expect(progress.handle[described_class::DELIVERED_KEY]).to eq(%w[43 3])
    end

    it 'announces the late ones as a follow-up, never repeating what the customer already read' do
      # Arrange — é o que impede a segunda mensagem de parecer uma cotação nova
      allow(connector).to receive(:quote_result).and_return(
        result('completed',
               [offer('43', 'Ezze', 'quoted', 2050.40), offer('9', 'Darwin', 'quoted', 3407.87)])
      )

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['43'] },
                           attempt: 5)

      # Assert
      expect(progress).to be_done
      expect(progress.deliveries.first).to start_with('Mais uma opção:')
      expect(progress.deliveries.first).to include('*Darwin* — R$ 3.407,87 no total')
      expect(progress.deliveries.first).not_to include('Ezze')
    end

    it 'never tells the customer that an insurer refused the risk' do
      # Arrange — o cliente pediu preço, não auditoria; a recusa fala do veículo e da região dele
      allow(connector).to receive(:quote_result).and_return(
        result('completed',
               [offer('43', 'Ezze', 'quoted', 2050.40), offer('47', 'Justos', 'declined')])
      )

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 3)

      # Assert
      expect(progress.deliveries.join).to include('Ezze')
      expect(progress.deliveries.join).not_to include('Justos')
    end

    it 'never leaks that our own credential is broken at an insurer' do
      # Arrange — é problema nosso, constrangedor e inútil para quem quer comprar seguro
      allow(connector).to receive(:quote_result).and_return(
        result('completed',
               [offer('43', 'Ezze', 'quoted', 2050.40), offer('5', 'Allianz', 'auth_required')])
      )

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 3)

      # Assert
      expect(progress.deliveries.join).not_to include('Allianz')
      expect(progress.deliveries.join).not_to match(/senha|credencial|login/i)
    end

    # A GUARDA AO CONTRÁRIO: não se prova que um teto de ofertas funciona, prova-se que ele NÃO
    # existe. Havia um — as 3 mais baratas, sobre a lista inteira —, e ele escondia do cliente 14
    # das 17 seguradoras que a corretora tinha acabado de pagar. Removido em 10/09/2026 por decisão
    # do Rodrigo. Sem este exemplo, alguém preocupado com "poluir a conversa" o traz de volta numa
    # linha, e as opções somem sem ninguém notar.
    it 'delivers every insurer that quoted — there is NO ceiling on options' do
      # Arrange
      offers = (1..17).map { |i| offer(i.to_s, "Seguradora#{i}", 'quoted', i * 100) }
      allow(connector).to receive(:quote_result).and_return(result('completed', offers))

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 4)

      # Assert — conta MARCADOR, e não linha: cada oferta ocupa duas linhas mais o espaço entre
      # elas, e contar linha mediria a formatação em vez do número de opções.
      expect(progress.deliveries.first.scan('• ').size).to eq(17)
      expect(progress.deliveries.first).to include('*Seguradora17*')
    end

    # O que impede afogar o cliente NÃO é teto: é a entrega em lotes. Cada volta manda só o que
    # chegou desde a anterior, na ordem em que as seguradoras respondem.
    it 'delivers only what arrived since the last batch' do
      # Arrange
      primeiro = [offer('1', 'A', 'quoted', 100), offer('2', 'B', 'quoted', 200)]
      allow(connector).to receive(:quote_result).and_return(result('partial', primeiro))
      parcial = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 1)

      # Act — na volta seguinte chega uma terceira
      allow(connector).to receive(:quote_result)
        .and_return(result('completed', primeiro + [offer('3', 'C', 'quoted', 300)]))
      segunda = tool.poll(handle: parcial.handle, attempt: 2)

      # Assert
      expect(parcial.deliveries.first.scan('• ').size).to eq(2)
      expect(segunda.deliveries.first).to include('*C*')
      expect(segunda.deliveries.first).not_to include('*A*')
    end

    it 'closes with the comparison PDF, one per quote, like the portal does' do
      # Arrange
      allow(connector).to receive(:quote_result).and_return(
        result('completed', [offer('43', 'Ezze', 'quoted', 2050.40)])
      )

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 4)

      # Assert — a lista serve para decidir; o PDF é o que o cliente leva adiante. Desde a entrega
      # 11 ele sai como ARQUIVO (a forma serializada de `EntregaDeArquivo`), com o link de reserva.
      comparativo = Autonomia::Agents::Tools::EntregaDeArquivo.de(progress.deliveries.last)
      expect(comparativo.legenda).to include('Comparativo com todas as opções')
      expect(comparativo.url).to eq('https://exemplo.test/comparativo.pdf')
      expect(comparativo.reserva).to include('https://exemplo.test/comparativo.pdf')
      expect(progress.handle[described_class::PDF_SENT_KEY]).to be(true)
      # O FECHAMENTO DO PORTAL SE GRAVA POR SI (entrega 8a): é ele que distingue "ainda tem
      # seguradora por responder" de "é isto que havia", e não pode depender de o PDF ter saído.
      expect(progress.handle[described_class::FECHADO_KEY]).to be(true)
      expect(connector).to have_received(:quote_proposal).with(hash_excluding(:insurer_code))
    end

    # O FECHO E O ENCERRAMENTO PERGUNTAM PELO FATO, e o fato é a MENSAGEM na conversa. Por isso as
    # três respostas da cotação ao `Tools::Encerramento` só se exercitam na ferramenta como o MOTOR
    # a monta: com a conversa e com a LINHA da execução (é do `execution_key` dela que nasce a
    # identidade de cada entrega). O handle diz o que esta execução TENTOU entregar; ele avança
    # mesmo quando a publicação é recusada, e foi por acreditar nele que a frase parcial saiu para
    # quem não tinha preço nenhum na tela.
    describe 'o fecho e o que ainda vale entregar' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }
      let(:agent_bot) { create(:agent_bot, account: account) }
      let(:run) do
        Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: {},
                                         scope: { conversation_id: conversation.id })
      end
      let(:tool_do_motor) do
        described_class.new(agent: agent, params: params, conversation: conversation, run: run)
      end
      let(:preco) { '*Ezze* — R$ 2.050,40 no total' }
      let(:fechado) { described_class::FECHADO_KEY }

      # A MENSAGEM que o publicador teria criado: o que a torna reconhecível é o token, a identidade
      # da entrega derivada do conteúdo. -> o token.
      def ja_publicado(entrega)
        token = Autonomia::Agents::Tools::EntregaPublicada.token_de(run, entrega)
        create(:message, account: account, inbox: inbox, conversation: conversation,
                         message_type: :outgoing, sender: agent_bot, content: entrega.to_s,
                         content_attributes: { 'autonomia_async_token' => token })
        token
      end

      # O handle de quem emitiu um preço: com a mensagem na conversa (o preço chegou) ou sem ela
      # (a publicação foi recusada e o handle avançou assim mesmo). São TEXTOS diferentes de
      # propósito — a identidade da entrega é o conteúdo, então o preço recusado não pode ser o
      # mesmo que já está na tela.
      def handle_com_preco(chegou:)
        texto = chegou ? preco : '*Ezze* — R$ 1.999,00 no total (o que a publicação recusou)'
        token = chegou ? ja_publicado(texto) : Autonomia::Agents::Tools::EntregaPublicada.token_de(run, texto)
        { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['43'],
          described_class::PRECOS_KEY => [token] }
      end

      # A IDENTIDADE DE CADA ENTREGA É GRAVADA NA PASSADA QUE A EMITE — é a única em que se sabe o
      # TEXTO, e é dele que o token nasce. Sem este registro o fecho não teria pelo que perguntar, e
      # voltaria a decidir pelo handle (a intenção) em vez de pela mensagem (o fato).
      it 'grava a identidade do preco e do comparativo que emitiu' do
        allow(connector).to receive(:quote_result).and_return(
          result('completed', [offer('43', 'Ezze', 'quoted', 2050.40)])
        )
        tokens = Autonomia::Agents::Tools::EntregaPublicada

        progresso = tool_do_motor.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 4)

        expect(progresso.handle[described_class::PRECOS_KEY])
          .to eq([tokens.token_de(run, progresso.deliveries.first)])
        expect(progresso.handle[described_class::COMPARATIVO_KEY])
          .to eq(tokens.token_de(run, progresso.deliveries.last))
        expect(progresso.handle[fechado]).to be(true)
      end

      # O `compact` DO FECHO É SÓ PARA A IDENTIDADE AUSENTE — e ele estava apagando QUALQUER chave
      # nula do handle da ferramenta no ramo `done`, mais largo do que o comentário ao lado dele
      # dizia. Hoje nenhuma chave da cotação é nula, então a diferença é inerte; inerte e silenciosa
      # é como um apagamento de handle chega à produção.
      it 'o fecho nao apaga chave nula que o handle da ferramenta ja carregava' do
        allow(connector).to receive(:quote_result).and_return(
          result('completed', [offer('43', 'Ezze', 'quoted', 2050.40)])
        )

        progresso = tool_do_motor.poll(handle: { 'quote_id' => 'abc:1', 'marca_da_ferramenta' => nil }, attempt: 4)

        expect(progresso.handle).to have_key('marca_da_ferramenta')
        expect(progresso.handle[described_class::COMPARATIVO_KEY]).to be_present
      end

      # O COMPARATIVO NÃO PODE SER REFÉM DA SEGURADORA MAIS LENTA. Ele saía só no ramo `done`,
      # quando o portal fechava a cotação — e em 08/09/2026 a execução entregou cinco preços e
      # estourou o prazo na 22ª consulta, então o PDF nunca saiu. O `AsyncRunJob` chama isto ao
      # desistir.
      it 'entrega o comparativo tambem quando a cotacao acaba sem fechar' do
        # Act — nenhum `done`: é o encerramento por prazo, com preços já entregues
        # As CHAVES importam: `closing_deliveries` recebe um keyword desde a entrega 8, e um hash
        # sem chaves na chamada vira keyword em vez de argumento posicional.
        entregas = tool_do_motor.closing_deliveries(handle_com_preco(chegou: true))

        # Assert
        expect(Autonomia::Agents::Tools::EntregaDeArquivo.de(entregas.first).url).to eq('https://exemplo.test/comparativo.pdf')
      end

      # E NÃO SE PEDE COMPARATIVO PARA QUEM NÃO TEM PREÇO. `deliver` roda antes de
      # `record_attempt!`, então uma entrega recusada (conversa encerrada, agente desligado no meio)
      # avança `entregues` no handle sem que mensagem nenhuma tenha entrado. Nesse estado o motor
      # pedia ao portal um comparativo de até 60 s para publicá-lo — provavelmente pelo mesmo canal
      # que acabara de recusar o preço — e o cliente, que precisava da frase honesta de falha, lia
      # "os preços acima são os que chegaram" sem nada acima.
      it 'nao pede o comparativo quando o preco nunca chegou ao cliente' do
        entregas = tool_do_motor.closing_deliveries(handle_com_preco(chegou: false))

        expect(entregas).to be_empty
        expect(connector).not_to have_received(:quote_proposal)
      end

      it 'nao repete o comparativo no encerramento se ele ja tinha saido' do
        entregas = tool_do_motor.closing_deliveries(
          handle_com_preco(chegou: true).merge(described_class::PDF_SENT_KEY => true)
        )

        expect(entregas).to be_empty
      end

      # O COMPARATIVO É TRABALHO NOVO NO PORTAL: login mais uma chamada de até 60 s, e depois o
      # download. No caminho do varredor — até 500 linhas em sequência num cron, com 25 s de
      # shutdown do Sidekiq — ele não sai: quem é morto no meio deixa a passada pela metade. O PDF
      # continua no portal; o cliente fica com os preços que já leu e com um fecho honesto sobre o
      # que ele tem.
      it 'nao gera o comparativo quando a passada nao pode comecar trabalho novo' do
        entregas = tool_do_motor.closing_deliveries(handle_com_preco(chegou: true), trabalho_novo: false)

        expect(entregas).to be_empty
        expect(connector).not_to have_received(:quote_proposal)
      end

      # RESULTADO É PREÇO QUE VIROU MENSAGEM. Nunca a pergunta pelo dado que falta (`poll` devolve
      # `handle['pedido']` como entrega e `delivered_count` a conta, e era por ela que uma cotação
      # que só perguntou dados fechava dizendo "o que chegou está aqui em cima") e nunca a lista de
      # `entregues`, que é a intenção de quem publicou.
      it 'so afirma resultado quando o preco virou MENSAGEM na conversa' do
        expect(tool_do_motor.resultado_entregue?(handle_com_preco(chegou: true))).to be(true)
        expect(tool_do_motor.resultado_entregue?(handle_com_preco(chegou: false))).to be(false)
        expect(tool_do_motor.resultado_entregue?('pedido' => 'Me diga a placa, por favor.')).to be(false)
      end

      # A JANELA DO DEPLOY, GUARDADA (P1 da rodada 3). A execução que já estava em voo emitiu o
      # preço na versão anterior e não tem `entregas_de_preco` no handle — a chave nasce na passada
      # que emite. Sem ler a marca antiga, o fecho dela diz "nenhum preço chegou": nem comparativo,
      # nem uma palavra, para quem já recebeu preço. É o incidente de 08/09/2026 de volta, durante
      # a vida das execuções em voo.
      #
      # É a MESMA saída de `portal_fechado?`: a marca antiga vale como prova LEGADA, e só quando a
      # nova está AUSENTE. Guardado assim o fallback não alcança execução nenhuma posterior ao
      # deploy — toda passada que emite preço grava a chave, mesmo quando a publicação é recusada —,
      # então ele não reabre a frase falsa que a rodada 1 corrigiu.
      it 'cai para `entregues` so quando a chave da identidade esta AUSENTE do handle' do
        # legado: a marca antiga é a única prova que a linha em voo carrega
        expect(tool_do_motor.resultado_entregue?(described_class::DELIVERED_KEY => ['43'])).to be(true)
        # com a chave nova presente, quem responde é a MENSAGEM — o legado não reabre a frase falsa
        expect(tool_do_motor.resultado_entregue?(handle_com_preco(chegou: false))).to be(false)
        # e `submeter` grava `entregues => []` desde a primeira passada: lista vazia não é preço
        expect(tool_do_motor.resultado_entregue?(described_class::DELIVERED_KEY => [])).to be(false)
      end

      # E SOBRA NÃO É "SEMPRE", POR MAIS QUE O ENCERRAMENTO SÓ EXISTA FORA DO CAMINHO FELIZ. Quem
      # prova que o portal fechou é `portal_fechado`, gravado no ramo `done` de `build_progress`
      # depois do `return … unless finished?(result)`. O que separa essa execução de um desfecho
      # feliz é só o `finish!('done')` que vem DEPOIS do `record_attempt!` — morto o worker entre os
      # dois, a linha fica `running` com a chave no banco e o varredor a encerra. Afirmar sobra ali
      # é dizer "algumas seguradoras não responderam a tempo" a quem recebeu preços E comparativo.
      it 'nao afirma sobra quando o portal fechou e nada ficou por chegar' do
        expect(tool_do_motor.resta_entregar?('quote_id' => 'abc:1')).to be(true)
        expect(tool_do_motor.resta_entregar?('quote_id' => 'abc:1', fechado => true)).to be(false)
      end

      # O COMPARATIVO EMITIDO QUE NÃO CHEGOU É SOBRA — e a sentinela não sabe disso: ela é gravada
      # quando a entrega sai da ferramenta, antes de o publicador dizer se a mensagem entrou. Com a
      # publicação recusada, o fecho calava sobre um comparativo que faltou (Codex).
      it 'afirma sobra quando o comparativo saiu da ferramenta e nao virou mensagem' do
        token = Autonomia::Agents::Tools::EntregaPublicada.token_de(run, 'Comparativo: https://exemplo.test/c.pdf')
        handle = { fechado => true, described_class::PDF_SENT_KEY => true,
                   described_class::COMPARATIVO_KEY => token }

        expect(tool_do_motor.resta_entregar?(handle)).to be(true)
        expect(tool_do_motor.resta_entregar?(handle.merge(
                                               described_class::COMPARATIVO_KEY => ja_publicado('Comparativo: https://exemplo.test/c.pdf')
                                             ))).to be(false)
      end

      # E O PORTAL PODE FECHAR SEM COMPARATIVO NENHUM: geração indisponível, portal sem arquivo. Aí
      # `comparativo_enviado` nunca é gravado — e ler a ausência dela como "ainda tem seguradora por
      # responder" é a frase de atraso dita a quem já recebeu tudo o que ia chegar (Codex).
      it 'nao afirma sobra quando o portal fechou sem gerar comparativo' do
        expect(tool_do_motor.resta_entregar?('quote_id' => 'abc:1', fechado => true)).to be(false)
      end

      # NÃO-REGRESSÃO DA JANELA DO DEPLOY: a execução que já estava voando não tem `portal_fechado`
      # no handle, e a única prova que ela carrega é `comparativo_enviado` — gravada no MESMO ramo
      # `done`. Sem lê-la, quem atravessou o deploy com tudo entregue fecharia com a frase falsa.
      it 'aceita o comparativo_enviado como prova do fechamento nas linhas que atravessam o deploy' do
        expect(tool_do_motor.resta_entregar?('quote_id' => 'abc:1',
                                             described_class::PDF_SENT_KEY => true)).to be(false)
      end
    end

    it 'never sends the PDF twice' do
      # Arrange
      allow(connector).to receive(:quote_result).and_return(
        result('completed', [offer('43', 'Ezze', 'quoted', 2050.40)])
      )
      handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['43'],
                 described_class::PDF_SENT_KEY => true }

      # Act
      progress = tool.poll(handle: handle, attempt: 6)

      # Assert
      expect(progress.deliveries).to be_empty
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'does not print a comparison when nobody quoted' do
      # Arrange — sem preço não há o que comparar
      allow(connector).to receive(:quote_result).and_return(
        result('failed', [offer('47', 'Justos', 'declined')])
      )

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 4)

      # Assert
      expect(progress.deliveries).to be_empty
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'keeps the prices when the PDF fails to generate' do
      # Arrange — um PDF que não sai não pode apagar preços que já chegaram
      allow(connector).to receive(:quote_result).and_return(
        result('completed', [offer('43', 'Ezze', 'quoted', 2050.40)])
      )
      allow(connector).to receive(:quote_proposal).and_raise(StandardError, 'print fora do ar')

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 4)

      # Assert
      expect(progress).to be_done
      expect(progress.deliveries.join).to include('Ezze')
      expect(progress.deliveries.join).not_to include('Comparativo')
    end

    it 'fails loudly when the handle lost the quote id' do
      # Act
      progress = tool.poll(handle: {}, attempt: 0)

      # Assert
      expect(progress).to be_failed
      expect(progress.failure_code).to eq('sem_id_de_cotacao')
    end
  end

  describe '.available_for?' do
    it 'is offered only when the broker has a connection ready' do
      # Arrange / Act / Assert
      expect(described_class.available_for?(agent)).to be(false)
      ready_connection
      expect(described_class.available_for?(agent)).to be(true)
    end
  end

  # CRITÉRIO 4.5 — problema de credencial de seguradora nunca chega ao cliente final; vai para a
  # tela de Conexões.
  describe 'credencial de seguradora (4.5)' do
    def polling_com(offers)
      conexao = ready_connection
      connector = instance_double(
        Autonomia::Insurance::Connector::Mock,
        quote_result: { 'status' => 'running', 'offers' => offers }
      )
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      [conexao, tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 1)]
    end

    it 'registra na conexão a seguradora que recusou o login da corretora' do
      # Arrange / Act
      conexao, = polling_com([offer('5', 'Allianz', 'auth_required'),
                              offer('8', 'Porto', 'quoted', 1200.0)])

      # Assert
      pendentes = conexao.reload.insurers_pending_auth
      expect(pendentes['codes']).to eq(['5'])
      expect(pendentes['names']).to eq(['Allianz'])
      expect(pendentes['observed_at']).to be_present
    end

    it 'nunca conta a seguradora com credencial recusada ao cliente' do
      # Arrange / Act — o cliente não tem o que fazer com isso, e não é recusa de risco
      _, progresso = polling_com([offer('5', 'Allianz', 'auth_required'),
                                  offer('8', 'Porto', 'quoted', 1200.0)])

      # Assert
      texto = progresso.deliveries.join("\n")
      expect(texto).to include('Porto')
      expect(texto).not_to include('Allianz')
      expect(texto.downcase).not_to include('credencial')
    end

    it 'limpa o registro quando as seguradoras voltam a cotar' do
      # Arrange
      conexao = ready_connection
      conexao.record_insurers_pending_auth!(['5'], nomes: ['Allianz'])
      connector = instance_double(
        Autonomia::Insurance::Connector::Mock,
        quote_result: { 'status' => 'running', 'offers' => [offer('5', 'Allianz', 'quoted', 900.0)] }
      )
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)

      # Act
      tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 1)

      # Assert
      expect(conexao.reload.insurers_pending_auth).to be_nil
    end
  end

  # CRITÉRIO 5.5 — valor com tipo, unidade e moeda exatos, distinguindo o total da parcela.
  #
  # "Porto Seguro: R$ 2.167,00" não diz se é o ano ou o mês, e o cliente lê pelo que lhe convém.
  # Errar isso para baixo é o lado que fecha venda e depois vira reclamação.
  describe 'o preço diz o que ele é (5.5)' do
    def progresso_para(*ofertas)
      ready_connection
      connector = instance_double(
        Autonomia::Insurance::Connector::Mock,
        quote_result: { 'status' => 'running', 'offers' => ofertas }
      )
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 1)
    end

    def oferta(code, name, premium)
      { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted', 'premium' => premium }
    end

    def texto_para(premium)
      progresso_para(oferta('8', 'Porto', premium)).deliveries.join("\n")
    end

    # O motivo que o adapter ESCREVIA para a Bp Assinatura na renovação real de 11/09/2026, quando
    # ainda a dava como `unknown` (antes de ler o `packageType=1`). Fica como exemplo de motivo de
    # oferta sem período; a Bp real hoje sai `monthly` (`motivo_mensal`).
    def motivo_bp
      'parcelamentos=[] (vazio): o portal nao ofereceu plano de pagamento; ' \
        'premioMensal=29.30 e premio/12 (derivado pelo portal, nao distingue periodo)'
    end

    # O motivo da assinatura mensal desde a noite de 11/09/2026: o marcador é do portal, e o PDF do
    # comparativo anexado na mesma conversa imprimia "R$ 298,43 por mês".
    def motivo_mensal(mensal = '24.87')
      # A string é a do adapter (autonomia-adapters#57), verbatim; `mensal` é premio/12 daquele valor.
      'packageType=1 (assinatura mensal: o relatorio do portal imprime "por mes"); ' \
        "parcelamentos=[] (assinatura nao parcela); premioMensal=#{mensal} e premio/12 (derivado pelo portal, nao distingue periodo)"
    end

    it 'diz o total e o parcelamento quando o portal informou os dois' do
      # Arrange / Act
      texto = texto_para({ 'amount' => 2167.0, 'currency' => 'BRL', 'basis' => 'total',
                           'installments' => { 'count' => 10, 'amount' => 216.7 } })

      # Assert
      expect(texto).to include('R$ 2.167,00 no total')
      expect(texto).to include('10x de R$ 216,70')
    end

    it 'diz apenas o total quando não há parcelamento' do
      # Arrange / Act
      texto = texto_para({ 'amount' => 980.0, 'currency' => 'BRL', 'basis' => 'total' })

      # Assert
      expect(texto).to include('R$ 980,00 no total')
    end

    it 'NÃO inventa período quando o portal não deu como derivar' do
      # Arrange / Act
      texto = texto_para({ 'amount' => 2167.0, 'currency' => 'BRL', 'basis' => 'unknown' })

      # Assert
      expect(texto).to include('*Porto* — R$ 2.167,00')
      expect(texto).not_to include('R$ 2.167,00 no total')
      expect(texto.downcase).not_to include('por mês')
      expect(texto.downcase).not_to include('ao ano')
      # A ressalva agora cola NA OFERTA a que pertence, em vez de virar parágrafo do bloco — mas
      # continua saindo uma vez só para esta oferta.
      expect(texto.scan('não informou se é o total').size).to eq(1)
    end

    # ENTREGA 13, termo 1 — o motivo fica REGISTRADO na execução, por seguradora, e é o que o
    # adapter escreveu (qual campo do portal faltou ou veio ambíguo). Consulta:
    # `autonomia_agent_tool_runs.handle->'preco_sem_periodo'`.
    it 'registra no handle, por seguradora, o motivo do adapter para o preço sem período' do
      # Arrange / Act
      progresso = progresso_para(
        oferta('55', 'Bp Assinatura', { 'amount' => 351.59, 'currency' => 'BRL', 'basis' => 'unknown',
                                        'basis_evidence' => motivo_bp }),
        oferta('8', 'Porto', { 'amount' => 1321.25, 'currency' => 'BRL', 'basis' => 'total',
                               'basis_evidence' => 'parcelas=10 x premioDemaisParc=132.12' })
      )

      # Assert
      expect(progresso.handle['preco_sem_periodo']).to eq('55' => motivo_bp)
      expect(progresso.handle['entregues']).to contain_exactly('55', '8')
    end

    it 'nao escreve a chave do registro quando toda oferta tem periodo' do
      progresso = progresso_para(oferta('8', 'Porto', { 'amount' => 980.0, 'currency' => 'BRL', 'basis' => 'total' }))

      expect(progresso.handle).not_to have_key('preco_sem_periodo')
    end

    it 'acumula o registro entre lotes, sem apagar o do lote anterior' do
      ready_connection
      connector = instance_double(
        Autonomia::Insurance::Connector::Mock,
        quote_result: { 'status' => 'running',
                        'offers' => [oferta('47', 'Justos', { 'amount' => 134.5, 'basis' => 'unknown',
                                                              'basis_evidence' => 'parcelamentos=[] (vazio)' })] }
      )
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)

      progresso = tool.poll(handle: { 'quote_id' => 'abc:1', 'entregues' => ['55'],
                                      'preco_sem_periodo' => { '55' => motivo_bp } }, attempt: 2)

      expect(progresso.handle['preco_sem_periodo']).to eq('55' => motivo_bp, '47' => 'parcelamentos=[] (vazio)')
    end

    # ENTREGA 13, termo 5 — no texto de um lote, o preço sem período nunca aparece na frente de um
    # total pelo número cru: 351,59 sem período não é "mais barato" que 1.321,25 no total.
    it 'no lote, o preço sem período vem depois dos totais, mesmo com número menor' do
      texto = progresso_para(
        oferta('55', 'Bp Assinatura', { 'amount' => 351.59, 'currency' => 'BRL', 'basis' => 'unknown',
                                        'basis_evidence' => motivo_bp }),
        oferta('8', 'Porto', { 'amount' => 1321.25, 'currency' => 'BRL', 'basis' => 'total' })
      ).deliveries.join("\n")

      expect(texto.index('Porto')).to be < texto.index('Bp Assinatura')
    end

    # ASSINATURA MENSAL (11/09/2026, noite) — o cliente lia "R$ 298,43 — a seguradora não informou se
    # é o total ou uma parcela" enquanto o PDF do portal, na mesma conversa, dizia "por mês". Com o
    # adapter lendo o `packageType=1`, o cliente lê "por mês", e a oferta NÃO entra no registro de
    # sem período: o portal informou, e o handle não pode dizer o contrário.
    it 'no lote, a assinatura mensal sai "por mês" e não entra no registro de sem período' do
      # Arrange / Act
      progresso = progresso_para(
        oferta('55', 'Bp Assinatura', { 'amount' => 298.43, 'currency' => 'BRL', 'basis' => 'monthly',
                                        'basis_evidence' => motivo_mensal }),
        oferta('8', 'Porto', { 'amount' => 1321.25, 'currency' => 'BRL', 'basis' => 'total' })
      )
      texto = progresso.deliveries.join("\n")

      # Assert
      expect(texto).to include('*Bp Assinatura* — R$ 298,43 por mês')
      expect(texto).not_to include('não informou se é o total')
      expect(progresso.handle).not_to have_key('preco_sem_periodo')
      expect(progresso.handle['entregues']).to contain_exactly('55', '8')
    end

    # Períodos diferentes não se comparam pelo número cru: 298,43 por mês não é "mais barato" que
    # 1.321,25 no total, e ×12 seria um número nosso. Bloco dos mensais depois dos totais, antes dos
    # sem período.
    it 'no lote, a mensal vem depois dos totais e antes dos sem período' do
      texto = progresso_para(
        oferta('999', 'Seguradora Exemplo', { 'amount' => 10.0, 'currency' => 'BRL', 'basis' => 'unknown' }),
        oferta('55', 'Bp Assinatura', { 'amount' => 298.43, 'currency' => 'BRL', 'basis' => 'monthly',
                                        'basis_evidence' => motivo_mensal }),
        oferta('8', 'Porto', { 'amount' => 1321.25, 'currency' => 'BRL', 'basis' => 'total' })
      ).deliveries.join("\n")

      expect(texto.index('Porto')).to be < texto.index('Bp Assinatura')
      expect(texto.index('Bp Assinatura')).to be < texto.index('Seguradora Exemplo')
    end
  end

  # Achado do revisor: a guarda comparava `atual.is_a?(Hash)`, e `nil.is_a?(Hash)` e falso — entao o
  # caminho feliz (nunca houve pendencia e continua nao havendo) gravava nil sobre nil a cada
  # consulta. Sao 20 a 25 consultas por cotacao.
  it 'nao escreve no banco quando nao ha nem passou a haver seguradora pendente' do
    # Arrange
    conexao = ready_connection
    connector = instance_double(
      Autonomia::Insurance::Connector::Mock,
      quote_result: { 'status' => 'running', 'offers' => [offer('8', 'Porto', 'quoted', 1200.0)] }
    )
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    antes = conexao.reload.updated_at

    # Act — tres consultas seguidas, como o polling faz
    3.times { tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 1) }

    # Assert
    expect(conexao.reload.updated_at).to eq(antes)
  end
end
