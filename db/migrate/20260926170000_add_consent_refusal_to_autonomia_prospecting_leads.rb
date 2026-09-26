# RECUSA DO LEAD INDEPENDENTE DO STATUS (chat#713, decisão de 26/09).
#
# O status do lead era o único lugar da recusa: descartar um lead em no_consent trocava o status e apagava o pedido da
# pessoa para não ser contatada. A recusa passa a ter coluna própria, que nenhuma troca de status toca:
# - consent_refused_at: quando o lead recusou. Nulo quer dizer "não recusou".
# - consent_refused_by_id: quem marcou na tela da Prospecção. Apagar o usuário só esquece o autor, a recusa fica.
#
# Os leads que hoje estão em no_consent entram já recusados (updated_at é a melhor data que existe). O índice parcial
# serve à leitura dos leads recusados da conta (ConsentVeto), que roda a cada segmento e a cada contato novo.
class AddConsentRefusalToAutonomiaProspectingLeads < ActiveRecord::Migration[7.2]
  NO_CONSENT = 3

  def change
    add_column :autonomia_prospecting_leads, :consent_refused_at, :datetime
    add_reference :autonomia_prospecting_leads, :consent_refused_by, index: false,
                                                                     foreign_key: { to_table: :users, on_delete: :nullify }
    add_index :autonomia_prospecting_leads, :account_id, name: 'idx_autonomia_prospecting_leads_consent_refused',
                                                         where: 'consent_refused_at IS NOT NULL'

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE autonomia_prospecting_leads SET consent_refused_at = updated_at
          WHERE status = #{NO_CONSENT} AND consent_refused_at IS NULL
        SQL
      end
    end
  end
end
