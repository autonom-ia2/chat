require 'rails_helper'

# IA entende a conversa F3 (flag `crm_ia_fecha_card`): a IA de etapa decide, na mesma avaliação, que o pedido do card
# terminou. Perdido com motivo em qualquer funil, Resolvido só em funil de Atender, Ganho nunca. A decisão é sempre
# sugestão, que a pessoa aceita num clique: a IA nunca fecha sozinha, nem com confiança 0,99 (decisão do Rodrigo, 30/10,
# #2389). Nunca por cima de uma pessoa ou de mensagem nova. O modelo é simulado: aqui se prova o código.
RSpec.describe Crm::Ai::FecharCard do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:funil_e_etapa) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => true } })
    [pipeline, stage]
  end
  let(:pipeline) { funil_e_etapa.first }
  let(:stage) { funil_e_etapa.last }
  let(:conversa) { create(:conversation, account: account) }

  before { account.enable_features!(described_class::FLAG) }

  def novo_card(funil: pipeline, etapa: stage, **atributos)
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Pedido', currency: 'BRL', primary_conversation: conversa, **atributos)
  end

  def funil_de_atender
    funil = account.crm_pipelines.create!(name: 'Atendimento', created_by: admin, status: :active, counts_as_sale: false,
                                          metadata: { 'ai' => { 'auto_move_enabled' => true } })
    [funil, account.crm_pipeline_stages.create!(pipeline: funil, name: 'Aberto', position: 0)]
  end

  # durante: o que acontece enquanto o modelo pensa (depois de a conversa ser lida para a avaliação).
  def ia_responde(fechar_card, suggested_stage_id: nil, durante: nil, handoff: nil)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
    )
    resposta = { suggested_stage_id: suggested_stage_id, confidence: 0.9, reasoning: 'x', model_used: 'm',
                 fechar_card: fechar_card, handoff: handoff }.with_indifferent_access
    classificador = instance_double(Crm::Ai::StageClassifier)
    allow(classificador).to receive(:perform) do
      durante&.call
      resposta
    end
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classificador)
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
  end

  # 0,96: a faixa dos fechamentos errados da semana (0,95–0,99). Vira sugestão, como qualquer confiança de sugerir.
  def fim(resultado: 'perdido', motivo: 'recusou', confidence: 0.96, retorno_em: nil)
    { resultado: resultado, motivo: motivo, retorno_em: retorno_em, confidence: confidence, reasoning: 'O cliente disse que não quer.' }
  end

  def avaliar(card, trigger: 'message')
    Crm::Ai::Evaluator.new(card: card, trigger: trigger).perform
  end

  def aceitar(sugestao) = Crm::Ai::SuggestionApplier.new(card: sugestao.card, suggestion: sugestao, actor: admin).perform

  # A IA sugere e a pessoa aceita: o card só fecha no aceite.
  def sugerir_e_aceitar(card)
    resultado = avaliar(card)
    expect(resultado.status).to eq(:suggested)
    expect(card.reload).to be_open
    aceitar(resultado.suggestion)
    resultado.suggestion
  end

  # Pega: o "Perdido" da IA ser só uma coluna, com o card aberto e sem motivo (achado H4 do placar).
  it 'perdido aceito: fecha como Perdido, com o motivo na língua da conta e a pessoa na linha do tempo', :aggregate_failures do
    account.update!(locale: 'pt_BR')
    card = novo_card
    ia_responde(fim(motivo: 'fechou_com_outra'), suggested_stage_id: stage.id)

    sugestao = sugerir_e_aceitar(card)

    expect(card.reload).to have_attributes(status: 'lost', lost_reason: 'Fechou com outra empresa')
    expect(card.closed_at).to be_present
    atividade = Crm::Activity.where(card: card, event_type: 'lost').sole
    expect(atividade).to have_attributes(actor_type: 'user', actor_id: admin.id)
    expect(atividade.payload)
      .to include('sugestao_da_ia' => sugestao.id, 'motivo' => 'fechou_com_outra', 'lost_reason' => 'Fechou com outra empresa')
    expect(atividade.payload).to have_key('closed_with')
  end

  # Pega: o card fechado ficar na etapa do meio quando o funil tem a etapa de perda (o quadro mente).
  it 'perdido aceito num funil com etapa de perda: o card vai para ela antes de fechar', :aggregate_failures do
    perda = create_crm_stage(account: account, pipeline: pipeline, name: 'Perdido', position: 9).tap { |etapa| etapa.update!(is_lost_stage: true) }
    card = novo_card
    ia_responde(fim, suggested_stage_id: stage.id)

    sugerir_e_aceitar(card)

    expect(card.reload).to have_attributes(stage_id: perda.id, status: 'lost')
    expect(Crm::Activity.where(card: card, event_type: 'move', actor_type: 'user')).to exist
  end

  # Pega: o perdido de um funil de Atender virar "lost" (venda) em vez de Cancelado.
  it 'perdido aceito num funil de Atender: fecha como Cancelado' do
    funil, etapa = funil_de_atender
    card = novo_card(funil: funil, etapa: etapa)
    ia_responde(fim(motivo: 'adiou'), suggested_stage_id: etapa.id)

    sugerir_e_aceitar(card)

    expect(card.reload).to have_attributes(status: 'cancelled', lost_reason: 'Postponed')
  end

  # Pega (regra j): o atendimento resolvido continuar aberto, e ir para a etapa de fim do funil de Atender.
  it 'resolvido aceito num funil de Atender: fecha como Resolvido, na etapa de fim', :aggregate_failures do
    funil, etapa = funil_de_atender
    final = create_crm_stage(account: account, pipeline: funil, name: 'Resolvido', position: 5).tap { |e| e.update!(is_won_stage: true) }
    card = novo_card(funil: funil, etapa: etapa)
    ia_responde(fim(resultado: 'resolvido', motivo: nil), suggested_stage_id: etapa.id)

    sugerir_e_aceitar(card)

    expect(card.reload).to have_attributes(status: 'resolved', stage_id: final.id, lost_reason: nil)
    expect(Crm::Activity.where(card: card, event_type: 'resolved').sole).to have_attributes(actor_type: 'user', actor_id: admin.id)
  end

  # Pega (regra c): a IA marcar Ganho. Num funil de venda, "resolvido" seria ganho: o código recusa e o card segue aberto.
  it 'resolvido num funil de venda: não fecha (a IA nunca marca Ganho)', :aggregate_failures do
    card = novo_card
    ia_responde(fim(resultado: 'resolvido', motivo: nil), suggested_stage_id: stage.id)

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'same_stage')
    expect(card.reload).to be_open
    expect(Crm::Activity.where(card: card, event_type: %w[won resolved])).to be_empty
  end

  it 'resultado fora da lista (ganho): não fecha' do
    card = novo_card
    ia_responde(fim(resultado: 'ganho', motivo: nil), suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
  end

  it 'perdido sem motivo da lista: não fecha' do
    card = novo_card
    ia_responde(fim(motivo: nil), suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: o fechamento valer numa conta sem a flag (o comportamento de antes tem de voltar inteiro).
  it 'conta sem a flag: nada fecha nem vira sugestão de fechar', :aggregate_failures do
    account.disable_features!(described_class::FLAG)
    card = novo_card
    ia_responde(fim(confidence: 0.8), suggested_stage_id: stage.id)

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'same_stage')
    expect(card.reload).to be_open
    expect(sugestoes_de_fechar(card)).to be_empty
  end

  def sugestoes_de_fechar(card)
    account.crm_ai_stage_suggestions.where(card: card).where("metadata ->> 'fechar' IS NOT NULL")
  end

  # Pega (decisão do Rodrigo, 30/10, #2389): a IA fechar sozinha. Os fechamentos errados da semana vieram com 0,95–0,99.
  describe 'a decisão de fechar vira sugestão de fechar' do
    let!(:perda) { create_crm_stage(account: account, pipeline: pipeline, name: 'Perdido', position: 9).tap { |e| e.update!(is_lost_stage: true) } }

    it 'grava a sugestão pendente com o resultado, o motivo, o retorno e o texto, e o card fica', :aggregate_failures do
      card = novo_card
      ia_responde(fim(motivo: 'adiou', confidence: 0.86, retorno_em: '2026-12-01'), suggested_stage_id: perda.id)

      resultado = avaliar(card)

      expect(resultado.status).to eq(:suggested)
      expect(card.reload).to have_attributes(status: 'open', stage_id: stage.id)
      expect(resultado.suggestion).to have_attributes(status: 'pending', from_stage_id: stage.id, to_stage_id: perda.id,
                                                      reasoning: 'O cliente disse que não quer.', confidence: 0.86)
      expect(resultado.suggestion.fechar).to eq('resultado' => 'perdido', 'motivo' => 'adiou', 'retorno_em' => '2026-12-01')
      expect(Crm::FollowUp.where(card: card)).to be_empty
    end

    # Pega: um limiar de "fechar sozinho" voltar. 0,94 a 1,0 cobre a faixa dos erros da semana e a confiança máxima.
    [0.94, 0.95, 0.96, 0.99, 1.0].each do |confianca|
      it "confiança #{confianca}: vira sugestão pendente, e o card fica aberto", :aggregate_failures do
        card = novo_card
        ia_responde(fim(confidence: confianca), suggested_stage_id: stage.id)

        resultado = avaliar(card)

        expect(resultado.status).to eq(:suggested)
        expect(resultado.suggestion).to have_attributes(status: 'pending', confidence: confianca)
        expect(card.reload).to have_attributes(status: 'open', closed_at: nil, stage_id: stage.id)
        expect(Crm::Activity.where(card: card, event_type: described_class::EVENTOS_DE_FECHAMENTO)).to be_empty
      end
    end

    # Pega: algum caminho da avaliação fechar o card sem pessoa. O único fechamento é o do aceite, com a pessoa como ator.
    it 'nenhuma avaliação fecha: o Closer só roda no aceite, com a pessoa', :aggregate_failures do
      allow(Crm::Cards::Closer).to receive(:new).and_call_original
      card = novo_card
      ['message', 'manual', described_class::TRIGGER_CARD_PARADO].each do |gatilho|
        card.update!(metadata: {})
        ia_responde(fim(confidence: 1.0), suggested_stage_id: stage.id)
        avaliar(card, trigger: gatilho)
      end
      expect(Crm::Cards::Closer).not_to have_received(:new)
      expect(card.reload).to be_open

      card.update!(metadata: {})
      ia_responde(fim(confidence: 1.0), suggested_stage_id: stage.id)
      aceitar(avaliar(card).suggestion)

      expect(Crm::Cards::Closer).to have_received(:new).once.with(hash_including(card: card, actor: admin))
      expect(card.reload).to be_lost
    end

    it 'chamado direto, com confiança 1,0: devolve a sugestão e não fecha', :aggregate_failures do
      card = novo_card

      resultado = described_class.new(card: card, decisao: fim(confidence: 1.0), lido_em: Time.current,
                                      origem: { model_used: 'm', trigger: 'message' }).aplicar!

      expect(resultado).to be_a(Crm::AiStageSuggestion).and(be_pending)
      expect(card.reload).to be_open
    end

    it 'confiança 0,99 no "resolvido" de um funil de Atender: também vira sugestão', :aggregate_failures do
      funil, etapa = funil_de_atender
      card = novo_card(funil: funil, etapa: etapa)
      ia_responde(fim(resultado: 'resolvido', motivo: nil, confidence: 0.99), suggested_stage_id: etapa.id)

      expect(avaliar(card).status).to eq(:suggested)
      expect(card.reload).to be_open
    end

    it 'abaixo da confiança de sugerir: nem fecha nem sugere fechar' do
      card = novo_card
      ia_responde(fim(confidence: 0.5), suggested_stage_id: stage.id)

      avaliar(card)

      expect(sugestoes_de_fechar(card)).to be_empty
    end

    it 'funil sem movimento automático: nunca fecha sozinho, nem com confiança alta; sugere', :aggregate_failures do
      pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => false } })
      card = novo_card
      ia_responde(fim(confidence: 0.99), suggested_stage_id: stage.id)

      expect(avaliar(card).status).to eq(:suggested)
      expect(card.reload).to be_open
      expect(sugestoes_de_fechar(card).sole).to be_pending
    end

    # Pega: a sugestão de fechar ficar na tela depois de o cliente seguir a conversa.
    it 'a leitura nova que não pede para fechar expira a sugestão de fechar' do
      card = novo_card
      ia_responde(fim(confidence: 0.8), suggested_stage_id: stage.id)
      avaliar(card)
      card.update!(metadata: {})
      ia_responde(nil, suggested_stage_id: stage.id)

      avaliar(card)

      expect(sugestoes_de_fechar(card).sole).to be_expired
    end

    # Pega (revisão): a sugestão velha seguir aceitável quando a leitura nova pede para fechar mas uma guarda barra.
    it 'a leitura nova barrada por pedido de pessoa também expira a sugestão de fechar', :aggregate_failures do
      card = novo_card
      ia_responde(fim(confidence: 0.8), suggested_stage_id: stage.id)
      velha = avaliar(card).suggestion
      card.update!(metadata: {})
      ia_responde(fim(confidence: 0.8), suggested_stage_id: stage.id,
                                        handoff: { intent: 'transferir', should_handoff: true, reason: 'Pediu uma pessoa', suggested_agent: nil })
      allow(Crm::Ai::HandoffExecutor).to receive(:new).and_return(instance_double(Crm::Ai::HandoffExecutor, perform: nil))

      avaliar(card)

      expect(velha.reload).to be_expired
      expect(sugestoes_de_fechar(card).pending).to be_empty
    end

    # Pega: o silêncio (card parado) apagar a sugestão que espera a pessoa.
    it 'a avaliação do card parado não mexe na sugestão de fechar' do
      card = novo_card
      ia_responde(fim(confidence: 0.8), suggested_stage_id: stage.id)
      sugestao = avaliar(card).suggestion
      card.update!(metadata: {})
      ia_responde(nil, suggested_stage_id: stage.id)

      avaliar(card, trigger: described_class::TRIGGER_CARD_PARADO)

      expect(sugestao.reload).to be_pending
    end
  end

  # Pega: "Avaliar agora" (a pessoa olhando o card) fechar o card sem ela pedir.
  it '"Avaliar agora": não fecha nem sugere fechar', :aggregate_failures do
    card = novo_card
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card, trigger: 'manual')

    expect(card.reload).to be_open
    expect(sugestoes_de_fechar(card)).to be_empty
  end

  # Pega (regra i): silêncio virar Perdido. A avaliação do card parado nunca fecha.
  it 'avaliação do card parado: não fecha' do
    card = novo_card
    ia_responde(fim(motivo: 'adiou'), suggested_stage_id: stage.id)

    avaliar(card, trigger: described_class::TRIGGER_CARD_PARADO)

    expect(card.reload).to be_open
  end

  # Pega (revisão adversarial F3): o fechamento barrado deixar o card ABERTO na coluna de perda, sem motivo nem retorno,
  # porque a etapa de fim que veio junto moveu sozinha (o achado H4, agora causado pela própria regra de fechar).
  describe 'fechamento barrado com a etapa de fim junto' do
    let(:perda) do
      create_crm_stage(account: account, pipeline: pipeline, name: 'Perdido', position: 9)
        .tap { |etapa| etapa.update!(is_lost_stage: true, metadata: { 'ai_criteria' => 'O cliente desistiu.' }) }
    end

    # Revisão adversarial 2 (item 12): nem a sugestão de etapa para a coluna de perda (aceita, deixaria o card aberto lá).
    it 'card parado: não move para a perda nem sugere a coluna', :aggregate_failures do
      card = novo_card
      ia_responde(fim(motivo: 'adiou'), suggested_stage_id: perda.id)

      resultado = avaliar(card, trigger: described_class::TRIGGER_CARD_PARADO)

      expect(resultado).to have_attributes(status: :skipped, error: 'etapa_de_fim_sem_fechar')
      expect(card.reload).to have_attributes(status: 'open', stage_id: stage.id)
      expect(account.crm_ai_stage_suggestions.where(card: card)).to be_empty
    end

    it 'mensagem nova do cliente: não move para a perda nem sugere a coluna', :aggregate_failures do
      card = novo_card
      nova = -> { create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'Espera') }
      ia_responde(fim, suggested_stage_id: perda.id, durante: nova)

      expect(avaliar(card).status).to eq(:skipped)
      expect(card.reload).to have_attributes(status: 'open', stage_id: stage.id)
      expect(account.crm_ai_stage_suggestions.where(card: card)).to be_empty
    end

    it 'etapa de perda sem pedido de fechar: não move nem sugere (perder é fechar, com motivo)', :aggregate_failures do
      card = novo_card
      ia_responde(nil, suggested_stage_id: perda.id)

      expect(avaliar(card).status).to eq(:skipped)
      expect(card.reload.stage_id).to eq(stage.id)
      expect(account.crm_ai_stage_suggestions.where(card: card)).to be_empty
    end

    it 'etapa de ganho sem pedido de fechar: move como sempre (o ganho é pela etapa)' do
      ganho = create_crm_stage(account: account, pipeline: pipeline, name: 'Ganho', position: 8)
      ganho.update!(is_won_stage: true, metadata: { 'ai_criteria' => 'O cliente fechou.' })
      card = novo_card
      ia_responde(nil, suggested_stage_id: ganho.id)

      expect(avaliar(card).status).to eq(:auto_moved)
    end

    it 'sem a flag: a etapa de perda move como sempre' do
      account.disable_features!(described_class::FLAG)
      card = novo_card
      ia_responde(fim, suggested_stage_id: perda.id)

      expect(avaliar(card).status).to eq(:auto_moved)
    end
  end

  # Pega: o pedido de pessoa sumir porque o card fechou antes da passagem.
  it 'pedido de pessoa na mesma resposta: não fecha nem sugere fechar', :aggregate_failures do
    card = novo_card
    ia_responde(fim(confidence: 0.8), suggested_stage_id: stage.id,
                                      handoff: { intent: 'transferir', should_handoff: true, reason: 'Pediu uma pessoa', suggested_agent: nil })
    allow(Crm::Ai::HandoffExecutor).to receive(:new).and_return(instance_double(Crm::Ai::HandoffExecutor, perform: nil))

    avaliar(card)

    expect(card.reload).to be_open
    expect(sugestoes_de_fechar(card)).to be_empty
  end

  # Pega: a decisão velha valer depois de o cliente escrever de novo enquanto o modelo pensava.
  it 'mensagem nova do cliente enquanto o modelo pensava: não fecha nem sugere fechar', :aggregate_failures do
    card = novo_card
    nova = -> { create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'Espera') }
    ia_responde(fim(confidence: 0.8), suggested_stage_id: stage.id, durante: nova)

    avaliar(card)

    expect(card.reload).to be_open
    expect(sugestoes_de_fechar(card)).to be_empty
  end

  # Pega: a IA fechar por cima de uma pessoa que acabou de reabrir o card.
  it 'reaberto por uma pessoa há pouco: não fecha nem sugere fechar', :aggregate_failures do
    card = novo_card
    Crm::ActivityLogger.new(card: card, actor: admin, event_type: 'reopen', payload: {}).perform
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
    expect(sugestoes_de_fechar(card)).to be_empty
  end

  it 'a sugestão de etapa pendente do card fechado expira' do
    card = novo_card
    outra = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    sugestao = account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: outra, confidence: 0.6,
                                                        reasoning: 'x', model_used: 'm', status: :pending)
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card)

    expect(sugestao.reload).to be_expired
  end

  # Aceitar a sugestão (Crm::Ai::SuggestionApplier, o mesmo do "Mover para"): o mesmo fechamento, com a pessoa como autora.
  describe 'a pessoa aceita a sugestão de fechar' do
    let!(:perda) { create_crm_stage(account: account, pipeline: pipeline, name: 'Perdido', position: 9).tap { |e| e.update!(is_lost_stage: true) } }
    let(:fuso) { Crm::Timezone::Resolver.new(account: account).zone_or_default }

    def sugerir(card, decisao)
      ia_responde(decisao, suggested_stage_id: stage.id)
      avaliar(card).suggestion
    end

    it 'perdido "adiou": vai para a perda, fecha com o motivo e a pessoa como autora, e agenda o retorno', :aggregate_failures do
      card = novo_card
      dia = fuso.today + 20
      sugestao = sugerir(card, fim(motivo: 'adiou', confidence: 0.86, retorno_em: dia.iso8601))

      aceitar(sugestao)

      expect(card.reload).to have_attributes(status: 'lost', stage_id: perda.id, lost_reason: 'Postponed')
      expect(sugestao.reload).to be_accepted
      fechamento = Crm::Activity.where(card: card, event_type: 'lost').sole
      expect(fechamento).to have_attributes(actor_type: 'user', actor_id: admin.id)
      expect(fechamento.payload).to include('sugestao_da_ia' => sugestao.id, 'motivo' => 'adiou')
      expect(fechamento.payload).not_to have_key('by')
      retorno = Crm::FollowUp.where(card: card).where("metadata ->> 'source' = ?", 'ai_callback').sole
      expect(retorno.due_at).to eq(fuso.parse("#{dia.iso8601} 09:00"))
      expect(described_class.fechados_pela_ia(account, 1.hour.ago)).to be_empty
    end

    it 'resolvido num funil de Atender: fecha como Resolvido', :aggregate_failures do
      funil, etapa = funil_de_atender
      card = novo_card(funil: funil, etapa: etapa)
      ia_responde(fim(resultado: 'resolvido', motivo: nil, confidence: 0.9), suggested_stage_id: etapa.id)
      sugestao = avaliar(card).suggestion

      aceitar(sugestao)

      expect(card.reload).to have_attributes(status: 'resolved', lost_reason: nil)
      expect(Crm::FollowUp.where(card: card)).to be_empty
    end

    # Pega: aceitar uma sugestão velha reabrir a discussão de um card que alguém já fechou.
    it 'card já fechado: não mexe nele, e a sugestão expira', :aggregate_failures do
      card = novo_card
      sugestao = sugerir(card, fim(confidence: 0.8))
      Crm::Cards::Closer.new(card: card, actor: admin, result: 'won').perform

      aceitar(sugestao)

      expect(card.reload).to be_won
      expect(sugestao.reload).to be_expired
    end

    # Revisão adversarial (item 10): o fechamento por qualquer caminho tira o "Encerrar" que esperava.
    it 'o card fechado por uma pessoa expira a sugestão de fechar na hora' do
      card = novo_card
      sugestao = sugerir(card, fim(confidence: 0.8))

      Crm::Cards::Closer.new(card: card, actor: admin, result: 'lost').perform

      expect(sugestao.reload).to be_expired
    end

    # Revisão adversarial (item 2): aceitar fechar por cima do que o cliente disse depois da leitura.
    it 'mensagem do cliente depois da leitura: não fecha, e a sugestão expira', :aggregate_failures do
      card = novo_card
      sugestao = sugerir(card, fim(confidence: 0.8))
      expect(sugestao.metadata['lido_em']).to be_present
      create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'Mudei de ideia')

      expect(described_class.aceitar!(sugestao, ator: admin)).to be(false)
      expect(card.reload).to be_open
      expect(sugestao.reload).to be_expired
    end

    # Pega (#2389): um aceite sem pessoa (ator nil) ou pelo automático fechar o card como sistema.
    it 'sem pessoa ou pelo automático: não fecha, e a sugestão expira', :aggregate_failures do
      [{ actor: nil, auto: false }, { actor: admin, auto: true }].each do |modo|
        card = novo_card
        sugestao = sugerir(card, fim(confidence: 0.99))

        Crm::Ai::SuggestionApplier.new(card: card, suggestion: sugestao, **modo).perform

        expect(card.reload).to be_open
        expect(sugestao.reload).to be_expired
        expect(Crm::Activity.where(card: card, event_type: described_class::EVENTOS_DE_FECHAMENTO)).to be_empty
      end
    end

    it 'mensagem da equipe depois da leitura não impede o aceite' do
      card = novo_card
      sugestao = sugerir(card, fim(confidence: 0.8))
      create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :outgoing, content: 'Tudo bem')

      expect(described_class.aceitar!(sugestao, ator: admin)).to be(true)
    end

    # Revisão adversarial (item 3, o caso que o Codex simulou): o "resolvido" sugerido num funil de Atender e aceito depois
    # que o card foi para um funil de venda virava Ganho. O funil muda entre a leitura do aceite e a trava.
    it '"resolvido" aceito depois de o card ir para um funil de venda: nunca vira Ganho; expira', :aggregate_failures do
      funil, etapa = funil_de_atender
      card = novo_card(funil: funil, etapa: etapa)
      ia_responde(fim(resultado: 'resolvido', motivo: nil, confidence: 0.9), suggested_stage_id: etapa.id)
      sugestao = avaliar(card).suggestion
      alvo = sugestao.card
      alvo.pipeline # o aceite já tinha lido o funil de Atender
      allow(alvo).to receive(:with_lock).and_wrap_original do |original, *args, &bloco|
        Crm::Card.where(id: alvo.id).update_all(pipeline_id: pipeline.id, stage_id: stage.id) # rubocop:disable Rails/SkipsModelValidations
        original.call(*args, &bloco)
      end

      expect(described_class.aceitar!(sugestao, ator: admin)).to be(false)
      expect(card.reload).to have_attributes(status: 'open', pipeline_id: pipeline.id)
      expect(sugestao.reload).to be_expired
    end

    it 'o card mudou de funil depois da sugestão: o "perdido" também expira' do
      card = novo_card
      sugestao = sugerir(card, fim(confidence: 0.8))
      outro, etapa = funil_de_atender
      card.update!(pipeline: outro, stage: etapa)

      expect(described_class.aceitar!(sugestao.reload, ator: admin)).to be(false)
    end

    # Revisão adversarial (item 9): o segundo aceite (com a sugestão velha na memória) apagar o "aceita" do primeiro.
    it 'dois aceites ao mesmo tempo: o segundo não expira a sugestão que o primeiro aceitou', :aggregate_failures do
      card = novo_card
      sugestao = sugerir(card, fim(confidence: 0.8))
      copia = Crm::AiStageSuggestion.find(sugestao.id)

      expect(described_class.aceitar!(sugestao, ator: admin)).to be(true)
      expect(described_class.aceitar!(copia, ator: admin)).to be(false)
      expect(sugestao.reload).to be_accepted
      expect(card.reload).to be_lost
    end
  end

  # Revisão adversarial (item 11): uma pessoa fecha o card enquanto o modelo pensa; a sugestão de etapa não pode nascer
  # num card fechado.
  it 'card fechado enquanto o modelo pensava: não grava sugestão de etapa', :aggregate_failures do
    card = novo_card
    outra = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    fechar = -> { Crm::Cards::Closer.new(card: Crm::Card.find(card.id), actor: admin, result: 'lost').perform }
    ia_responde(nil, suggested_stage_id: outra.id, durante: fechar)
    pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => false } })

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'card_not_open')
    expect(account.crm_ai_stage_suggestions.where(card: card)).to be_empty
  end

  # Verificação do Codex (item 11, parcial): o "voltar de etapa" (regra h) gravava a sugestão sem a trava, e uma pessoa
  # que fechava o card enquanto o modelo pensava deixava uma sugestão pendente num card perdido.
  it 'voltar de etapa com o card fechado enquanto o modelo pensava: não grava sugestão', :aggregate_failures do
    proposta = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    card = novo_card(etapa: proposta)
    Crm::ActivityLogger.new(card: card, actor: admin, event_type: 'move', payload: {}).perform
    fechar = -> { Crm::Cards::Closer.new(card: Crm::Card.find(card.id), actor: admin, result: 'lost').perform }
    ia_responde(nil, suggested_stage_id: stage.id, durante: fechar)

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'card_not_open')
    expect(card.reload).to be_lost
    expect(account.crm_ai_stage_suggestions.where(card: card)).to be_empty
  end

  # Verificação do Codex (item 11): a trava nova não pode custar nada às contas sem a IA entende a conversa.
  describe 'consultas da gravação da sugestão de etapa' do
    def travas_ao_sugerir(card)
      outra = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
      pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => false } })
      ia_responde(nil, suggested_stage_id: outra.id)
      travas = []
      contador = ->(*, dados) { travas << dados[:sql] if dados[:sql].include?('FOR UPDATE') }
      resultado = nil
      ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') { resultado = avaliar(card) }
      expect(resultado.status).to eq(:suggested)
      travas.size
    end

    it 'sem as 4 flags: só a trava de sempre (a do carimbo da avaliação), como na main' do
      account.disable_features!(described_class::FLAG)

      expect(travas_ao_sugerir(novo_card)).to eq(1)
    end

    it 'com uma flag F1–F4: a trava a mais que relê o card antes de gravar' do
      account.disable_features!(described_class::FLAG)
      account.enable_features!(Crm::Ai::FatosDaConversa::FLAG)

      expect(travas_ao_sugerir(novo_card)).to eq(2)
    end
  end

  describe '.fechados_pela_ia' do
    it 'traz o card fechado pela IA e tira o que uma pessoa fechou ou reabriu depois', :aggregate_failures do
      pela_ia = novo_card
      depois_pela_pessoa = novo_card
      pela_pessoa = novo_card
      [pela_ia, depois_pela_pessoa].each do |card|
        Crm::Cards::Closer.new(card: card, actor: nil, result: 'lost', payload_extra: { by: 'ai' }).perform
      end
      Crm::ActivityLogger.new(card: depois_pela_pessoa, actor: admin, event_type: 'reopen', payload: {}).perform
      Crm::Cards::Closer.new(card: pela_pessoa, actor: admin, result: 'lost').perform

      expect(described_class.fechados_pela_ia(account, 1.hour.ago)).to eq([pela_ia.id])
    end
  end
end
