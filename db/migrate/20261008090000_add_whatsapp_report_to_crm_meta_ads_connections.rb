# Anúncios da Meta F4b (#1100): resumo diário e alerta no WhatsApp. Aditiva, com default e sem backfill; vem
# desligado. O número de destino fica numa coluna própria porque `encrypts` não cifra chave de jsonb.
class AddWhatsappReportToCrmMetaAdsConnections < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_meta_ads_connections, :whatsapp_report, :jsonb, default: {}, null: false
    add_column :crm_meta_ads_connections, :whatsapp_report_phone, :string
  end
end
