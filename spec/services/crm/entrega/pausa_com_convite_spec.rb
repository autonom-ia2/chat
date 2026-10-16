require 'rails_helper'

# Pausar um agente de IA não apaga o convite aberto (#1140, correção 6): a IA do CRM convidou a Ana numa conversa da
# Lia (o agente que atende a caixa) e alguém pausa a Lia. O robô sai (AgentInbox#release_bot_conversations! →
# bot_handoff!(keep_bot: false)), e o convite continua: a conversa espera a Ana até ela pegar ou o convite vencer.
RSpec.describe 'Pausar agente de IA com convite aberto' do # rubocop:disable RSpec/DescribeClass
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:lia) { agente_da_porta }
  let!(:card) { create_card(pipeline: comercial) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    [ana, bruno].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    comercial.stages.first.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite',
                                                                 'invite_ttl_seconds' => 3600 } })
    online(ana)
    Crm::Entrega.new(conversation: conversation, motivo: 'ia_crm', origem: 'message').call
  end

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  def marca
    Crm::Entrega::Marca.dados(conversation.reload)
  end

  def ciclo
    card.reload.metadata.dig('ai', 'handoff')
  end

  # Pega: pausar a Lia trocava o convite da Ana por "segurando" ou por um convite novo a outra pessoa, sem a Ana saber.
  it 'a Lia pausada sai da conversa e o convite da Ana continua', :aggregate_failures do
    expect(marca).to include('modo' => Crm::Entrega::Marca::CONVITE)
    convite = marca
    online(bruno)

    lia.update!(status: :paused)

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: nil, status: 'open')
    expect(marca).to eq(convite)
    expect(ciclo).to include('invited_agent_id' => ana.id)
    expect(ciclo['canceled_at']).to be_nil
    expect(conversation.conversation_participants.pluck(:user_id)).to eq([ana.id])
  end

  # Pega: o convite vencido prender a conversa sem robô; vencido, a passagem segue a regra de sempre (convida de novo).
  it 'convite já vencido: a regra convida de novo quem está online', :aggregate_failures do
    online(bruno)

    travel 7.hours do
      lia.update!(status: :paused)
    end

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: nil)
    expect(ciclo).to include('invited_agent_id' => bruno.id)
  end
end
