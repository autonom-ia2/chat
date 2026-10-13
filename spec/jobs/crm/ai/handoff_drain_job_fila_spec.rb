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

  it 'com o teto de tempo estourado, para antes de tratar conversas e cards', :aggregate_failures do
    primeira, = tres_seguras
    online(ana)
    stub_const("#{described_class}::TEMPO_MAXIMO_DA_RODADA", -1)
    allow(Crm::Pipeline).to receive(:active).and_call_original

    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { described_class.perform_now }

    expect(primeira.reload.assignee_id).to be_nil
    expect(tentado_em(primeira)).to be_nil
  end

  # Pega rodadas sobrepostas (cron atrasado, dois workers): a segunda sai sem fazer nada.
  it 'com outra rodada em andamento (trava de sessão do Postgres em outra conexão), sai sem tratar nada' do
    primeira, = tres_seguras
    online(ana)
    # Uma conexão de verdade, fora do pool: no spec o pool devolve a mesma conexão (e a trava de sessão é reentrante).
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    outra = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username],
                       password: config[:password].presence)
    begin
      outra.exec("SELECT pg_advisory_lock(#{described_class::TRAVA_DA_RODADA})")

      described_class.perform_now

      expect(primeira.reload.assignee_id).to be_nil
    ensure
      outra.exec("SELECT pg_advisory_unlock(#{described_class::TRAVA_DA_RODADA})")
      outra.close
    end
  end

  it 'solta a trava ao terminar: a rodada seguinte roda' do
    primeira, = tres_seguras
    described_class.perform_now
    online(ana)

    described_class.perform_now

    expect(primeira.reload.assignee_id).to eq(ana.id)
  end
end
