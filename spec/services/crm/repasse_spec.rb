require 'rails_helper'

# Decisão "a" (#1606): o assunto mudou com uma pessoa no nome. Nada troca sozinho; só ela vê a sugestão; "Passar" usa a
# Atribuição do funil novo e a passagem vem do listener (motivo 'assunto'); "Ficar" não repete para o mesmo assunto.
RSpec.describe Crm::Repasse do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm Fora') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Seguros') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia Agentes') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:seguros) { create_crm_pipeline(account: account, user: admin, name: 'Seguros') }
  let(:agentes) { create_crm_pipeline(account: account, user: admin, name: 'Agentes de IA') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open, assignee: ana).reload }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Access::AccountFlag).to receive(:any?).and_return(true)
    [ana, bia].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online', bia.id.to_s => 'online' })
    acesso(ana, seguros)
    acesso(bia, agentes)
    card_em(seguros, focused_at: 1.minute.ago)
  end

  after { Current.reset }

  def acesso(user, funil)
    row = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    row.agent_pipelines.create!(account: account, pipeline: funil.first)
  end

  def card_em((pipeline, stage), focused_at: Time.current)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: pipeline.name,
                                     primary_conversation: conversation, inbox: inbox)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: focused_at)
    card
  end

  def regra!(funil)
    funil.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
  end

  def marca
    conversation.reload.additional_attributes[described_class::CHAVE]
  end

  describe '.sugerir!' do
    it 'grava a sugestão quando o assunto vai para um funil de que a pessoa não cuida, e só ela vê' do
      card = card_em(agentes)
      allow(Crm::Subjects::Notifier).to receive(:notify)

      expect(described_class.sugerir!(conversation.reload)).to be(true)

      expect(marca).to include('card_id' => card.id, 'pipeline_id' => agentes.first.id, 'user_id' => ana.id)
      expect(conversation.reload.assignee).to eq(ana)
      expect(described_class.para(conversation, ana)).to eq(card_id: card.id, pipeline_name: 'Agentes de IA')
      expect(described_class.para(conversation, bia)).to be_nil
      expect(Crm::Subjects::Notifier).to have_received(:notify).once
    end

    it 'não sugere quando a pessoa cuida do funil novo' do
      acesso_extra = Crm::InboxAgentAccess.find_by(user: ana)
      acesso_extra.agent_pipelines.create!(account: account, pipeline: agentes.first)
      card_em(agentes)

      expect(described_class.sugerir!(conversation.reload)).to be(false)
      expect(marca).to be_nil
    end

    it 'não sugere sem equipe no funil novo (ninguém além dela para receber)' do
      InboxMember.where(inbox: inbox, user: bia).destroy_all
      card_em(agentes)

      described_class.sugerir!(conversation.reload)

      expect(marca).to be_nil
    end

    it 'não sugere sem pessoa no nome' do
      conversation.update!(assignee: nil)
      card_em(agentes)

      described_class.sugerir!(conversation.reload)

      expect(marca).to be_nil
    end

    it 'apaga a sugestão quando o assunto volta para um funil da pessoa, e não avisa de novo sem mudança' do
      card_em(agentes)
      described_class.sugerir!(conversation.reload)
      expect(described_class.sugerir!(conversation.reload)).to be(false)

      card_em(seguros)
      described_class.sugerir!(conversation.reload)

      expect(marca).to be_nil
    end

    it 'sugestão de outra pessoa não vale quando a conversa muda de mãos' do
      card_em(agentes)
      described_class.sugerir!(conversation.reload)
      conversation.update!(assignee: bia)

      expect(described_class.para(conversation.reload, ana)).to be_nil
      expect(described_class.para(conversation, bia)).to be_nil
    end
  end

  describe 'a troca de assunto agenda a avaliação' do
    it 'só com pessoa no nome' do
      clear_enqueued_jobs
      card_em(agentes)
      expect(Crm::RepasseJob).to have_been_enqueued.with(conversation.id)

      clear_enqueued_jobs
      conversation.update!(assignee: nil)
      card_em(seguros, focused_at: 1.second.from_now)
      expect(Crm::RepasseJob).not_to have_been_enqueued
    end

    it 'também quando o card do assunto muda de funil' do
      card = card_em(seguros, focused_at: Time.current)
      clear_enqueued_jobs

      card.update!(pipeline: agentes.first, stage: agentes.last)

      expect(Crm::RepasseJob).to have_been_enqueued.with(conversation.id)
    end
  end

  describe '.passar!' do
    let!(:card) { card_em(agentes) }

    before { described_class.sugerir!(conversation.reload) }

    it 'a pessoa sai, a Atribuição do funil novo escolhe, e o listener grava a passagem com motivo assunto' do
      regra!(agentes)
      Current.user = ana

      described_class.passar!(conversation.reload, ana, card.id)

      expect(conversation.reload.assignee).to eq(bia)
      expect(marca).to be_nil
      passagens = Crm::Passagem.where(conversation_id: conversation.id).order(:id)
      expect(passagens.where(motivo: 'assunto').count).to eq(1)
      expect(passagens.last)
        .to have_attributes(de_type: 'User', de_id: ana.id, para_type: 'User', para_id: bia.id, motivo: 'assunto',
                            card_id: card.id)
    end

    it 'só quem está com a conversa' do
      expect { described_class.passar!(conversation.reload, bia, card.id) }
        .to raise_error(described_class::Error) { |erro| expect(erro.code).to eq('repasse_nao_e_seu') }
      expect(conversation.reload.assignee).to eq(ana)
    end

    it 'recusa quando o assunto mudou de novo (card que não é mais o da sugestão)' do
      card_em(seguros)

      expect { described_class.passar!(conversation.reload, ana, card.id) }
        .to raise_error(described_class::Error) { |erro| expect(erro.code).to eq('repasse_mudou') }
      expect(conversation.reload.assignee).to eq(ana)
    end
  end

  describe '.manter!' do
    let!(:card) { card_em(agentes) }

    before { described_class.sugerir!(conversation.reload) }

    it 'apaga a sugestão, a conversa fica com a pessoa e o mesmo assunto não volta a sugerir' do
      described_class.manter!(conversation.reload, ana, card.id)

      expect(marca).to be_nil
      expect(conversation.reload.assignee).to eq(ana)
      expect(described_class.sugerir!(conversation.reload)).to be(false)
      expect(marca).to be_nil
    end

    it 'outro assunto novo de que ela não cuida sugere de novo' do
      described_class.manter!(conversation.reload, ana, card.id)
      outro = card_em(agentes)

      described_class.sugerir!(conversation.reload)

      expect(marca).to include('card_id' => outro.id)
    end
  end
end
