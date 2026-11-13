require 'rails_helper'

# #2934: a busca do "buscar informação em outro sistema". Só https, sem usuário no endereço, nunca rede interna (nem pelo
# nome que resolve para ela), sem seguir redirecionamento, prazo e tamanho curtos. O nome resolve uma vez só e a conexão
# vai para o IP conferido: o DNS que muda entre a conferência e a conexão (DNS rebinding) não alcança a rede interna.
RSpec.describe Autonomia::Automacao::ConsultaDeFora do
  let(:host) { 'loja.exemplo.com' }
  let(:url) { "https://#{host}/pedidos/10482?token=abc" }

  around { |exemplo| with_modified_env(FRONTEND_URL: 'https://app.plataforma.com') { exemplo.run } }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with(host).and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses).with('app.plataforma.com').and_return(['151.101.1.69'])
  end

  def responder(status: 200, corpo: { pedido: { status: 'enviado', previsao: '18/11' } })
    stub_request(:get, url).to_return(status: status, body: corpo.is_a?(String) ? corpo : corpo.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
  end

  describe '.problema_do_endereco' do
    it 'recusa o que não é https, o endereço com usuário e o nome interno, com a frase deste passo', :aggregate_failures do
      expect(described_class.problema_do_endereco('http://loja.exemplo.com/x')).to eq('consulta_so_https')
      expect(described_class.problema_do_endereco('nada disso')).to eq('consulta_so_https')
      expect(described_class.problema_do_endereco('https://eu:senha@loja.exemplo.com/x')).to eq('consulta_sem_senha_no_endereco')
      expect(described_class.problema_do_endereco('https://localhost/x')).to eq('consulta_endereco_interno')
      expect(described_class.problema_do_endereco('https://10.0.0.5/x')).to eq('consulta_endereco_interno')
      expect(described_class.problema_do_endereco(url)).to be_nil
    end
  end

  describe '#buscar' do
    it 'devolve os dados da resposta JSON' do
      responder

      resposta = described_class.new(url).buscar

      expect(resposta).to have_attributes(ok?: true, codigo: 200, dados: { 'pedido' => { 'status' => 'enviado', 'previsao' => '18/11' } })
    end

    it 'o nome que resolve para a rede interna não é chamado' do
      allow(Resolv).to receive(:getaddresses).with(host).and_return(['10.0.0.5'])
      pedido = responder

      expect(described_class.new(url).buscar.motivo).to eq('consulta_endereco_interno')
      expect(pedido).not_to have_been_requested
    end

    it 'o nome que resolve para a própria plataforma também não' do
      allow(Resolv).to receive(:getaddresses).with(host).and_return(['151.101.1.69'])

      expect(described_class.new(url).buscar.motivo).to eq('consulta_endereco_interno')
    end

    it 'DNS rebinding: resolve uma vez só e conecta no IP conferido, mesmo que o nome passe a apontar para dentro', :aggregate_failures do
      allow(Resolv).to receive(:getaddresses).with(host).and_return(['93.184.216.34'], ['10.0.0.5'])
      conectado = []
      allow(SafeFetch).to receive(:fetch).and_wrap_original do |original, endereco, **opcoes, &bloco|
        conectado.concat(opcoes[:resolver].call(host).map(&:to_s))
        original.call(endereco, **opcoes, &bloco)
      end
      responder

      expect(described_class.new(url).buscar).to be_ok
      expect(conectado).to eq(['93.184.216.34'])
      expect(Resolv).to have_received(:getaddresses).with(host).once
    end

    it 'erro do outro sistema, redirecionamento, resposta sem dados e falta de resposta viram o motivo', :aggregate_failures do
      responder(status: 500)
      expect(described_class.new(url).buscar).to have_attributes(motivo: 'consulta_recusada', codigo: 500)

      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://10.0.0.5/' })
      expect(described_class.new(url).buscar.ok?).to be(false)

      responder(corpo: '<html>oi</html>')
      expect(described_class.new(url).buscar.motivo).to eq('consulta_resposta_sem_dados')

      responder(corpo: '"só um texto"')
      expect(described_class.new(url).buscar.motivo).to eq('consulta_resposta_sem_dados')

      stub_request(:get, url).to_timeout
      expect(described_class.new(url).buscar.motivo).to eq('consulta_sem_resposta')
    end

    it 'resposta grande demais é recusada' do
      responder(corpo: { texto: 'x' * (described_class::RESPOSTA_MAXIMA + 10) })

      expect(described_class.new(url).buscar.motivo).to eq('consulta_resposta_grande')
    end
  end

  describe '.achatar e .valor_em' do
    let(:dados) { { 'pedido' => { 'status' => 'enviado', 'itens' => [{ 'nome' => 'Caneca' }], 'pago' => true, 'nada' => nil } } }

    it 'lista os dados simples com o caminho e lê o valor de um caminho, inclusive em lista', :aggregate_failures do
      expect(described_class.achatar(dados)).to eq([{ caminho: 'pedido.status', valor: 'enviado' },
                                                    { caminho: 'pedido.itens.0.nome', valor: 'Caneca' },
                                                    { caminho: 'pedido.pago', valor: true }])
      expect(described_class.valor_em(dados, 'pedido.itens.0.nome')).to eq('Caneca')
      expect(described_class.valor_em(dados, 'pedido.status.x')).to be_nil
      expect(described_class.valor_em(dados, 'pedido.itens.um')).to be_nil
    end
  end
end
