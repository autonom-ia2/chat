require 'rails_helper'

# #1975: antes de entregar a espera da IA do CRM, a fila pede uma releitura (uma vez, e de novo só com mensagem nova).
# A releitura roda num job (Crm::Ai::RevalidaPassagemJob): a fila só enfileira e segura a conversa enquanto ela não
# termina. As outras esperas seguem como antes.
RSpec.describe Crm::Ai::HandoffDrainJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'trigger' => 'pedido de pessoa' } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', primary_conversation: conversation,
                              inbox: inbox)
  end
  let(:revalida) { instance_double(Crm::Ai::RevalidaPassagem) }

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    card
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::RevalidaPassagem).to receive(:new).and_return(revalida)
    allow(revalida).to receive(:call)
  end

  after { ActiveRecord::Base.connection.execute('SELECT pg_advisory_unlock_all()') }

  def segurar!(motivo: Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA, razao: 'cliente pediu a cotação e o robô falhou')
    Crm::Entrega::Marca.marcar(conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: motivo, falha: 'ninguem_online', razao: razao)
    conversation.save!
  end

  def fala!(texto, tipo: :outgoing, **extra)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo, content: texto, **extra)
  end

  def marca
    Crm::Entrega::Marca.dados(conversation.reload)
  end

  def releituras
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == Crm::Ai::RevalidaPassagemJob }
  end

  def roda_releituras!
    jobs = releituras
    ActiveJob::Base.queue_adapter.enqueued_jobs.reject! { |job| jobs.include?(job) }
    jobs.each { |job| Crm::Ai::RevalidaPassagemJob.perform_now(*job[:args]) }
  end

  def responde!(passa, motivo)
    allow(revalida).to receive(:call).and_return({ passa: passa, motivo: motivo, decisao: passa ? 'problema_em_aberto' : 'resolvido' })
    Crm::Ai::RevalidaPassagemJob.perform_now(conversation.id, marca['revalidando_desde'])
  end

  # Revisão do PR #1980: a chamada leva até 74 s, e a rodada tem 45 s por passo. A fila não chama o modelo.
  it 'a fila não chama o modelo: grava a releitura em curso, enfileira o job e segura a conversa', :aggregate_failures do
    segurar!

    described_class.perform_now

    expect(Crm::Ai::RevalidaPassagem).not_to have_received(:new)
    expect(conversation.reload.assignee_id).to be_nil
    expect(marca['revalidando_desde']).to be_present
    expect(releituras.sole[:args]).to eq([conversation.id, marca['revalidando_desde']])
  end

  it 'enfileira uma vez por espera: de novo só uma vez, se o job parece perdido (5 min)', :aggregate_failures do
    segurar!

    described_class.perform_now
    travel(2.minutes) { described_class.perform_now }
    expect(releituras.size).to eq(1)

    travel(6.minutes) { described_class.perform_now }
    travel(8.minutes) { described_class.perform_now }
    expect(releituras.size).to eq(2)
    expect(releituras.map { |job| job[:args].last }.uniq).to eq([marca['revalidando_desde']])
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'releitura sem resposta em 10 min: entrega como hoje, sem reler', :aggregate_failures do
    segurar!
    described_class.perform_now

    travel(11.minutes) { described_class.perform_now }

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(releituras.size).to eq(1)
    expect(revalida).not_to have_received(:call)
  end

  it 'releitura com o problema aberto: a rodada seguinte entrega, com o motivo novo', :aggregate_failures do
    segurar!
    described_class.perform_now
    responde!(true, 'cliente pediu explicação de DMH e o robô não soube')

    described_class.perform_now

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(Crm::Activity.where(card_id: card.id, event_type: 'ai_handoff').sole.payload['reason'])
      .to eq('cliente pediu explicação de DMH e o robô não soube')
  end

  it 'depois de relida, nota privada e atividade não pedem outra releitura', :aggregate_failures do
    segurar!
    described_class.perform_now
    responde!(true, 'dúvida sem resposta')

    travel(1.minute) do
      fala!('nota interna', private: true)
      fala!('Conversa atribuída', tipo: :activity)
      described_class.perform_now
    end

    expect(releituras.size).to eq(1)
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'mensagem nova do cliente depois da releitura pede outra' do
    segurar!
    described_class.perform_now
    responde!(true, 'dúvida sem resposta')

    travel(1.minute) do
      fala!('Alguém pode me ajudar?', tipo: :incoming)
      described_class.perform_now
    end

    expect(releituras.size).to eq(2)
  end

  it 'com a IA do CRM desligada, entrega como hoje, sem enfileirar', :aggregate_failures do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)
    segurar!

    described_class.perform_now

    expect(releituras).to be_empty
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'a espera que o próprio agente pediu não é relida' do
    segurar!(motivo: 'robo_pediu')

    described_class.perform_now

    expect(releituras).to be_empty
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  # Revisão do PR #1980 (ALTO 1): com uma mensagem chegando durante cada releitura, toda resposta é velha e seria
  # descartada para sempre. O prazo total (10 min desde a primeira releitura da espera) não recomeça: a conversa é
  # entregue na primeira rodada depois dele.
  it 'mensagem chegando durante cada releitura: a conversa é entregue em até 10 min', :aggregate_failures do
    segurar!
    allow(revalida).to receive(:call) do
      fala!('mais uma coisa', tipo: :incoming)
      { passa: false, motivo: 'resolvido', decisao: 'resolvido' }
    end
    inicio = Time.current

    [0, 2, 4, 6, 8, 10].each do |minuto|
      travel_to(inicio + minuto.minutes) do
        described_class.perform_now
        roda_releituras!
      end
    end
    expect(conversation.reload.assignee_id).to be_nil

    travel_to(inicio + 12.minutes) { described_class.perform_now }
    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(revalida).to have_received(:call).at_least(5).times
  end

  # MÉDIO 4: a mesma regra de funil da avaliação do card (Crm::Ai::Config.pipeline_ai_enabled?).
  it 'funil com a IA desligada: entrega como hoje, sem enfileirar', :aggregate_failures do
    card.pipeline.update!(metadata: (card.pipeline.metadata || {}).merge('ai' => { 'enabled' => false }))
    segurar!

    described_class.perform_now

    expect(releituras).to be_empty
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  # 3ª revisão do Codex (ALTO 1): o prazo total vale enquanto a espera é a mesma. Uma confirmação ("passa") seguida de
  # mensagem nova antes da rodada seguinte, várias vezes, não o zera: a conversa sai na primeira rodada depois dele.
  it 'confirmação seguida de mensagem nova, várias vezes: entrega na rodada depois dos 10 min', :aggregate_failures do
    segurar!
    allow(revalida).to receive(:call).and_return({ passa: true, motivo: 'segue aberto', decisao: 'problema_em_aberto' })
    inicio = Time.current

    [0, 2, 4, 6, 8, 10].each do |minuto|
      travel_to(inicio + minuto.minutes) do
        described_class.perform_now
        roda_releituras!
        fala!('e mais isto', tipo: :incoming)
      end
    end
    expect(conversation.reload.assignee_id).to be_nil

    travel_to(inicio + 12.minutes) { described_class.perform_now }
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'a nova tentativa de entrega sem ninguém disponível não zera o prazo total', :aggregate_failures do
    segurar!
    described_class.perform_now
    prazo = marca['revalidacao_comecou_em']
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})

    Crm::Entrega.new(conversation: conversation.reload, motivo: Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA, origem: 'message',
                     pedido: { razao: 'cliente pediu a cotação e o robô falhou' }).call

    expect(prazo).to be_present
    expect(marca['revalidacao_comecou_em']).to eq(prazo)
  end

  # 3ª revisão do Codex (ALTO 2): o funil pode ter a IA desligada com o job na fila ou durante a chamada.
  it 'funil desligado depois de enfileirar: o job não chama a IA e a rodada seguinte entrega', :aggregate_failures do
    segurar!
    described_class.perform_now
    card.pipeline.update!(metadata: (card.pipeline.metadata || {}).merge('ai' => { 'enabled' => false }))

    roda_releituras!
    described_class.perform_now

    expect(revalida).not_to have_received(:call)
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'funil desligado durante a chamada: o "resolvido" não é aplicado e a rodada seguinte entrega', :aggregate_failures do
    segurar!
    described_class.perform_now
    allow(revalida).to receive(:call) do
      card.pipeline.update!(metadata: (card.pipeline.metadata || {}).merge('ai' => { 'enabled' => false }))
      { passa: false, motivo: 'resolvido', decisao: 'resolvido' }
    end

    roda_releituras!
    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(true)

    described_class.perform_now
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  # 4ª revisão do Codex (ALTO 1): só a entrega confirmada (a marca sai) ou o pedido retirado encerram o prazo total. A
  # pessoa sai antes da entrega: a tentativa não entrega, o prazo segue, e vencido a conversa sai na rodada seguinte com
  # alguém online, sem reler, com o log do vencimento uma vez.
  it 'entrega que falha no meio do prazo não o zera: com mensagens chegando, sai na rodada depois dos 10 min', :aggregate_failures do
    allow(Rails.logger).to receive(:info).and_call_original
    allow(revalida).to receive(:call).and_return({ passa: true, motivo: 'segue aberto', decisao: 'problema_em_aberto' })
    segurar!
    inicio = Time.current

    [0, 2, 4, 6].each do |minuto|
      travel_to(inicio + minuto.minutes) do
        fala!('e mais isto', tipo: :incoming) if minuto.positive?
        described_class.perform_now
        roda_releituras!
      end
    end
    prazo = marca['revalidacao_comecou_em']

    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    travel_to(inicio + 8.minutes) { described_class.perform_now }
    expect(conversation.reload.assignee_id).to be_nil
    expect(marca['revalidacao_comecou_em']).to eq(prazo)

    travel_to(inicio + 10.minutes) do
      fala!('ainda estou aqui', tipo: :incoming)
      described_class.perform_now
    end
    expect(releituras).to be_empty
    expect(marca['revalidacao_comecou_em']).to eq(prazo)

    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    travel_to(inicio + 12.minutes) do
      fala!('alô?', tipo: :incoming)
      described_class.perform_now
    end
    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(releituras).to be_empty
    expect(revalida).to have_received(:call).exactly(4).times
    expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=revalidacao_vencida')).once
  end

  # O caso da Issue (conversa 327): o pedido da meia-noite, ninguém online, o cliente resolve às 3h, alguém entra às 9h.
  # O prazo só conta com alguém para receber: antes das 9h nada é relido; às 9h a releitura lê tudo até ali.
  def madrugada!(resolucao:)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    meia_noite = Time.current.beginning_of_day + 1.day
    travel_to(meia_noite) { segurar! }
    rodadas_da_madrugada!(meia_noite, resolucao)
    nada_relido_nem_prazo!
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    meia_noite
  end

  # Rodadas da fila da meia-noite às 8h, com a mensagem do cliente às 3h.
  def rodadas_da_madrugada!(meia_noite, resolucao)
    [0, 10, 60, 120, 180, 240, 360, 480].each do |minuto|
      travel_to(meia_noite + minuto.minutes) do
        fala!(resolucao, tipo: :incoming) if minuto == 180
        described_class.perform_now
      end
    end
  end

  def nada_relido_nem_prazo!
    expect(releituras).to be_empty
    expect(Crm::Ai::RevalidaPassagem).not_to have_received(:new)
    expect(marca).not_to have_key('revalidacao_comecou_em')
  end

  it 'madrugada: o cliente resolve às 3h e, às 9h, a releitura retira o pedido sem entregar', :aggregate_failures do
    allow(revalida).to receive(:call).and_return({ passa: false, motivo: 'cliente resolveu', decisao: 'resolvido' })
    meia_noite = madrugada!(resolucao: 'já resolvi, obrigado')

    travel_to(meia_noite + 9.hours) do
      described_class.perform_now
      expect(conversation.reload.assignee_id).to be_nil
      roda_releituras!
    end
    travel_to(meia_noite + 9.hours + 2.minutes) { described_class.perform_now }

    expect(revalida).to have_received(:call).once
    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(false)
    expect(conversation.assignee_id).to be_nil
  end

  it 'madrugada sem resolução: às 9h relê tudo até ali e entrega na rodada seguinte', :aggregate_failures do
    allow(revalida).to receive(:call).and_return({ passa: true, motivo: 'segue aberto', decisao: 'problema_em_aberto' })
    meia_noite = madrugada!(resolucao: 'alguém pode me ajudar?')
    ultima = conversation.messages.where(message_type: :incoming).maximum(:id)

    travel_to(meia_noite + 9.hours) do
      described_class.perform_now
      roda_releituras!
    end
    expect(conversation.reload.assignee_id).to be_nil
    expect(marca['revalidado_ate']).to eq(ultima)

    travel_to(meia_noite + 9.hours + 2.minutes) { described_class.perform_now }
    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(revalida).to have_received(:call).once
  end

  def leva_o_card_para_outro_funil!(com_ia:)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: card.stage.metadata)
    pipeline.update!(metadata: (pipeline.metadata || {}).merge('ai' => { 'enabled' => com_ia }))
    Crm::Card.find(card.id).update!(pipeline: pipeline, stage: stage)
  end

  # 4ª revisão do Codex (ALTO 2): o card muda de funil durante a chamada; a resposta é do funil antigo.
  it 'card levado a um funil sem IA durante a chamada: o "resolvido" não é aplicado e a conversa é entregue', :aggregate_failures do
    segurar!
    described_class.perform_now
    allow(revalida).to receive(:call) do
      leva_o_card_para_outro_funil!(com_ia: false)
      { passa: false, motivo: 'resolvido', decisao: 'resolvido' }
    end

    roda_releituras!
    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(true)

    described_class.perform_now
    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(releituras).to be_empty
  end

  it 'card levado a outro funil com IA durante a chamada: a resposta é descartada e a rodada seguinte relê', :aggregate_failures do
    segurar!
    described_class.perform_now
    allow(revalida).to receive(:call) do
      leva_o_card_para_outro_funil!(com_ia: true)
      { passa: false, motivo: 'resolvido', decisao: 'resolvido' }
    end

    roda_releituras!
    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(true)

    described_class.perform_now
    expect(conversation.reload.assignee_id).to be_nil
    expect(releituras.size).to eq(1)
  end
end
