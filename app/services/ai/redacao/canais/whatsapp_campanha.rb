# Texto livre de campanha no WhatsApp oficial (#1335, Modelos WhatsApp G): a mensagem escrita que vai para quem falou
# com a caixa nas últimas 24 horas. É o mesmo texto livre do `whatsapp_texto` (mesma conferência: chaves do catálogo e
# link só por campo), com o prompt de campanha no lugar do de avisos do agendamento (que fala em "1 dia antes" e numa
# linha de parar que a campanha não põe).
#
# Diferença de conferência, sobrescrita aqui (nunca um `if canal` no WhatsappTexto): campo no começo ou no fim vale. O
# texto livre não passa pela análise da Meta, e a bateria da #1335 mostrou que o link no fim ("Veja: {{link}}.") é o
# texto bom de campanha.
class Ai::Redacao::Canais::WhatsappCampanha < Ai::Redacao::Canais::WhatsappTexto
  def self.nome
    'whatsapp_campanha'
  end

  def self.problema_das_pontas(_texto)
    nil
  end
  private_class_method :problema_das_pontas
end
