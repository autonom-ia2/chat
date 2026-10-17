require 'rails_helper'

# A fila do motor de entrega no HandoffDrainJob (#1454): rodada limitada, as menos tentadas primeiro (sem estado fora do
# banco), uma rodada por vez e teto de tempo para os dois passos.
RSpec.describe Crm::Ai::HandoffDrainJob do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }

  before do
    stub_const("#{described_class}::CONVERSAS_POR_RODADA", 2)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    online
  end

  # A trava da rodada é de sessão: sobrevive ao rollback do exemplo. Um exemplo que dubla o unlock (ou falha no meio)
  # a deixava presa na conexão do ActiveRecord, e o spec seguinte no mesmo processo a via (booker_spec:300). Solta
  # todas pelo execute, que nenhum exemplo dubla (a trava de sessão acumula: pegar duas vezes pede soltar duas).
  after { ActiveRecord::Base.connection.execute('SELECT pg_advisory_unlock_all()') }

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  # Três conversas seguras pelo motor (ninguém online na passagem).
  def tres_seguras
    Array.new(3) do
      conversation = create(:conversation, account: account, inbox: inbox, status: :open).reload
      conversation.update!(ai_assignee: bot, assignee: nil)
      conversation.bot_handoff!
      conversation.reload
    end
  end

  def tentado_em(conversation)
    Crm::Entrega::Marca.dados(conversation.reload)&.dig('tentado_em')
  end

  # Pega: fila que dependia de um cursor no Redis parava quando ele caía, e uma rodada cheia deixava sempre as mesmas
  # de fora.
  it 'trata no máximo uma rodada, as nunca tentadas primeiro, e a seguinte pega a que ficou de fora', :aggregate_failures do
    primeira, segunda, terceira = tres_seguras

    described_class.perform_now
    expect([primeira, segunda].map { |c| tentado_em(c) }).to all(be_present)
    expect(tentado_em(terceira)).to be_nil

    online(ana)
    described_class.perform_now
    expect(terceira.reload.assignee_id).to eq(ana.id)
  end

  it 'lê a presença de cada conta uma vez só por rodada, também quando ela falha', :aggregate_failures do
    tres_seguras
    expect(OnlineStatusTracker).to receive(:get_available_users).with(account.id).once.and_raise(Redis::CannotConnectError)

    expect { described_class.perform_now }.not_to raise_error
  end

  # Outra conexão de verdade, fora do pool: no spec o pool devolve a mesma conexão (e a trava de sessão é reentrante).
  def outra_conexao
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    conexao = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username],
                         password: config[:password].presence)
    yield conexao
  ensure
    conexao&.close
  end

  def trava_livre?(conexao)
    livre = conexao.exec("SELECT pg_try_advisory_lock(#{described_class::TRAVA_DA_RODADA})").getvalue(0, 0) == 't'
    conexao.exec("SELECT pg_advisory_unlock(#{described_class::TRAVA_DA_RODADA})") if livre
    livre
  end

  def card_com_espera_antiga
    admin = create(:user, account: account, role: :administrator)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    conversa = create(:conversation, account: account, inbox: inbox, status: :open).reload
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: conversa.contact, title: 'Antigo',
                              primary_conversation: conversa,
                              metadata: { 'ai' => { 'handoff_hold' => { 'held_at' => 1.hour.ago.iso8601,
                                                                        'handoff' => { 'intent' => 'transferir' } } } })
    conversa
  end

  # Pega a fila cheia de conversas comendo a rodada inteira: os cards antigos têm orçamento próprio.
  it 'com o orçamento das conversas estourado, os cards antigos ainda rodam', :aggregate_failures do
    primeira, = tres_seguras
    conversa_do_card = card_com_espera_antiga
    online(ana)
    stub_const("#{described_class}::ORCAMENTO_CONVERSAS", -1)

    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { described_class.perform_now }

    expect(primeira.reload.assignee_id).to be_nil
    expect(conversa_do_card.reload.assignee_id).to eq(ana.id)
  end

  it 'a ordem dos passos alterna por rodada do cron de 2 minutos (conversas primeiro numa, cards na seguinte)', :aggregate_failures do
    job = described_class.new
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') do
      travel_to(Time.zone.local(2026, 10, 13, 10, 4)) { expect(job.send(:passos).first).to eq(:drain_held_conversations) }
      travel_to(Time.zone.local(2026, 10, 13, 10, 6)) { expect(job.send(:passos).first).to eq(:drain_held_cards) }
    end
  end

  it 'pega primeiro as nunca tentadas e depois as tentadas há mais tempo', :aggregate_failures do
    recente, antiga, nunca = tres_seguras
    {
      recente => '2026-10-13T10:00:00.000000Z', antiga => '2026-10-13T08:00:00.000000Z'
    }.each do |conversa, quando|
      atributos = conversa.additional_attributes
      atributos['crm_entrega'] = atributos['crm_entrega'].merge('tentado_em' => quando)
      conversa.update_columns(additional_attributes: atributos) # rubocop:disable Rails/SkipsModelValidations
    end
    online(ana)

    described_class.perform_now

    expect([nunca, antiga].map { |c| c.reload.assignee_id }).to eq([ana.id, ana.id])
    expect(recente.reload.assignee_id).to be_nil
  end

  # Pega uma linha travada por outra transação: a conversa é pulada (e carimbada), a fila segue.
  it 'conversa com a trava ocupada é pulada, logada e carimbada; as outras seguem', :aggregate_failures do
    primeira, segunda = tres_seguras
    online(ana)
    allow(Crm::Entrega).to receive(:new).and_call_original
    allow(Crm::Entrega).to receive(:new).with(hash_including(conversation: primeira)).and_raise(ActiveRecord::LockWaitTimeout)
    allow(Rails.logger).to receive(:warn).and_call_original

    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with(/conversa=#{primeira.id} pulada: trava ocupada/)
    expect(tentado_em(primeira)).to be_present
    expect(segunda.reload.assignee_id).to eq(ana.id)
  end

  it 'falha ao carimbar a tentativa só é logada' do
    tres_seguras
    allow(Conversation).to receive(:where).and_call_original
    allow(Conversation).to receive(:where).with(hash_including(:id)).and_raise(ActiveRecord::StatementInvalid)
    allow(Rails.logger).to receive(:error).and_call_original

    expect { described_class.perform_now }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/tentativa não carimbada/).at_least(:once)
  end

  # Pega rodadas sobrepostas (cron atrasado, dois workers): a segunda sai sem fazer nada.
  it 'com outra rodada em andamento (trava em outra conexão), sai sem tratar nada' do
    primeira, = tres_seguras
    online(ana)
    outra_conexao do |outra|
      outra.exec("SELECT pg_advisory_lock(#{described_class::TRAVA_DA_RODADA})")
      described_class.perform_now
      expect(primeira.reload.assignee_id).to be_nil
    ensure
      outra.exec("SELECT pg_advisory_unlock(#{described_class::TRAVA_DA_RODADA})")
    end
  end

  it 'solta a trava ao terminar: outra conexão consegue pegá-la' do
    tres_seguras
    described_class.perform_now

    outra_conexao { |outra| expect(trava_livre?(outra)).to be(true) }
  end

  it 'sem confirmar a soltura da trava, derruba a conexão (a trava de sessão vai junto) e loga', :aggregate_failures do
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:select_value).and_call_original
    allow(connection).to receive(:select_value).with(/pg_advisory_unlock/).and_return(false)
    allow(connection).to receive(:disconnect!)
    allow(Rails.logger).to receive(:error).and_call_original

    described_class.perform_now

    expect(connection).to have_received(:disconnect!)
    expect(Rails.logger).to have_received(:error).with(/trava não confirmada/)
  end
end
