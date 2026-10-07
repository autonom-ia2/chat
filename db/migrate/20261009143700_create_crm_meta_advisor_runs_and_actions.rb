# Anúncios da Meta F5 (#1110): o consultor de tráfego. Aditiva, só tabelas do fork.
#
# `crm_meta_advisor_runs` guarda cada análise do dia (fatos, regras, decisão e o texto da IA), uma por conta ·
# dia · idioma · assinatura: a mesma decisão não gera run nem chamada à IA de novo. `crm_meta_advisor_actions`
# guarda cada ação recomendada e o que a pessoa fez com ela (mostrou, abriu, aceitou, dispensou), para a meta
# do PRD "aceita ≥ 4 de 5". A ação sobrevive ao run (`on_delete: :nullify`): a retenção dos runs é de 90 dias e
# a das ações, de 400.
class CreateCrmMetaAdvisorRunsAndActions < ActiveRecord::Migration[7.2]
  def change
    create_runs
    index_runs
    create_actions
    index_actions
  end

  private

  def create_runs
    create_table :crm_meta_advisor_runs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :ad_account_id, null: false
      t.date :local_date, null: false
      t.string :locale, limit: 10, null: false
      t.string :signature, limit: 64, null: false
      t.string :rules_version, limit: 16, null: false
      t.string :trigger, limit: 16, null: false
      # `texts` guarda o que a IA escreveu, com os marcadores `{{fato}}` ainda sem valor.
      t.jsonb :facts, :texts, null: false, default: {}
      t.jsonb :rules, :decision, null: false, default: []
      t.string :writer_status, limit: 16, null: false, default: 'pending'
      t.string :writer_reason, limit: 32
      t.integer :writer_attempts, limit: 2, null: false, default: 0
      t.datetime :writing_started_at, :retry_after
      t.string :model, limit: 64
      t.string :prompt_version, limit: 16
      t.timestamps
    end
  end

  def index_runs
    add_index :crm_meta_advisor_runs, [:account_id, :local_date, :locale, :signature],
              unique: true, name: 'idx_crm_meta_advisor_runs_unique'
    add_index :crm_meta_advisor_runs, [:account_id, :created_at], name: 'idx_crm_meta_advisor_runs_account_created'
  end

  # As referências a runs e a users ganham o índice padrão: o `on_delete: :nullify` (retenção dos runs, usuário
  # removido) precisa achar as ações sem varrer a tabela.
  def create_actions
    create_table :crm_meta_advisor_actions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :run, foreign_key: { to_table: :crm_meta_advisor_runs, on_delete: :nullify }
      t.references :last_run, foreign_key: { to_table: :crm_meta_advisor_runs, on_delete: :nullify }
      t.date :local_date, null: false
      t.string :kind, limit: 32, null: false
      t.string :subject_key, limit: 64, null: false
      t.string :variant, limit: 32
      t.string :ad_id
      t.integer :position, limit: 2, null: false
      t.jsonb :facts, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.datetime :shown_at, :opened_at, :resolved_at
      t.references :opened_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :opened_via, limit: 16
      t.references :resolved_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :resolved_via, limit: 16
      t.timestamps
    end
  end

  def index_actions
    add_index :crm_meta_advisor_actions, [:account_id, :local_date, :kind, :subject_key],
              unique: true, name: 'idx_crm_meta_advisor_actions_unique'
    add_index :crm_meta_advisor_actions, [:account_id, :status, :local_date], name: 'idx_crm_meta_advisor_actions_status'
  end
end
