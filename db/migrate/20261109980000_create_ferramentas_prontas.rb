# Vitrine de ferramentas prontas, F0 (#2858): a fundação, sem tela.
# - `autonomia_agent_tools.fonte_pronta`: a ferramenta pronta é uma linha da mesma tabela das ferramentas do agente,
#   que aponta para uma fonte do catálogo (`Autonomia::FerramentasProntas::Catalogo`) em vez de um link digitado. Assim
#   ela passa pelo mesmo turno e pela mesma consulta em segundo plano (#2749), que acham a ferramenta pelo id.
# - `autonomia_ferramentas_prontas_acessos`: a chave interna de cada conta em cada fonte, criada no "Incluir", com o
#   limite diário próprio (vazio = o do catálogo) e o corte individual.
# - `autonomia_ferramentas_prontas_usos`: o contador do dia por conta e por fonte, com o motivo de cada falha.
# Só aditiva: uma coluna que aceita vazio e duas tabelas novas. Nada é lido sem a flag `agente_ferramentas_prontas`. O
# down remove as três.
class CreateFerramentasProntas < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_agent_tools, :fonte_pronta, :string
    criar_acessos
    criar_usos
  end

  private

  def criar_acessos
    create_table :autonomia_ferramentas_prontas_acessos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :fonte, null: false
      t.string :chave, null: false
      t.integer :limite_diario
      t.datetime :cortada_em
      t.string :motivo_do_corte
      t.bigint :incluida_por_id
      t.timestamps
    end
    add_index :autonomia_ferramentas_prontas_acessos, %i[account_id fonte], unique: true, name: 'idx_prontas_acessos_conta_fonte'
    add_index :autonomia_ferramentas_prontas_acessos, :chave, unique: true, name: 'idx_prontas_acessos_chave'
  end

  def criar_usos
    create_table :autonomia_ferramentas_prontas_usos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :fonte, null: false
      t.date :dia, null: false
      %i[consultas do_cache pela_reserva nao_encontradas sem_resposta recusadas].each do |contador|
        t.integer contador, null: false, default: 0
      end
      t.jsonb :motivos, null: false, default: {}
      t.timestamps
    end
    add_index :autonomia_ferramentas_prontas_usos, %i[account_id fonte dia], unique: true, name: 'idx_prontas_usos_conta_fonte_dia'
  end
end
