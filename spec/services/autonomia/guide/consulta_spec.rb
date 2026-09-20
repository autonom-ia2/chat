require 'rails_helper'

RSpec.describe Autonomia::Guide::Consulta do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:consulta) { described_class.new(account: conta, user: admin) }

  # Para os testes de RESUMO, o transporte é dublado de propósito: o que está
  # sendo medido ali é como a resposta é encurtada, não como ela chega. O
  # caminho de verdade tem os seus próprios testes, contra a aplicação real.
  def plataforma_responde(codigo, corpo)
    allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_return(
      instance_double(Autonomia::Guide::ChamadaInterna,
                      chamar: Autonomia::Guide::ChamadaInterna::Resposta.new(codigo: codigo, corpo: corpo))
    )
  end

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
    it 'recusa tentativa de sair do caminho da conta', :aggregate_failures do
      expect(consulta.ler('../../../admin/users')).to include('Não sei consultar isso')
      expect(consulta.ler('/api/v1/accounts/999/inboxes')).to include('Não sei consultar isso')
    end

    it 'recusa ler UM item sem saber qual, em vez de chutar' do
      expect(consulta.ler('contacts/:id')).to include('preciso saber qual id')
    end

    it 'não faz chamada nenhuma quando o recurso é recusado' do
      expect(Autonomia::Guide::ChamadaInterna).not_to receive(:new)

      consulta.ler('qualquer_coisa')
    end
  end

  # Estes NÃO dublam nada: a leitura passa pela pilha real do Rails — rota,
  # autenticação por token, controller, Pundit. Antes eram feitos contra um
  # dublê de `Net::HTTP`, e por isso mediam o pedido que EU montava em vez do
  # que a plataforma aceita.
  describe 'a leitura, contra a aplicação de verdade' do
    it 'traz o que existe na conta de quem perguntou' do
      create_crm_inbox(account: conta, name: 'Comercial', members: [admin])

      expect(consulta.ler('inboxes')).to include('Comercial')
    end

    it 'lê UM item pelo identificador' do
      contato = conta.contacts.create!(name: 'Fulano de Tal')

      expect(consulta.ler('contacts/:id', { id: contato.id })).to include('Fulano de Tal')
    end

    # O caminho é montado com o id DESTA conta, sempre; o valor do modelo entra
    # escapado, como um segmento, nunca como pedaço de rota.
    it 'não alcança dado de outra conta pelo identificador' do
      outra_conta, = create_account_and_user
      alheio = outra_conta.contacts.create!(name: 'Segredo Alheio')

      resposta = consulta.ler('contacts/:id', { id: "../../#{outra_conta.id}/contacts/#{alheio.id}" })

      expect(resposta).not_to include('Segredo Alheio')
    end

    it 'não derruba a resposta quando a chamada interna estoura' do
      allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_raise(StandardError, 'falhou')

      expect(consulta.ler('inboxes')).to include('Não consegui ler')
    end
  end

  describe 'o resumo da resposta' do
    it 'explica quando a plataforma nega, em vez de inventar resposta' do
      plataforma_responde('403', '{}')

      expect(consulta.ler('inboxes')).to include('respondeu 403')
    end

    it 'corta lista longa para não estourar o contexto' do
      plataforma_responde('200', { payload: Array.new(100) { |i| { name: "Caixa #{i}" } } }.to_json)

      expect(consulta.ler('inboxes').scan('"name"').size).to be <= described_class::MAX_ITENS
    end

    # Cortar em silêncio faz o modelo contar o pedaço: "você tem 25" para quem
    # tem 300. O total tem que sobreviver ao corte.
    it 'leva o total junto quando a plataforma informa, mesmo cortando a lista' do
      plataforma_responde('200',
                          { payload: Array.new(100) { |i| { name: "Contato #{i}" } }, meta: { count: 317 } }.to_json)

      expect(consulta.ler('contacts')).to include('total nesta conta: 317')
    end

    it 'avisa que não sabe o total quando a plataforma não informa e a lista encheu' do
      plataforma_responde('200', { payload: Array.new(100) { |i| { name: "Contato #{i}" } } }.to_json)

      expect(consulta.ler('contacts')).to include('NÃO afirme quantos são')
    end

    it 'não inventa aviso quando a lista cabe inteira', :aggregate_failures do
      plataforma_responde('200', { payload: [{ name: 'Comercial' }, { name: 'Suporte' }] }.to_json)

      expect(consulta.ler('inboxes')).not_to include('total nesta conta')
      expect(consulta.ler('inboxes')).not_to include('NÃO afirme')
    end

    # Medido em produção: uma caixa de entrada pesa ~3.000 bytes (43 campos).
    # Com o orçamento antigo de 6.000 cabia UMA, e o Guia dizia "apareceu uma
    # caixa" para quem tem três — honesto, porque avisava do corte, e inútil.
    it 'cabe a conta real de quem tem várias caixas pesadas' do
      pesadas = Array.new(3) { |i| { name: "Caixa #{i}", campos: 'x' * 2_900 } }
      plataforma_responde('200', { payload: pesadas }.to_json)

      resposta = consulta.ler('inboxes')

      expect(resposta).to include('Caixa 0', 'Caixa 1', 'Caixa 2')
    end

    # Um objeto cortado no meio vira uma lista que PARECE inteira: o modelo conta
    # o pedaço e responde "você tem 5 caixas" para quem tem 8. O corte é por
    # item, e o que ficou de fora é sempre dito.
    it 'nunca corta um item no meio' do
      grandes = Array.new(40) { |i| { name: "Caixa #{i}", descricao: 'x' * 400 } }
      plataforma_responde('200', { payload: grandes }.to_json)

      resposta = consulta.ler('inboxes')

      expect { JSON.parse(resposta[0, resposta.rindex(']') + 1]) }.not_to raise_error
    end
  end
end
