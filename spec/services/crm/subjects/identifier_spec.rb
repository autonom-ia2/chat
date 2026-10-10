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

  def stub_review(resposta:, titulo: '', seguro: true)
    allow(cliente).to receive(:create).and_return(text: { resposta: resposta, titulo: titulo, seguro: seguro, motivo: 'ok' }.to_json)
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
end
