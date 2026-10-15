# Pausa do WhatsApp API (#1487): a sessão para no motor sem desvincular o aparelho. Enquanto houver data aqui, o
# roteador nunca escolhe o WhatsApp API e nada religa a sessão sozinho; só o "Retomar" da aba limpa o campo.
class AddPausedAtToWhatsappHybridConnections < ActiveRecord::Migration[7.2]
  def change
    add_column :whatsapp_hybrid_connections, :paused_at, :datetime
  end
end
