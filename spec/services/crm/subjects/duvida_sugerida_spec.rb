require 'rails_helper'

# #2162: com a flag `crm_ia_duvida_vira_sugestao`, a dúvida da IA de assunto em que alguém (o Jev ou o modelo maior) viu
# um pedido novo vira sugestão de criar o card, que a equipe aceita ou ignora. Nada é criado sozinho. A dúvida sem sinal
# de pedido novo fica como antes. O Jev e o modelo maior são simulados: nenhuma IA paga.
RSpec.describe 'IA de assunto: dúvida com sinal de pedido novo vira sugestão' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Comercial') }
  let(:comercial) { pipeline_and_stage.first }
  let(:first_stage) { pipeline_and_stage.last }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda').first }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:mode) { :auto }

  before do
    [comercial, pos_venda].each do |pipeline|
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: pipeline.stages.first, auto_create_card: false,
                                           created_by: admin)
    end
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: mode)
    account.enable_features!(Crm::Subjects::DuvidaSugerida::FLAG)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    allow(Crm::Subjects::Notifier).to receive(:notify)
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def create_card(title:, pipeline: comercial, metadata: {})
    card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, contact: contact, primary_conversation: conversation,
                                     inbox: inbox, title: title, metadata: metadata)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: Time.current)
    card
  end

  def stub_jev(choice, confidence: 0.95)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(
      status: 200,
      body: { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
              answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }.to_json
    )
  end

  # Serve às duas perguntas (um assunto e vários assuntos, com um item que é o principal).
  def stub_review(resposta:, titulo: '', seguro: false)
    item = { resposta: resposta, titulo: titulo, seguro: seguro }
    allow(cliente).to receive(:create).and_return(text: item.merge(motivo: 'não ficou claro', assuntos: [item], principal: 0).to_json)
  end

  def identify(message)
    Crm::Subjects::Identifier.new(conversation: conversation, message: message).perform
  end

  def novo(pipeline = comercial) = "novo_#{pipeline.id}"

  describe 'caminho feliz' do
    it 'o Jev viu pedido novo com certeza e o modelo maior ficou em dúvida: sugestão com o nome do modelo, nenhum card' do
      create_card(title: 'Seguro do Onix', metadata: { 'subject' => { 'source' => 'ai' } })
      stub_jev(novo, confidence: 0.88)
      stub_review(resposta: novo, titulo: 'Cotação seguro residencial')

      decisao = identify(incoming('quero cotar um seguro pra minha casa também'))

      expect(decisao).to have_attributes(state: 'suggested', action: 'create', pipeline_id: comercial.id, card_id: nil,
                                         title: 'Cotação seguro residencial', reason: 'duvida_pedido_novo', decided_by: 'review',
                                         jev_answer: 'novo', review_reason: 'pedido_novo')
      expect(account.crm_cards.count).to eq(1)
      expect(Crm::Subjects::Notifier).to have_received(:notify).with(conversation)
    end

    it 'só o Jev viu o pedido novo, com certeza baixa: sugestão no funil dele, sem nome' do
      stub_jev(novo(pos_venda), confidence: 0.27)
      stub_review(resposta: 'sem_assunto')

      decisao = identify(incoming('segue a proposta nova e o primeiro boleto'))

      expect(decisao).to have_attributes(state: 'suggested', action: 'create', pipeline_id: pos_venda.id, title: nil,
                                         reason: 'duvida_pedido_novo', review_reason: 'certeza_baixa')
      expect(account.crm_cards.count).to eq(0)
    end

    it 'o modelo maior escolheu pedido novo mas não deu nome: sugestão sem nome' do
      stub_jev(novo, confidence: 0.3)
      stub_review(resposta: novo, titulo: '', seguro: true)

      expect(identify(incoming('preciso de uma cotação'))).to have_attributes(state: 'suggested', title: nil, pipeline_id: comercial.id)
    end

    it 'aceita sem nome, o card nasce sem nome e a IA de assunto dá o nome quando o pedido fica claro (#1918)' do
      stub_jev(novo, confidence: 0.3)
      stub_review(resposta: 'sem_assunto')
      decisao = identify(incoming('oi, preciso de uma ajuda'))

      card = Crm::Subjects::SuggestionResponder.new(decision: decisao, user: admin).accept

      expect(card).to have_attributes(title: 'Joana Lima', pipeline_id: comercial.id)
      expect(Crm::Subjects::Naming.named?(card)).to be(false)
      expect(decisao.reload).to have_attributes(state: 'accepted', card_id: card.id)

      stub_jev(novo, confidence: 0.95)
      stub_review(resposta: novo, titulo: 'Seguro do Kwid', seguro: true)
      identify(incoming('é pro kwid 2020 da minha filha'))
      expect(card.reload.title).to eq('Seguro do Kwid')
    end

    it 'aceita com nome, o card nasce com o nome da IA' do
      stub_jev(novo, confidence: 0.88)
      stub_review(resposta: novo, titulo: 'Seguro residencial')
      decisao = identify(incoming('e pra casa, vocês fazem?'))

      card = Crm::Subjects::SuggestionResponder.new(decision: decisao, user: admin).accept

      expect(card.title).to eq('Seguro residencial')
      expect(Crm::Subjects::Naming.named?(card)).to be(true)
    end

    context 'with the inbox in Suggest mode' do
      let(:mode) { :suggest }

      it 'a dúvida com sinal também vira sugestão' do
        stub_jev(novo, confidence: 0.4)
        stub_review(resposta: novo, titulo: 'Seguro residencial')

        expect(identify(incoming('e pra casa?'))).to have_attributes(state: 'suggested', reason: 'duvida_pedido_novo')
      end
    end

    context 'with several subjects per message (#1693)' do
      before { account.enable_features!(Crm::Conversations::CardEmFoco::FLAG) }

      it 'o principal em dúvida com sinal vira sugestão' do
        create_card(title: 'Seguro do Onix', metadata: { 'subject' => { 'source' => 'ai' } })
        stub_jev(novo, confidence: 0.5)
        stub_review(resposta: novo, titulo: 'Seguro residencial')

        decisao = identify(incoming('e pra casa?'))

        expect(decisao).to have_attributes(state: 'suggested', action: 'create', reason: 'duvida_pedido_novo')
        expect(account.crm_cards.count).to eq(1)
      end
    end
  end

  # #2084: a pessoa marca o contato como parceiro enquanto o modelo maior pensa. A dúvida não vira sugestão.
  it 'contato marcado parceiro durante a dúvida: nenhuma sugestão fica esperando' do
    account.enable_features!('contato_relacao')
    create_card(title: 'Seguro do Onix', metadata: { 'subject' => { 'source' => 'ai' } })
    stub_jev(novo, confidence: 0.88)
    item = { resposta: novo, titulo: 'Cotação seguro residencial', seguro: false }
    allow(cliente).to receive(:create) do
      contact.update!(relacao: :parceiro)
      { text: item.merge(motivo: 'não ficou claro', assuntos: [item], principal: 0).to_json }
    end

    decisao = identify(incoming('quero cotar um seguro pra minha casa também'))

    expect(decisao.state).not_to eq('suggested')
    expect(Crm::SubjectDecision.where(state: 'suggested')).to be_empty
    expect(account.crm_cards.count).to eq(1)
  end

  describe 'caminho triste' do
    it 'dúvida sem sinal de pedido novo fica como antes' do
      create_card(title: 'Seguro do Onix', metadata: { 'subject' => { 'source' => 'ai' } })
      stub_jev('mesmo_assunto', confidence: 0.4)
      stub_review(resposta: 'mesmo_assunto')

      expect(identify(incoming('hmm, vou ver'))).to have_attributes(state: 'doubt', action: 'none', reason: 'não ficou claro')
      expect(Crm::SubjectDecision.where(state: 'suggested')).to be_empty
    end

    it 'sem a flag, a dúvida não muda nada' do
      account.disable_features!(Crm::Subjects::DuvidaSugerida::FLAG)
      stub_jev(novo, confidence: 0.88)
      stub_review(resposta: novo, titulo: 'Seguro residencial')

      expect(identify(incoming('e pra casa?'))).to have_attributes(state: 'doubt', action: 'none')
      expect(Crm::Subjects::Notifier).not_to have_received(:notify)
    end

    it 'sugestão ignorada não volta (#1260)' do
      stub_jev(novo, confidence: 0.3)
      stub_review(resposta: novo, titulo: 'Seguro residencial')
      primeira = identify(incoming('e pra casa?'))
      Crm::Subjects::SuggestionResponder.new(decision: primeira, user: admin).dismiss

      stub_jev('sem_assunto', confidence: 0.3)
      segunda = identify(incoming('é um apartamento'))

      expect(segunda).to have_attributes(state: 'doubt', action: 'none')
      expect(primeira.reload.state).to eq('dismissed')
    end

    it 'o card sem nome da conversa recebe o pedido quando ficar claro: a dúvida fica' do
      create_card(title: 'Joana Lima')
      stub_jev(novo, confidence: 0.3)
      stub_review(resposta: novo, titulo: 'Seguro residencial')

      expect(identify(incoming('e pra casa?'))).to have_attributes(state: 'doubt')
    end
  end

  describe 'estresse' do
    it 'cinco dúvidas seguidas no mesmo funil: uma sugestão só, as outras ficam em dúvida ou mantidas' do
      stub_jev('sem_assunto', confidence: 0.2)
      stub_review(resposta: novo, titulo: 'Seguro residencial')

      decisoes = Array.new(5) { |indice| identify(incoming("mensagem #{indice}")) }

      expect(decisoes.map(&:state)).to eq(%w[suggested doubt doubt doubt doubt])
      expect(Crm::SubjectDecision.where(state: 'suggested').count).to eq(1)
      expect(account.crm_cards.count).to eq(0)
    end

    it 'com uma sugestão esperando a pessoa, a dúvida de outro funil não a derruba' do
      stub_jev('sem_assunto', confidence: 0.2)
      stub_review(resposta: novo, titulo: 'Seguro residencial')
      primeira = identify(incoming('e pra casa?'))
      stub_review(resposta: novo(pos_venda), titulo: 'Segunda via do boleto')

      segunda = identify(incoming('e o boleto venceu'))

      expect(primeira.reload.state).to eq('suggested')
      expect(segunda).to have_attributes(state: 'doubt', action: 'none')
    end

    it 'respondida a sugestão, a próxima dúvida de outro funil pode sugerir' do
      stub_jev('sem_assunto', confidence: 0.2)
      stub_review(resposta: novo, titulo: 'Seguro residencial')
      primeira = identify(incoming('e pra casa?'))
      Crm::Subjects::SuggestionResponder.new(decision: primeira, user: admin).accept
      stub_review(resposta: novo(pos_venda), titulo: 'Segunda via do boleto')

      expect(identify(incoming('e o boleto venceu'))).to have_attributes(state: 'suggested', pipeline_id: pos_venda.id)
    end

    it 'uma mensagem mais nova já decidida passa na frente: nada é sugerido' do
      mensagem = incoming('e pra casa?')
      mais_nova = incoming('esquece')
      Crm::SubjectDecision.create!(account: account, conversation: conversation, message: mais_nova, mode: 'auto', action: 'none',
                                   state: 'kept')
      stub_jev(novo, confidence: 0.3)
      stub_review(resposta: novo, titulo: 'Seguro residencial')

      expect(identify(mensagem)).to have_attributes(state: 'superseded')
      expect(Crm::SubjectDecision.where(state: 'suggested')).to be_empty
    end
  end

  describe 'medição' do
    it 'conta dúvidas, sugeridas e o que a equipe fez' do
      stub_jev('sem_assunto', confidence: 0.2)
      stub_review(resposta: novo, titulo: 'Seguro residencial')
      aceita = identify(incoming('e pra casa?'))
      Crm::Subjects::SuggestionResponder.new(decision: aceita, user: admin).accept
      stub_review(resposta: novo(pos_venda), titulo: 'Boleto')
      ignorada = identify(incoming('e o boleto?'))
      Crm::Subjects::SuggestionResponder.new(decision: ignorada, user: admin).dismiss
      stub_review(resposta: 'mesmo_assunto')
      identify(incoming('ok'))

      expect(Crm::Subjects::DuvidaSugerida.medicao(account: account, desde: 1.day.ago))
        .to eq(duvidas_sem_sugestao: 1, sugeridas: 2, aceitas: 1, ignoradas: 1, esperando: 0, vencidas: 0, superadas: 0)
    end
  end
end
