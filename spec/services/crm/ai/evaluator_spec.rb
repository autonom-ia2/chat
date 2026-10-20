require 'rails_helper'

RSpec.describe Crm::Ai::Evaluator do
  around do |example|
    previous_crm = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    previous_ai = ENV.fetch('CRM_AI_ENABLED', nil)
    previous_attr = ENV.fetch('CRM_AI_ATTR_EXTRACTION', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    ENV['CRM_AI_ENABLED'] = 'true'
    example.run
  ensure
    previous_crm.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_crm
    previous_ai.nil? ? ENV.delete('CRM_AI_ENABLED') : ENV['CRM_AI_ENABLED'] = previous_ai
    previous_attr.nil? ? ENV.delete('CRM_AI_ATTR_EXTRACTION') : ENV['CRM_AI_ATTR_EXTRACTION'] = previous_attr
  end

  # #1498: funil de Atender não tem valor de venda; a IA não preenche.
  describe 'valor achado na conversa' do
    def preencher(card)
      attributes = {}
      ai = {}
      described_class.new(card: card).send(:apply_ai_value!, ai, { amount_cents: 120_000, currency: 'BRL' }, attributes)
      [attributes, ai]
    end

    it 'preenche num funil de Vender e não num de Atender' do
      account, admin = create_account_and_user
      venda, etapa_venda = create_crm_pipeline(account: account, user: admin)
      atender, etapa_atender = create_crm_pipeline(account: account, user: admin, name: 'Suporte')
      atender.update!(counts_as_sale: false)

      card_venda = account.crm_cards.create!(pipeline: venda, stage: etapa_venda, title: 'Plano anual')
      card_atender = account.crm_cards.create!(pipeline: atender, stage: etapa_atender, title: 'Troca')

      expect(preencher(card_venda).first).to include(value_cents: 120_000)
      expect(preencher(card_atender)).to eq([{}, {}])
    end
  end

  it 'skips when confidence is below suggestion threshold' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    target_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    target_stage.update!(metadata: { 'ai_criteria' => 'Proposta enviada' })
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      currency: 'BRL'
    )

    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
    )
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
      instance_double(
        Crm::Ai::StageClassifier,
        perform: {
          suggested_stage_id: target_stage.id,
          confidence: 0.5,
          reasoning: 'Baixa confiança',
          model_used: 'gpt-5.4-mini'
        }
      )
    )

    result = described_class.new(card: card).perform
    expect(result.status).to eq(:below_threshold)
    expect(account.crm_ai_stage_suggestions.where(card: card).count).to eq(0)
  end

  it 'creates a pending suggestion when confidence is between thresholds' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    target_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    target_stage.update!(metadata: { 'ai_criteria' => 'Proposta enviada' })
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      currency: 'BRL'
    )

    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
    )
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
      instance_double(
        Crm::Ai::StageClassifier,
        perform: {
          suggested_stage_id: target_stage.id,
          confidence: 0.65,
          reasoning: 'Cliente pediu orçamento',
          model_used: 'gpt-5.4-mini'
        }
      )
    )

    result = described_class.new(card: card).perform
    expect(result.status).to eq(:suggested)
    expect(result.suggestion).to be_pending
    expect(result.suggestion.to_stage_id).to eq(target_stage.id)
  end

  # #1918: card que uma pessoa moveu, reabriu ou criou numa etapa há pouco: em nenhum gatilho automático (a mensagem, que
  # também é o gatilho do EvaluateCardJob agendado pelo StaleCardsJob) a IA move ou sugere etapa; "Avaliar agora" é a
  # pessoa pedindo.
  describe 'movido por uma pessoa há pouco' do
    def preparar
      account, admin = create_account_and_user
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => true } })
      proposta = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
      alvo = create_crm_stage(account: account, pipeline: pipeline, name: 'Fechamento', position: 2)
      alvo.update!(metadata: { 'ai_criteria' => 'Cliente aceitou' })
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', currency: 'BRL')
      travel_to(1.hour.ago) { Crm::Cards::Mover.new(card: card, actor: admin, target_stage: proposta).perform }
      ia_responde(alvo)
      card
    end

    def ia_responde(alvo)
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
        instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
      )
      allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
        instance_double(Crm::Ai::StageClassifier, perform: { suggested_stage_id: alvo.id, confidence: 0.95, reasoning: 'x', model_used: 'm' })
      )
      allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
    end

    def sem_mexer(card)
      result = described_class.new(card: card, trigger: 'message').perform

      expect(result).to have_attributes(status: :skipped, error: 'pessoa_mexeu_na_etapa')
      expect(card.account.crm_ai_stage_suggestions.where(card: card, status: %i[pending auto_applied])).to be_empty
      card.reload
    end

    it 'gatilho automático: não move nem sugere' do
      card = preparar

      expect(sem_mexer(card).stage.name).to eq('Proposta')
    end

    it 'reaberto por uma pessoa há pouco: não move nem sugere' do
      card = preparar
      card.update!(status: :lost)
      travel_to(30.minutes.ago) { Crm::Cards::Closer.new(card: card, actor: card.account.users.first, result: 'reopen').perform }
      Crm::Activity.where(card: card, event_type: 'move').delete_all

      expect(sem_mexer(card)).to have_attributes(status: 'open')
      expect(card.stage.name).to eq('Proposta')
    end

    def criado_pela_pessoa(card, tempo:, etapa_escolhida:)
      Crm::Activity.where(card: card).delete_all
      travel_to(tempo.ago) do
        Crm::Cards::Creator.new(account: card.account, user: card.account.users.first, etapa_escolhida: etapa_escolhida,
                                params: { pipeline_id: card.pipeline_id, stage_id: card.stage_id, title: 'Novo' }).perform
      end
    end

    it 'criado por uma pessoa que escolheu a etapa há pouco: não move nem sugere' do
      novo = criado_pela_pessoa(preparar, tempo: 30.minutes, etapa_escolhida: true)

      expect(sem_mexer(novo).stage.name).to eq('Proposta')
    end

    it 'criado por uma pessoa na etapa padrão (aceitou a sugestão de assunto, criou pela conversa): a IA move' do
      novo = criado_pela_pessoa(preparar, tempo: 30.minutes, etapa_escolhida: false)

      expect(described_class.new(card: novo, trigger: 'message').perform.status).to eq(:auto_moved)
    end

    it 'passada a janela, a etapa escolhida na criação não trava mais' do
      novo = criado_pela_pessoa(preparar, tempo: described_class::RESPEITO_AO_MOVIMENTO + 1.minute, etapa_escolhida: true)

      expect(described_class.new(card: novo, trigger: 'message').perform.status).to eq(:auto_moved)
    end

    it 'com a IA respondendo a mesma etapa, a sugestão de antes também sai, e a tela é avisada' do
      card = preparar
      antiga = card.account.crm_ai_stage_suggestions.create!(card: card, from_stage: card.stage, to_stage: card.pipeline.stages.last,
                                                             confidence: 0.6, model_used: 'm', status: :pending)
      ia_responde(card.stage)
      allow(Crm::Cards::Broadcaster).to receive(:broadcast)

      expect(described_class.new(card: card, trigger: 'message').perform.error).to eq('pessoa_mexeu_na_etapa')
      expect(antiga.reload).to be_expired
      expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(card, Events::Types::CRM_CARD_UPDATED)
    end

    it 'a sugestão de etapa de antes da escolha da pessoa sai, e o resto da avaliação segue' do
      card = preparar
      antiga = card.account.crm_ai_stage_suggestions.create!(card: card, from_stage: card.stage, to_stage: card.stage, confidence: 0.6,
                                                             model_used: 'm', status: :pending)
      extracao = instance_double(Crm::Ai::AttributeExtraction, schema: { contact: [], conversation: [] }, apply: nil)
      allow(Crm::Ai::AttributeExtraction).to receive(:new).and_return(extracao)

      sem_mexer(card)

      expect(antiga.reload).to be_expired
      expect(extracao).to have_received(:apply)
      expect(card.metadata.dig('ai', 'last_evaluated_at')).to be_present
    end

    it 'só a atividade da IA (sistema) não trava' do
      card = preparar
      Crm::Activity.where(card: card).update_all(actor_type: 'system', actor_id: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.new(card: card, trigger: 'message').perform.status).to eq(:auto_moved)
    end

    it '"Avaliar agora": move' do
      card = preparar

      result = described_class.new(card: card, trigger: 'manual').perform

      expect(result.status).to eq(:auto_moved)
      expect(card.reload.stage.name).to eq('Fechamento')
    end
  end

  it 'applies extracted attributes even when the stage does not change' do
    ENV.delete('CRM_AI_ATTR_EXTRACTION')
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'attribute_extraction_enabled' => true, 'attribute_prefix' => 'sw_' } })
    create(
      :custom_attribute_definition,
      account: account,
      attribute_key: 'sw_cidade',
      attribute_model: 'contact_attribute',
      attribute_display_type: 'text'
    )
    inbox = create_crm_inbox(account: account)
    contact = create(:contact, account: account)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      contact: contact,
      primary_conversation: conversation,
      currency: 'BRL'
    )

    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
    )
    classifier = instance_double(
      Crm::Ai::StageClassifier,
      perform: {
        suggested_stage_id: stage.id,
        confidence: 0.95,
        reasoning: 'Permanece no estágio atual',
        value: nil,
        handoff: nil,
        callback_request: nil,
        extracted_attributes: {
          contact: [{ key: 'sw_cidade', value: 'Guarapuava', confidence: 0.9, evidence: 'Sou de Guarapuava' }],
          conversation: []
        },
        model_used: 'gpt-5.4-mini'
      }
    )
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classifier)

    result = described_class.new(card: card).perform

    expect(result.status).to eq(:skipped)
    expect(result.error).to eq('same_stage')
    expect(contact.reload.custom_attributes).to include('sw_cidade' => 'Guarapuava')
  end

  it 'uses the destination stage handoff settings after an automatic move' do
    account, admin = create_account_and_user
    agent = create(:user, account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = create(:contact, account: account)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    pipeline, source_stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'enabled' => true, 'auto_move_enabled' => true, 'handoff' => { 'enabled' => false } } })
    target_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Em atendimento', position: 1)
    handoff = { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'pool_type' => 'user', 'pool_id' => agent.id, 'prefer_online' => false }
    target_stage.update!(metadata: { 'ai_criteria' => 'Cliente precisa de atendimento humano', 'ai_handoff' => handoff })
    card = account.crm_cards.create!(pipeline: pipeline, stage: source_stage, title: 'Lead', contact: contact, inbox: inbox,
                                     primary_conversation: conversation, currency: 'BRL')

    stub_crm_ai_credential
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    first_classifier = instance_double(
      Crm::Ai::StageClassifier,
      perform: classification_for(target_stage, handoff: nil, reasoning: 'Move para atendimento')
    )
    handoff_classifier = instance_double(
      Crm::Ai::StageClassifier,
      perform: classification_for(
        target_stage,
        handoff: { intent: 'transferir', should_handoff: true, reason: 'Gatilho da etapa atendido', suggested_agent: nil },
        reasoning: 'Transferir para humano'
      )
    )

    expect(Crm::Ai::StageClassifier).to receive(:new).with(hash_including(handoff_enabled: false)).ordered
                                                     .and_return(first_classifier)
    expect(Crm::Ai::StageClassifier).to receive(:new).with(hash_including(handoff_enabled: true)).ordered
                                                     .and_return(handoff_classifier)

    result = described_class.new(card: card).perform

    expect(result.status).to eq(:auto_moved)
    expect(card.reload.stage_id).to eq(target_stage.id)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'does not assign after an automatic move to a stage without handoff enabled' do
    account, admin = create_account_and_user
    agent = create(:user, account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = create(:contact, account: account)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    pipeline, source_stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'enabled' => true, 'auto_move_enabled' => true, 'handoff' => { 'enabled' => false } } })
    target_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Em atendimento', position: 1)
    target_stage.update!(metadata: { 'ai_criteria' => 'Cliente precisa de atendimento humano' })
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: source_stage,
      title: 'Lead',
      contact: contact,
      inbox: inbox,
      primary_conversation: conversation,
      currency: 'BRL'
    )

    stub_crm_ai_credential
    classifier = instance_double(
      Crm::Ai::StageClassifier,
      perform: classification_for(target_stage, handoff: nil, reasoning: 'Move para atendimento')
    )
    expect(Crm::Ai::StageClassifier).to receive(:new).once.and_return(classifier)

    result = described_class.new(card: card).perform

    expect(result.status).to eq(:auto_moved)
    expect(card.reload.stage_id).to eq(target_stage.id)
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'keeps handoff behavior when the card stays in the current stage' do
    account, admin = create_account_and_user
    agent = create(:user, account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = create(:contact, account: account)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'enabled' => true, 'auto_move_enabled' => true } })
    stage.update!(
      metadata: {
        'ai_criteria' => 'Atendimento humano',
        'ai_handoff' => {
          'enabled' => true,
          'handoff_mode' => 'r2_direct',
          'pool_type' => 'user',
          'pool_id' => agent.id,
          'prefer_online' => false
        }
      }
    )
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      contact: contact,
      inbox: inbox,
      primary_conversation: conversation,
      currency: 'BRL'
    )

    stub_crm_ai_credential
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    classifier = instance_double(
      Crm::Ai::StageClassifier,
      perform: classification_for(
        stage,
        handoff: { intent: 'transferir', should_handoff: true, reason: 'Gatilho atendido', suggested_agent: nil },
        reasoning: 'Permanece em atendimento'
      )
    )
    expect(Crm::Ai::StageClassifier).to receive(:new).once.with(hash_including(handoff_enabled: true)).and_return(classifier)

    result = described_class.new(card: card).perform

    expect(result.status).to eq(:skipped)
    expect(result.error).to eq('same_stage')
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'passes an empty attribute schema and does not call the applier when the gate is disabled' do
    ENV['CRM_AI_ATTR_EXTRACTION'] = 'false'
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'attribute_extraction_enabled' => true, 'attribute_prefix' => 'sw_' } })
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      currency: 'BRL'
    )

    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
    )
    classifier = instance_double(
      Crm::Ai::StageClassifier,
      perform: {
        suggested_stage_id: stage.id,
        confidence: 0.95,
        reasoning: 'Permanece no estágio atual',
        value: nil,
        handoff: nil,
        callback_request: nil,
        extracted_attributes: {
          contact: [{ key: 'sw_cidade', value: 'Guarapuava', confidence: 0.9, evidence: 'Sou de Guarapuava' }],
          conversation: []
        },
        model_used: 'gpt-5.4-mini'
      }
    )

    expect(Crm::Ai::StageClassifier).to receive(:new).with(hash_including(attribute_schema: { contact: [], conversation: [], card: [] }))
                                                     .and_return(classifier)
    expect(Crm::Ai::AttributeExtractorApplier).not_to receive(:new)

    described_class.new(card: card).perform
  end

  def stub_crm_ai_credential
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
    )
  end

  def classification_for(stage, handoff:, reasoning:)
    {
      suggested_stage_id: stage.id,
      confidence: 0.95,
      reasoning: reasoning,
      value: nil,
      handoff: handoff,
      callback_request: nil,
      extracted_attributes: { contact: [], conversation: [] },
      score_signals: {},
      model_used: 'gpt-5.4-mini'
    }
  end

  # #1711 (C36): a IA de assunto leva o card da chegada para outro funil enquanto uma avaliação antiga pensa.
  describe 'card que mudou de funil' do
    let(:account) { create_account_and_user.first }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:comercial) { create_crm_pipeline(account: account, user: admin, name: 'Comercial') }
    let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
    let(:fechamento) do
      create_crm_stage(account: account, pipeline: comercial.first, name: 'Fechamento', position: 1).tap do |etapa|
        etapa.update!(metadata: { 'ai_criteria' => 'Cliente fechou' })
      end
    end
    let(:card) { account.crm_cards.create!(pipeline: comercial.first, stage: comercial.last, title: 'Lead', currency: 'BRL') }
    let(:resposta) do
      { suggested_stage_id: fechamento.id, confidence: 0.95, reasoning: 'Fechou', model_used: 'gpt-6-luna' }
    end

    before do
      comercial.first.update!(metadata: { 'ai' => { 'auto_move_enabled' => true } })
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
        instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
      )
    end

    it 'a resposta sobre as etapas do funil antigo é descartada: o card não volta e a avaliação não é carimbada' do
      classificador = instance_double(Crm::Ai::StageClassifier)
      allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classificador)
      allow(classificador).to receive(:perform) do
        # Enquanto o modelo pensa, a IA de assunto leva o card para Sinistro (outro processo, outro objeto).
        Crm::Card.find(card.id).update!(pipeline: sinistro.first, stage: sinistro.last)
        resposta
      end

      result = described_class.new(card: card).perform

      expect(result).to have_attributes(status: :skipped, error: 'pipeline_changed')
      expect(card.reload).to have_attributes(pipeline_id: sinistro.first.id, stage_id: sinistro.last.id)
      expect(card.metadata.to_h.dig('ai', 'last_evaluated_at')).to be_nil
      expect(account.crm_ai_stage_suggestions.where(card: card)).to be_empty
    end

    it 'a avaliação nova, no funil novo, não é pulada pela espera de 15 s da avaliação feita no funil antigo' do
      card.update!(pipeline: sinistro.first, stage: sinistro.last,
                   metadata: { 'ai' => { 'last_evaluated_at' => 5.seconds.ago.iso8601,
                                         'last_evaluated_pipeline_id' => comercial.first.id } })
      allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
        instance_double(Crm::Ai::StageClassifier, perform: resposta.merge(suggested_stage_id: sinistro.last.id))
      )

      result = described_class.new(card: card).perform

      expect(result.error).not_to eq('debounced')
      expect(Crm::Ai::StageClassifier).to have_received(:new)
      expect(card.reload.metadata.dig('ai', 'last_evaluated_pipeline_id')).to eq(sinistro.first.id)
    end

    it 'no mesmo funil, a espera de 15 s continua valendo' do
      card.update!(metadata: { 'ai' => { 'last_evaluated_at' => 5.seconds.ago.iso8601,
                                         'last_evaluated_pipeline_id' => comercial.first.id } })
      allow(Crm::Ai::StageClassifier).to receive(:new)

      expect(described_class.new(card: card).perform.error).to eq('debounced')
      expect(Crm::Ai::StageClassifier).not_to have_received(:new)
    end
  end
end
