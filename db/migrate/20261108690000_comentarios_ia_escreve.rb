# #2458 — IA cuida dos comentários: a IA escreve as respostas (PR 2 do #2436, flag meta_ads_comentarios_ia_escreve).
#
# O que o dono diz no passo 2, além do "para quem" de hoje:
# - `temas`: os temas que recebem o privado, cada um nas palavras da tela (os chips somam). O `para_quem` continua sendo a
#   frase que a tela mostra com eles, e é ela que o Classificador lê: o motor de hoje não muda. O cuidado que já existe
#   começa sem tema marcado e com o `para_quem` dele no campo: a frase antiga não é um chip, e copiá-la para `temas`
#   deixaria um tema que a tela não mostra nem desmarca.
# - `assunto_proibido`: sobre o que a IA não fala; o comentário sobre isso fica com o dono, com o motivo.
# - `tom`: o pedido de tom, numa frase, para todas as respostas escritas pela IA.
#
# Reversível: o down tira as três colunas; o `para_quem` não é tocado, então nada se perde.
class ComentariosIaEscreve < ActiveRecord::Migration[7.2]
  def up
    add_column :crm_meta_ads_comment_cares, :temas, :jsonb, null: false, default: []
    add_column :crm_meta_ads_comment_cares, :assunto_proibido, :string
    add_column :crm_meta_ads_comment_cares, :tom, :string
  end

  def down
    remove_column :crm_meta_ads_comment_cares, :tom
    remove_column :crm_meta_ads_comment_cares, :assunto_proibido
    remove_column :crm_meta_ads_comment_cares, :temas
  end
end
