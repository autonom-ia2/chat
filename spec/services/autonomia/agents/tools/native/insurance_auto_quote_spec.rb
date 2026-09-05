require 'rails_helper'

# A primeira ferramenta ASSÍNCRONA de verdade. O que estes exemplos travam é o CONTRATO com o
# cliente: o que ele lê, o que ele nunca lê, e por que a segunda mensagem se anuncia como
# complemento em vez de parecer uma cotação nova.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceAutoQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:params) { { 'cpf' => '042.979.126-78', 'placa' => 'TYV8I74', 'cep' => '31110-210' } }
  let(:tool) { described_class.new(agent: agent, params: params) }

  before { enable_test_encryption! }

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def ready_connection
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com',
                                                      password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def offer(code, name, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status }
    amount ? base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL' }) : base
  end

  it 'is asynchronous, because a quote takes minutes and the turn cannot wait' do
    expect(described_class.async?).to be(true)
  end

  describe '#start' do
    it 'submits and keeps the quote id for the polling that follows' do
      # Arrange
      ready_connection
      connector = instance_double(Autonomia::Insurance::Connector::Mock,
                                  quote_start: { 'quote_id' => 'abc:1', 'status' => 'queued' })
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)

      # Act
      handle = tool.start

      # Assert
      expect(handle['quote_id']).to eq('abc:1')
      expect(handle[described_class::DELIVERED_KEY]).to eq([])
      expect(connector).to have_received(:quote_start).with(
        hash_including(product: 'auto',
                       input: hash_including('insured' => { 'document' => '04297912678' },
                                             'vehicle' => { 'plate' => 'TYV8I74' }))
      )
    end

    # RENOVAÇÃO. O portal cobra menos de quem já tem seguro, e a conta sai destes três campos. Sem
    # eles a renovação era cotada como primeira apólice — mais cara, e o comparativo perdia para o
    # preço que o cliente já paga.
    context 'when o cliente está renovando' do
      it 'não manda `quotation` numa cotação nova, para o adapter usar os próprios padrões' do
        # Arrange
        ready_connection
        connector = instance_double(Autonomia::Insurance::Connector::Mock,
                                    quote_start: { 'quote_id' => 'abc:1' })
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
        connector = instance_double(Autonomia::Insurance::Connector::Mock,
                                    quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        renovacao = described_class.new(agent: agent,
                                        params: params.merge('renovacao' => true, 'bonus' => 7,
                                                             'sinistros' => 1))

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
        connector = instance_double(Autonomia::Insurance::Connector::Mock,
                                    quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        sem_sinistro = described_class.new(agent: agent,
                                           params: params.merge('renovacao' => true, 'bonus' => 5,
                                                                'sinistros' => 0))

        # Act
        sem_sinistro.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]['quotation']['previousClaimsCount']).to eq(0)
        end
      end

      # String vazia é o modelo dizendo "não sei", não "zero". Sem esta distinção o portal receberia
      # `previousClaimsCount: 0` como se o cliente tivesse afirmado que não teve sinistro.
      it 'omite sinistros quando vem string vazia, que é ausência e não zero' do
        # Arrange
        ready_connection
        connector = instance_double(Autonomia::Insurance::Connector::Mock,
                                    quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        sem_resposta = described_class.new(agent: agent,
                                           params: params.merge('renovacao' => true,
                                                                'sinistros' => ''))

        # Act
        sem_resposta.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]['quotation']).to eq('isRenewal' => true)
        end
      end

      # O modelo manda o que o cliente disse, e o cliente diz "sim". Sem o cast, a string "true"
      # seria só um valor verdadeiro qualquer — e `false` como string entraria como renovação.
      it 'trata "false" como cotação nova, não como qualquer string verdadeira' do
        # Arrange
        ready_connection
        connector = instance_double(Autonomia::Insurance::Connector::Mock,
                                    quote_start: { 'quote_id' => 'abc:1' })
        allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
        nova = described_class.new(agent: agent, params: params.merge('renovacao' => 'false'))

        # Act
        nova.start

        # Assert
        expect(connector).to have_received(:quote_start) do |**kwargs|
          expect(kwargs[:input]).not_to have_key('quotation')
        end
      end
    end

    it 'strips the formatting the customer typed, because the portal wants digits' do
      # Arrange
      ready_connection
      captured = nil
      connector = instance_double(Autonomia::Insurance::Connector::Mock)
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
    let(:connector) { instance_double(Autonomia::Insurance::Connector::Mock) }

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
      expect(progress.deliveries.first)
        .to eq("Primeiros preços que chegaram:\nEzze: R$ 2050,40\nMapfre: R$ 2582,76")
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
      expect(progress.deliveries.first).to eq("Chegaram mais opções:\nDarwin: R$ 3407,87")
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

    it 'shows at most three options, because more turns into a table and stops helping' do
      # Arrange
      offers = [offer('1', 'A', 'quoted', 100), offer('2', 'B', 'quoted', 200),
                offer('3', 'C', 'quoted', 300), offer('4', 'D', 'quoted', 400)]
      allow(connector).to receive(:quote_result).and_return(result('completed', offers))

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 4)

      # Assert
      expect(progress.deliveries.first.lines.size).to eq(described_class::MAX_OFFERS + 1)
      expect(progress.deliveries.first).not_to include('D:')
    end

    it 'closes with the comparison PDF, one per quote, like the portal does' do
      # Arrange
      allow(connector).to receive(:quote_result).and_return(
        result('completed', [offer('43', 'Ezze', 'quoted', 2050.40)])
      )

      # Act
      progress = tool.poll(handle: { 'quote_id' => 'abc:1' }, attempt: 4)

      # Assert — a lista serve para decidir; o PDF é o que o cliente leva adiante
      expect(progress.deliveries.last).to include('Comparativo com todas as opções')
      expect(progress.deliveries.last).to include('https://exemplo.test/comparativo.pdf')
      expect(progress.handle[described_class::PDF_SENT_KEY]).to be(true)
      expect(connector).to have_received(:quote_proposal).with(hash_excluding(:insurer_code))
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
end
