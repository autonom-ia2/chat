# Retenção do "lido" do e-mail sincronizado (#1870): apaga, em lotes, as linhas sem mudança há mais que
# ConversaCanal::EmailLido::RETENCAO: e-mails fora das janelas de leitura e de escrita, inclusive as linhas que ficaram
# para trás num recomeço da caixa (que já deixaram de valer na hora). Fora do lock da importação. Agendado no
# config/schedule.yml (fila low, uma vez por dia).
class ConversaCanal::LimparEmailLidosJob < ApplicationJob
  queue_as :low

  LOTE = 1000

  def perform
    ConversaCanal::EmailLido.where(sincronizado_em: ...ConversaCanal::EmailLido::RETENCAO.ago).in_batches(of: LOTE).delete_all
  end
end
