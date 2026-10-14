# #1460/#1461/#1462 — crm_follow_ups (tabela do fork) ganha, só com colunas e índices novos:
# - card_id opcional: lembrete só no calendário, de um cliente sem negócio ou de uma empresa (company_id, criado pela
#   ficha do Relacionamento) (#1461). A trava pede ao menos um dono: card, contato, empresa ou quem criou.
# - series_id + occurrence_at: a vez da série (#1460). O índice único impede criar a mesma vez duas vezes.
# - recipient_mode, recipient_user_ids, recipient_team_id: quem recebe o aviso (#1462). 0 (legacy) é o comportamento
#   de hoje (quem vê o card + o responsável): as linhas antigas não mudam.
#
# Sem transação: os índices entram com CONCURRENTLY e a FK e a trava são validadas depois, sem travar escrita.
class AddSeriesAndRecipientsToCrmFollowUps < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TRAVA = 'crm_follow_ups_has_owner'.freeze
  INDICE_VEZ = 'idx_crm_followups_series_occurrence_uniq'.freeze

  def up
    # DROP NOT NULL pede trava exclusiva rápida: com uma transação longa na frente, desiste em 5 s em vez de enfileirar
    # leitura e escrita atrás dela (rodar de novo depois).
    execute "SET lock_timeout = '5s'"
    change_column_null :crm_follow_ups, :card_id, true
    execute 'RESET lock_timeout'
    add_column :crm_follow_ups, :series_id, :bigint unless column_exists?(:crm_follow_ups, :series_id)
    add_column :crm_follow_ups, :occurrence_at, :datetime unless column_exists?(:crm_follow_ups, :occurrence_at)
    add_column :crm_follow_ups, :recipient_mode, :integer, null: false, default: 0 unless column_exists?(:crm_follow_ups, :recipient_mode)
    add_recipient_columns
    add_keys
  end

  def down
    remove_check_constraint :crm_follow_ups, name: TRAVA, if_exists: true
    remove_foreign_key :crm_follow_ups, :crm_follow_up_series, column: :series_id, if_exists: true
    remove_foreign_key :crm_follow_ups, :teams, column: :recipient_team_id, if_exists: true
    remove_foreign_key :crm_follow_ups, :companies, if_exists: true
    remove_index :crm_follow_ups, :company_id, algorithm: :concurrently, if_exists: true
    remove_index :crm_follow_ups, name: INDICE_VEZ, algorithm: :concurrently, if_exists: true
    remove_index :crm_follow_ups, :recipient_team_id, algorithm: :concurrently, if_exists: true
    %i[series_id occurrence_at recipient_mode recipient_user_ids recipient_team_id company_id].each do |coluna|
      remove_column :crm_follow_ups, coluna, if_exists: true
    end
    # Voltar card_id a obrigatório só funciona sem lembrete sem card: a migration para aqui se houver algum.
    change_column_null :crm_follow_ups, :card_id, false
  end

  private

  def add_recipient_columns
    unless column_exists?(:crm_follow_ups, :recipient_user_ids)
      add_column :crm_follow_ups, :recipient_user_ids, :bigint, array: true, null: false, default: []
    end
    add_column :crm_follow_ups, :recipient_team_id, :bigint unless column_exists?(:crm_follow_ups, :recipient_team_id)
    add_column :crm_follow_ups, :company_id, :bigint unless column_exists?(:crm_follow_ups, :company_id)
  end

  def add_keys
    add_index :crm_follow_ups, [:series_id, :occurrence_at], unique: true, name: INDICE_VEZ,
                                                             where: 'series_id IS NOT NULL', algorithm: :concurrently, if_not_exists: true
    add_index :crm_follow_ups, :recipient_team_id, algorithm: :concurrently, if_not_exists: true
    add_index :crm_follow_ups, :company_id, algorithm: :concurrently, if_not_exists: true
    add_foreign_keys
    unless check_constraint_exists?(:crm_follow_ups, name: TRAVA)
      add_check_constraint :crm_follow_ups, 'card_id IS NOT NULL OR contact_id IS NOT NULL OR company_id IS NOT NULL OR created_by_id IS NOT NULL',
                           name: TRAVA, validate: false
    end
    validate_foreign_key :crm_follow_ups, :crm_follow_up_series, column: :series_id
    validate_foreign_key :crm_follow_ups, :teams, column: :recipient_team_id
    validate_foreign_key :crm_follow_ups, :companies
    validate_check_constraint :crm_follow_ups, name: TRAVA
  end

  # Rodar de novo depois de uma falha no meio não quebra com "já existe".
  def add_foreign_keys
    { crm_follow_up_series: [:series_id, :nullify], teams: [:recipient_team_id, :nullify], companies: [:company_id, :cascade] }
      .each do |tabela, (coluna, ao_apagar)|
        next if foreign_key_exists?(:crm_follow_ups, tabela, column: coluna)

        add_foreign_key :crm_follow_ups, tabela, column: coluna, on_delete: ao_apagar, validate: false
      end
  end
end
