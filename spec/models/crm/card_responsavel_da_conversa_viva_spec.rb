require 'rails_helper'

# QUEM O QUADRO DIZ QUE ESTÁ ATENDENDO (issue #555).
#
# Desde a #553 a escalada atribui a conversa VIVA. O card continuava lendo a PRIMÁRIA para decidir
# o nome que aparece no Kanban: mostrava quem atendeu o cliente semanas atrás, ou o bot, enquanto
# o atendimento estava com outra pessoa. O cliente não ficava sem ninguém — quem mentia era o
# quadro, e o filtro por responsável perdia justamente os cards escalados.
RSpec.describe Crm::Card do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:quem_atende) { create(:user, account: account) }
  let(:quem_atendeu_antes) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [quem_atende, quem_atendeu_antes]) }
  let(:conversa_antiga) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:conversa_viva) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  def card_com_as_duas
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversa_antiga, title: 'Lead', metadata: {}
    )
    [conversa_antiga, conversa_viva].each_with_index do |conversa, posicao|
      card.card_conversations.create!(account: account, conversation: conversa, is_primary: posicao.zero?)
    end
    card
  end

  describe '#responsible_descriptor' do
    it 'mostra quem está com a conversa viva, e não quem ficou na antiga' do
      # Arrange — o estado que a escalada deixa: antiga resolvida com o dono de antes, viva atribuída
      conversa_antiga.update!(status: :resolved, assignee: quem_atendeu_antes)
      conversa_viva.update!(assignee: quem_atende)

      # Act
      descriptor = card_com_as_duas.responsible_descriptor

      # Assert
      expect(descriptor).to include(type: 'agent', id: quem_atende.id)
    end

    it 'sem ninguém na conversa viva, não credita o dono da conversa antiga' do
      # Arrange
      conversa_antiga.update!(status: :resolved, assignee: quem_atendeu_antes)

      # Act
      descriptor = card_com_as_duas.responsible_descriptor

      # Assert — pode ser bot ou ninguém; o que não pode é dizer que o antigo está atendendo
      expect(descriptor&.dig(:id)).not_to eq(quem_atendeu_antes.id)
    end

    it 'conversa resolvida não vira a atual só por ser a mais recente' do
      # Arrange — o cliente resolveu o assunto novo e voltou ao antigo, que segue aberto. Sem o
      # filtro de estado, a resolvida (mais recente) ganharia e o card creditaria quem a atendeu.
      conversa_antiga.update!(assignee: quem_atende, last_activity_at: 2.hours.ago)
      conversa_viva.update!(status: :resolved, assignee: quem_atendeu_antes, last_activity_at: 1.minute.ago)
      carregado = account.crm_cards.preload(linked_conversations: :assignee).find(card_com_as_duas.id)

      # Act / Assert
      expect(carregado.responsible_descriptor).to include(id: quem_atende.id)
    end

    it 'com as conversas pré-carregadas, não faz consulta nenhuma' do
      # Arrange — o quadro pré-carrega `linked_conversations` de todos os cards de uma vez. Uma
      # consulta por card aqui devolveria o N+1 num lugar que desenha centenas deles.
      card_com_as_duas
      conversa_viva.update!(assignee: quem_atende)
      carregado = account.crm_cards.preload(linked_conversations: :assignee).first
      consultas = []
      assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, dados|
        consultas << dados[:sql] unless dados[:name].to_s.in?(%w[SCHEMA TRANSACTION])
      end

      # Act
      descriptor = carregado.responsible_descriptor

      # Assert
      ActiveSupport::Notifications.unsubscribe(assinatura)
      expect(descriptor).to include(id: quem_atende.id)
      expect(consultas).to be_empty, "esperava zero consultas, saíram #{consultas.size}: #{consultas.first(3)}"
    end
  end
end
