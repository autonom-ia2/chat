require 'rails_helper'

# Decisão "a" (#1606) com a Atribuição do funil novo apontando um agente de IA (#1620): o agente conta como "tem quem
# receba". A sugestão aparece mesmo sem pessoa na equipe, o aviso de "ninguém online" não aparece, e "Passar" leva a
# conversa ao agente pelo motor de entrega.
RSpec.describe Crm::Repasse do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Comercial') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    allow(Crm::Access::AccountFlag).to receive(:any?).and_return(true)
    create(:inbox_member, inbox: inbox, user: ana)
    acesso = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: ana, all_pipelines: false, triage: false)
    acesso.agent_pipelines.create!(account: account, pipeline: comercial)
    # Ninguém online: só a regra com o agente de IA pode fazer o aviso de "ninguém online" sumir.
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    # Pessoa no nome sem robô gravado: o estado que a atribuição de uma pessoa deixa.
    conversation.update!(assignee: ana, ai_assignee: nil)
    create_card(pipeline: comercial, focused_at: 1.minute.ago)
  end

  after { Current.reset }

  def regra_aponta!(agente)
    suporte.stages.first.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct',
                                                               'pool_type' => 'ai_agent', 'pool_id' => agente.id } })
  end

  def regra_aponta_a_area!
    regra_aponta!(area)
  end

  it 'regra apontando a porta (sem robô gravado na conversa): também conta como quem recebe' do
    regra_aponta!(agente_da_porta)
    create_card(pipeline: suporte)

    described_class.sugerir!(conversation.reload)

    expect(described_class.para(conversation.reload, ana)).to include(equipe_online: true)
  end

  it 'regra com agente de IA: sugere, e o aviso de "ninguém online" não aparece' do
    regra_aponta_a_area!
    card = create_card(pipeline: suporte)

    described_class.sugerir!(conversation.reload)

    expect(described_class.para(conversation.reload, ana)).to eq(card_id: card.id, pipeline_name: 'Suporte', equipe_online: true)
  end

  it 'sem a regra apontando o agente (e sem ninguém mais no funil), não há para quem passar: nada é sugerido' do
    create_card(pipeline: suporte)

    described_class.sugerir!(conversation.reload)

    expect(described_class.para(conversation.reload, ana)).to be_nil
  end

  it 'Passar com a regra apontando o agente: a conversa vai para ele, sem pessoa no nome' do
    regra_aponta_a_area!
    card = create_card(pipeline: suporte)
    described_class.sugerir!(conversation.reload)
    Current.user = ana

    described_class.passar!(conversation.reload, ana, card.id)

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
    expect(conversation.additional_attributes[described_class::CHAVE]).to be_nil
    # O registro: a Ana sai pelo assunto (para o robô que espera), e o motor passa à área depois do commit.
    passagens = Crm::Passagem.where(conversation_id: conversation.id).order(:id).to_a
    saida = passagens.find { |passagem| passagem.de_type == 'User' && passagem.de_id == ana.id }
    expect(saida).to have_attributes(motivo: 'assunto', devolvida_em: be_present)
    expect(passagens.last).to have_attributes(para_type: 'Autonomia::Agents::Agent', para_id: area.id, devolvida_em: nil)
    expect(Crm::Passagem.where(conversation_id: conversation.id, para_type: 'User', para_id: ana.id).abertas).to be_empty
  end
end
