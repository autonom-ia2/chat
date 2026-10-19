# Ponto de partida do "lido" sincronizado de uma caixa de e-mail (#1870). Nada recebido antes dele é marcado, em nenhum
# sentido: ligar a flag não muda em massa o lido das conversas aqui nem o \Seen no servidor do cliente.
# - Nasce na primeira sincronização da importação ou na primeira abertura de conversa da caixa, o que vier antes.
# - Caixa que ficou mais que RECOMECO sem sincronizar (flag desligada, importação parada): recomeça do zero, com o ponto
#   de partida agora. Nada é apagado aqui (o recomeço roda dentro do lock da importação): as linhas gravadas antes do
#   ponto novo deixam de valer (ConversaCanal::EmailLidoDoServidor as trata como primeira vez) e saem na limpeza diária.
#   E-mail importado depois do ponto novo que já chega lido conta como lido, inclusive o acumulado da parada: são
#   e-mails novos que a pessoa leu (decisão do Rodrigo, 19/10: "confirmo o lido").
class ConversaCanal::EmailLidoCaixa < ApplicationRecord
  self.table_name = 'conversa_canal_email_lido_caixas'

  RECOMECO = 1.hour

  belongs_to :account
  belongs_to :inbox

  def self.da_caixa(inbox)
    find_by(inbox_id: inbox.id) ||
      create_or_find_by!(inbox_id: inbox.id) do |caixa|
        caixa.account_id = inbox.account_id
        caixa.ponto_de_partida = Time.current
      end
  end

  # Chamado a cada sincronização da importação (dentro do lock da caixa).
  def self.sincronizando!(inbox)
    caixa = da_caixa(inbox)
    agora = Time.current
    atributos = { sincronizado_em: agora, updated_at: agora }
    atributos[:ponto_de_partida] = agora if caixa.sincronizado_em.present? && caixa.sincronizado_em < RECOMECO.ago
    caixa.update_columns(atributos) # rubocop:disable Rails/SkipsModelValidations
    caixa
  end
end
