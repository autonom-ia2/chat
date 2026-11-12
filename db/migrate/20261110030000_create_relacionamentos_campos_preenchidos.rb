# "Trazer minha lista", fatia 3 (#2896): o que cada linha de uma lista preencheu, para o "Desfazer" devolver só isso.
# A lista nunca troca um valor que já existia: só preenche o que estava vazio. Então não há "valor de antes" para
# guardar; basta saber qual campo a linha preencheu e reconhecer, na hora de desfazer, se o valor de hoje ainda é o que
# ela pôs. Uma linha desta tabela por campo preenchido (Relacionamentos::CampoPreenchido).
#
# Colunas:
# - campo: nome, telefone, email, cidade, empresa, cliente, telefone_da_empresa ou "informacao:<chave do atributo>";
# - valor_posto_hash: o resumo com segredo (HMAC-SHA256, chave derivada do secret_key_base) do valor que a lista pôs.
#   Nunca o valor, nem um hash puro: telefone tem pouca entropia e um hash puro se descobre por tentativa;
# - tipo_anterior: só no campo "cliente", o contact_type que a pessoa tinha antes de a lista marcá-la (0 visitante,
#   1 lead). É um número do enum, não é dado pessoal. O Desfazer devolve a pessoa a esse tipo, e não sempre a lead.
#   Fica vazio nos outros campos, que voltam sempre a vazio. smallint: o enum tem três valores;
# - devolvido_em: quando o Desfazer devolveu o campo. Vazio enquanto não devolveu (ou quando o valor já era outro).
#
# Chaves:
# - campaign_import_row: em cascata. A anotação é da linha da importação e some com ela; não há rotina que apague
#   linhas de importação fora da exclusão da própria importação, então a cascata não leva nada de surpresa;
# - contact: sem chave, como campaign_import_rows.contact_id. A pessoa pode ser apagada ou mesclada depois, e a
#   anotação fica (o Desfazer pula quem não existe mais). Ela não guarda nada da pessoa além do id;
# - account: sem chave. A coluna serve para separar as contas e para a exclusão da conta apagar as linhas dela em lote
#   (Autonomia::ExclusaoDaConta), antes de as importações saírem.
#
# Índices:
# - único (campaign_import_row_id, campo): uma anotação por campo de cada linha; também atende a cascata da chave;
# - contact_id: achar o que uma lista preencheu numa pessoa;
# - account_id: o DELETE em lote da exclusão da conta.
#
# Travas: só CREATE TABLE. A chave para campaign_import_rows pega SHARE ROW EXCLUSIVE nela pelo instante do comando
# (segura a escrita de uma importação que esteja gravando, sem varrer linha: a tabela nova nasce vazia). Roda com o
# lock_timeout curto do strong_migrations (5 s, 3 tentativas): se uma transação longa segura a tabela, a migration
# desiste em vez de enfileirar as escritas atrás dela. Nada que já existe muda de dado nem de estrutura, e o código
# anterior não conhece a tabela.
class CreateRelacionamentosCamposPreenchidos < ActiveRecord::Migration[7.2]
  def up
    create_table :relacionamentos_campos_preenchidos do |t|
      t.bigint :account_id, null: false
      t.references :campaign_import_row, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :contact_id
      t.string :campo, null: false
      t.string :valor_posto_hash, null: false
      t.integer :tipo_anterior, limit: 2
      t.datetime :devolvido_em
      t.timestamps
      t.index :account_id
      t.index %i[campaign_import_row_id campo], unique: true, name: 'idx_rel_campos_preenchidos_linha_campo'
      t.index :contact_id
    end
  end

  def down
    drop_table :relacionamentos_campos_preenchidos
  end
end
