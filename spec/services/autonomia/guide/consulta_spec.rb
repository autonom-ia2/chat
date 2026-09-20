require 'rails_helper'

RSpec.describe Autonomia::Guide::Consulta do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:consulta) { described_class.new(account: conta, user: admin) }

  describe 'o catálogo' do
    # Cobertura escrita à mão nunca vira cobertura da plataforma: o catálogo sai
    # do roteador, como o mapa do Guia.
    it 'nasce do roteador e cobre a plataforma, não uma lista escolhida' do
      expect(consulta.catalogo.size).to be > 250
      expect(consulta.catalogo).to include('inboxes', 'labels', 'crm/pipelines', 'conversations', 'teams')
    end

    # Cortar as rotas com `:id` tirava metade da leitura da plataforma: o Guia
    # listava as caixas e não conseguia abrir nenhuma.
    it 'inclui a leitura de UM item, não só as listas' do
      expect(consulta.catalogo).to include('contacts/:id', 'inboxes/:id')
    end
  end

  describe 'o que ele recusa' do
    it 'recusa recurso fora do catálogo, em vez de tentar adivinhar' do
      expect(consulta.ler('contas_de_outra_empresa')).to include('Não sei consultar isso')
    end

    # A superfície é fechada pelo catálogo: não adianta escapar com caminho relativo.
    it 'recusa tentativa de sair do caminho da conta' do
      expect(consulta.ler('../../../admin/users')).to include('Não sei consultar isso')
      expect(consulta.ler('/api/v1/accounts/999/inboxes')).to include('Não sei consultar isso')
    end

    it 'recusa ler UM item sem saber qual, em vez de chutar' do
      expect(consulta.ler('contacts/:id')).to include('preciso saber qual id')
    end

    it 'não deixa o identificador sair da conta' do
      capturada = nil
      allow(Net::HTTP).to receive(:start) do |_host, _porta, _opcoes, &bloco|
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) do |req|
          capturada = req
          instance_double(Net::HTTPResponse, code: '200', body: '[]')
        end
        bloco.call(http)
      end

      consulta.ler('contacts/:id', { id: '../../999/contacts' })

      expect(capturada.path).to start_with("/api/v1/accounts/#{conta.id}/contacts/")
      expect(capturada.path).not_to include('999/contacts')
    end

    it 'não faz chamada nenhuma quando o recurso é recusado' do
      expect(Net::HTTP).not_to receive(:start)

      consulta.ler('qualquer_coisa')
    end
  end

  describe 'a leitura' do
    def responder(codigo, corpo)
      resposta = instance_double(Net::HTTPResponse, code: codigo, body: corpo)
      allow(Net::HTTP).to receive(:start).and_return(resposta)
    end

    it 'vai pela API da conta, com o token de quem perguntou' do
      requisicao_capturada = nil
      allow(Net::HTTP).to receive(:start) do |_host, _porta, _opcoes, &bloco|
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) do |req|
          requisicao_capturada = req
          instance_double(Net::HTTPResponse, code: '200', body: '[]')
        end
        bloco.call(http)
      end

      consulta.ler('inboxes')

      expect(requisicao_capturada.path).to eq("/api/v1/accounts/#{conta.id}/inboxes")
      expect(requisicao_capturada['api_access_token']).to eq(admin.access_token.token)
    end

    # A porta vem do processo, não de um palpite: fixa em 3000, uma mudança de
    # porta faria toda leitura falhar em silêncio.
    it 'chama a porta em que o Rails está de fato escutando' do
      porta_capturada = nil
      allow(Net::HTTP).to receive(:start) do |_host, porta, _opcoes, &bloco|
        porta_capturada = porta
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request).and_return(instance_double(Net::HTTPResponse, code: '200', body: '[]'))
        bloco.call(http)
      end

      with_modified_env PORT: '4001' do
        consulta.ler('inboxes')
      end

      expect(porta_capturada).to eq(4001)
    end

    it 'devolve o conteúdo que a API entregou' do
      responder('200', '{"payload":[{"name":"Comercial"}]}')

      expect(consulta.ler('inboxes')).to include('Comercial')
    end

    it 'explica quando a plataforma nega, em vez de inventar resposta' do
      responder('403', '{}')

      expect(consulta.ler('inboxes')).to include('respondeu 403')
    end

    it 'corta lista longa para não estourar o contexto' do
      muitos = Array.new(100) { |i| { name: "Caixa #{i}" } }
      responder('200', { payload: muitos }.to_json)

      expect(consulta.ler('inboxes').scan(/Caixa \d+/).size).to be <= described_class::MAX_ITENS
    end

    # Cortar em silêncio faz o modelo contar o pedaço: "você tem 25" para quem
    # tem 300. O total tem que sobreviver ao corte.
    it 'leva o total junto quando a plataforma informa, mesmo cortando a lista' do
      muitos = Array.new(100) { |i| { name: "Contato #{i}" } }
      responder('200', { payload: muitos, meta: { count: 317 } }.to_json)

      expect(consulta.ler('contacts')).to include('total nesta conta: 317')
    end

    it 'avisa que não sabe o total quando a plataforma não informa e a lista encheu' do
      muitos = Array.new(100) { |i| { name: "Contato #{i}" } }
      responder('200', { payload: muitos }.to_json)

      expect(consulta.ler('contacts')).to include('NÃO afirme quantos são')
    end

    it 'não inventa aviso quando a lista cabe inteira' do
      responder('200', { payload: [{ name: 'Comercial' }, { name: 'Suporte' }] }.to_json)

      expect(consulta.ler('inboxes')).not_to include('total nesta conta')
      expect(consulta.ler('inboxes')).not_to include('NÃO afirme')
    end

    it 'não derruba a resposta quando a plataforma devolve algo inesperado' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect(consulta.ler('inboxes')).to include('Não consegui ler')
    end
  end
end
