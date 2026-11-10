require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G13: mandar os dados para outro sistema e usar a resposta. Provado nos
# passos 3 e 4 do exemplo 20 ("Manda os dados para o sistema de cobrança e grava no card o número de cliente que ele
# devolve. O sistema de cobrança recusou: avisa o financeiro com o motivo que veio na resposta."). O Ricardo monta e
# liga pela API da tela, o card ganho sai pelo emissor do CRM, o despacho leva o evento ao motor e o pedido chega a um
# receptor de teste que grava a chamada (F9.7). O exemplo 20 inteiro fica no pendentes_spec até a G7 fechar; o 14, até
# a G20.
RSpec.describe 'Fechamento #2414 · G13: mandar para outro sistema', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:ricardo) { create(:user, account: account, role: :administrator, name: 'Ricardo Sócio') }
  let(:financeiro) { create(:user, account: account, role: :agent, name: 'Paula Financeiro') }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [ricardo, financeiro]) }
  let(:cliente) { account.contacts.create!(name: 'Clínica Sorriso', phone_number: '+5511900000020') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: cliente) }
  let(:funil) { create_crm_pipeline(account: account, user: ricardo).first }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: funil.stages.first, inbox: inbox, contact: cliente, primary_conversation: conversa,
                              title: 'Plano Pro anual', owner: ricardo,
                              custom_attributes: { 'cnpj' => '12.345.678/0001-90', 'email_financeiro' => 'financeiro@sorriso.com.br' })
  end
  let(:cobranca) { 'https://cobranca.exemplo.com/api/clientes' }
  let(:chamadas) { [] }

  let(:mandar_a_cobranca) do
    { id: 'cobranca', tipo: 'webhook', descricao: 'Mandar ao sistema de cobrança', url: cobranca,
      corpo: { cnpj: { '$valor' => 'card.atributos.cnpj' }, email: { '$valor' => 'card.atributos.email_financeiro' },
               plano: { '$valor' => 'card.titulo' } },
      gravar: [{ chave: 'cliente.numero', destino: 'card.atributos.numero_cliente' },
               { chave: 'erro', destino: 'card.atributos.motivo_cobranca' }],
      se_recusar: [{ id: 'avisar_financeiro', tipo: 'avisar', para: { pessoas: [financeiro.id] },
                     texto: ['A cobrança recusou ', { '$valor' => 'contato.nome' }, ': ', { '$valor' => 'card.atributos.motivo_cobranca' }] }] }
  end

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    { 'cnpj' => 'CNPJ', 'email_financeiro' => 'E-mail do financeiro', 'numero_cliente' => 'Número de cliente',
      'motivo_cobranca' => 'Motivo da cobrança' }.each do |chave, nome|
      create(:custom_attribute_definition, account: account, attribute_model: 'card_attribute', attribute_key: chave,
                                           attribute_display_name: nome, attribute_display_type: 'text')
    end
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('cobranca.exemplo.com').and_return(['93.184.216.34'])
    card
    clear_enqueued_jobs
  end

  after { Current.reset }

  def sistema_de_cobranca_responde(status, corpo)
    stub_request(:post, cobranca).to_return do |pedido|
      chamadas << pedido
      { status: status, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # Um job por vez, como no Sidekiq, com o job do evento do card no meio.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def ligada_no_card_ganho
    receita = { gatilho: { tipo: 'card.ganho', funil_id: funil.id }, passos: [mandar_a_cobranca] }
    montar_automacao(ricardo, account, nome: 'Venda fechada vai para a cobrança', receita: receita).tap do |automacao|
      ligar_automacao(ricardo, account, automacao)
    end
  end

  def ganhar_o_card
    Crm::Cards::Closer.new(card: card, actor: ricardo, result: 'won').perform
    drenar
  end

  it 'passo 3: o card ganho manda os dados assinados e grava no card o número de cliente devolvido', :aggregate_failures do
    sistema_de_cobranca_responde(201, { cliente: { numero: 'CLI-20931' } })
    automacao = ligada_no_card_ganho

    ganhar_o_card

    expect(historico_de(automacao)).to eq([['cobranca', 'ok', nil]])
    expect(card.reload.custom_attributes).to include('numero_cliente' => 'CLI-20931')
    chamada = chamadas.sole
    expect(JSON.parse(chamada.body)).to eq('cnpj' => '12.345.678/0001-90', 'email' => 'financeiro@sorriso.com.br', 'plano' => 'Plano Pro anual')
    segredo = Autonomia::Automacao::SegredoDoWebhook.new(Autonomia::Automacao::Definicao.find(automacao['id'])).valor
    assinatura = OpenSSL::HMAC.hexdigest('SHA256', segredo, "#{chamada.headers['X-Automacao-Timestamp']}.#{chamada.body}")
    expect(chamada.headers['X-Automacao-Signature']).to eq("sha256=#{assinatura}")
  end

  it 'passo 4: a cobrança recusou, e o financeiro é avisado com o motivo que veio na resposta', :aggregate_failures do
    sistema_de_cobranca_responde(422, { erro: 'CNPJ com pendência na Receita Federal' })
    automacao = ligada_no_card_ganho

    ganhar_o_card

    expect(historico_de(automacao)).to eq([%w[cobranca ok webhook_recusado], ['avisar_financeiro', 'ok', nil]])
    aviso = conversa.messages.where(private: true).sole
    expect(aviso.content).to include('A cobrança recusou Clínica Sorriso: CNPJ com pendência na Receita Federal',
                                     "mention://user/#{financeiro.id}/")
    expect(Notification.where(user: financeiro, notification_type: 'conversation_mention').count).to eq(1)
    expect(card.reload.custom_attributes).not_to have_key('numero_cliente')
  end
end
