require 'rails_helper'

# O cano da cotação: submeter, consultar e pegar a proposta. Uma cotação leva até ~90s, então o
# contrato é de DUAS fases — quem espera é o job assíncrono, nunca a chamada.
# rubocop:disable RSpec/DescribeClass -- o assunto é o CONTRATO de cotação, cumprido por duas
# implementações (Mock e Http); apontar para uma só delas descreveria menos do que o arquivo testa.
RSpec.describe 'Autonomia::Insurance::Connector quote' do
  let(:session) { { 'multicalculoToken' => 'multi' } }
  let(:mock) { Autonomia::Insurance::Connector::Mock.new }
  let(:input) { { 'placa' => 'ABC1D23', 'cpf' => '000.000.000-00' } }

  def start
    mock.quote_start(provider: 'agger', session: session, product: 'auto', input: input)
  end

  describe 'the mock, which is what lets the whole async path be tested without the portal' do
    it 'submits and returns immediately with an id to poll with' do
      # Act
      handle = start

      # Assert
      expect(handle['status']).to eq('queued')
      expect(handle['quote_id']).to be_present
    end

    it 'reports running while nothing has come back yet' do
      # Arrange
      handle = start

      # Act
      result = mock.quote_result(provider: 'agger', session: session, quote_id: handle['quote_id'])

      # Assert
      expect(result['status']).to eq('running')
      expect(result['offers']).to be_empty
    end

    it 'delivers a partial result before the slowest insurer answers' do
      # Arrange — é exatamente o caso que a entrega parcial existe para atender
      handle = start

      # Act
      result = travel(10.seconds) do
        mock.quote_result(provider: 'agger', session: session, quote_id: handle['quote_id'])
      end

      # Assert
      expect(result['status']).to eq('partial')
      expect(result['offers'].map { |offer| offer['insurer']['name'] }).to eq(['Porto Seguro', 'Mapfre'])
      expect(result['offers'].first['premium']).to eq('amount' => 1200.5, 'currency' => 'BRL')
    end

    it 'completes with every insurer once the slow one lands' do
      # Arrange
      handle = start

      # Act
      result = travel(30.seconds) do
        mock.quote_result(provider: 'agger', session: session, quote_id: handle['quote_id'])
      end

      # Assert
      expect(result['status']).to eq('completed')
      expect(result['offers'].size).to eq(3)
    end

    it 'hands back a proposal url' do
      # Arrange
      handle = start

      # Act
      proposal = mock.quote_proposal(provider: 'agger', session: session, quote_id: handle['quote_id'])

      # Assert
      expect(proposal['url']).to start_with('https://')
    end
  end

  describe 'guards' do
    it 'refuses to quote without an open session, like the real adapter' do
      expect { mock.quote_start(provider: 'agger', session: nil, product: 'auto', input: input) }
        .to raise_error(an_object_having_attributes(kind: :auth_required))
    end

    it 'refuses a branch that has no adapter yet instead of pretending' do
      expect { mock.quote_start(provider: 'agger', session: session, product: 'vida', input: input) }
        .to raise_error(an_object_having_attributes(kind: :not_implemented))
    end

    it 'refuses an unknown platform' do
      expect { mock.quote_result(provider: 'quiver', session: session, quote_id: 'x:1') }
        .to raise_error(an_object_having_attributes(kind: :not_implemented))
    end

    it 'refuses a quote without the one field the portal cannot resolve on its own' do
      # A placa é o que traz FIPE, ano, modelo e chassi. Sem ela não há o que cotar.
      expect { mock.quote_start(provider: 'agger', session: session, product: 'auto', input: {}) }
        .to raise_error(an_object_having_attributes(kind: :validation))
    end
  end

  describe 'the HTTP client, which is what talks to the real portal' do
    let(:client) { Autonomia::Insurance::Connector::Http.new }

    it 'sends the open session and the quote id on every quote call' do
      # Arrange
      captured = []
      allow(client).to receive(:invoke) do |path, payload|
        captured << [path, payload]
        {}
      end

      # Act
      client.quote_start(provider: 'agger', session: session, product: 'auto', input: input)
      client.quote_result(provider: 'agger', session: session, quote_id: 'abc:1')
      client.quote_proposal(provider: 'agger', session: session, quote_id: 'abc:1')

      # Assert
      expect(captured.map(&:first))
        .to eq(%w[/v1/agger/quote/start /v1/agger/quote/result /v1/agger/quote/proposal])
      expect(captured.map(&:last)).to all(include(session: session))
      expect(captured[1][1][:quoteId]).to eq('abc:1')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
