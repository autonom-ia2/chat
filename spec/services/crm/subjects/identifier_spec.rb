require 'rails_helper'

# Multifunil 5/11 (#1145): os cenários do mockup (docs/multifunil/jornada.html) com o Jev e o modelo maior simulados.
RSpec.describe Crm::Subjects::Identifier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Comercial') }
  let(:comercial) { pipeline_and_stage.first }
  let(:first_stage) { pipeline_and_stage.last }
  let(:finder) { Crm::Cards::ConversationCardFinder.new(account: account) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:mode) { :auto }

  before do
    comercial.update!(when_to_use: 'Venda dos produtos: Agentes de IA e Chat2You.')
    create_crm_stage(account: account, pipeline: comercial, name: 'Proposta', position: 1)
    account.crm_pipeline_inboxes.create!(pipeline: comercial, inbox: inbox, default_stage: first_stage, auto_create_card: true, created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: true, subject_ai_mode: mode)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def create_card(title:, focused_at: nil, metadata: {})
    card = account.crm_cards.create!(pipeline: comercial, stage: first_stage, contact: contact, primary_conversation: conversation,
                                     inbox: inbox, title: title, metadata: metadata)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: focused_at)
    card
  end

  # O Jev responde a escolha `choice` com a certeza dada; devolve os corpos enviados.
  def stub_jev(choice, confidence: 0.95)
    requests = []
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
      requests << JSON.parse(request.body)
      body = { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
               answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }
      { status: 200, body: body.to_json }
    end
    requests
  end

  # A resposta serve às duas perguntas: a de um assunto e, com a flag `crm_avaliar_toda_mensagem` (#1693), a de vários
  # assuntos (a lista com um item só, que é o principal).
  def stub_review(resposta:, titulo: '', seguro: true)
    resposta_dos_dois = { resposta: resposta, titulo: titulo, seguro: seguro, motivo: 'ok',
                          assuntos: [{ resposta: resposta, titulo: titulo, seguro: seguro }], principal: 0 }
    allow(cliente).to receive(:create).and_return(text: resposta_dos_dois.to_json)
  end

  def identify(message)
    described_class.new(conversation: conversation, message: message).perform
  end

  it 'com a IA desligada na caixa não pergunta nada' do
    account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :off)
    requests = stub_jev('sem_assunto')

    expect(identify(incoming('Quero um agente de IA'))).to be_nil
    expect(requests).to be_empty
    expect(Crm::SubjectDecision.count).to eq(0)
  end

  # #2084: contato marcado parceiro ou não é negócio não passa pela IA de assunto, nem em Sugerir.
  context 'with the contact out of the funnel (contato_relacao)' do
    before { account.enable_features!('contato_relacao') }

    %i[parceiro nao_e_negocio].each do |relacao|
      it "#{relacao}: não pergunta ao Jev nem ao modelo maior, não cria card nem decisão" do
        contact.update!(relacao: relacao)
        requests = stub_jev("novo_#{comercial.id}")
        stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

        expect(identify(incoming('E o Chat2You, quanto custa para 5 atendentes?'))).to be_nil
        expect(requests).to be_empty
        expect(cliente).not_to have_received(:create)
        expect(account.crm_cards.count).to eq(0)
        expect(Crm::SubjectDecision.count).to eq(0)
      end
    end

    it 'em Sugerir também não sugere nada' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :suggest)
      contact.update!(relacao: :parceiro)
      requests = stub_jev("novo_#{comercial.id}")

      expect(identify(incoming('Queria também o plano anual'))).to be_nil
      expect(requests).to be_empty
      expect(Crm::SubjectDecision.where(state: 'suggested')).to be_empty
    end

    it 'interessado segue como sempre: o assunto novo vira card' do
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

      expect(identify(incoming('E o Chat2You, quanto custa?'))).to have_attributes(state: 'applied')
      expect(account.crm_cards.count).to eq(1)
    end

    # A pessoa marca enquanto o Jev pensa: o Identifier já tinha conferido, o Applier confere de novo dentro da trava.
    def marcar_parceiro_enquanto_pensa(choice)
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do
        contact.update!(relacao: :parceiro)
        body = { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
                 answers: { decisao: { type: 'choice', choice: choice, confidence: 0.95 } } }
        { status: 200, body: body.to_json }
      end
    end

    it 'marcado parceiro enquanto a IA pensa: o card não nasce' do
      marcar_parceiro_enquanto_pensa("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

      expect(identify(incoming('E o Chat2You, quanto custa?'))).to have_attributes(state: 'kept', reason: 'fora_do_funil')
      expect(account.crm_cards.count).to eq(0)
    end

    it 'marcado parceiro enquanto a IA pensa, em Sugerir: nenhuma sugestão fica esperando' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :suggest)
      marcar_parceiro_enquanto_pensa("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

      identify(incoming('Queria também o plano anual'))

      expect(Crm::SubjectDecision.where(state: 'suggested')).to be_empty
      expect(account.crm_cards.count).to eq(0)
    end

    it 'com a flag desligada, a marca não muda nada' do
      account.disable_features!('contato_relacao')
      contact.update!(relacao: :parceiro)
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

      expect(identify(incoming('E o Chat2You, quanto custa?'))).to have_attributes(state: 'applied')
      expect(account.crm_cards.count).to eq(1)
    end
  end

  it '"Oi, bom dia" não cria card nem dá nome: o Jev diz que ainda não há assunto e o modelo maior não é chamado' do
    card = create_card(title: 'Joana Lima')
    requests = stub_jev('sem_assunto')

    decision = identify(incoming('Oi, bom dia'))

    expect(decision).to have_attributes(action: 'none', state: 'kept', decided_by: 'jev')
    expect(card.reload.title).to eq('Joana Lima')
    expect(account.crm_cards.count).to eq(1)
    expect(cliente).not_to have_received(:create)
    expect(requests.first['questions']['decisao']['criteria'].keys).to contain_exactly('sem_assunto', "novo_#{comercial.id}")
  end

  it '1º assunto: o card que a conversa já tem, ainda sem assunto, ganha o nome em vez de nascer outro' do
    card = create_card(title: 'Joana Lima')
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Agentes de IA')

    decision = identify(incoming('Queria saber dos agentes de IA para o meu atendimento'))

    expect(decision).to have_attributes(action: 'rename', state: 'applied', title: 'Agentes de IA', card_id: card.id)
    expect(card.reload.title).to eq('Agentes de IA')
    expect(card.metadata.dig('subject', 'source')).to eq('ai')
    expect(account.crm_cards.count).to eq(1)
  end

  it '2º assunto no mesmo funil: nasce outro card na primeira etapa e ele vira o assunto atual' do
    agentes = create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    requests = stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

    decision = identify(incoming('E o Chat2You, quanto custa para 5 atendentes?'))

    novo = account.crm_cards.order(:id).last
    expect(decision).to have_attributes(action: 'create', state: 'applied', title: 'Chat2You', card_id: novo.id)
    expect(novo).to have_attributes(title: 'Chat2You', pipeline_id: comercial.id, stage_id: first_stage.id, status: 'open')
    expect(finder.find(conversation)).to eq(novo)
    expect(agentes.reload.status).to eq('open')
    expect(requests.first['questions']['decisao']['criteria'].keys)
      .to contain_exactly('sem_assunto', 'mesmo_assunto', "novo_#{comercial.id}")
  end

  it 'volta a um assunto aberto antigo: troca o assunto atual sem chamar o modelo maior' do
    agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago)
    create_card(title: 'Chat2You', focused_at: 1.hour.ago)
    stub_jev("card_#{agentes.id}")

    decision = identify(incoming('Voltando aos agentes: fechamos o plano anual'))

    expect(decision).to have_attributes(action: 'focus', state: 'applied', card_id: agentes.id)
    expect(finder.find(conversation)).to eq(agentes)
    expect(cliente).not_to have_received(:create)
  end

  it 'avisa a tela da conversa quando aplica, e fica quieto quando nada muda' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    allow(Crm::Subjects::Notifier).to receive(:notify)
    stub_jev('mesmo_assunto')
    identify(incoming('Pode mandar a proposta?'))

    expect(Crm::Subjects::Notifier).not_to have_received(:notify)

    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')
    identify(incoming('E o Chat2You?'))

    expect(Crm::Subjects::Notifier).to have_received(:notify).with(conversation).once
  end

  it 'continua no mesmo assunto: não mexe em nada' do
    card = create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
    stub_jev('mesmo_assunto')

    decision = identify(incoming('Pode mandar a proposta?'))

    expect(decision).to have_attributes(action: 'none', state: 'kept')
    expect(finder.find(conversation)).to eq(card)
    expect(account.crm_cards.count).to eq(1)
  end

  it 'na dúvida (Jev inseguro e modelo maior inseguro) mantém o que está e registra a dúvida' do
    card = create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
    stub_jev("novo_#{comercial.id}", confidence: 0.4)
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Talvez outro', seguro: false)

    decision = identify(incoming('E aquilo outro?'))

    expect(decision).to have_attributes(state: 'doubt', decided_by: 'review', title: 'Talvez outro')
    expect(account.crm_cards.count).to eq(1)
    expect(finder.find(conversation)).to eq(card)
  end

  it 'Jev inseguro, mas o modelo maior seguro: vale a resposta do modelo maior' do
    agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago)
    create_card(title: 'Chat2You', focused_at: 1.hour.ago)
    stub_jev('mesmo_assunto', confidence: 0.5)
    stub_review(resposta: "card_#{agentes.id}", titulo: '')

    decision = identify(incoming('Sobre os agentes, ainda tenho uma dúvida'))

    expect(decision).to have_attributes(action: 'focus', state: 'applied', decided_by: 'review')
    expect(finder.find(conversation)).to eq(agentes)
  end

  it 'assunto novo sem título do modelo maior fica como dúvida: card sem assunto não nasce' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: ' ')

    expect(identify(incoming('Outra coisa'))).to have_attributes(state: 'doubt')
    expect(account.crm_cards.count).to eq(1)
  end

  context 'with the inbox in Suggest mode' do
    let(:mode) { :suggest }

    it 'não cria o card: grava a sugestão e a anterior que ninguém respondeu expira' do
      agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago)
      create_card(title: 'Chat2You', focused_at: 1.hour.ago)
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Plano anual')
      antiga = identify(incoming('Queria também o plano anual'))

      expect(account.crm_cards.count).to eq(2)
      expect(antiga).to have_attributes(action: 'create', state: 'suggested', mode: 'suggest', pipeline_id: comercial.id,
                                        title: 'Plano anual')

      stub_jev("card_#{agentes.id}")
      nova = identify(incoming('Voltando aos agentes'))

      expect(nova).to have_attributes(action: 'focus', state: 'suggested', card_id: agentes.id)
      expect(antiga.reload.state).to eq('expired')
      expect(finder.find(conversation).title).to eq('Chat2You')
    end

    it 'sugestão de uma mensagem já ultrapassada por outra mais nova não fica valendo' do
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
      message = incoming('E o Chat2You?')
      newer = incoming('Para 5 atendentes')
      stub_jev("novo_#{comercial.id}")
      allow(cliente).to receive(:create) do
        Crm::SubjectDecision.create!(account: account, conversation: conversation, message: newer, mode: 'suggest',
                                     action: 'create', state: 'suggested', pipeline: comercial, title: 'Chat2You')
        { text: { resposta: "novo_#{comercial.id}", titulo: 'Chat2You', seguro: true, motivo: 'ok' }.to_json }
      end

      expect(identify(message)).to have_attributes(state: 'superseded')
      expect(Crm::SubjectDecision.suggested.pluck(:message_id)).to eq([newer.id])
    end

    it 'com a sugestão de pedido novo no funil ainda esperando, não paga o modelo maior de novo' do
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')
      identify(incoming('E o Chat2You?'))

      decision = identify(incoming('Quanto custa?'))

      expect(decision).to have_attributes(state: 'kept', reason: 'sugestao_pendente')
      expect(cliente).to have_received(:create).once
      expect(Crm::SubjectDecision.suggested.count).to eq(1)
    end
  end

  it 'a mesma mensagem não é perguntada duas vezes' do
    create_card(title: 'Joana Lima')
    requests = stub_jev('sem_assunto')
    message = incoming('Oi')

    first = identify(message)

    expect(identify(message)).to eq(first)
    expect(requests.size).to eq(1)
  end

  it 'sem cota no mês não pergunta ao Jev' do
    stub_const('Crm::Subjects::LIMITE_MENSAL', 1)
    create_card(title: 'Joana Lima')
    requests = stub_jev('sem_assunto')
    identify(incoming('Oi'))

    expect(identify(incoming('Tudo bem?'))).to have_attributes(state: 'no_quota')
    expect(requests.size).to eq(1)
  end

  it 'falha do Jev fica registrada, sem mudar a conversa' do
    create_card(title: 'Joana Lima')
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(status: 200, body: { model: 'outro' }.to_json)

    expect(identify(incoming('Quero agentes'))).to have_attributes(state: 'failed', reason: 'typesafe_invalid_response')
    expect(account.crm_cards.count).to eq(1)
  end

  it 'conversa sem mensagem para ler (só áudio) não vai ao Jev' do
    requests = stub_jev('sem_assunto')

    expect(identify(incoming(nil))).to have_attributes(state: 'no_content')
    expect(requests).to be_empty
  end

  it 'rajada "texto + áudio": a pergunta do áudio lê o texto de antes e acha o assunto' do
    card = create_card(title: 'Joana Lima')
    requests = stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Seguro do Onix')
    incoming('Quero cotar o seguro do Onix')

    decision = identify(incoming(nil))

    expect(decision).to have_attributes(action: 'rename', state: 'applied')
    expect(card.reload.title).to eq('Seguro do Onix')
    expect(requests.first['state'].to_json).to include('Onix')
  end

  # #1924: o pedido ficava fora das 5 últimas mensagens depois de algumas idas e vindas com a equipe.
  it 'o Jev e o modelo maior leem o pedido feito antes das 5 últimas mensagens da conversa' do
    create_card(title: 'Joana Lima')
    requests = stub_jev("novo_#{comercial.id}", confidence: 0.5)
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Cancelamento do plano')
    incoming('Quero cancelar o meu plano')
    4.times do |indice|
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: "Equipe #{indice}")
    end

    identify(incoming('Pode ser hoje?'))

    expect(requests.first['state']['messages'].first).to eq('Customer: Quero cancelar o meu plano')
    expect(cliente).to have_received(:create).with(hash_including(input: include('Quero cancelar o meu plano'),
                                                                  instructions: include(Crm::Subjects::Question::REGRA_DO_TIPO)))
  end

  it 'retry do job com a decisão já reservada não pergunta nem aplica de novo' do
    create_card(title: 'Joana Lima')
    requests = stub_jev('sem_assunto')
    message = incoming('Quero agentes')
    reservada = Crm::SubjectDecision.create!(account: account, conversation: conversation, message: message, mode: 'auto',
                                             action: 'none', state: 'pending')

    expect(identify(message)).to eq(reservada)
    expect(requests).to be_empty
  end

  it 'uma mensagem mais nova já na fila passa na frente: esta não cria card' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    message = incoming('E o Chat2You?')
    newer = incoming('Para 5 atendentes')
    stub_jev("novo_#{comercial.id}")
    allow(cliente).to receive(:create) do
      Crm::SubjectDecision.create!(account: account, conversation: conversation, message: newer, mode: 'auto',
                                   action: 'none', state: 'pending')
      { text: { resposta: "novo_#{comercial.id}", titulo: 'Chat2You', seguro: true, motivo: 'ok' }.to_json }
    end

    expect(identify(message)).to have_attributes(action: 'create', state: 'superseded')
    expect(account.crm_cards.count).to eq(1)
  end

  it 'mensagem mais nova que falhou não passa na frente de uma decisão certa' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    message = incoming('E o Chat2You?')
    newer = incoming('???')
    Crm::SubjectDecision.create!(account: account, conversation: conversation, message: newer, mode: 'auto', action: 'none',
                                 state: 'failed')
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

    expect(identify(message)).to have_attributes(action: 'create', state: 'applied')
    expect(account.crm_cards.count).to eq(2)
  end

  it 'erro inesperado antes de aplicar tira a reserva, para o retry do job perguntar de novo' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')
    allow(Crm::Cards::Creator).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'boom')
    message = incoming('E o Chat2You?')

    expect { identify(message) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Crm::SubjectDecision.where(message: message)).to be_empty
    expect(account.crm_cards.count).to eq(1)
  end

  it 'falha no aviso em tempo real depois de aplicar não repete a criação no retry' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')
    allow(Crm::Cards::Broadcaster).to receive(:broadcast).and_raise(Redis::CannotConnectError)
    message = incoming('E o Chat2You?')

    expect { identify(message) }.to raise_error(Redis::CannotConnectError)
    expect(identify(message)).to have_attributes(action: 'create', state: 'applied')
    expect(account.crm_cards.count).to eq(2)
  end

  it 'não sobrescreve o nome que uma pessoa deu ao card enquanto a IA pensava' do
    card = create_card(title: 'Joana Lima')
    stub_jev("novo_#{comercial.id}")
    allow(cliente).to receive(:create) do
      card.update!(title: 'Plano anual de agentes')
      { text: { resposta: "novo_#{comercial.id}", titulo: 'Agentes de IA', seguro: true, motivo: 'ok' }.to_json }
    end

    expect(identify(incoming('Quero agentes de IA'))).to have_attributes(action: 'rename', state: 'kept', reason: 'card_mudou')
    expect(card.reload.title).to eq('Plano anual de agentes')
  end

  it 'card fechado enquanto a IA pensava não volta a ser o assunto atual' do
    agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago)
    chat2you = create_card(title: 'Chat2You', focused_at: 1.hour.ago)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do
      agentes.update!(status: :won)
      body = { model: 'jev-1.13.0', usage: { input_tokens: 1, output_tokens: 1 },
               answers: { decisao: { type: 'choice', choice: "card_#{agentes.id}", confidence: 0.95 } } }
      { status: 200, body: body.to_json }
    end

    expect(identify(incoming('Sobre os agentes...'))).to have_attributes(action: 'focus', state: 'kept')
    expect(finder.find(conversation)).to eq(chat2you)
  end

  it 'custo do Jev e do modelo maior entram na Gestão IA com as features de assunto' do
    create_card(title: 'Joana Lima')
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Agentes de IA')

    identify(incoming('Quero agentes de IA'))

    expect(Crm::AiUsageEvent.where(account_id: account.id).pluck(:feature)).to include('assunto')
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'assunto_revisao', account: account))
  end

  describe 'ligada por padrão, respeitando a pessoa (#1260)' do
    it 'caixa nova nasce Desligada: quem liga é o admin, caixa por caixa' do
      outra = create(:inbox, account: account)

      expect(account.crm_inbox_settings.create!(inbox: outra, crm_enabled: true)).to be_subject_ai_off
    end

    it 'funil com a IA do funil desligada fica de fora: não pergunta nada' do
      comercial.update!(metadata: { 'ai' => { 'enabled' => false } })
      requests = stub_jev("novo_#{comercial.id}")

      expect(identify(incoming('Quero o Chat2You'))).to be_nil
      expect(requests).to be_empty
    end

    it 'IA do CRM desligada na instalação: não pergunta nada' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)
      requests = stub_jev("novo_#{comercial.id}")

      expect(identify(incoming('Quero o Chat2You'))).to be_nil
      expect(requests).to be_empty
    end

    it 'assunto escolhido por uma pessoa há pouco: voltar a outro vira sugestão' do
      agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago)
      chat2you = create_card(title: 'Chat2You', focused_at: 1.hour.ago)
      Crm::Cards::Focus.new(account: account, card: chat2you, conversation: conversation, user: admin).perform
      stub_jev("card_#{agentes.id}")

      decision = identify(incoming('Voltando aos agentes'))

      expect(decision).to have_attributes(action: 'focus', state: 'suggested', card_id: agentes.id)
      expect(finder.find(conversation)).to eq(chat2you)
    end

    it 'escolha da pessoa de mais de 4 h atrás não segura mais a IA' do
      agentes = create_card(title: 'Agentes de IA', focused_at: 6.hours.ago)
      chat2you = create_card(title: 'Chat2You', focused_at: 5.hours.ago)
      Crm::CardConversation.find_by(card: chat2you, conversation: conversation).update!(focused_by_id: admin.id)
      stub_jev("card_#{agentes.id}")

      expect(identify(incoming('Voltando aos agentes'))).to have_attributes(action: 'focus', state: 'applied')
    end

    it 'card daquele funil fechado há pouco: o pedido novo vira sugestão, não card' do
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago).update!(status: :lost)
      create_card(title: 'Chat2You', focused_at: 2.hours.ago)
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Agentes de IA')

      expect { identify(incoming('Quero os agentes de novo')) }.not_to change(Crm::Card, :count)
      expect(Crm::SubjectDecision.last).to have_attributes(action: 'create', state: 'suggested')
    end

    it 'sugestão dispensada não volta: nem sugere de novo nem chama o modelo maior' do
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
      Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'auto', action: 'create',
                                   state: 'dismissed', pipeline: comercial, title: 'Chat2You')
      stub_jev("novo_#{comercial.id}")

      decision = identify(incoming('E o Chat2You?'))

      expect(decision).to have_attributes(state: 'kept', reason: 'sugestao_dispensada')
      expect(cliente).not_to have_received(:create)
    end

    it 'card de funil com a IA desligada não é opção para voltar' do
      suporte = account.crm_pipelines.create!(name: 'Suporte', created_by: admin, status: :active,
                                              metadata: { 'ai' => { 'enabled' => false } })
      etapa = account.crm_pipeline_stages.create!(pipeline: suporte, name: 'Aberto', position: 0)
      fora = account.crm_cards.create!(pipeline: suporte, stage: etapa, contact: contact, primary_conversation: conversation,
                                       inbox: inbox, title: 'Troca de senha')
      Crm::CardConversation.find_or_create_by!(account: account, card: fora, conversation: conversation).update!(focused_at: 2.hours.ago)
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
      requests = stub_jev('sem_assunto')

      identify(incoming('Oi'))

      expect(requests.first['questions']['decisao']['criteria'].keys).not_to include("card_#{fora.id}")
    end

    it 'card arquivado há pouco naquele funil: o pedido novo vira sugestão' do
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago).update!(status: :archived)
      create_card(title: 'Chat2You', focused_at: 2.hours.ago)
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Agentes de IA')

      expect { identify(incoming('Quero os agentes de novo')) }.not_to change(Crm::Card, :count)
      expect(Crm::SubjectDecision.last).to have_attributes(action: 'create', state: 'suggested')
    end

    # Pega (#1922): o arquivamento da IA ("não é negócio") contar como fechamento de uma pessoa, e o cliente que volta
    # ganhar só uma sugestão: um falso positivo da IA viraria pedido perdido em silêncio.
    it 'card arquivado pela IA como "não é negócio": o pedido novo vira card' do
      arquivado = create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
      arquivado.update!(status: :archived)
      Crm::ActivityLogger.new(card: arquivado, actor: nil, event_type: 'archive', payload: { by: 'ai', motivo: 'fora_do_negocio' }).perform
      create_card(title: 'Chat2You', focused_at: 2.hours.ago)
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Agentes de IA')

      expect { identify(incoming('Quero os agentes de novo')) }.to change(Crm::Card, :count).by(1)
    end

    it 'sugestão de nome dispensada também não volta' do
      create_card(title: 'Joana Lima', focused_at: 1.hour.ago)
      Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'auto', action: 'rename',
                                   state: 'dismissed', pipeline: comercial, title: 'Chat2You')
      stub_jev("novo_#{comercial.id}")

      expect(identify(incoming('Quero o Chat2You'))).to have_attributes(state: 'kept', reason: 'sugestao_dispensada')
    end

    it 'sugestão esquecida há mais de 24 h não prende a conversa' do
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago, metadata: { 'subject' => { 'source' => 'ai' } })
      antiga = Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'auto', action: 'create',
                                            state: 'suggested', pipeline: comercial, title: 'Chat2You')
      antiga.update_columns(updated_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

      expect(identify(incoming('E o Chat2You?'))).to have_attributes(action: 'create', state: 'applied')
    end

    it 'card criado pelo sistema não tira o assunto que uma pessoa escolheu' do
      chat2you = create_card(title: 'Chat2You', focused_at: 1.hour.ago)
      Crm::Cards::Focus.new(account: account, card: chat2you, conversation: conversation, user: admin).perform
      Crm::Cards::Creator.new(account: account, user: nil, conversation: conversation,
                              params: { pipeline_id: comercial.id, stage_id: first_stage.id, title: 'Outro' }).perform

      expect(finder.find(conversation)).to eq(chat2you)
    end
  end

  describe 'mensagem recuperada pelo WhatsApp Híbrido (#1638)' do
    let(:aviso) { 'Esta mensagem não é suportada' }

    def recuperar(message, content, quando: Time.current)
      message.update!(content: content,
                      content_attributes: message.content_attributes.merge('hybrid_recovered_at' => quando.utc.iso8601))
    end

    def decisao_da_ia_no_aviso
      create_card(title: 'Joana Lima')
      stub_jev('sem_assunto')
      message = incoming(aviso)
      identify(message)
      [message, Crm::SubjectDecision.find_by!(message: message)]
    end

    # A IA criou um card em cima do aviso (o pior caso): a decisão é applied/create com o card dela.
    def card_criado_no_aviso(titulo: 'Atendimento')
      card = create_card(title: titulo, focused_at: 1.minute.ago, metadata: { 'subject' => { 'source' => 'ai' } })
      message = incoming(aviso)
      decisao = Crm::SubjectDecision.create!(account: account, conversation: conversation, message: message, mode: 'auto',
                                             action: 'create', state: 'applied', card: card, pipeline: comercial,
                                             title: titulo, decided_by: 'review')
      [message, decisao, card]
    end

    def jev_com_titulo(titulo)
      stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: titulo)
    end

    it 'a decisão automática tomada em cima do aviso é reaberta na mesma linha e decidida com o texto real' do
      message, anterior = decisao_da_ia_no_aviso
      expect(anterior).to have_attributes(state: 'kept', action: 'none')

      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      requests = stub_jev("novo_#{comercial.id}")
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Seguro do Onix')

      decision = identify(message)

      expect(decision).to have_attributes(id: anterior.id, action: 'rename', state: 'applied', title: 'Seguro do Onix')
      expect(Crm::SubjectDecision.where(message: message).count).to eq(1)
      expect(requests.size).to eq(1)
      expect(requests.first['state'].to_json).to include('Onix')
    end

    it 'o card que a IA criou em cima do aviso ganha o assunto real: mesmo card, nenhum segundo' do
      message, anterior, card = card_criado_no_aviso
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      jev_com_titulo('Seguro do Onix')

      decision = identify(message)

      expect(decision).to have_attributes(id: anterior.id, action: 'rename', state: 'applied', card_id: card.id,
                                          title: 'Seguro do Onix')
      expect(card.reload.title).to eq('Seguro do Onix')
      expect(account.crm_cards.count).to eq(1)
      expect(finder.find(conversation)).to eq(card)
    end

    it 'nome que a pessoa trocou à mão depois da IA fica' do
      message, anterior, card = card_criado_no_aviso
      card.update!(title: 'Renovação da frota')
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      jev_com_titulo('Seguro do Onix')

      # Nada mudou: a decisão volta ao que era antes.
      expect(identify(message)).to have_attributes(id: anterior.id, state: 'applied', action: 'create', card_id: card.id)
      expect(card.reload.title).to eq('Renovação da frota')
      expect(account.crm_cards.count).to eq(1)
    end

    it 'mesmo assunto com o texto real: nada muda e a tela não é avisada de novo' do
      message, anterior, card = card_criado_no_aviso(titulo: 'Seguro do Onix')
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      jev_com_titulo('Seguro do Onix')
      allow(Crm::Subjects::Notifier).to receive(:notify)
      allow(Crm::Cards::Broadcaster).to receive(:broadcast)

      expect(identify(message)).to have_attributes(id: anterior.id, state: 'applied', action: 'create', card_id: card.id)
      expect(card.reload.title).to eq('Seguro do Onix')
      expect(Crm::Subjects::Notifier).not_to have_received(:notify)
      expect(Crm::Cards::Broadcaster).not_to have_received(:broadcast)
    end

    it 'sem assunto no texto real: a decisão volta ao que era e o card do aviso fica como estava' do
      message, anterior, card = card_criado_no_aviso
      travel 1.minute
      recuperar(message, 'ok')
      stub_jev('sem_assunto')

      identify(message)

      expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id, title: 'Atendimento',
                                                 decided_by: 'review')
      expect(card.reload).to have_attributes(title: 'Atendimento', pipeline_id: comercial.id)
    end

    context 'when the real subject is in another pipeline' do
      let(:suporte_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Suporte') }
      let(:suporte) { suporte_e_etapa.first }

      before do
        account.crm_pipeline_inboxes.create!(pipeline: suporte, inbox: inbox, default_stage: suporte_e_etapa.last,
                                             auto_create_card: true, created_by: admin)
      end

      def jev_no_suporte(titulo)
        stub_jev("novo_#{suporte.id}")
        stub_review(resposta: "novo_#{suporte.id}", titulo: titulo)
      end

      it 'leva o card do aviso para a 1ª etapa do funil certo e dá o nome: nenhum segundo card' do
        message, anterior, card = card_criado_no_aviso
        travel 1.minute
        recuperar(message, 'Minha internet caiu')
        jev_no_suporte('Internet caiu')

        decision = identify(message)

        expect(decision).to have_attributes(id: anterior.id, action: 'rename', state: 'applied', card_id: card.id,
                                            pipeline_id: suporte.id, title: 'Internet caiu')
        expect(card.reload).to have_attributes(pipeline_id: suporte.id, stage_id: suporte_e_etapa.last.id, title: 'Internet caiu')
        expect(account.crm_cards.count).to eq(1)
      end

      { 'etapa' => 'move', 'dono' => 'update' }.each do |mexida, evento|
        it "card em que uma pessoa mexeu (#{mexida}) fica como está, e nada novo nasce" do
          message, anterior, card = card_criado_no_aviso
          travel 30.seconds
          Crm::ActivityLogger.new(card: card, actor: admin, event_type: evento, payload: {}).perform
          travel 30.seconds
          recuperar(message, 'Minha internet caiu')
          jev_no_suporte('Internet caiu')
          allow(Rails.logger).to receive(:info)

          identify(message)

          expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id)
          expect(card.reload).to have_attributes(pipeline_id: comercial.id, title: 'Atendimento')
          expect(account.crm_cards.count).to eq(1)
          expect(Rails.logger).to have_received(:info).with(include('card do aviso mantido', "card=#{card.id}"))
        end
      end

      it 'nome trocado à mão: o card não muda de funil' do
        message, anterior, card = card_criado_no_aviso
        card.update!(title: 'Renovação da frota')
        travel 1.minute
        recuperar(message, 'Minha internet caiu')
        jev_no_suporte('Internet caiu')

        identify(message)

        expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id)
        expect(card.reload).to have_attributes(pipeline_id: comercial.id, title: 'Renovação da frota')
        expect(account.crm_cards.count).to eq(1)
      end

      context 'with the inbox in Suggest mode' do
        let(:mode) { :suggest }

        it 'a troca de funil não vira sugestão: o card fica e só o log registra' do
          message, anterior, card = card_criado_no_aviso
          travel 1.minute
          recuperar(message, 'Minha internet caiu')
          jev_no_suporte('Internet caiu')
          allow(Rails.logger).to receive(:info)

          identify(message)

          expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id)
          expect(card.reload).to have_attributes(pipeline_id: comercial.id, title: 'Atendimento')
          expect(Crm::SubjectDecision.suggested).to be_empty
          expect(Rails.logger).to have_received(:info).with(include('card do aviso mantido'))
        end
      end
    end

    describe 'resultado sem mudança depois de reabrir volta ao que era' do
      it 'dúvida (Jev e modelo maior inseguros)' do
        message, anterior, card = card_criado_no_aviso
        travel 1.minute
        recuperar(message, 'Talvez outra coisa')
        stub_jev("novo_#{comercial.id}", confidence: 0.4)
        stub_review(resposta: "novo_#{comercial.id}", titulo: 'Outra coisa', seguro: false)

        identify(message)

        expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id, title: 'Atendimento')
        expect(card.reload.title).to eq('Atendimento')
      end

      it 'vencida por uma mensagem mais nova enquanto a IA pensava' do
        message, anterior, card = card_criado_no_aviso
        travel 1.minute
        recuperar(message, 'Quero cotar o seguro do Onix')
        newer = incoming('Para dois carros')
        stub_jev("novo_#{comercial.id}", confidence: 0.4)
        allow(cliente).to receive(:create) do
          Crm::SubjectDecision.create!(account: account, conversation: conversation, message: newer, mode: 'auto',
                                       action: 'none', state: 'pending')
          { text: { resposta: "novo_#{comercial.id}", titulo: 'Seguro do Onix', seguro: true, motivo: 'ok' }.to_json }
        end

        identify(message)

        expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id, title: 'Atendimento')
        expect(card.reload.title).to eq('Atendimento')
      end

      it 'repetida: a mesma sugestão já espera uma pessoa' do
        message, anterior, card = card_criado_no_aviso
        outra = incoming('Outra mensagem')
        Crm::SubjectDecision.create!(account: account, conversation: conversation, message: outra, mode: 'suggest',
                                     action: 'create', state: 'suggested', pipeline: comercial, title: 'Seguro do Onix')
        travel 1.minute
        recuperar(message, 'Quero cotar o seguro do Onix')
        requests = stub_jev("novo_#{comercial.id}")

        identify(message)

        expect(requests.size).to eq(1)
        expect(cliente).not_to have_received(:create)
        expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id, title: 'Atendimento')
        expect(card.reload.title).to eq('Atendimento')
      end
    end

    it 'mensagem sem content_attributes não quebra a pergunta repetida (fluxo normal)' do
      create_card(title: 'Joana Lima')
      requests = stub_jev('sem_assunto')
      message = incoming('Oi')
      first = identify(message)
      message.update_column(:content_attributes, nil) # rubocop:disable Rails/SkipsModelValidations

      expect(identify(Message.find(message.id))).to eq(first)
      expect(requests.size).to eq(1)
    end

    it 'erro inesperado na decisão reaberta devolve a decisão ao que era, sem apagar a linha' do
      message, anterior, card = card_criado_no_aviso
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      jev_com_titulo('Seguro do Onix')
      # Falha dentro do lock, depois de renomear o card: a transação volta atrás.
      allow(Crm::ActivityLogger).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { identify(message) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id, title: 'Atendimento',
                                                 pipeline_id: comercial.id, decided_by: 'review')
      expect(card.reload.title).to eq('Atendimento')
      expect(anterior.updated_at).to be < 1.minute.ago + 1.second

      allow(Crm::ActivityLogger).to receive(:new).and_call_original
      expect(identify(message)).to have_attributes(id: anterior.id, action: 'rename', state: 'applied', title: 'Seguro do Onix')
      expect(account.crm_cards.count).to eq(1)
    end

    it 'falha no aviso depois de aplicar a reaberta: a nova tentativa não reabre nem cria outro card' do
      message, anterior, card = card_criado_no_aviso
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      travel Crm::Subjects::DEBOUNCE
      jev_com_titulo('Seguro do Onix')
      allow(Crm::Cards::Broadcaster).to receive(:broadcast).and_raise(Redis::CannotConnectError)

      expect { identify(message) }.to raise_error(Redis::CannotConnectError)
      requests = stub_jev("novo_#{comercial.id}")

      expect(identify(message)).to have_attributes(id: anterior.id, action: 'rename', state: 'applied', card_id: card.id)
      expect(requests).to be_empty
      expect(card.reload.title).to eq('Seguro do Onix')
      expect(account.crm_cards.count).to eq(1)
    end

    it 'card da IA fechado depois do aviso: o assunto real segue o caminho de sempre' do
      message, _anterior, card = card_criado_no_aviso
      card.update!(status: :won, closed_at: Time.current)
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      jev_com_titulo('Seguro do Onix')

      decision = identify(message)

      # Fechado há pouco por uma pessoa: o pedido novo vira sugestão (#1260), e o card fechado não é renomeado.
      expect(decision).to have_attributes(action: 'create', state: 'suggested', title: 'Seguro do Onix')
      expect(card.reload.title).to eq('Atendimento')
      expect(account.crm_cards.count).to eq(1)
    end

    it 'Jev fora do ar na decisão reaberta: vale o que valia antes' do
      message, anterior, card = card_criado_no_aviso
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(status: 200, body: { model: 'outro' }.to_json)

      identify(message)

      expect(anterior.reload).to have_attributes(state: 'applied', action: 'create', card_id: card.id, title: 'Atendimento')
    end

    it 'voltar ao mesmo assunto de antes avisa a tela quando o foco tinha mudado no meio-tempo' do
      agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago, metadata: { 'subject' => { 'source' => 'ai' } })
      outro = create_card(title: 'Chat2You', focused_at: 3.hours.ago, metadata: { 'subject' => { 'source' => 'ai' } })
      message = incoming(aviso)
      anterior = Crm::SubjectDecision.create!(account: account, conversation: conversation, message: message, mode: 'auto',
                                              action: 'focus', state: 'applied', card: agentes, decided_by: 'jev')
      Crm::Subjects::Acoes.focar(conversation: conversation, card: outro)
      travel 1.minute
      recuperar(message, 'Voltando aos agentes')
      stub_jev("card_#{agentes.id}")
      allow(Crm::Subjects::Notifier).to receive(:notify)

      expect(identify(message)).to have_attributes(id: anterior.id, action: 'focus', state: 'applied', card_id: agentes.id)
      expect(finder.find(conversation)).to eq(agentes)
      expect(Crm::Subjects::Notifier).to have_received(:notify)
    end

    it 'decisão gravada no mesmo segundo da recuperação reabre (o horário chega sem fração)' do
      travel_to(Time.zone.parse('2026-10-15 10:00:00.700'), with_usec: true)
      message, anterior = decisao_da_ia_no_aviso
      recuperar(message, 'Quero cotar o seguro do Onix', quando: Time.zone.parse('2026-10-15 10:00:00'))
      travel 20.seconds
      requests = stub_jev('sem_assunto')

      identify(message)

      expect(requests.size).to eq(1)
      expect(anterior.reload.updated_at).to be > Time.zone.parse('2026-10-15 10:00:01')
    end

    it 'reabre uma vez só: a decisão tomada depois da recuperação já leu o texto real' do
      message, = decisao_da_ia_no_aviso
      travel 1.minute
      recuperar(message, 'Quero cotar o seguro do Onix')
      travel Crm::Subjects::DEBOUNCE
      requests = stub_jev('sem_assunto')
      identify(message)
      travel 1.minute

      identify(message)

      expect(requests.size).to eq(1)
    end

    it 'sem a marca de recuperação a mensagem decidida não é perguntada de novo' do
      message, anterior = decisao_da_ia_no_aviso
      travel 1.minute
      message.update!(content: 'Editada sem recuperar')
      requests = stub_jev("novo_#{comercial.id}")

      expect(identify(message)).to eq(anterior)
      expect(requests).to be_empty
    end

    %w[accepted dismissed suggested pending].each do |state|
      it "decisão #{state} (escolha da pessoa, sugestão esperando ou reserva em curso) fica como está" do
        message, anterior = decisao_da_ia_no_aviso
        anterior.update!(state: state, action: 'create', pipeline: comercial, title: 'Escolha')
        travel 1.minute
        recuperar(message, 'Quero cotar o seguro do Onix')
        requests = stub_jev("novo_#{comercial.id}")

        expect(identify(message)).to have_attributes(id: anterior.id, state: state, title: 'Escolha')
        expect(requests).to be_empty
      end
    end
  end

  # C36 (#1711): cliente com card ganho volta por outro assunto numa caixa com card ao chegar.
  context 'when the inbox creates the card on arrival and the subject is in another pipeline (C36)' do
    let(:sinistro_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
    let(:sinistro) { sinistro_e_etapa.first }
    let!(:ganho) do
      account.crm_cards.create!(pipeline: comercial, stage: first_stage, contact: contact, title: 'Seguro do Tracker',
                                status: :won, closed_at: 60.days.ago, metadata: { 'subject' => { 'source' => 'ai' } })
    end

    before do
      # Sinistro com duas etapas: o card adotado vai para a primeira.
      create_crm_stage(account: account, pipeline: sinistro, name: 'Em análise', position: 1)
      account.crm_pipeline_inboxes.create!(pipeline: sinistro, inbox: inbox, default_stage: sinistro_e_etapa.last,
                                           auto_create_card: false, created_by: admin)
      account.enable_features!(Crm::Conversations::CardEmFoco::FLAG)
      allow(Crm::Config).to receive(:enabled?).and_return(true)
      allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    end

    def chega(texto)
      message = incoming(texto)
      chegada = Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: message).perform
      [message, chegada]
    end

    def jev_no_sinistro
      stub_jev("novo_#{sinistro.id}")
      stub_review(resposta: "novo_#{sinistro.id}", titulo: 'Sinistro por roubo do Tracker')
    end

    def abertos
      account.crm_cards.where(status: :open)
    end

    # Roda o bloco depois de a IA escolher o card da chegada e antes da trava em que ela aplica.
    # O bloco roda depois que este método já voltou (quando a IA chama .de): por isso guardado, não yield.
    def enquanto_a_ia_pensa(&mexida)
      acao = mexida
      allow(Crm::Subjects::CardDaChegada).to receive(:de).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap { acao.call }
      end
    end

    it 'leva o card da chegada para o funil do sinistro e dá o nome: nenhum card vazio em Comercial', :aggregate_failures do
      message, chegada = chega('roubaram meu carro hoje de madrugada 😭 o que eu faço?')
      expect(chegada).to have_attributes(pipeline_id: comercial.id, title: 'Joana Lima')
      jev_no_sinistro

      decision = identify(message)

      expect(decision).to have_attributes(action: 'rename', state: 'applied', card_id: chegada.id, pipeline_id: sinistro.id,
                                          title: 'Sinistro por roubo do Tracker')
      expect(chegada.reload).to have_attributes(pipeline_id: sinistro.id, stage_id: sinistro.stages.order(:position, :id).first.id,
                                                title: 'Sinistro por roubo do Tracker', status: 'open')
      expect(abertos.where(pipeline_id: comercial.id)).to be_empty
      expect(abertos.count).to eq(1)
      expect(finder.find(conversation)).to eq(chegada)
      expect(ganho.reload).to have_attributes(status: 'won', pipeline_id: comercial.id)
    end

    # #1918: o sem assunto toca o card em foco, menos o card vazio da chegada ainda intacto (movido pela IA num "oi", ele
    # deixaria de ser adotado pelo pedido seguinte de outro funil).
    it '"oi" sem assunto não toca o card da chegada intacto, e o pedido seguinte ainda o adota' do
      message, chegada = chega('oi, boa tarde')
      stub_jev('sem_assunto')

      expect(identify(message)).to have_attributes(state: 'kept', touched_card_ids: [])

      seguinte = incoming('roubaram meu carro hoje de madrugada')
      jev_no_sinistro
      expect(identify(seguinte)).to have_attributes(action: 'rename', state: 'applied', card_id: chegada.id)
    end

    it 'sem assunto toca o card da chegada que já mudou de etapa' do
      message, chegada = chega('já fechei com outra corretora')
      segunda = create_crm_stage(account: account, pipeline: comercial, name: 'Em atendimento', position: 1)
      Crm::Cards::Mover.new(card: chegada, actor: nil, target_stage: segunda).perform
      stub_jev('sem_assunto')

      expect(identify(message)).to have_attributes(state: 'kept', touched_card_ids: [chegada.id])
    end

    it 'agenda a IA do CRM no card já no funil do sinistro' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      jev_no_sinistro
      funis_na_chamada = []
      allow(Crm::Ai::Observer).to receive(:new).and_wrap_original do |original, card:|
        funis_na_chamada << [card.id, card.pipeline_id]
        original.call(card: card)
      end

      identify(message)

      expect(funis_na_chamada).to include([chegada.id, sinistro.id])
    end

    it 'uma pessoa escolheu o assunto há pouco: vira sugestão, como a criação, e o card da chegada não se move (#1260)' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      Crm::CardConversation.find_by(card: chegada, conversation: conversation).update!(focused_by_id: admin.id)
      jev_no_sinistro

      expect(identify(message)).to have_attributes(action: 'create', state: 'suggested')
      expect(chegada.reload.pipeline_id).to eq(comercial.id)
    end

    it 'o card mudou enquanto a IA pensava: o pedido não se perde, nasce o card do sinistro' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      jev_no_sinistro
      # A pessoa dá nome ao card entre a decisão e a trava (mexida real, com ator): a 2ª conferência recusa a adoção.
      enquanto_a_ia_pensa do
        chegada.update!(title: 'Renovação da frota')
        Crm::ActivityLogger.new(card: chegada, actor: admin, event_type: 'update', payload: { title: 'Renovação da frota' }).perform
      end

      decision = identify(message)

      expect(decision).to have_attributes(action: 'create', state: 'applied', pipeline_id: sinistro.id)
      expect(decision.card_id).not_to eq(chegada.id)
      expect(chegada.reload).to have_attributes(pipeline_id: comercial.id, title: 'Renovação da frota')
    end

    it 'a pessoa foca outro assunto enquanto a IA pensa: vira sugestão, nada é adotado (#1260)' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      outro = account.crm_cards.create!(pipeline: comercial, stage: first_stage, contact: contact, title: 'Renovação',
                                        primary_conversation: conversation, inbox: inbox)
      jev_no_sinistro
      enquanto_a_ia_pensa do
        Crm::Cards::Focus.new(account: account, card: outro, conversation: conversation, user: admin).perform
      end

      expect(identify(message)).to have_attributes(action: 'create', state: 'suggested', card_id: nil)
      expect(chegada.reload).to have_attributes(pipeline_id: comercial.id, title: 'Joana Lima')
      expect(abertos.where(pipeline_id: sinistro.id)).to be_empty
    end

    it 'a pessoa fecha um card de Sinistro desta conversa enquanto a IA pensa: vira sugestão, nada é adotado (#1260)' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      jev_no_sinistro
      enquanto_a_ia_pensa do
        account.crm_cards.create!(pipeline: sinistro, stage: sinistro_e_etapa.last, contact: contact, title: 'Sinistro antigo',
                                  primary_conversation: conversation, inbox: inbox, status: :lost, closed_at: Time.current)
      end

      expect(identify(message)).to have_attributes(action: 'create', state: 'suggested')
      expect(chegada.reload.pipeline_id).to eq(comercial.id)
      expect(abertos.where(pipeline_id: sinistro.id)).to be_empty
    end

    context 'with access per pipeline (#1148)' do
      def ana
        @ana ||= create_crm_agent(account: account, name: 'Ana Vendas').first
      end

      def so_comercial(user)
        acesso = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: true)
        acesso.agent_pipelines.create!(account: account, pipeline: comercial)
      end

      it 'dono do card da chegada sem o funil do sinistro: o card fica em Comercial e nasce o do sinistro' do
        message, chegada = chega('roubaram meu carro hoje de madrugada')
        chegada.update!(owner: ana)
        so_comercial(ana)
        jev_no_sinistro

        expect(identify(message)).to have_attributes(action: 'create', state: 'applied', pipeline_id: sinistro.id)
        expect(chegada.reload).to have_attributes(pipeline_id: comercial.id, owner_id: ana.id)
      end

      it 'sem acesso por funil na conta, o card da chegada com dono vai para o sinistro' do
        message, chegada = chega('roubaram meu carro hoje de madrugada')
        chegada.update!(owner: ana)
        jev_no_sinistro

        expect(identify(message)).to have_attributes(action: 'rename', card_id: chegada.id, pipeline_id: sinistro.id)
        expect(chegada.reload).to have_attributes(pipeline_id: sinistro.id, owner_id: ana.id)
      end
    end

    it 'card sem nome de outra conversa do cliente não é adotado' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      outra = create(:conversation, account: account, inbox: inbox, contact: contact)
      chegada.update!(conversation_id: outra.id)
      jev_no_sinistro

      expect(identify(message)).to have_attributes(action: 'create', pipeline_id: sinistro.id)
      expect(chegada.reload.pipeline_id).to eq(comercial.id)
    end

    it 'sem a flag, como antes: nasce o card do sinistro e o da chegada fica' do
      account.disable_features!(Crm::Conversations::CardEmFoco::FLAG)
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      jev_no_sinistro

      decision = identify(message)

      expect(decision).to have_attributes(action: 'create', state: 'applied', pipeline_id: sinistro.id)
      expect(chegada.reload).to have_attributes(pipeline_id: comercial.id, title: 'Joana Lima')
      expect(abertos.count).to eq(2)
    end

    it 'card da chegada que já mudou de etapa é de um assunto de Comercial: fica, e nasce o do sinistro' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      proposta = comercial.stages.find_by(name: 'Proposta')
      Crm::Cards::Mover.new(card: chegada, actor: nil, target_stage: proposta, automation_context: { skip_automations: true }).perform
      jev_no_sinistro

      decision = identify(message)

      expect(decision).to have_attributes(action: 'create', pipeline_id: sinistro.id)
      expect(chegada.reload).to have_attributes(pipeline_id: comercial.id, stage_id: proposta.id)
    end

    it 'card da chegada em que uma pessoa mexeu no dono: fica, e nasce o do sinistro' do
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      Crm::ActivityLogger.new(card: chegada, actor: admin, event_type: 'update', payload: {}).perform
      jev_no_sinistro

      expect(identify(message)).to have_attributes(action: 'create', pipeline_id: sinistro.id)
      expect(chegada.reload.pipeline_id).to eq(comercial.id)
    end

    it 'com a caixa em Sugerir, nada se move: a sugestão segue como antes' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :suggest)
      message, chegada = chega('roubaram meu carro hoje de madrugada')
      jev_no_sinistro

      expect(identify(message)).to have_attributes(action: 'create', state: 'suggested')
      expect(chegada.reload.pipeline_id).to eq(comercial.id)
    end
  end
end
