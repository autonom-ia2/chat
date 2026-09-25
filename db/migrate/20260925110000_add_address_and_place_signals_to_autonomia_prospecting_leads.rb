# ENDEREÇO ESTRUTURADO E SINAIS DO LUGAR NO LEAD DA PROSPECÇÃO (chat#677, E1 frente C).
#
# Bairro, cidade, estado e país passam a vir de `addressComponents` do Google, não da leitura do texto do endereço, e o
# lead guarda o link do lugar no Maps. Fotos e horário viram colunas para o filtro avançado e a pontuação lerem o que o
# provider devolveu, sem reabrir o `raw_payload`. Só acrescenta colunas anuláveis, sem backfill.
#
# Os booleanos são de três estados de propósito: `nil` é "não sabemos". Lead antigo não passou por aqui, e o Google
# nem sempre diz se o lugar está aberto; um `false` padrão o faria passar no filtro "sem fotos" ou "fechado agora".
class AddAddressAndPlaceSignalsToAutonomiaProspectingLeads < ActiveRecord::Migration[7.2]
  def change
    # rubocop:disable Rails/ThreeStateBooleanColumn
    change_table :autonomia_prospecting_leads, bulk: true do |t|
      t.string :neighborhood
      t.string :google_maps_uri
      t.boolean :has_photos
      t.integer :photo_count
      t.boolean :open_now
      t.boolean :has_opening_hours
    end
    # rubocop:enable Rails/ThreeStateBooleanColumn
  end
end
