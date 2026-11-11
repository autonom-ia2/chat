require 'rails_helper'

# G13 (#2670): o passo "webhook" pelo motor de verdade. O outro sistema é um receptor de teste (WebMock) que grava o
# pedido; o DNS do host é fixado num IP público, como o SafeFetch exige.
RSpec.describe Autonomia::Automacao::PassoDeWebhook, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
  let(:contato) { account.contacts.create!(name: 'Mercado Bom Preço', phone_number: '+5511987654321') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, inbox: inbox, contact: contato,
                              primary_conversation: conversa, title: 'Plano anual', owner: admin,
                              custom_attributes: { 'cnpj' => '12.345.678/0001-90' })
  end
  let(:url) { 'https://cobranca.exemplo.com/clientes?token=abc' }
  let(:pedidos) { [] }

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true', FRONTEND_URL: 'https://app.plataforma.com') { exemplo.run } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    %w[cnpj numero_cliente motivo_da_recusa].each do |chave|
      create(:custom_attribute_definition, account: account, attribute_model: 'card_attribute', attribute_key: chave,
                                           attribute_display_name: chave, attribute_display_type: 'text')
    end
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('cobranca.exemplo.com').and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses).with('app.plataforma.com').and_return(['151.101.1.69'])
  end

  after { Current.reset }

  def responder(status, corpo = {})
    stub_request(:post, url).to_return do |pedido|
      pedidos << pedido
      { status: status, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def webhook(id = 'cobranca', **campos)
    { 'id' => id, 'tipo' => 'webhook', 'descricao' => 'Mandar ao sistema de cobrança', 'url' => url,
      'corpo' => { 'cnpj' => { '$valor' => 'card.atributos.cnpj' }, 'nome' => { '$valor' => 'contato.nome' } },
      'gravar' => [{ 'chave' => 'cliente.numero', 'destino' => 'card.atributos.numero_cliente' },
                   { 'chave' => 'motivo', 'destino' => 'card.atributos.motivo_da_recusa' }] }.merge(campos.stringify_keys)
  end

  def rodar(passos)
    definicao = automacao_ligada(account, admin, passos, gatilho: { 'tipo' => 'card.ganho', 'funil_id' => funil_e_etapa.first.id })
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'card.ganho').call
    end
    Autonomia::Automacao::Execucao.where(automacao: definicao).last
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  def dados(execucao, passo) = Autonomia::Automacao::Registro.where(execucao: execucao, passo: passo).last.dados

  it 'manda o corpo assinado e grava no card o número que o outro sistema devolveu', :aggregate_failures do
    responder(201, { cliente: { numero: 'C-1042' } })

    execucao = rodar([webhook])

    expect(registros(execucao)).to eq([['cobranca', 'ok', nil]])
    expect(execucao.reload.estado).to eq('concluida')
    expect(card.reload.custom_attributes).to include('numero_cliente' => 'C-1042')
    pedido = pedidos.sole
    expect(JSON.parse(pedido.body)).to eq('cnpj' => '12.345.678/0001-90', 'nome' => 'Mercado Bom Preço')
    instante = pedido.headers['X-Automacao-Timestamp']
    segredo = Autonomia::Automacao::SegredoDoWebhook.new(execucao.automacao).valor
    expect(pedido.headers['X-Automacao-Signature']).to eq("sha256=#{OpenSSL::HMAC.hexdigest('SHA256', segredo, "#{instante}.#{pedido.body}")}")
    expect(pedido.headers['X-Automacao-Execucao']).to eq(execucao.id.to_s)
  end

  it 'o histórico guarda o host, o código e as chaves, nunca a URL com o token, o corpo ou a resposta', :aggregate_failures do
    responder(200, { cliente: { numero: 'C-1042' } })

    execucao = rodar([webhook])

    registro = dados(execucao, 'cobranca')
    expect(registro).to include('host' => 'cobranca.exemplo.com', 'codigo' => 200, 'gravados' => ['cliente.numero'], 'ausentes' => ['motivo'])
    expect(registro.to_json).not_to include('token', 'abc', '12.345.678', 'C-1042', 'Bom Preço')
  end

  # O card sem conversa não tem onde gravar o que vai para a conversa: a chave não some em silêncio, o histórico diz
  # quais ficaram sem lugar, e o que tem lugar (o card) grava.
  describe 'resposta para um lugar que o alvo não tem' do
    let(:card) do
      account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, inbox: inbox, contact: contato,
                                title: 'Plano anual', owner: admin, custom_attributes: { 'cnpj' => '12.345.678/0001-90' })
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute', attribute_key: 'protocolo',
                                           attribute_display_name: 'protocolo', attribute_display_type: 'text')
    end

    it 'registra as chaves sem lugar e grava as outras', :aggregate_failures do
      responder(200, { cliente: { numero: 'C-1042' }, protocolo: 'P-77' })
      gravar = [{ 'chave' => 'cliente.numero', 'destino' => 'card.atributos.numero_cliente' },
                { 'chave' => 'protocolo', 'destino' => 'conversa.atributos.protocolo' }]

      execucao = rodar([webhook(gravar: gravar)])

      expect(registros(execucao)).to eq([['cobranca', 'ok', nil]])
      expect(dados(execucao, 'cobranca')).to include('gravados' => ['cliente.numero'], 'ausentes' => [], 'sem_lugar' => ['protocolo'])
      expect(card.reload.custom_attributes).to include('numero_cliente' => 'C-1042')
    end
  end

  it 'recusa (4xx): grava o motivo da resposta e segue pelo se_recusar', :aggregate_failures do
    responder(422, { motivo: 'CNPJ com pendência na Receita' })
    avisar = { 'id' => 'avisa', 'tipo' => 'parar' }

    execucao = rodar([webhook(se_recusar: [avisar]), { 'id' => 'depois', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }])

    expect(registros(execucao)).to eq([%w[cobranca ok webhook_recusado], ['avisa', 'ok', nil]])
    expect(card.reload.custom_attributes).to include('motivo_da_recusa' => 'CNPJ com pendência na Receita')
  end

  it 'recusa sem se_recusar: a execução para com o motivo', :aggregate_failures do
    responder(400, {})

    execucao = rodar([webhook, { 'id' => 'depois', 'tipo' => 'parar' }])

    expect(registros(execucao)).to eq([%w[cobranca falhou webhook_recusado]])
    expect(execucao.reload.estado).to eq('falhou')
  end

  it 'erro do outro sistema (5xx) é passageiro: tenta de novo mais tarde, sem repetir sem fim', :aggregate_failures do
    responder(503)

    execucao = rodar([webhook])

    expect(registros(execucao)).to eq([%w[cobranca falhou webhook_sem_resposta]])
    expect(execucao.reload).to have_attributes(estado: 'esperando', cursor: 'cobranca', tentativas: 1)
    [2.minutes, 10.minutes].each { |depois| travel(depois) { varrer } }
    expect(execucao.reload.estado).to eq('falhou')
    expect(pedidos.size).to eq(3)
  end

  it 'sem resposta no prazo também é passageiro' do
    stub_request(:post, url).to_timeout

    execucao = rodar([webhook])

    expect(registros(execucao)).to eq([%w[cobranca falhou webhook_sem_resposta]])
  end

  it 'redirecionamento não é seguido e para na hora' do
    stub_request(:post, url).to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/latest/meta-data' })

    execucao = rodar([webhook])

    expect(registros(execucao)).to eq([%w[cobranca falhou webhook_redirecionou]])
  end

  it 'host que resolve para rede interna é bloqueado antes de sair, mesmo com a rede interna liberada na instalação', :aggregate_failures do
    allow(Resolv).to receive(:getaddresses).with('cobranca.exemplo.com').and_return(['10.0.0.7'])
    responder(200)

    execucao = with_modified_env(SAFE_FETCH_ALLOW_PRIVATE_NETWORK: 'true') { rodar([webhook]) }

    expect(registros(execucao)).to eq([%w[cobranca falhou webhook_endereco_interno]])
    expect(pedidos).to be_empty
  end

  it 'valor vazio no corpo pula o passo sem mandar nada', :aggregate_failures do
    card.update!(custom_attributes: {})
    responder(200)

    execucao = rodar([webhook])

    expect(registros(execucao)).to eq([%w[cobranca pulado faltou_valor]])
    expect(pedidos).to be_empty
  end

  it 'gravar a resposta falhou depois do 2xx: para sem mandar de novo', :aggregate_failures do
    responder(200, { cliente: { numero: 'C-1042' } })
    falha = Autonomia::Automacao::PassoDeAcao::Resultado.new(tipo: :passageiro, motivo: 'erro_passageiro', dados: {})
    allow_any_instance_of(Autonomia::Automacao::PassoDeAcao).to receive(:executar).and_return(falha) # rubocop:disable RSpec/AnyInstance

    execucao = rodar([webhook])
    [2.minutes, 10.minutes].each { |depois| travel(depois) { varrer } }

    expect(registros(execucao)).to eq([%w[cobranca falhou webhook_gravar_falhou]])
    expect(execucao.reload.estado).to eq('falhou')
    expect(pedidos.size).to eq(1)
  end

  it 'recusa sem se_recusar não grava nada do texto de quem recusou' do
    responder(422, { motivo: 'qualquer coisa' })

    rodar([webhook])

    expect(card.reload.custom_attributes).not_to have_key('motivo_da_recusa')
  end

  it 'chave que passa por um valor simples não acha nada, e as outras continuam gravando', :aggregate_failures do
    responder(200, { cliente: 'texto', motivo: 'ok' })

    execucao = rodar([webhook])

    expect(dados(execucao, 'cobranca')).to include('gravados' => ['motivo'], 'ausentes' => ['cliente.numero'])
    expect(card.reload.custom_attributes).to include('motivo_da_recusa' => 'ok')
  end

  it 'IPv4 dentro de IPv6, o IP da própria plataforma, o metadata e as faixas reservadas são bloqueados', :aggregate_failures do
    %w[::ffff:10.0.0.7 151.101.1.69 169.254.169.254 fd00:ec2::254 224.0.0.1 198.18.0.5 2002:a00::1].each do |ip|
      allow(Resolv).to receive(:getaddresses).with('cobranca.exemplo.com').and_return([ip])
      responder(200)

      execucao = rodar([webhook("w#{ip.delete(':.')}")])

      expect(registros(execucao).last.last).to eq('webhook_endereco_interno'), ip
    end
    expect(pedidos).to be_empty
  end

  it 'conecta no IP conferido, mesmo que o nome passe a apontar para a rede interna (sem DNS rebinding)', :aggregate_failures do
    allow(Resolv).to receive(:getaddresses).with('cobranca.exemplo.com').and_return(['93.184.216.34'], ['10.0.0.7'])
    resolvedores = []
    allow(SafeFetch).to receive(:fetch).and_wrap_original do |original, *args, **opcoes, &bloco|
      resolvedores << opcoes[:resolver]
      original.call(*args, **opcoes, &bloco)
    end
    responder(200)

    execucao = rodar([webhook])

    expect(registros(execucao)).to eq([['cobranca', 'ok', nil]])
    expect(resolvedores.sole.call('cobranca.exemplo.com')).to eq([IPAddr.new('93.184.216.34')])
    expect(Resolv).to have_received(:getaddresses).with('cobranca.exemplo.com').once
  end

  it 'texto longo da resposta é cortado antes de gravar' do
    responder(201, { cliente: { numero: 'C' * 5000 } })

    rodar([webhook])

    expect(card.reload.custom_attributes['numero_cliente'].length).to eq(described_class::TEXTO_MAXIMO)
  end

  it 'nome que não resolve (DNS fora) é passageiro, não bloqueio' do
    allow(Resolv).to receive(:getaddresses).with('cobranca.exemplo.com').and_return([])

    execucao = rodar([webhook])

    expect(registros(execucao)).to eq([%w[cobranca falhou webhook_sem_resposta]])
  end

  it 'a chave de integrações tirada no meio da execução vale já: o passo pede a pausa e nada sai', :aggregate_failures do
    responder(200)
    execucao = rodar([webhook])
    agente = create(:user, account: account, role: :agent)
    funcao = create(:custom_role, account: account, permissions: %w[automation_manage integration_manage crm_admin])
    conta_do_agente = agente.account_users.find_by(account: account)
    conta_do_agente.update!(custom_role: funcao)
    acesso = instance_double(Autonomia::Automacao::Acesso, account_user: conta_do_agente)
    # A execução carregou a pessoa com a chave; a função perde a chave depois, por outro caminho.
    CustomRole.find(funcao.id).update!(permissions: %w[automation_manage crm_admin])

    resultado = described_class.new(execucao: execucao, passo: webhook, valores: nil, acesso: acesso).executar

    expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'webhook_sem_permissao'])
    expect(pedidos.size).to eq(1)
  end
end
