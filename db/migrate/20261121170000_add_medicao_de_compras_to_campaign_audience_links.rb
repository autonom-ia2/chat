# #3098 (F2 do épico #3095): quem recebeu a campanha e comprou, e o grupo de controle.
#
# Na campanha com público (CampaignAudienceLink), duas escolhas novas da revisão:
# - `janela_de_compra_dias`: conta as compras feitas até N dias depois do envio (7, 15 ou 30). Padrão 7;
# - `grupo_de_controle_pct`: a parte do público sorteada para NÃO receber (5, 10 ou 20); 0 = sem grupo de controle.
# Default no banco: as campanhas antigas ficam com 7 dias e sem grupo, sem preenchimento.
#
# `campaign_control_contacts`: quem foi sorteado para ficar sem receber, uma linha por pessoa. O sorteio é fixo (hash
# do link + contato), então rodar o envio de novo sorteia as mesmas pessoas; a tabela guarda o resultado para a tela de
# resultado contar quem do grupo comprou e para o envio por e-mail, que sincroniza mais de uma vez. Não entra em
# "Puladas": quem está no grupo não faz parte de quem ia receber.
#
# Chaves em cascata: apagar o link (campanha), a pessoa ou a conta apaga as linhas. Tabela nova e vazia e colunas com
# default constante (sem reescrever a tabela no Postgres 11+): sem travas longas. Código antigo não lê nada disto.
class AddMedicaoDeComprasToCampaignAudienceLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :campaign_audience_links, :janela_de_compra_dias, :integer, null: false, default: 7
    add_column :campaign_audience_links, :grupo_de_controle_pct, :integer, null: false, default: 0

    create_table :campaign_control_contacts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :campaign_audience_link, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false
      t.index %i[campaign_audience_link_id contact_id], unique: true, name: 'idx_campaign_control_contacts_link_contact'
    end
  end
end
