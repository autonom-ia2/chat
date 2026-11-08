require 'rails_helper'

# #1693: uma mensagem pode tocar vários assuntos, em funis diferentes. Os cenários da Issue, ponta a ponta: a IA de
# assunto (Jev + modelo maior, simulados) decide, o IdentifyJob agenda, e as avaliações agendadas rodam com a IA do CRM
# simulada. Nada de IA paga: o Jev é um stub HTTP e o modelo da conta é um dublê do ResponsesClient.
RSpec.describe 'Vários assuntos numa mensagem' do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'João Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  # O que a IA viu e respondeu. movimentos: o que a IA do CRM responde para cada card, pelo título ({ etapa:,
  # atributos:, handoff: }; sem entrada, mantém). revisao: a resposta do modelo maior na pergunta de vários assuntos.
  let(:ia) { { chamadas: [], movimentos: {}, revisao: {}, passagens: [] } }
  let(:vendas) { funil('Vendas', %w[Proposta Fechamento]) }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive_messages(enabled?: true, media_enabled?: false)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    allow(Crm::Subjects::Notifier).to receive(:notify)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create) { |**args| responder(args) }
    allow(Crm::Ai::HandoffExecutor).to receive(:new) do |card:, handoff:, pelo_card: false, **|
      passagens << [card.id, handoff&.as_json, pelo_card]
      instance_double(Crm::Ai::HandoffExecutor, perform: nil)
    end
    account.enable_features!(Crm::Conversations::CardEmFoco::FLAG)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :auto)
    clear_enqueued_jobs
  end

  # Um funil ligado à caixa, com a IA movendo sozinha e um critério em cada etapa.
  def funil(nome, etapas, handoff: nil)
    pipeline, primeira = create_crm_pipeline(account: account, user: admin, name: nome)
    ai = { 'auto_move_enabled' => true, 'attribute_extraction_enabled' => true }
    ai['handoff'] = { 'enabled' => true, 'trigger' => handoff } if handoff
    pipeline.update!(metadata: { 'ai' => ai })
    primeira.update!(metadata: { 'ai_criteria' => 'Cliente chegou' })
    etapas.each.with_index(1) do |etapa, posicao|
      create_crm_stage(account: account, pipeline: pipeline, name: etapa, position: posicao)
        .update!(metadata: { 'ai_criteria' => "Critério de #{etapa}" })
    end
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: primeira, auto_create_card: false,
                                         created_by: admin)
    pipeline
  end

  def chamadas = ia[:chamadas]
  def movimentos = ia[:movimentos]
  def revisao = ia[:revisao]
  def passagens = ia[:passagens]

  def etapa(pipeline, nome)
    pipeline.stages.find_by!(name: nome)
  end

  def card(pipeline, titulo, etapa_nome, focused_at:)
    card = account.crm_cards.create!(pipeline: pipeline, stage: etapa(pipeline, etapa_nome), contact: contact, inbox: inbox,
                                     primary_conversation: conversation, title: titulo,
                                     metadata: { 'subject' => { 'source' => 'ai' } }, last_activity_at: 3.days.ago)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: focused_at)
    card
  end

  def stub_jev(choice, confidence: 0.95)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(
      status: 200,
      body: { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
              answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }.to_json
    )
  end

  def responder(args)
    chamadas << args
    entrada = JSON.parse(args[:input])
    corpo = case args.dig(:schema, :name)
            when 'assuntos_revisao' then revisao.merge(assuntos: revisao[:assuntos].map { |assunto| assunto.reverse_merge(seguro: true) })
            when 'stage_classification' then classificacao(entrada)
            when 'stage_classification_cards' then { cards: entrada['cards'].map { |pacote| classificacao(pacote).merge(card_id: id(pacote)) } }
            end
    { text: corpo.to_json, usage: { input_tokens: 1000, output_tokens: 100 }, response_id: 'resp' }
  end

  def classificacao(pacote)
    movimento = movimentos[pacote['card']['title']] || {}
    destino = pacote['stages'].find { |stage| stage['name'] == movimento[:etapa] }
    { suggested_stage_id: destino ? destino['id'] : pacote['card']['current_stage_id'], confidence: 0.95, reasoning: 'ok',
      value: nil, handoff: movimento[:handoff], callback_request: nil,
      extracted_attributes: { contact: [], conversation: [], card: movimento[:atributos] || [] }, score_signals: nil }
  end

  def id(pacote) = pacote.dig('card', 'id')

  def avaliacoes
    chamadas.select { |args| args.dig(:schema, :name).to_s.start_with?('stage_classification') }
  end

  # A mensagem do cliente: o IdentifyJob decide o assunto e agenda; depois do debounce, as avaliações agendadas rodam.
  def receber(texto)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto)
    clear_enqueued_jobs
    Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)
    rodar_avaliacoes
    Crm::SubjectDecision.find_by!(message_id: message.id)
  end

  def rodar_avaliacoes
    jobs = enqueued_jobs.select { |job| [Crm::Ai::EvaluateCardJob.name, Crm::Ai::EvaluateCardsJob.name].include?(job['job_class']) }
    clear_enqueued_jobs
    travel((Crm::Ai::Config::DEBOUNCE_SECONDS + 1).seconds) do
      jobs.each { |job| job['job_class'].constantize.perform_now(*ActiveJob::Arguments.deserialize(job['arguments'])) }
    end
  end

  def foco
    Crm::Assunto.funil_atual(conversation.reload)
  end

  describe 'com um funil e dois cards (Auto em Fechamento, Residencial em Proposta)' do
    let!(:auto) { card(vendas, 'Seguro auto', 'Fechamento', focused_at: 1.minute.ago) }
    let!(:residencial) { card(vendas, 'Seguro residencial', 'Proposta', focused_at: 2.minutes.ago) }

    it '(1) mensagem sobre o residencial: só o Residencial anda, numa avaliação de um card como a de hoje' do
      stub_jev("card_#{residencial.id}")
      movimentos['Seguro residencial'] = { etapa: 'Fechamento' }
      movimentos['Seguro auto'] = { etapa: 'Proposta' }

      decisao = receber('Pode seguir com o residencial, aceito a proposta')

      expect(decisao).to have_attributes(action: 'focus', state: 'applied', card_id: residencial.id, touched_card_ids: [residencial.id])
      expect(foco).to eq(residencial)
      expect(residencial.reload.stage.name).to eq('Fechamento')
      expect(auto.reload.stage.name).to eq('Fechamento')
      expect(avaliacoes.size).to eq(1)
      expect(avaliacoes.first.dig(:schema, :name)).to eq('stage_classification')
      expect(JSON.parse(avaliacoes.first[:input])['card']['id']).to eq(residencial.id)
    end
  end

  describe 'com um funil e só o Auto, em Proposta' do
    let!(:auto) { card(vendas, 'Seguro auto', 'Proposta', focused_at: 1.minute.ago) }

    it '(2) "fecha o auto e quero cotação do residencial de 100 mil": o Auto anda, nasce o Residencial com o dado e fica em foco' do
      create(:custom_attribute_definition, account: account, attribute_key: 'cobertura_incendio', attribute_model: 'card_attribute',
                                           attribute_display_type: 'number')
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: 'mesmo_assunto', titulo: '' }, { resposta: "novo_#{vendas.id}", titulo: 'Seguro residencial' }],
                     principal: 1, motivo: 'ok')
      movimentos['Seguro auto'] = { etapa: 'Fechamento' }
      movimentos['Seguro residencial'] = {
        atributos: [{ key: 'cobertura_incendio', value: 100_000, confidence: 0.95, evidence: '100 mil de incêndio' }]
      }

      decisao = receber('Pode fechar o auto. E quero cotação do residencial, 100 mil de incêndio')

      novo = account.crm_cards.find_by!(title: 'Seguro residencial')
      expect(decisao).to have_attributes(action: 'create', state: 'applied', card_id: novo.id, touched_card_ids: [novo.id, auto.id])
      expect(foco).to eq(novo)
      expect(auto.reload.stage.name).to eq('Fechamento')
      expect(novo.reload).to have_attributes(pipeline_id: vendas.id, status: 'open')
      expect(novo.custom_attributes['cobertura_incendio']).to eq(100_000)
      expect(avaliacoes.size).to eq(1)
      expect(avaliacoes.first.dig(:schema, :name)).to eq('stage_classification_cards')
    end

    # #2084: marcado parceiro enquanto o modelo maior separa os assuntos. O outro pedido não vira card.
    it 'contato marcado parceiro durante a decisão: o outro pedido não nasce' do
      account.enable_features!('contato_relacao')
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: 'mesmo_assunto', titulo: '' }, { resposta: "novo_#{vendas.id}", titulo: 'Seguro residencial' }],
                     principal: 0, motivo: 'ok')
      allow(cliente).to receive(:create) do |**args|
        contact.update!(relacao: :parceiro) if args.dig(:schema, :name) == 'assuntos_revisao'
        responder(args)
      end

      receber('Pode fechar o auto. E quero cotação do residencial, 100 mil de incêndio')

      expect(account.crm_cards.where(title: 'Seguro residencial')).to be_empty
    end

    it 'erro no principal depois de criar o outro pedido: a decisão fica como falha e o retry não duplica o card' do
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: "novo_#{vendas.id}", titulo: 'Seguro moto' },
                                { resposta: "novo_#{vendas.id}", titulo: 'Seguro residencial' }], principal: 1, motivo: 'ok')
      allow(Crm::Subjects::Applier).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap { |applier| allow(applier).to receive(:aplicar).and_raise(ActiveRecord::StatementInvalid) }
      end

      decisao = receber('Quero cotar a moto e o residencial')
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, decisao.message_id)

      moto = account.crm_cards.find_by!(title: 'Seguro moto')
      expect(decisao.reload).to have_attributes(state: 'failed', reason: 'ActiveRecord::StatementInvalid', touched_card_ids: [moto.id])
      expect(account.crm_cards.where(title: 'Seguro moto').count).to eq(1)
      expect(foco).to eq(auto)
    end

    it 'erro depois de o card principal ser salvo: a decisão fica como falha, o foco fica nele e o retry não duplica' do
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: 'mesmo_assunto', titulo: '' }, { resposta: "novo_#{vendas.id}", titulo: 'Seguro residencial' }],
                     principal: 1, motivo: 'ok')
      allow(Crm::Subjects::Applier).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap { |applier| allow(applier).to receive(:card_do_principal).and_raise(ActiveRecord::StatementInvalid) }
      end

      decisao = receber('Fecha o auto e quero cotar o residencial')
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, decisao.message_id)

      residencial = account.crm_cards.find_by!(title: 'Seguro residencial')
      expect(decisao.reload).to have_attributes(state: 'failed', action: 'create', card_id: residencial.id, title: 'Seguro residencial',
                                                touched_card_ids: [residencial.id])
      expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(residencial, Events::Types::CRM_CARD_CREATED)
      expect(account.crm_cards.where(title: 'Seguro residencial').count).to eq(1)
      expect(foco).to eq(residencial)
    end

    it 'vencida por uma mensagem mais nova depois de criar o outro pedido: o foco volta e só o card criado é avaliado' do
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: "novo_#{vendas.id}", titulo: 'Seguro moto' },
                                { resposta: "novo_#{vendas.id}", titulo: 'Seguro residencial' }], principal: 1, motivo: 'ok')
      allow(Crm::Subjects::Applier).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap { |applier| allow(applier).to receive(:mensagem_mais_nova?).and_return(false, true) }
      end

      decisao = receber('Quero cotar a moto e o residencial')

      moto = account.crm_cards.find_by!(title: 'Seguro moto')
      expect(decisao).to have_attributes(state: 'superseded', touched_card_ids: [moto.id])
      expect(foco).to eq(auto)
      expect(account.crm_cards.where(title: 'Seguro residencial')).to be_empty
      expect(avaliacoes.size).to eq(1)
    end
  end

  describe 'com dois funis (Vendas com o Auto, Pós-venda com o Sinistro)' do
    let(:pos_venda) { funil('Pós-venda', %w[Análise Resolvido]) }
    let!(:auto) { card(vendas, 'Seguro auto', 'Proposta', focused_at: 1.minute.ago) }
    let!(:sinistro) { card(pos_venda, 'Sinistro do carro', 'Novo Lead', focused_at: 2.minutes.ago) }

    it '(3) mensagem sobre o sinistro: o foco vai para o Sinistro e só ele anda' do
      stub_jev("card_#{sinistro.id}")
      movimentos['Sinistro do carro'] = { etapa: 'Análise' }
      movimentos['Seguro auto'] = { etapa: 'Fechamento' }

      decisao = receber('Mandei as fotos da batida, o sinistro já pode ir para análise?')

      expect(decisao.touched_card_ids).to eq([sinistro.id])
      expect(foco).to eq(sinistro)
      expect(sinistro.reload.stage.name).to eq('Análise')
      expect(auto.reload.stage.name).to eq('Proposta')
      expect(avaliacoes.size).to eq(1)
    end

    describe 'no modo Sugerir' do
      let(:pedido) { { intent: 'transferir', should_handoff: true, reason: 'Pediu atendente', suggested_agent: nil } }

      before { account.crm_inbox_settings.find_by!(inbox: inbox).update!(subject_ai_mode: :suggest) }

      it 'um card tocado só (fora do foco) com pedido de atendente: vale a regra de antes, a do foco' do
        pos_venda.update!(metadata: { 'ai' => pos_venda.metadata['ai'].merge('handoff' => { 'enabled' => true }) })
        stub_jev("card_#{sinistro.id}")
        movimentos['Sinistro do carro'] = { handoff: pedido }

        decisao = receber('quero falar com alguém sobre o sinistro')

        expect(decisao).to have_attributes(state: 'suggested', touched_card_ids: [sinistro.id])
        expect(foco).to eq(auto)
        expect(avaliacoes.map { |args| args.dig(:schema, :name) }).to eq(['stage_classification'])
        expect(passagens).to eq([[sinistro.id, pedido.as_json, false]])
      end

      it 'principal em dúvida e o outro pedido sem virar card: sem lista, relê o card em foco (#1675)' do
        stub_jev(Crm::Subjects::Question::VARIOS)
        revisao.merge!(assuntos: [{ resposta: "novo_#{vendas.id}", titulo: 'Seguro moto' },
                                  { resposta: "card_#{sinistro.id}", titulo: '', seguro: false }], principal: 1, motivo: 'x')

        decisao = receber('quero cotar a moto e o outro lá')

        expect(decisao).to have_attributes(state: 'doubt', touched_card_ids: nil)
        expect(account.crm_cards.where(title: 'Seguro moto')).to be_empty
        expect(avaliacoes.map { |args| JSON.parse(args[:input]).dig('card', 'id') }).to eq([auto.id])
      end
    end

    describe 'com o Auto ligado também ao e-mail (#1664)' do
      let(:email) { conversa_de_email(auto, ['Mandei a CNH por aqui', 'Segue o documento do carro por e-mail'], 2.hours.ago) }
      let(:assuntos) { [{ resposta: 'mesmo_assunto', titulo: '' }, { resposta: "card_#{sinistro.id}", titulo: '' }] }

      before do
        email
        stub_jev(Crm::Subjects::Question::VARIOS)
        revisao.merge!(assuntos: assuntos, principal: assuntos.size - 1, motivo: 'ok')
      end

      # Uma conversa de e-mail do João, ligada ao card, com as mensagens do cliente (um minuto entre elas, a partir de `desde`).
      # A caixa de e-mail alimenta o funil do card (senão as mensagens dela não entram no pacote, ver o caso abaixo).
      def conversa_de_email(card, textos, desde, funil: true)
        caixa = create(:inbox, account: account)
        ligar_ao_funil(card.pipeline, caixa) if funil
        create(:conversation, account: account, inbox: caixa, contact: contact).tap do |conversa|
          textos.each_with_index do |texto, minuto|
            create(:message, account: account, inbox: conversa.inbox, conversation: conversa, message_type: :incoming, content: texto,
                             created_at: desde + minuto.minutes)
          end
          # Só o que o cliente escreveu: as mensagens automáticas da caixa nova (pedido de e-mail) não importam aqui.
          conversa.messages.where.not(message_type: :incoming).delete_all
          Crm::CardConversation.create!(account: account, card: card, conversation: conversa)
        end
      end

      def ligar_ao_funil(pipeline, caixa)
        account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: caixa, default_stage: pipeline.stages.first, auto_create_card: false,
                                             created_by: admin)
      end

      def pacotes
        JSON.parse(avaliacoes.first[:input])['cards'].index_by { |pacote| id(pacote) }
      end

      def outras(card)
        pacotes[card.id]['other_conversations_messages']&.pluck('content')
      end

      it 'mensagem nova no WhatsApp: a chamada conjunta leva as mensagens do e-mail no pacote do Auto' do
        receber('O sinistro já tem as fotos. E o auto, posso fechar?')

        expect(avaliacoes.size).to eq(1)
        expect(JSON.parse(avaliacoes.first[:input])['recent_messages'].pluck('content')).not_to include('Mandei a CNH por aqui')
        expect(outras(auto)).to eq(['Mandei a CNH por aqui', 'Segue o documento do carro por e-mail'])
        expect(pacotes[auto.id]['other_conversations_messages'].last['conversation_id']).to eq(email.id)
        expect(pacotes[sinistro.id]).not_to have_key('other_conversations_messages')
      end

      it 'conversa de uma caixa que não alimenta o funil do Auto não entra no pacote dele' do
        conversa_de_email(auto, ['Mensagem de um canal de outro funil'], 1.hour.ago, funil: false)

        receber('O sinistro já tem as fotos. E o auto, posso fechar?')

        expect(outras(auto)).to eq(['Mandei a CNH por aqui', 'Segue o documento do carro por e-mail'])
      end

      it 'a conversa primária do próprio card entra mesmo de uma caixa que não alimenta o funil (como num card só)' do
        primaria = conversa_de_email(auto, ['O auto foi aberto por aqui'], 3.hours.ago, funil: false)
        auto.update!(primary_conversation: primaria)

        receber('O sinistro já tem as fotos. E o auto, posso fechar?')

        expect(outras(auto)).to include('O auto foi aberto por aqui')
      end

      it 'limite por card: só as mais recentes de cada card' do
        stub_const('Crm::Ai::OutrasConversas::MAX_POR_CARD', 1)

        receber('O sinistro já tem as fotos. E o auto, posso fechar?')

        expect(outras(auto)).to eq(['Segue o documento do carro por e-mail'])
      end

      describe 'com o Seguro viagem ligado a outro e-mail, mais novo' do
        let!(:viagem) { card(vendas, 'Seguro viagem', 'Novo Lead', focused_at: 3.minutes.ago) }
        let(:assuntos) do
          [{ resposta: 'mesmo_assunto', titulo: '' }, { resposta: "card_#{viagem.id}", titulo: '' },
           { resposta: "card_#{sinistro.id}", titulo: '' }]
        end

        it 'limite total: as mais recentes entre todos os cards, e não na ordem dos cards' do
          conversa_de_email(viagem, ['Vou viajar dia 20'], 10.minutes.ago)
          stub_const('Crm::Ai::OutrasConversas::MAX_TOTAL', 2)

          receber('O sinistro já tem as fotos, o auto posso fechar e a viagem confirmo')

          expect(outras(viagem)).to eq(['Vou viajar dia 20'])
          expect(outras(auto)).to eq(['Segue o documento do carro por e-mail'])
        end
      end

      it 'não repete o que a janela do principal já tem' do
        Crm::CardConversation.create!(account: account, card: sinistro, conversation: email)

        receber('O sinistro já tem as fotos. E o auto, posso fechar?')

        expect(JSON.parse(avaliacoes.first[:input])['recent_messages'].pluck('content')).to include('Mandei a CNH por aqui')
        expect(pacotes[auto.id]).not_to have_key('other_conversations_messages')
      end

      it 'texto igual no mesmo segundo em outro canal continua sendo outra mensagem' do
        igual = email.messages.find_by!(content: 'Mandei a CNH por aqui')
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                         content: igual.content, created_at: igual.created_at)

        receber('O sinistro já tem as fotos. E o auto, posso fechar?')

        expect(JSON.parse(avaliacoes.first[:input])['recent_messages'].pluck('content')).to include('Mandei a CNH por aqui')
        expect(outras(auto)).to include('Mandei a CNH por aqui')
      end
    end
  end

  describe 'com três funis (Vendas, Pós-venda e Renovações)' do
    let(:pos_venda) { funil('Pós-venda', %w[Análise Resolvido], handoff: 'O cliente pede um atendente do sinistro') }
    let(:renovacoes) { funil('Renovações', %w[Renovando Renovado], handoff: 'O cliente pede um atendente da renovação') }
    let!(:auto) { card(vendas, 'Seguro auto', 'Proposta', focused_at: 1.minute.ago) }
    let!(:sinistro) { card(pos_venda, 'Sinistro do carro', 'Novo Lead', focused_at: 2.minutes.ago) }
    let!(:vida) { card(renovacoes, 'Renovação do vida', 'Novo Lead', focused_at: 3.minutes.ago) }

    before do
      card(vendas, 'Seguro viagem', 'Novo Lead', focused_at: 4.minutes.ago)
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: 'mesmo_assunto', titulo: '' }, { resposta: "card_#{sinistro.id}", titulo: '' },
                                { resposta: "card_#{vida.id}", titulo: '' }], principal: 2, motivo: 'ok')
    end

    it '(4) três assuntos em três funis: três cards tocados, cada um com o funil dele, numa chamada só' do
      movimentos['Seguro auto'] = { etapa: 'Fechamento' }
      movimentos['Sinistro do carro'] = { etapa: 'Análise' }
      movimentos['Renovação do vida'] = { etapa: 'Renovando' }

      decisao = receber('Fecha o auto, o sinistro já tem as fotos e quero renovar o vida')

      expect(decisao.touched_card_ids).to eq([vida.id, auto.id, sinistro.id])
      expect(foco).to eq(vida)
      expect([auto, sinistro, vida].map { |card| card.reload.stage.name }).to eq(%w[Fechamento Análise Renovando])
      expect(avaliacoes.pluck(:instructions)).to eq([Crm::Ai::ClassifierPrompt::TEXT_VARIOS])
      entrada = JSON.parse(avaliacoes.first[:input])
      expect(entrada['cards'].map { |pacote| [pacote['card']['id'], pacote['stages'].map { |stage| stage['name'] }] })
        .to eq([[vida.id, ['Novo Lead', 'Renovando', 'Renovado']], [auto.id, ['Novo Lead', 'Proposta', 'Fechamento']],
                [sinistro.id, ['Novo Lead', 'Análise', 'Resolvido']]])
      expect(entrada['other_subjects']).to eq([{ 'title' => 'Seguro viagem', 'pipeline' => 'Vendas', 'stage' => 'Novo Lead' }])
      expect(entrada['recent_messages'].pluck('content')).to include(a_string_including('quero renovar o vida'))
    end

    it 'o retry do IdentifyJob não agenda outra avaliação da mesma mensagem' do
      decisao = receber('Fecha o auto, o sinistro já tem as fotos e quero renovar o vida')
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, decisao.message_id)
      rodar_avaliacoes

      expect(avaliacoes.size).to eq(1)
    end

    it 'o principal muda para uma etapa com outra regra de pedido de atendente: só então relê o pedido dele' do
      etapa(renovacoes, 'Renovando').update!(metadata: { 'ai_criteria' => 'Critério de Renovando',
                                                         'ai_handoff' => { 'enabled' => true, 'trigger' => 'Qualquer dúvida de preço' } })
      movimentos['Seguro auto'] = { etapa: 'Fechamento' }
      movimentos['Renovação do vida'] = { etapa: 'Renovando' }

      receber('Fecha o auto, o sinistro já tem as fotos e quero renovar o vida')

      expect(avaliacoes.map { |args| args.dig(:schema, :name) }).to eq(%w[stage_classification_cards stage_classification])
      expect(JSON.parse(avaliacoes.last[:input])).to include('card' => include('id' => vida.id), 'handoff_trigger' => 'Qualquer dúvida de preço')
    end

    it 'no modo Sugerir: nenhum card nasce sozinho e o foco não muda; os assuntos abertos são avaliados juntos' do
      account.crm_inbox_settings.find_by!(inbox: inbox).update!(subject_ai_mode: :suggest)
      revisao.merge!(assuntos: [{ resposta: "card_#{sinistro.id}", titulo: '' }, { resposta: "novo_#{vendas.id}", titulo: 'Seguro moto' }],
                     principal: 0, motivo: 'ok')

      decisao = receber('O sinistro já tem as fotos. E quero cotar a moto')

      expect(decisao).to have_attributes(action: 'focus', state: 'suggested', card_id: sinistro.id, touched_card_ids: [sinistro.id])
      expect(account.crm_cards.where(title: 'Seguro moto')).to be_empty
      expect(foco).to eq(auto)
      expect(avaliacoes.size).to eq(1)
    end

    it '(6) dois assuntos e o pedido de atendente nos dois: vale o principal' do
      revisao.merge!(assuntos: [{ resposta: "card_#{sinistro.id}", titulo: '' }, { resposta: "card_#{vida.id}", titulo: '' }],
                     principal: 1, motivo: 'ok')
      pedido = { intent: 'transferir', should_handoff: true, reason: 'Pediu atendente', suggested_agent: nil }
      movimentos['Sinistro do carro'] = { handoff: pedido }
      movimentos['Renovação do vida'] = { handoff: pedido }

      receber('Sobre o sinistro e a renovação do vida, quero falar com um atendente')

      expect(avaliacoes.size).to eq(1)
      gatilhos = JSON.parse(avaliacoes.first[:input])['cards'].to_h { |pacote| [pacote['card']['id'], pacote['handoff_trigger']] }
      expect(gatilhos).to eq(vida.id => 'O cliente pede um atendente da renovação', sinistro.id => 'O cliente pede um atendente do sinistro')
      expect(passagens.map(&:first)).to eq([vida.id])
    end
  end

  # Do teste de estresse de 16/10 (docs/multifunil/STRESS-TEST-2026-10-16.md, PR #1708), cliente novo, sem card.
  describe 'teste de estresse: pedido de atendente e assunto em dúvida' do
    let(:vendas) { funil('Vendas', %w[Proposta Fechamento], handoff: 'O cliente pede um atendente de vendas') }
    let(:pos_venda) { funil('Sinistro', %w[Análise Resolvido], handoff: 'O cliente pede um atendente do sinistro') }
    let(:pedido) { { intent: 'transferir', should_handoff: true, reason: 'Pediu atendente', suggested_agent: nil } }

    before { stub_jev(Crm::Subjects::Question::VARIOS) }

    def dois_pedidos_novos
      revisao.merge!(assuntos: [{ resposta: "novo_#{pos_venda.id}", titulo: 'Sinistro do carro' },
                                { resposta: "novo_#{vendas.id}", titulo: 'Seguro residencial' }], principal: 1, motivo: 'ok')
    end

    it 'C26: o pedido ligado ao sinistro vai pela regra do sinistro, mesmo com o residencial em foco' do
      dois_pedidos_novos
      movimentos['Sinistro do carro'] = { handoff: pedido }

      receber('preciso falar com uma pessoa. é sobre o sinistro do meu carro (bateram) e quero cotar residencial tb')

      sinistro, residencial = ['Sinistro do carro', 'Seguro residencial'].map { |titulo| account.crm_cards.find_by!(title: titulo) }
      expect(foco).to eq(residencial)
      expect(JSON.parse(avaliacoes.first[:input])['cards'].to_h { |pacote| [id(pacote), pacote['principal']] })
        .to eq(residencial.id => true, sinistro.id => false)
      expect(passagens).to eq([[sinistro.id, pedido.as_json, true]])
    end

    it 'pedido sem ligação a um assunto: a IA o põe no principal, e vale a regra dele' do
      dois_pedidos_novos
      movimentos['Seguro residencial'] = { handoff: pedido }

      receber('quero falar com uma pessoa. tenho um sinistro do carro e quero cotar residencial')

      expect(passagens.map(&:first)).to eq([account.crm_cards.find_by!(title: 'Seguro residencial').id])
    end

    it 'C27: o vida em dúvida não segura o sinistro, que nasce e leva o pedido de atendente' do
      revisao.merge!(assuntos: [{ resposta: "novo_#{vendas.id}", titulo: 'Seguro de vida', seguro: false },
                                { resposta: "novo_#{pos_venda.id}", titulo: 'Sinistro do celular' }], principal: 0, motivo: 'vida?')
      movimentos['Sinistro do celular'] = { handoff: pedido }

      decisao = receber('me passa pra um atendente. é pra cotar seguro de vida. e tb abrir um sinistro do celular q foi roubado')

      sinistro = account.crm_cards.find_by!(title: 'Sinistro do celular')
      expect(decisao).to have_attributes(state: 'doubt', title: 'Seguro de vida', touched_card_ids: [sinistro.id])
      expect(account.crm_cards.where(title: 'Seguro de vida')).to be_empty
      expect(foco).to eq(sinistro)
      expect(passagens).to eq([[sinistro.id, pedido.as_json, false]])
    end
  end

  describe 'com um card em foco' do
    let!(:auto) { card(vendas, 'Seguro auto', 'Proposta', focused_at: 1.minute.ago) }

    # #1918 revoga o critério 5 do #1693: mensagem sem pedido novo relê o card em foco, e a IA de etapa decide se ele
    # fica (aqui fica: a IA responde a mesma etapa).
    it '(5) "obrigado!" relê o card em foco: conta como atividade e a IA do CRM decide (fica)' do
      stub_jev('sem_assunto')

      decisao = receber('obrigado!')

      expect(decisao).to have_attributes(state: 'kept', touched_card_ids: [auto.id])
      expect(avaliacoes.size).to eq(1)
      expect(JSON.parse(avaliacoes.first[:input])['card']['id']).to eq(auto.id)
      expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone').with do |request|
        JSON.parse(request.body)['state']['instructions']
            .include?('A greeting, a thank-you, an acknowledgement or a goodbye that says nothing about a request')
      end).to have_been_made
      expect(auto.reload.stage.name).to eq('Proposta')
      expect(auto.last_activity_at).to be > 1.minute.ago
    end

    it 'o modelo maior responde a lista vazia: o card em foco é o tocado' do
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [], principal: 0, motivo: 'só agradeceu')

      decisao = receber('valeu')

      expect(decisao).to have_attributes(state: 'kept', touched_card_ids: [auto.id])
      expect(avaliacoes.size).to eq(1)
    end

    it 'sugestão de pedido novo esperando uma pessoa: a lista segue vazia e nada é avaliado (#1147)' do
      anterior = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'x')
      Crm::SubjectDecision.create!(account: account, conversation: conversation, message: anterior, mode: 'auto', action: 'create',
                                   state: 'suggested', pipeline_id: vendas.id, title: 'Seguro moto')
      stub_jev("novo_#{vendas.id}")

      decisao = receber('e a moto?')

      expect(decisao).to have_attributes(state: 'kept', reason: 'sugestao_pendente', touched_card_ids: [])
      expect(avaliacoes).to be_empty
    end

    describe 'movido por uma pessoa há pouco (#1918)' do
      def mover_pela_pessoa(card, nome, tempo:)
        travel_to(tempo.ago) { Crm::Cards::Mover.new(card: card, actor: admin, target_stage: etapa(vendas, nome)).perform }
      end

      def sugestoes(card)
        account.crm_ai_stage_suggestions.where(card: card)
      end

      it '"ok" não mexe no card que a pessoa acabou de mover: nem move, nem sugere' do
        mover_pela_pessoa(auto, 'Fechamento', tempo: 1.hour)
        stub_jev('sem_assunto')
        movimentos['Seguro auto'] = { etapa: 'Proposta' }

        decisao = receber('ok')

        expect(decisao.touched_card_ids).to eq([auto.id])
        expect(avaliacoes.size).to eq(1)
        expect(auto.reload.stage.name).to eq('Fechamento')
        expect(sugestoes(auto)).to be_empty
      end

      it '"ok" não mexe no card que a pessoa acabou de reabrir' do
        auto.update!(status: :lost)
        travel_to(1.hour.ago) { Crm::Cards::Closer.new(card: auto, actor: admin, result: 'reopen').perform }
        stub_jev('sem_assunto')
        movimentos['Seguro auto'] = { etapa: 'Fechamento' }

        decisao = receber('ok')

        expect(decisao.touched_card_ids).to eq([auto.id])
        expect(avaliacoes.size).to eq(1)
        expect(auto.reload).to have_attributes(status: 'open')
        expect(auto.stage.name).to eq('Proposta')
        expect(sugestoes(auto)).to be_empty
      end

      it 'passada a janela de respeito, a IA volta a mover sozinha' do
        mover_pela_pessoa(auto, 'Fechamento', tempo: Crm::Ai::Evaluator::RESPEITO_AO_MOVIMENTO + 1.minute)
        stub_jev('sem_assunto')
        movimentos['Seguro auto'] = { etapa: 'Proposta' }

        receber('ok')

        expect(auto.reload.stage.name).to eq('Proposta')
      end

      it 'movimento da própria IA não conta como de pessoa' do
        travel_to(1.hour.ago) { Crm::Cards::Mover.new(card: auto, actor: nil, target_stage: etapa(vendas, 'Fechamento')).perform }
        stub_jev('sem_assunto')
        movimentos['Seguro auto'] = { etapa: 'Proposta' }

        receber('ok')

        expect(auto.reload.stage.name).to eq('Proposta')
      end

      it '"Avaliar agora" (manual) é escolha da pessoa: move mesmo assim' do
        mover_pela_pessoa(auto, 'Fechamento', tempo: 1.hour)
        movimentos['Seguro auto'] = { etapa: 'Proposta' }

        Crm::Ai::Evaluator.new(card: auto.reload, trigger: 'manual').perform

        expect(auto.reload.stage.name).to eq('Proposta')
      end
    end

    it 'assunto em dúvida: relê o card em foco, como no #1675' do
      stub_jev('mesmo_assunto', confidence: 0.3)
      revisao.merge!(assuntos: [{ resposta: 'mesmo_assunto', titulo: '', seguro: false }], principal: 0, motivo: 'ambíguo')
      movimentos['Seguro auto'] = { etapa: 'Fechamento' }

      decisao = receber('hmm, talvez')

      expect(decisao).to have_attributes(state: 'doubt', touched_card_ids: nil)
      expect(avaliacoes.size).to eq(1)
      expect(auto.reload.stage.name).to eq('Fechamento')
    end

    it 'decisão reaberta pelo WhatsApp Híbrido: volta a ser de um assunto só, sem lista' do
      stub_jev('mesmo_assunto')
      decisao = receber('Pode fechar o auto')
      expect(decisao.touched_card_ids).to eq([auto.id])

      requisicoes = []
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
        requisicoes << JSON.parse(request.body)
        { status: 200, body: { model: 'jev-1.13.0', usage: {},
                               answers: { decisao: { type: 'choice', choice: 'mesmo_assunto', confidence: 0.95 } } }.to_json }
      end
      decisao.message.update!(content_attributes: { 'hybrid_recovered_at' => 5.seconds.from_now.iso8601 })
      Crm::Subjects::Identifier.new(conversation: conversation, message: decisao.message.reload).perform

      expect(requisicoes.first['questions']['decisao']['criteria'].keys).not_to include(Crm::Subjects::Question::VARIOS)
      expect(decisao.reload.touched_card_ids).to be_nil
    end

    it '(7) flag desligada: a pergunta e a avaliação são as de hoje' do
      account.disable_features!(Crm::Conversations::CardEmFoco::FLAG)
      requisicoes = []
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
        requisicoes << JSON.parse(request.body)
        { status: 200, body: { model: 'jev-1.13.0', usage: {},
                               answers: { decisao: { type: 'choice', choice: 'mesmo_assunto', confidence: 0.95 } } }.to_json }
      end

      decisao = receber('Pode fechar o auto')

      expect(decisao).to have_attributes(state: 'kept', touched_card_ids: nil)
      expect(requisicoes.first['questions']['decisao']['criteria'].keys).not_to include(Crm::Subjects::Question::VARIOS)
      expect(requisicoes.first['state']['instructions']).to eq(Crm::Subjects::Question::INSTRUCOES)
      expect(avaliacoes).to be_empty
    end
  end

  # #1918: o card que a caixa criou com o nome do contato. PR1: o sem_assunto relê o card. PR2: ele também é "o mesmo
  # assunto", e a notícia sobre o pedido fica nele em vez de virar "dar nome".
  describe 'com o card sem nome em foco, em Proposta' do
    let(:vendas) { funil('Vendas', %w[Proposta Perdido]) }
    let!(:sem_nome) do
      card(vendas, contact.name, 'Proposta', focused_at: 1.minute.ago).tap { |card| card.update!(metadata: {}) }
    end

    it '"já fechei com outra corretora": a IA do CRM relê o card e ele vai para Perdido' do
      stub_jev('sem_assunto')
      movimentos[contact.name] = { etapa: 'Perdido' }

      decisao = receber('já fechei com outra corretora, obrigado')

      expect(decisao).to have_attributes(state: 'kept', touched_card_ids: [sem_nome.id])
      expect(sem_nome.reload.stage.name).to eq('Perdido')
    end

    it 'a pergunta oferece "o mesmo assunto" sem o nome do contato e separa a cortesia da notícia sobre o pedido' do
      requisicoes = []
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
        requisicoes << JSON.parse(request.body)
        { status: 200, body: { model: 'jev-1.13.0', usage: {},
                               answers: { decisao: { type: 'choice', choice: 'mesmo_assunto', confidence: 0.95 } } }.to_json }
      end
      revisao.merge!(assuntos: [{ resposta: 'mesmo_assunto', titulo: '' }], principal: 0, motivo: 'ok')
      movimentos[contact.name] = { etapa: 'Perdido' }

      decisao = receber('desisti, fechei com outra')

      criterios = requisicoes.first['questions']['decisao']['criteria']
      expect(criterios.keys).to include('sem_assunto', 'mesmo_assunto', "novo_#{vendas.id}")
      expect(criterios['mesmo_assunto']).to include('no name yet', '"Vendas"', '"Proposta"')
      expect(criterios['mesmo_assunto']).not_to include(contact.name)
      expect(requisicoes.first['state']['instructions']).to eq(Crm::Subjects::Question::INSTRUCOES_VARIOS)
      expect(decisao).to have_attributes(state: 'kept', action: 'none', card_id: sem_nome.id, touched_card_ids: [sem_nome.id])
      expect(sem_nome.reload).to have_attributes(title: contact.name, stage: etapa(vendas, 'Perdido'))
      expect(sem_nome.metadata).not_to have_key('subject')
    end

    it 'o Jev com certeza alta em "o mesmo assunto" do card sem nome não decide sozinho: o modelo maior pode dar o nome' do
      stub_jev('mesmo_assunto')
      revisao.merge!(assuntos: [{ resposta: "novo_#{vendas.id}", titulo: 'Seguro do Corolla' }], principal: 0, motivo: 'ok')

      decisao = receber('quero cotar o seguro do meu Corolla')

      expect(decisao).to have_attributes(state: 'applied', action: 'rename', decided_by: 'review', card_id: sem_nome.id)
      expect(sem_nome.reload.title).to eq('Seguro do Corolla')
      expect(account.crm_cards.count).to eq(1)
    end

    it 'no Sugerir, com o nome dele dispensado há pouco: o "mesmo assunto" do Jev vale e o modelo maior não é chamado (#1260)' do
      account.crm_inbox_settings.find_by!(inbox: inbox).update!(subject_ai_mode: :suggest)
      anterior = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
      Crm::SubjectDecision.create!(account: account, conversation: conversation, message: anterior, mode: 'suggest',
                                   action: 'rename', state: 'dismissed', pipeline_id: vendas.id, card: sem_nome)
      stub_jev('mesmo_assunto')

      decisao = receber('mandei o comprovante')

      expect(decisao).to have_attributes(state: 'kept', action: 'none', decided_by: 'jev', card_id: sem_nome.id)
      expect(chamadas.map { |args| args.dig(:schema, :name) }).not_to include('assuntos_revisao')
      expect(Crm::SubjectDecision.where(state: 'suggested')).to be_empty
    end

    it 'flag desligada: sem "o mesmo assunto" e com a descrição de sempre do pedido novo' do
      account.disable_features!(Crm::Conversations::CardEmFoco::FLAG)
      requisicoes = []
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
        requisicoes << JSON.parse(request.body)
        { status: 200, body: { model: 'jev-1.13.0', usage: {},
                               answers: { decisao: { type: 'choice', choice: 'sem_assunto', confidence: 0.95 } } }.to_json }
      end

      receber('desisti, fechei com outra')

      criterios = requisicoes.first['questions']['decisao']['criteria']
      expect(criterios.keys).to contain_exactly('sem_assunto', "novo_#{vendas.id}")
      expect(criterios["novo_#{vendas.id}"])
        .to eq('The customer shows what they want, and it belongs to the pipeline "Vendas" (type: sales, closing a deal).')
      expect(requisicoes.first['state']['instructions']).to eq(Crm::Subjects::Question::INSTRUCOES)
    end

    it 'decisão reaberta pelo WhatsApp Híbrido: de um assunto só, sem "o mesmo assunto" para o card sem nome (#1638)' do
      stub_jev('sem_assunto')
      decisao = receber('oi')

      requisicoes = []
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
        requisicoes << JSON.parse(request.body)
        { status: 200, body: { model: 'jev-1.13.0', usage: {},
                               answers: { decisao: { type: 'choice', choice: 'sem_assunto', confidence: 0.95 } } }.to_json }
      end
      decisao.message.update!(content_attributes: { 'hybrid_recovered_at' => 5.seconds.from_now.iso8601 })
      Crm::Subjects::Identifier.new(conversation: conversation, message: decisao.message.reload).perform

      expect(requisicoes.first['questions']['decisao']['criteria'].keys).to contain_exactly('sem_assunto', "novo_#{vendas.id}")
      expect(requisicoes.first['state']['instructions']).to eq(Crm::Subjects::Question::INSTRUCOES)
    end

    describe 'quando ele é o card da chegada intocado (C36)' do
      before do
        sem_nome.update!(metadata: { Crm::Conversations::CardSyncer::AUTO_SYNC_METADATA =>
                                       { 'source' => Crm::Conversations::CardSyncer::OBSERVER_SOURCE } })
      end

      it 'não é "o mesmo assunto": a pergunta não oferece a opção e a cortesia não o move' do
        requisicoes = []
        stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
          requisicoes << JSON.parse(request.body)
          { status: 200, body: { model: 'jev-1.13.0', usage: {},
                                 answers: { decisao: { type: 'choice', choice: 'sem_assunto', confidence: 0.95 } } }.to_json }
        end
        movimentos[contact.name] = { etapa: 'Perdido' }

        decisao = receber('oi, bom dia')

        expect(requisicoes.first['questions']['decisao']['criteria'].keys).not_to include('mesmo_assunto')
        expect(decisao).to have_attributes(state: 'kept', touched_card_ids: [])
        expect(sem_nome.reload.stage.name).to eq('Proposta')
        expect(avaliacoes).to be_empty
      end
    end

    it 'o modelo maior põe o card sem nome na lista como o mesmo assunto: nada nasce, nada ganha nome e a IA do CRM avalia' do
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: 'mesmo_assunto', titulo: '' }], principal: 0, motivo: 'ok')
      movimentos[contact.name] = { etapa: 'Perdido' }

      decisao = receber('mandei o comprovante, mas no fim desisti')

      expect(decisao).to have_attributes(state: 'kept', decided_by: 'review', touched_card_ids: [sem_nome.id])
      expect(sem_nome.reload.title).to eq(contact.name)
      expect(sem_nome.stage.name).to eq('Perdido')
      expect(account.crm_cards.count).to eq(1)
    end

    it 'o primeiro pedido no funil dele ainda dá nome ao card, e a IA do CRM avalia o card nomeado' do
      stub_jev("novo_#{vendas.id}")
      revisao.merge!(assuntos: [{ resposta: "novo_#{vendas.id}", titulo: 'Seguro do Corolla' }], principal: 0, motivo: 'ok')

      decisao = receber('quero cotar o seguro do meu Corolla')

      expect(decisao).to have_attributes(state: 'applied', action: 'rename', card_id: sem_nome.id, touched_card_ids: [sem_nome.id])
      expect(sem_nome.reload.title).to eq('Seguro do Corolla')
      expect(avaliacoes.size).to eq(1)
      expect(account.crm_cards.count).to eq(1)
    end
  end

  describe 'sem card aberto na conversa' do
    it '"obrigado!" não toca nada e nada é avaliado' do
      vendas
      stub_jev('sem_assunto')

      decisao = receber('obrigado!')

      expect(decisao).to have_attributes(state: 'kept', touched_card_ids: [])
      expect(avaliacoes).to be_empty
    end
  end

  describe 'com dois assuntos (Auto em foco, Sinistro fora do foco)' do
    let(:pos_venda) { funil('Pós-venda', %w[Análise Resolvido]) }
    let!(:auto) { card(vendas, 'Seguro auto', 'Proposta', focused_at: 1.minute.ago) }
    let!(:sinistro) { card(pos_venda, 'Sinistro do carro', 'Análise', focused_at: 2.minutes.ago) }

    before do
      movimentos['Seguro auto'] = { etapa: 'Fechamento' }
      movimentos['Sinistro do carro'] = { etapa: 'Resolvido' }
    end

    it 'guarda de regressão: "obrigado" ligado ao Sinistro (card_) relê só ele, e o Auto não anda' do
      stub_jev("card_#{sinistro.id}")

      decisao = receber('obrigado pela ajuda com o sinistro')

      expect(decisao.touched_card_ids).to eq([sinistro.id])
      expect(avaliacoes.map { |args| JSON.parse(args[:input]).dig('card', 'id') }).to eq([sinistro.id])
      expect(auto.reload.stage.name).to eq('Proposta')
    end

    it 'dois cards tocados e só o Sinistro movido por uma pessoa há pouco: ele fica como está, o Auto anda' do
      travel_to(1.hour.ago) { Crm::Cards::Mover.new(card: sinistro, actor: admin, target_stage: etapa(pos_venda, 'Novo Lead')).perform }
      stub_jev(Crm::Subjects::Question::VARIOS)
      revisao.merge!(assuntos: [{ resposta: "card_#{sinistro.id}", titulo: '' }, { resposta: 'mesmo_assunto', titulo: '' }],
                     principal: 1, motivo: 'ok')

      receber('ok para os dois')

      expect(avaliacoes.map { |args| args.dig(:schema, :name) }).to eq(['stage_classification_cards'])
      expect(auto.reload.stage.name).to eq('Fechamento')
      expect(sinistro.reload.stage.name).to eq('Novo Lead')
      expect(account.crm_ai_stage_suggestions.where(card: sinistro)).to be_empty
    end

    it 'sem assunto: só o card em foco é relido, e o Sinistro fora do foco não anda' do
      stub_jev('sem_assunto')

      decisao = receber('obrigado!')

      expect(decisao.touched_card_ids).to eq([auto.id])
      expect(avaliacoes.map { |args| JSON.parse(args[:input]).dig('card', 'id') }).to eq([auto.id])
      expect(sinistro.reload.stage.name).to eq('Análise')
    end
  end
end
