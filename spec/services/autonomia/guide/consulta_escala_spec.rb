require 'rails_helper'

# A conta de verdade, no tamanho de verdade.
#
# Os outros testes de leitura usam uma resposta fabricada por mim, e por isso
# mediam o que EU achava que a plataforma devolve. Aqui as caixas, os funis e os
# contatos são criados no banco e a leitura passa pelo caminho completo —
# serializador real, payload real, tamanho real.
#
# Existe porque em 20/09/2026 o Guia respondeu "apareceu uma caixa" para uma
# conta com três: o orçamento tinha sido dimensionado olhando etiqueta (92
# bytes) sem nunca olhar caixa de entrada (~3.000). Nenhum teste pegou, porque
# nenhum teste tinha uma caixa de entrada de verdade dentro.
RSpec.describe Autonomia::Guide::Consulta do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:consulta) { described_class.new(account: conta, user: admin) }

  # O pedido do Rodrigo, literal: "quero que ele responda se tiver 40 caixas".
  it 'responde a conta com 40 caixas de entrada, sem cortar', :aggregate_failures do
    40.times { |i| create_crm_inbox(account: conta, name: "Caixa #{i}", members: [admin]) }

    resposta = consulta.ler('inboxes')

    expect(resposta).to include('Caixa 0')
    expect(resposta).to include('Caixa 39')
    # Todas as 40, não 39: quem responde "quantas eu tenho" conta o que recebeu.
    expect(resposta.scan('"name"').size).to eq(40)
  end

  it 'responde a conta com 40 funis, sem cortar', :aggregate_failures do
    40.times { |i| create_crm_pipeline(account: conta, user: admin, name: "Funil #{i}") }

    resposta = with_modified_env CRM_KANBAN_ENABLED: 'true' do
      consulta.ler('crm/pipelines')
    end

    expect(resposta).to include('Funil 0', 'Funil 39')
  end

  # Recurso desligado na conta responde 404. Isso NÃO pode virar "a plataforma
  # respondeu 404" na tela de quem está tentando trabalhar.
  it 'explica recurso desligado sem mostrar código de status' do
    resposta = with_modified_env CRM_KANBAN_ENABLED: 'false' do
      consulta.ler('crm/pipelines')
    end

    expect(resposta).to include('não está disponível nesta conta')
  end

  # Contato é o recurso que escala sem teto — uma conta real tem milhares. Aqui
  # o certo NÃO é caber tudo: é cortar e dizer que cortou, para o Guia nunca
  # contar a amostra como se fosse o total.
  it 'corta o que não cabe e avisa, em vez de contar a amostra', :aggregate_failures do
    120.times { |i| conta.contacts.create!(name: "Contato #{i}", phone_number: "+5511900000#{format('%03d', i)}") }

    resposta = consulta.ler('contacts')

    expect(resposta).to include('Contato 0')
    expect(resposta).to include('no total').or include('NÃO afirme um total')
  end

  # O que sustenta tudo acima: a lista manda o que identifica, e o detalhe de um
  # item se pede pelo item. Se esta leitura vier enxuta, a de lista não tem como
  # ser o lugar do detalhe — e o desenho inteiro cai.
  it 'a leitura de UM item continua vindo inteira', :aggregate_failures do
    caixa = create_crm_inbox(account: conta, name: 'Detalhada', members: [admin])

    item = consulta.ler('inboxes/:id', { id: caixa.id })

    # Campos que o enxugamento da lista tiraria: só sobrevivem se o item não
    # passou por ele. Comparar tamanho com a lista não pegava a regressão.
    expect(item).to include('"working_hours":[')
    expect(item).to include('Detalhada')
  end

  # Conversa é o recurso mais pesado e mais perguntado, e vem embrulhado em dois
  # níveis: `data: { meta:, payload: [...] }`. Desembrulhar um nível só fazia a
  # lista cair no caminho do item único — sem enxugar, sem corte por item e sem
  # aviso: a partir de umas doze conversas o modelo recebia um JSON partido no
  # meio achando que estava inteiro.
  it 'lê conversas sem entregar JSON partido em silêncio', :aggregate_failures do
    caixa = create_crm_inbox(account: conta, name: 'Atendimento', members: [admin])
    30.times do
      contato = conta.contacts.create!(name: 'Cliente', phone_number: "+5511#{rand(100_000_000..999_999_999)}")
      inbox_contato = ContactInbox.create!(contact: contato, inbox: caixa, source_id: SecureRandom.uuid)
      conta.conversations.create!(inbox: caixa, contact: contato, contact_inbox: inbox_contato)
    end

    resposta = consulta.ler('conversations')

    # Tem que chegar como LISTA. Se o desembrulho parar no primeiro nível, isto
    # vira o objeto `{"meta":...,"payload":[...]}` e todo o tratamento de lista
    # — enxugar, cortar por item, avisar — deixa de acontecer.
    expect(resposta).to start_with('[')
    expect(resposta.length).to be <= described_class::MAX_TEXTO
    expect { JSON.parse(resposta.split(' [NOTA INTERNA').first) }.not_to raise_error
  end

  # Regra §6 do Rodrigo: credencial nunca sai em mensagem. O corte por forma não
  # pega isto — um token é uma string curta, igualzinha a um nome de caixa.
  it 'nunca manda segredo da conta, nem na lista nem no item', :aggregate_failures do
    caixa = create_crm_inbox(account: conta, name: 'Com segredo', members: [admin])
    # O segredo que vazava não estava no topo: a chave da API de uma caixa de
    # WhatsApp mora DENTRO de `provider_config`. Na lista o objeto aninhado caía
    # por forma; no item único ia inteiro.
    # Criar o canal dispara sincronização de modelos e webhook na Meta; aqui o
    # que interessa é o `provider_config` gravado, não a integração. Por isso o
    # canal é montado e gravado sem validação nem callbacks externos.
    # rubocop:disable Rails/SkipsModelValidations -- gravar sem validar é o ponto:
    # queremos o provider_config no banco sem falar com a Meta.
    conta.whatsapp_channels.insert!(
      { phone_number: '+5511999990000', provider: 'whatsapp_cloud',
        provider_config: { 'api_key' => 'CHAVE-QUE-NAO-PODE-SAIR', 'phone_number_id' => '123' },
        message_templates: [], message_templates_last_updated: Time.current,
        created_at: Time.current, updated_at: Time.current }
    )
    # rubocop:enable Rails/SkipsModelValidations
    canal = conta.whatsapp_channels.last
    com_provedor = conta.inboxes.create!(name: 'WhatsApp', channel: canal)

    respostas = [consulta.ler('inboxes'),
                 consulta.ler('inboxes/:id', { id: caixa.id }),
                 consulta.ler('inboxes/:id', { id: com_provedor.id })]

    respostas.each do |resposta|
      expect(resposta).not_to include('hmac_token')
      expect(resposta).not_to include('inbox_identifier')
      expect(resposta).not_to include('CHAVE-QUE-NAO-PODE-SAIR')
    end
  end

  # A conversa só é útil com o nome de quem está do outro lado, e esse nome mora
  # aninhado (`meta.sender.name`). O corte por forma jogava o `meta` inteiro
  # fora: a lista vinha só com id e status, anônima.
  it 'traz o nome de quem está na conversa' do
    caixa = create_crm_inbox(account: conta, name: 'Atendimento', members: [admin])
    contato = conta.contacts.create!(name: 'Joana Cliente', phone_number: '+5511988887777')
    inbox_contato = ContactInbox.create!(contact: contato, inbox: caixa, source_id: SecureRandom.uuid)
    conta.conversations.create!(inbox: caixa, contact: contato, contact_inbox: inbox_contato)

    expect(consulta.ler('conversations')).to include('Joana Cliente')
  end

  # Trazer o aninhado trouxe junto o texto da última mensagem, e a conversa
  # quintuplicou de tamanho: uma página cheia deixava sete de fora. O teto por
  # item resolve mantendo o que identifica e descartando o conteúdo.
  it 'cabe uma página cheia de conversas com mensagem', :aggregate_failures do
    caixa = create_crm_inbox(account: conta, name: 'Atendimento', members: [admin])
    25.times do |i|
      contato = conta.contacts.create!(name: "Cliente #{i}", phone_number: "+5511977770#{format('%03d', i)}")
      inbox_contato = ContactInbox.create!(contact: contato, inbox: caixa, source_id: SecureRandom.uuid)
      conversa = conta.conversations.create!(inbox: caixa, contact: contato, contact_inbox: inbox_contato)
      conversa.messages.create!(account: conta, inbox: caixa, message_type: :incoming,
                                content: "Bom dia, #{('preciso de ajuda com o meu pedido. ' * 12)}")
    end

    resposta = consulta.ler('conversations')

    # Todas as 25, com o nome de cada cliente, e sem aviso de corte nosso.
    expect(resposta).to include('Cliente 0')
    expect(resposta).to include('Cliente 24')
    expect(resposta).not_to include('ficaram de fora')
  end

  # O teto por item corta o que veio de dentro de objeto aninhado antes do que é
  # do próprio registro. Só por tamanho, o nome de um contato sairia antes de
  # vinte e cinco atributos curtos — medido, o nome sumia da lista.
  it 'não deixa o teto por item comer o nome do registro', :aggregate_failures do
    conta.contacts.create!(name: 'Maria Aparecida dos Santos Albuquerque de Oliveira Nascimento Filha',
                           phone_number: '+5511911112222', email: 'maria@exemplo.com',
                           custom_attributes: (1..25).to_h { |n| ["campo#{n}", "valor#{n}"] })

    resposta = consulta.ler('contacts')

    expect(resposta).to include('Maria Aparecida')
    expect(resposta).to include('+5511911112222')
  end

  # A plataforma pagina, e cada recurso pagina de um jeito. Quando ela informa o
  # total, o Guia usa. Quando não informa, ele diz quantos recebeu — sem se
  # recusar a responder, que foi o erro que eu cometi ao consertar isto.
  it 'usa o total da plataforma quando ela informa, mesmo aninhado' do
    resposta = consulta.ler('notifications')

    expect(resposta).to include('no total desta conta')
  end

  it 'responde com o número recebido quando a plataforma não informa o total', :aggregate_failures do
    5.times { |i| conta.labels.create!(title: "etiqueta#{i}") }

    resposta = consulta.ler('labels')

    expect(resposta).to include('Diga quantos são')
    expect(resposta).not_to include('NÃO afirme um total')
  end

  # Único caso vivo de lista embrulhada dentro de outra chave
  # (`{"payload":{"webhooks":[...]}}`). Sem teste, qualquer mexida no
  # desembrulho o quebra em silêncio.
  it 'lê webhooks, que vêm embrulhados dentro de outra chave' do
    conta.webhooks.create!(url: 'https://exemplo.invalid/hook', webhook_type: :account_type)

    expect(consulta.ler('webhooks')).to start_with('[')
  end

  # Negativa de permissão nesta aplicação chega como 401, não 403. Antes isso
  # caía no erro genérico e quem não tinha acesso ouvia "tente de novo".
  it 'diz que é falta de acesso quando o perfil não alcança o recurso' do
    agente, = create_crm_agent(account: conta)
    como_agente = described_class.new(account: conta, user: agente)

    expect(como_agente.ler('webhooks')).to include('não tem acesso a isto')
  end
end
