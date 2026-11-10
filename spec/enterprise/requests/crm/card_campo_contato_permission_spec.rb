require 'rails_helper'

# #2675 (parecer de Funções no #2876): o campo do tipo contato do card guarda o id de um contato, que o card devolve e o
# "em outro registro" lê. Como no vínculo do contato (#1849), só grava quem pode vincular esse contato
# (ContactPolicy#attach?): a base com "Ver contatos", ou o contato de uma conversa que a pessoa vê. O id de outra conta
# recebe a mesma recusa, sem dizer se existe.
RSpec.describe 'Campo do tipo contato do card e Ver contatos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, admin]) }
  let(:contact) { create(:contact, account: account, name: 'Marcos Prado') }
  let(:outro) { create(:contact, account: account, name: 'Outro da base') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: contact,
                              primary_conversation: conversation, inbox: inbox, owner: agent, title: 'Renovação',
                              external_id: 'erp-2675')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  before do
    create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_model: :card_attribute,
                                         attribute_display_type: :contato)
  end

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def patch_campo(valor)
    patch "#{base}/cards/#{card.id}", params: { card: { custom_attributes: { indicado_por: valor } } },
                                      headers: agent.create_new_auth_token, as: :json
  end

  describe 'sem Ver contatos' do
    before { give_role(%w[crm_view crm_manage_cards conversation_participating_manage]) }

    it 'não grava contato da base no campo, e o campo não muda', :aggregate_failures do
      patch_campo(outro.id)

      expect(response).to have_http_status(:unauthorized)
      expect(card.reload.custom_attributes).not_to have_key('indicado_por')
    end

    it 'não grava pelo upsert por external_id' do
      card
      post "#{base}/cards", params: { card: { pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id,
                                              title: 'Renovação', external_id: 'erp-2675', custom_attributes: { indicado_por: outro.id } } },
                            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(card.reload.custom_attributes).not_to have_key('indicado_por')
    end

    it 'o contato de outra conta recebe a mesma recusa que o contato sem permissão', :aggregate_failures do
      patch_campo(outro.id)
      sem_permissao = [response.status, response.parsed_body]
      patch_campo(create(:contact, account: create(:account)).id)

      expect([response.status, response.parsed_body]).to eq(sem_permissao)
      expect(card.reload.custom_attributes).not_to have_key('indicado_por')
    end

    it 'grava o contato de uma conversa que vê' do
      patch_campo(contact.id)

      expect(response).to have_http_status(:ok)
      expect(card.reload.custom_attributes['indicado_por']).to eq(contact.id)
    end
  end

  it 'com Ver contatos grava qualquer contato da base' do
    give_role(%w[crm_view crm_manage_cards conversation_participating_manage contact_view])
    patch_campo(outro.id)

    expect(response).to have_http_status(:ok)
    expect(card.reload.custom_attributes['indicado_por']).to eq(outro.id)
  end

  it 'o campo que não mudou não é conferido de novo' do
    card.update!(custom_attributes: { 'indicado_por' => outro.id })
    give_role(%w[crm_view crm_manage_cards conversation_participating_manage])
    patch "#{base}/cards/#{card.id}", params: { card: { custom_attributes: { indicado_por: outro.id.to_s, nota: 'x' } } },
                                      headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end
end
