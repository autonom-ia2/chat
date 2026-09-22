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
    # Explica, mas em português de gente: o número do status fica no log, não na
    # tela de quem está tentando trabalhar.
    it 'explica quando a plataforma nega, sem mostrar o código', :aggregate_failures do
      plataforma_responde('403', '{}')

      resposta = consulta.ler('inboxes')

      expect(resposta).to include('não tem acesso a isto')
      expect(resposta).not_to include('403')
    end

    it 'corta lista longa para não estourar o contexto' do
      plataforma_responde('200', { payload: Array.new(100) { |i| { name: "Caixa #{i}" } } }.to_json)

      expect(consulta.ler('inboxes').scan('"name"').size).to be <= Autonomia::Guide::Resumo::MAX_ITENS
    end

    # Cortar em silêncio faz o modelo contar o pedaço: "você tem 25" para quem
    # tem 300. O total tem que sobreviver ao corte.
    it 'leva o total junto quando a plataforma informa, mesmo cortando a lista' do
      plataforma_responde('200',
                          { payload: Array.new(100) { |i| { name: "Contato #{i}" } }, meta: { count: 317 } }.to_json)

      expect(consulta.ler('contacts')).to include('317 no total')
    end

    # Sem o total da plataforma, ninguém aqui sabe se a lista veio inteira ou se
    # é uma página. O Guia diz quantos recebeu e proíbe tratar isso como total.
    it 'responde com o número recebido quando a plataforma não informa o total' do
      plataforma_responde('200', { payload: Array.new(100) { |i| { name: "Contato #{i}" } } }.to_json)

      expect(consulta.ler('contacts')).to include('Diga quantos são')
    end

    # Cada recurso chama o total dele de um jeito. Com só `count` e `all_count`,
    # artigos e portais diziam "não sei quantos" com o número na mão.
    it 'entende o total com qualquer um dos nomes que a plataforma usa', :aggregate_failures do
      { 'articles_count' => 57, 'portals_count' => 9, 'total_count' => 31 }.each do |chave, valor|
        plataforma_responde('200', { payload: [{ name: 'x' }], meta: { chave => valor } }.to_json)

        expect(consulta.ler('portals')).to include("#{valor} no total")
      end
    end

    # Tirar o segredo de dentro de um objeto deixava a casca vazia no lugar. Na
    # LISTA isso não aparece, porque objeto aninhado já cai por forma — o
    # desperdício estava na leitura de UM item, que vai inteira.
    it 'não deixa casca vazia onde tirou o segredo, na leitura de um item', :aggregate_failures do
      item = { 'id' => 1, 'name' => 'Caixa', 'config' => { 'api_key' => 'x' },
               'outros' => { 'api_key' => 'y', 'cor' => 'azul' } }
      plataforma_responde('200', item.to_json)

      resposta = consulta.ler('inboxes/:id', { id: 1 })

      expect(resposta).not_to include('"config"')
      expect(resposta).to include('azul')
      expect(resposta).not_to include('api_key')
    end

    # Quando o corte é NOSSO, a frase tem que ser outra: sobrou coisa de fora.
    it 'diz quando foi ele que cortou, e quanto ficou de fora' do
      # Item grande feito de campos pequenos: campo acima do teto cai sozinho, e
      # o que precisa estourar aqui é o orçamento da LISTA, não o do campo.
      gordos = Array.new(100) do |i|
        { name: "Contato #{i}" }.merge((1..20).to_h { |n| ["nota#{n}", 'x' * 300] })
      end
      plataforma_responde('200', { payload: gordos }.to_json)

      expect(consulta.ler('contacts')).to include('o resto ficou de fora')
    end

    it 'não inventa aviso quando a lista cabe inteira', :aggregate_failures do
      plataforma_responde('200', { payload: [{ name: 'Comercial' }, { name: 'Suporte' }] }.to_json)

      expect(consulta.ler('inboxes')).not_to include('no total desta conta')
      expect(consulta.ler('inboxes')).not_to include('NÃO afirme')
    end

    # Medido em produção: uma caixa de entrada pesa ~3.000 bytes em 43 campos.
    # Com o orçamento antigo cabia UMA, e o Guia dizia "apareceu uma caixa" para
    # quem tem três. Aumentar o orçamento só adiava o problema para quem tem
    # dez; o que resolve é não mandar o que não identifica nada.
    it 'cabe a conta de quem tem muitas caixas pesadas', :aggregate_failures do
      pesadas = Array.new(20) do |i|
        { id: i, name: "Caixa #{i}", channel_type: 'Channel::Whatsapp', phone_number: "+55119#{i}",
          provider_config: { api_key: 'segredo', webhook: 'x' }, greeting_message: 'y' * 300,
          business_name: nil, medium: '' }
      end
      plataforma_responde('200', { payload: pesadas }.to_json)

      resposta = consulta.ler('inboxes')

      expect(resposta).to include('Caixa 0', 'Caixa 19')
      expect(resposta).not_to include('NÃO afirme quantos são')
    end

    # O que some é o que não distingue um item do outro: vazio e texto longo.
    # O valor simples que está aninhado SOBE, com o caminho no nome — é assim
    # que o nome do cliente (`meta.sender.name`) sobrevive numa conversa.
    it 'tira o que não identifica e sobe o que identifica', :aggregate_failures do
      plataforma_responde('200', { payload: [{ name: 'Comercial', meta: { sender: { name: 'Joana' } },
                                               vazio: nil, texto: 'z' * 2_500 }] }.to_json)

      # Só os ITENS: a nota de campos disponíveis cita os nomes de propósito.
      itens = consulta.ler('inboxes').split(' [NOTA INTERNA').first

      expect(itens).to include('Comercial')
      expect(itens).to include('Joana')
      expect(itens).not_to include('vazio')
      expect(itens).not_to include('z' * 2_001)
    end

    # Um card do CRM traz cliente, funil e caixa em objetos aninhados. Com o
    # teto por item em 800 ele estourava por dezesseis caracteres e perdia os
    # três nomes de uma vez: "quais negócios eu tenho" respondia títulos soltos,
    # sem cliente e sem funil.
    it 'mantém cliente, funil e caixa num card do CRM', :aggregate_failures do
      card = { 'id' => 1, 'title' => 'Negócio grande', 'description' => 'x' * 120,
               'contact' => { 'id' => 9, 'name' => 'João Pedro da Silva Santos' },
               'inbox' => { 'id' => 3, 'name' => 'Caixa Comercial WhatsApp' },
               'pipeline' => { 'id' => 2, 'name' => 'Funil de Vendas Novo' } }
      plataforma_responde('200', { payload: [card] }.to_json)

      resposta = consulta.ler('crm/cards')

      expect(resposta).to include('João Pedro')
      expect(resposta).to include('Caixa Comercial')
      expect(resposta).to include('Funil de Vendas')
    end

    # Um objeto cortado no meio vira uma lista que PARECE inteira: o modelo conta
    # o pedaço e responde "você tem 5 caixas" para quem tem 8. O corte é por
    # item, e o que ficou de fora é sempre dito.
    it 'nunca corta um item no meio' do
      grandes = Array.new(40) { |i| { name: "Caixa #{i}", descricao: 'x' * 400 } }
      plataforma_responde('200', { payload: grandes }.to_json)

      resposta = consulta.ler('inboxes')

      expect { JSON.parse(resposta.split(' [NOTA INTERNA').first) }.not_to raise_error
    end
  end

  # #593 — em 22/09/2026 o Guia disse a um cliente que a caixa WhatsApp Comercial
  # estava no funil Renovações. Não foi o modelo inventando: duas leituras
  # devolveram dado errado sem avisar. Os dois casos aqui são os de verdade,
  # contra a aplicação.
  describe 'nada some calado da leitura' do
    around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

    let(:auto) { create_crm_pipeline(account: conta, user: admin, name: 'Seguro Auto').first }
    let(:renovacoes) { create_crm_pipeline(account: conta, user: admin, name: 'Renovações').first }

    # Pedindo `name` às caixas de um funil (que têm `inbox.name`), o item voltava
    # só com `{"id":N}` — o id da LIGAÇÃO, que o modelo tomou pelo da caixa.
    it 'avisa qual campo pedido não existe e quais existem', :aggregate_failures do
      caixa = create_crm_inbox(account: conta, name: 'Email Renovação', members: [admin])
      conta.crm_pipeline_inboxes.create!(pipeline: renovacoes, inbox: caixa, created_by: admin)

      resposta = consulta.ler('crm/pipelines/:pipeline_id/inboxes', { 'pipeline_id' => renovacoes.id }, {},
                              campos: %w[id name])

      expect(resposta).to include('NÃO existem neste recurso e não vieram: name')
      expect(resposta).to include('inbox.name')
    end

    it 'não inventa aviso quando todos os campos pedidos existem' do
      caixa = create_crm_inbox(account: conta, name: 'Email Renovação', members: [admin])
      conta.crm_pipeline_inboxes.create!(pipeline: renovacoes, inbox: caixa, created_by: admin)

      resposta = consulta.ler('crm/pipelines/:pipeline_id/inboxes', { 'pipeline_id' => renovacoes.id }, {},
                              campos: %w[inbox_id inbox.name])

      expect(resposta).not_to include('NÃO existem')
    end

    # O kanban lê `?pipeline_id=`. Antes o parâmetro era jogado fora e vinha o
    # funil padrão — o Guia pediu o 10 e recebeu o 8.
    it 'leva o parâmetro que não é do caminho como filtro, e traz o funil pedido', :aggregate_failures do
      auto
      resposta = consulta.ler('crm/kanban', { 'pipeline_id' => renovacoes.id })

      expect(resposta).to include('Renovações')
      expect(resposta).not_to include('Seguro Auto')
    end
  end
end
