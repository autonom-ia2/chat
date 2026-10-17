require 'rails_helper'

RSpec.describe Crm::Memoria::Compromissos do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana') }
  let(:bruno) { create(:user, account: account, name: 'Bruno') }
  let(:robo_de_fora) { create(:user, account: account, name: 'Ana Maciel') }

  before do
    ligar_memoria!(account)
    conversation.reload
    [ana, bruno].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
  end

  def passar(de:, para:, motivo: 'passar_para') # rubocop:disable Naming/MethodParameterName
    Crm::Passagens.registrar!(conversation: conversation, de: de, para: para, pedida_por: nil, motivo: motivo)
  end

  def processar(passagem)
    Crm::Memoria::PassagemJob.perform_now(passagem.id)
  end

  def responder(autor = ana, **attrs)
    message = mensagem!(conversation, :outgoing, sender: autor, content: 'Oi, sou a Ana', **attrs)
    Crm::Memoria::OrigemJob.perform_now(message.id)
    message
  end

  def tarefas
    described_class.da_conversa(conversation)
  end

  describe 'nascimento (W2)' do
    it 'a passagem da IA para uma pessoa cria UMA tarefa, com a Ana como dona, sem prazo para vencer' do
      processar(passar(de: porta, para: ana))
      conversation.update!(assignee: ana)

      tarefa = tarefas.sole
      expect(tarefa).to have_attributes(follow_up_type: 'task', status: 'pending', recipient_mode: 'users', recipient_user_ids: [ana.id],
                                        contact_id: contact.id, conversation_id: conversation.id)
      expect(tarefa.metadata['memoria']).to include('tipo' => 'retomar_atendimento', 'origem' => 'passagem')
    end

    it 'pessoa -> pessoa e o convite não criam tarefa' do
      processar(passar(de: ana, para: bruno))
      processar(passar(de: porta, para: bruno, motivo: Crm::Passagens::CONVITE))

      expect(tarefas).to be_empty
    end

    it 'A2: três rodadas da fila com a conversa segurada e depois a entrega geram uma tarefa só, reaproveitada' do
      conversation.update!(additional_attributes: { 'crm_entrega' => { 'modo' => 'segurando', 'motivo' => 'robo_pediu' } })
      3.times { Crm::Memoria::ConversaJob.perform_now(conversation.id, 'segurada') }
      processar(passar(de: porta, para: ana))

      tarefa = tarefas.sole
      expect(tarefa.metadata['memoria']).to include('origem' => 'segurada', 'passagem_id' => Crm::Passagem.last.id)
    end

    it 'sem ninguém com a conversa e ninguém que cuide, a dona são os administradores da caixa; sem eles, os da conta' do
      admin_da_caixa = create(:user, account: account, role: :administrator)
      allow(Crm::Entrega::QuemCuida).to receive(:new).and_return(instance_double(Crm::Entrega::QuemCuida, pessoas: []))
      described_class.abrir_retomada!(conversation: conversation, origem: 'segurada')
      expect(tarefas.sole.recipient_user_ids).to match_array(AccountUser.where(account: account).administrator.pluck(:user_id))

      create(:inbox_member, user: admin_da_caixa, inbox: inbox)
      tarefas.delete_all
      described_class.abrir_retomada!(conversation: conversation, origem: 'segurada')
      expect(tarefas.sole.recipient_user_ids).to eq([admin_da_caixa.id])
      expect(tarefas.sole.metadata.dig('memoria', 'sem_dono_agora')).to be(true)
    end

    it 'o DueProcessor não vence nem avisa a tarefa, e ela não vira o próximo retorno do card (D3: sem prazo)' do
      card = create_card(pipeline: suporte)
      processar(passar(de: porta, para: ana))
      travel_to(2.days.from_now) { Crm::FollowUps::DueProcessor.new.perform }

      expect(tarefas.sole).to have_attributes(status: 'pending', card_id: card.id)
      Crm::FollowUps::CardNextDueUpdater.update(card)
      expect(card.reload.next_follow_up_at).to be_nil
    end

    it 'a resposta que chegou antes de a tarefa nascer (job atrasado), depois do início da espera, fecha a tarefa' do
      conversation.update!(additional_attributes: { 'crm_entrega' => { 'modo' => 'segurando', 'desde' => 1.minute.ago.iso8601 } })
      resposta = mensagem!(conversation, :outgoing, sender: ana, content: 'Oi!')
      described_class.abrir_retomada!(conversation: conversation, origem: 'segurada')
      expect(tarefas.sole.status).to eq('pending')

      Crm::Memoria::OrigemJob.perform_now(resposta.id)
      expect(tarefas.sole.status).to eq('done')
    end
  end

  describe 'cumprimento (W3)' do
    before do
      processar(passar(de: porta, para: ana))
      conversation.update!(assignee: ana)
    end

    it 'nota privada, follow-up automático, robô declarado e encaminhada NÃO fecham; a resposta pública da Ana fecha' do
      Crm::MemoriaConfig.create!(account: account, usuarios_robo_ids: [robo_de_fora.id])
      responder(ana, private: true)
      responder(ana, content_attributes: { crm_follow_up_id: 1 })
      responder(robo_de_fora)
      responder(ana, content_attributes: { forwarded: true })
      expect(tarefas.sole.status).to eq('pending')

      resposta = responder(ana)
      expect(tarefas.sole).to have_attributes(status: 'done')
      expect(tarefas.sole.metadata.dig('memoria', 'cumprida_por_message_id')).to eq(resposta.id)
    end

    it 'a resposta que falhou no envio não fecha; a que fechou e depois falhou reabre a tarefa' do
      responder(ana, status: :failed)
      expect(tarefas.sole.status).to eq('pending')

      resposta = responder(ana)
      expect(tarefas.sole.status).to eq('done')
      resposta.update!(status: :failed)
      Crm::Memoria::OrigemJob.perform_now(resposta.id)
      expect(tarefas.sole.status).to eq('pending')
    end

    it 'a resposta pelo celular (eco) fecha' do
      eco = create(:message, :bot_message, conversation: conversation, account: account, inbox: inbox, content: 'Te ligo',
                                           content_attributes: { external_echo: true })
      Crm::Memoria::OrigemJob.perform_now(eco.id)

      expect(tarefas.sole.status).to eq('done')
    end
  end

  describe 'dono acompanha a conversa' do
    it 'a troca de responsável leva a tarefa; sem ninguém, volta para quem cuida, marcada "sem dono agora"' do
      processar(passar(de: porta, para: ana))
      conversation.update!(assignee: bruno)
      Crm::Memoria::ConversaJob.perform_now(conversation.id, 'dono')
      expect(tarefas.sole).to have_attributes(recipient_user_ids: [bruno.id], assignee_id: bruno.id)

      conversation.update!(assignee: nil)
      Crm::Memoria::ConversaJob.perform_now(conversation.id, 'dono')
      expect(tarefas.sole.recipient_user_ids).to include(ana.id, bruno.id)
      expect(tarefas.sole.metadata.dig('memoria', 'sem_dono_agora')).to be(true)
    end

    it 'conversa resolvida com a tarefa aberta fica marcada "confirmar", sem fechar' do
      processar(passar(de: porta, para: ana))
      Crm::Memoria::ConversaJob.perform_now(conversation.id, 'resolvida')

      expect(tarefas.sole).to have_attributes(status: 'pending')
      expect(tarefas.sole.metadata.dig('memoria', 'confirmar')).to be(true)
    end
  end

  it 'sem a flag nada nasce' do
    account.disable_features!(Crm::Memoria::FLAG)
    processar(passar(de: porta, para: ana))

    expect(tarefas).to be_empty
  end
end
