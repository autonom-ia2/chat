# Link por cliente do agendamento (#1190, F1-C): um convite é a capacidade de acesso de um contato a uma página
# nova (e, depois de agendado, à reunião). O código curto vai no link `/b/<code>`; o resto nunca sai para o público.
#
# Tabela nova (sem coluna em tabela do Chatwoot): as FKs para contatos, conversas e usuários nascem com a tabela
# vazia, então validar é instantâneo. Toda FK tem índice próprio. Perfil ganha o texto e a validade do convite.
class CreateCrmBookingInvites < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_booking_invites do |t|
      invite_references(t)
      invite_columns(t)
      t.timestamps
    end
    add_invite_indexes

    change_table :crm_agent_booking_profiles, bulk: true do |t|
      t.text :invite_text
      t.integer :invite_ttl_days, default: 7, null: false
    end
  end

  private

  def invite_references(table)
    table.bigint :account_id, null: false
    table.references :booking_profile, null: false, foreign_key: { to_table: :crm_agent_booking_profiles, on_delete: :cascade }
    table.references :booking_link, foreign_key: { to_table: :crm_agent_booking_links, on_delete: :nullify }
    table.references :contact, null: false, foreign_key: { on_delete: :cascade }
    table.references :card, foreign_key: { to_table: :crm_cards, on_delete: :nullify }
    table.references :conversation, foreign_key: { on_delete: :nullify }
    table.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
    table.references :meeting, foreign_key: { to_table: :crm_meetings, on_delete: :nullify }
  end

  def invite_columns(table)
    table.string :code, null: false
    table.string :channel, null: false, default: 'copy'
    table.datetime :expires_at, null: false
    %i[sent_at first_opened_at last_opened_at].each { |name| table.datetime name }
    table.integer :open_count, null: false, default: 0
    %i[scheduled_at canceled_at].each { |name| table.datetime name }
    table.jsonb :metadata, null: false, default: {}
  end

  def add_invite_indexes
    add_index :crm_booking_invites, :code, unique: true
    { contact: :contact_id, creator: :created_by_id, created: :created_at, card: :card_id, conversation: :conversation_id }.each do |name, column|
      add_index :crm_booking_invites, [:account_id, column], name: "idx_crm_booking_invites_account_#{name}"
    end
  end
end
