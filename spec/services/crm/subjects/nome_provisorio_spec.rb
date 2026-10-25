require 'rails_helper'

# #2163: com a flag `crm_ia_nome_provisorio`, o nome genérico ("Nova cotação") que o modelo maior deu por falta de
# informação é refinado UMA vez quando o detalhe chega no mesmo pedido, no mesmo card. Nome dado ou editado por pessoa
# nunca muda. O card sem nome que já carregava um pedido não é renomeado pelo segundo: nasce outro card.
# O Jev e o modelo maior são simulados: nenhuma IA paga.
RSpec.describe 'IA de assunto: nome genérico refinado uma vez' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Comercial') }
  let(:comercial) { pipeline_and_stage.first }
  let(:first_stage) { pipeline_and_stage.last }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:mode) { :auto }
  let(:novo) { "novo_#{comercial.id}" }

  before do
    account.crm_pipeline_inboxes.create!(pipeline: comercial, inbox: inbox, default_stage: first_stage, auto_create_card: false,
                                         created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: mode)
    account.enable_features!(Crm::Subjects::NomeProvisorio::FLAG)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def create_card(title:, metadata: {})
    card = account.crm_cards.create!(pipeline: comercial, stage: first_stage, contact: contact, primary_conversation: conversation,
                                     inbox: inbox, title: title, metadata: metadata)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: Time.current)
    card
  end

  # O Jev responde `choice`; devolve os corpos enviados (as opções e as descrições que ele leu).
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

  # Serve às duas perguntas (um assunto e vários assuntos, com um item que é o principal).
  def stub_review(resposta:, titulo: '', generico: false, seguro: true)
    item = { resposta: resposta, titulo: titulo, seguro: seguro, nome_generico: generico }
    allow(cliente).to receive(:create) do |**args|
      chamadas << args
      { text: item.merge(motivo: 'ok', assuntos: [item], principal: 0).to_json }
    end
  end

  # Os pedidos ao modelo maior, na ordem.
  def chamadas
    @chamadas ||= []
  end

  def identify(message)
    Crm::Subjects::Identifier.new(conversation: conversation, message: message).perform
  end

  def chamada_ao_modelo = chamadas.last

  def pedido_generico
    stub_jev(novo)
    stub_review(resposta: novo, titulo: 'Nova cotação', generico: true)
    identify(incoming('consegue fazer outra cotação?'))
    account.crm_cards.order(:id).last
  end

  describe 'nome genérico' do
    it 'o modelo maior diz se o nome é genérico, e o card nasce com a marca de provisório' do
      card = pedido_generico

      chamada = chamada_ao_modelo
      expect(chamada[:schema][:schema][:required]).to include('nome_generico')
      expect(chamada[:instructions]).to include(Crm::Subjects::Reviewer::INSTRUCOES_NOME_GENERICO)
      expect(card.title).to eq('Nova cotação')
      expect(card.metadata['subject']).to include('source' => 'ai', 'provisorio' => true, 'titulo' => 'Nova cotação')
    end

    it 'nome específico nasce sem a marca' do
      stub_jev(novo)
      stub_review(resposta: novo, titulo: 'Seguro do Kwid', generico: false)

      identify(incoming('quero cotar o seguro do kwid 2020 da minha filha'))

      expect(account.crm_cards.order(:id).last.metadata['subject']).not_to have_key('provisorio')
    end

    it 'o detalhe que chega depois ("mesmo assunto") refina o nome, no mesmo card, uma vez só', :aggregate_failures do
      card = pedido_generico
      requests = stub_jev('mesmo_assunto')
      stub_review(resposta: 'mesmo_assunto', titulo: 'Seguro do Kwid da filha')

      decisao = identify(incoming('é pro carro da minha filha, um kwid 2020'))

      expect(decisao).to have_attributes(action: 'rename', state: 'applied', card_id: card.id, title: 'Seguro do Kwid da filha',
                                         review_reason: 'nome_provisorio', reason: 'nome_refinado')
      expect(account.crm_cards.count).to eq(1)
      expect(card.reload.title).to eq('Seguro do Kwid da filha')
      expect(card.metadata['subject']).not_to have_key('provisorio')
      expect(requests.last.dig('questions', 'decisao', 'criteria', 'mesmo_assunto')).to include(Crm::Subjects::Question::NOME_GENERICO)
      expect(chamada_ao_modelo[:instructions]).to include(Crm::Subjects::Reviewer::INSTRUCOES_NOME_DO_ATUAL)

      # Refinado, o nome não muda de novo: o Jev decide sozinho e o modelo maior não é chamado.
      stub_jev('mesmo_assunto')
      stub_review(resposta: 'mesmo_assunto', titulo: 'Outro nome')
      expect(identify(incoming('ela tem 19 anos e é a condutora'))).to have_attributes(action: 'none', state: 'kept', review_reason: nil)
      expect(card.reload.title).to eq('Seguro do Kwid da filha')
      expect(chamadas.size).to eq(2)
    end

    it 'o Jev vê pedido novo, o modelo maior entende que é o detalhe do mesmo pedido: um card só, com o nome específico' do
      card = pedido_generico
      stub_jev(novo)
      stub_review(resposta: 'mesmo_assunto', titulo: 'Seguro do Kwid da filha')

      decisao = identify(incoming('é pro carro da minha filha, um kwid 2020'))

      expect(decisao).to have_attributes(action: 'rename', state: 'applied', card_id: card.id, review_reason: 'pedido_novo')
      expect(account.crm_cards.count).to eq(1)
      expect(card.reload.title).to eq('Seguro do Kwid da filha')
    end

    it 'o detalhe ainda não chegou (nome vazio ou genérico de novo): o nome e a marca ficam' do
      card = pedido_generico
      stub_jev('mesmo_assunto')
      stub_review(resposta: 'mesmo_assunto', titulo: 'Outra cotação', generico: true)

      decisao = identify(incoming('pode ser hoje ainda?'))

      expect(decisao).to have_attributes(action: 'none', state: 'kept', reason: 'mesmo_assunto')
      expect(card.reload).to have_attributes(title: 'Nova cotação')
      expect(card.metadata.dig('subject', 'provisorio')).to be(true)

      stub_review(resposta: 'mesmo_assunto', titulo: '')
      expect(identify(incoming('?'))).to have_attributes(action: 'none', state: 'kept')
      expect(card.reload.title).to eq('Nova cotação')
    end

    it 'o detalhe que nunca chega não custa sem fim: o "mesmo assunto" pede o nome ao modelo maior no máximo 3 vezes' do
      card = pedido_generico
      stub_jev('mesmo_assunto')
      stub_review(resposta: 'mesmo_assunto', titulo: '')

      motivos = Array.new(4) { |indice| identify(incoming("mensagem #{indice}")).review_reason }

      expect(motivos).to eq(['nome_provisorio', 'nome_provisorio', 'nome_provisorio', nil])
      expect(chamadas.size).to eq(4)
      expect(card.reload.title).to eq('Nova cotação')
    end

    it 'um pedido diferente de verdade (o modelo diz pedido novo) segue criando outro card' do
      pedido_generico
      stub_jev(novo)
      stub_review(resposta: novo, titulo: 'Seguro residencial')

      identify(incoming('e também quero um seguro pra minha casa'))

      expect(account.crm_cards.order(:id).pluck(:title)).to eq(['Nova cotação', 'Seguro residencial'])
    end

    it 'nome editado por pessoa nunca é trocado, nem quando o modelo manda um nome' do
      card = pedido_generico
      card.update!(title: 'Cotação Kwid')
      Crm::ActivityLogger.new(card: card, actor: admin, event_type: 'update', payload: { title: 'Cotação Kwid' }).perform
      requests = stub_jev('mesmo_assunto')

      decisao = identify(incoming('é pro carro da minha filha'))

      expect(decisao).to have_attributes(action: 'none', state: 'kept', review_reason: nil)
      expect(chamadas.size).to eq(1)
      expect(requests.last.dig('questions', 'decisao', 'criteria', 'mesmo_assunto')).not_to include(Crm::Subjects::Question::NOME_GENERICO)

      stub_jev(novo, confidence: 0.3)
      stub_review(resposta: 'mesmo_assunto', titulo: 'Seguro do Kwid da filha')
      identify(incoming('um kwid 2020'))
      expect(card.reload.title).to eq('Cotação Kwid')
    end

    it 'nome dado por pessoa (sem a marca) não é refinado' do
      card = create_card(title: 'Nova cotação', metadata: { 'subject' => { 'source' => 'ai' } })
      stub_jev('mesmo_assunto', confidence: 0.3)
      stub_review(resposta: 'mesmo_assunto', titulo: 'Seguro do Kwid')

      identify(incoming('é um kwid 2020'))

      expect(card.reload.title).to eq('Nova cotação')
    end
  end

  describe 'card sem nome que já carregava um pedido' do
    before { account.enable_features!(Crm::Conversations::CardEmFoco::FLAG) }

    let!(:card) { create_card(title: 'Joana Lima') }

    def mesmo_assunto!(texto = 'vou mostrar pros dois e te aviso')
      stub_jev('mesmo_assunto')
      stub_review(resposta: 'mesmo_assunto')
      identify(incoming(texto))
    end

    it 'o 1º pedido no card sem nome ainda dá nome a ele (#1918)' do
      stub_jev(novo)
      stub_review(resposta: novo, titulo: 'Seguro viagem EUA')

      identify(incoming('casal pros EUA saindo 21/09, consegue?'))

      expect(card.reload.title).to eq('Seguro viagem EUA')
      expect(account.crm_cards.count).to eq(1)
    end

    it '"o mesmo assunto" marca que o card carrega um pedido' do
      expect(mesmo_assunto!).to have_attributes(action: 'none', state: 'kept', card_id: card.id, reason: 'mesmo_assunto')
      expect(Crm::Subjects::NomeProvisorio.carrega_pedido?(card)).to be(true)
    end

    it 'o pedido novo no mesmo funil vira outro card: o primeiro pedido não é apagado' do
      mesmo_assunto!
      requests = stub_jev(novo)
      stub_review(resposta: novo, titulo: 'Seguro viagem Uruguai')

      decisao = identify(incoming('tenho uma senhora de 71 que vai pro Uruguai'))

      novo_card = account.crm_cards.order(:id).last
      expect(novo_card).not_to eq(card)
      expect(decisao).to have_attributes(action: 'create', state: 'applied', card_id: novo_card.id, reason: 'card_ja_tinha_pedido')
      expect(novo_card.title).to eq('Seguro viagem Uruguai')
      expect(card.reload.title).to eq('Joana Lima')
      criterios = requests.last.dig('questions', 'decisao', 'criteria')
      expect(criterios['mesmo_assunto']).to include(Crm::Subjects::Question::SEM_NOME_COM_PEDIDO)
      expect(criterios[novo]).to include('something new, different from the subjects above')
    end

    it 'ganha nome pelo "mesmo assunto" quando o modelo diz qual é o pedido' do
      mesmo_assunto!
      stub_jev('mesmo_assunto')
      stub_review(resposta: 'mesmo_assunto', titulo: 'Seguro viagem EUA casal')

      decisao = identify(incoming('são 2, de 58 e 60 anos, pros EUA'))

      expect(decisao).to have_attributes(action: 'rename', state: 'applied', card_id: card.id, title: 'Seguro viagem EUA casal')
      expect(card.reload.title).to eq('Seguro viagem EUA casal')
      expect(account.crm_cards.count).to eq(1)
    end

    context 'with the inbox in Suggest mode' do
      let(:mode) { :suggest }

      it 'o "mesmo assunto" não dá nome, e o modelo maior não pede o nome genérico' do
        mesmo_assunto!
        stub_jev('mesmo_assunto', confidence: 0.3)
        stub_review(resposta: 'mesmo_assunto', titulo: 'Seguro viagem EUA casal')

        identify(incoming('são 2, de 58 e 60 anos'))

        chamada = chamada_ao_modelo
        expect(chamada[:schema][:schema][:properties][:assuntos][:items][:required]).not_to include('nome_generico')
        expect(chamada[:instructions]).not_to include(Crm::Subjects::Reviewer::INSTRUCOES_NOME_DO_ATUAL)
        expect(card.reload.title).to eq('Joana Lima')
      end
    end
  end

  describe 'sem a flag' do
    before { account.disable_features!(Crm::Subjects::NomeProvisorio::FLAG) }

    it 'pergunta e comportamento de antes: sem marca, sem nome_generico, "o mesmo assunto" sem reason' do
      stub_jev(novo)
      stub_review(resposta: novo, titulo: 'Nova cotação', generico: true)
      identify(incoming('consegue fazer outra cotação?'))
      card = account.crm_cards.order(:id).last

      chamada = chamada_ao_modelo
      expect(chamada[:schema][:schema][:required]).not_to include('nome_generico')
      expect(chamada[:instructions]).not_to include(Crm::Subjects::Reviewer::INSTRUCOES_NOME_GENERICO)
      expect(card.metadata['subject']).not_to have_key('provisorio')

      stub_jev('mesmo_assunto')
      stub_review(resposta: 'mesmo_assunto', titulo: 'Seguro do Kwid')
      expect(identify(incoming('é um kwid 2020'))).to have_attributes(action: 'none', state: 'kept', reason: nil, review_reason: nil)
      expect(card.reload.title).to eq('Nova cotação')
    end
  end
end
