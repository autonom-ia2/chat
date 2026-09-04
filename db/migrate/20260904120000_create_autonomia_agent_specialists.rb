class CreateAutonomiaAgentSpecialists < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_agent_specialists do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.bigint :autonomia_agent_id, null: false
      t.string :name, null: false
      # Vira o nome da função exposta ao modelo (consultar_<slug>), por isso o formato é restrito.
      t.string :slug, null: false
      # O QUE o modelo lê para decidir delegar. É o único critério de escolha dele — precisa ser
      # específico ("cotação de seguro de automóvel"), nunca genérico ("ajuda com seguros").
      t.text :description, null: false
      # Instrução do especialista em DOIS blocos: `instruction` é do sistema (travado, versionado por
      # nós — campos do ramo, tabelas de código, regras de execução) e `custom_instruction` é do dono
      # da conta (tom, particularidades da corretora). O runner concatena nessa ordem, e a UI só
      # expõe o segundo (#321).
      t.text :instruction, null: false
      t.text :custom_instruction
      t.boolean :enabled, null: false, default: true
      # Slugs de `autonomia_agent_tools` reservados a este especialista. As ferramentas continuam
      # sendo do agente; o especialista declara quais usa — e o principal deixa de vê-las. É isso que
      # mantém o contexto do principal limpo: ele não precisa conhecer a ferramenta de cotação, só
      # saber que existe um especialista de Auto.
      t.jsonb :tool_slugs, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :autonomia_agent_specialists, :autonomia_agent_id
    add_index :autonomia_agent_specialists, [:autonomia_agent_id, :slug], unique: true,
                                                                          name: 'idx_autonomia_agent_specialists_agent_slug'
    add_index :autonomia_agent_specialists, [:account_id, :enabled],
              name: 'idx_autonomia_agent_specialists_account_enabled'
  end
end
