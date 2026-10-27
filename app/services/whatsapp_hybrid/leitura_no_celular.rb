# #2246 no Híbrido: a sessão auxiliar é um aparelho vinculado do mesmo número e recebe do motor (GOWS) o
# `message.ack` de "outro aparelho meu leu uma mensagem recebida": ack 3 (lido) ou 4 (ouvido) com fromMe=false, um por
# id físico lido. Antes, o WebhookEventJob só procurava o id entre as mensagens que SAÍRAM pelo WhatsApp API e
# descartava esse ack. Agora ele vira o "visto" do agente (ConversaCanal::VistaNoCelular).
#
# A mensagem do cliente chega pela Cloud, com o wamid no source_id; o id físico está dentro dele
# (WhatsappHybrid::Wamid.message_id). Na chegada, o id físico é guardado no Redis apontando para a mensagem
# (`indexar`, chamado por WhatsappHybrid::RecebidaIndexada), como o WebTransport faz com as que saem.
#
# Quando conta como "pessoa leu no celular" (o resto é descartado em silêncio, errando para "não lida"):
# - flag `leitura_no_celular` da conta;
# - fromMe=false e ack 3 ou 4;
# - o aparelho que leu é o 0, o celular principal (`_data.Sender` "<número>:<aparelho>@..."; sem ":", é o 0). Leitura
#   feita por aparelho vinculado (WhatsApp Web, a Cloud na coexistência, outra automação) não conta;
# - nenhuma leitura mandada pelo próprio sistema nesta conversa há pouco (ConversaCanal::LeituraDoSistema): a lida
#   pela Cloud de um robô respondendo volta ao motor como leitura de outro aparelho.
# Hipóteses ainda não medidas em produção (passo 0 da Issue): que o aparelho 0 é o celular e que a lida pela Cloud
# não chega como aparelho 0. Com a confirmação de leitura desligada no celular, o GOWS manda `read-self` e descarta:
# nada chega, e a bolinha fica como antes.
class WhatsappHybrid::LeituraNoCelular
  ACKS_DE_LEITURA = [3, 4].freeze
  CELULAR_PRINCIPAL = '0'.freeze
  INDICE_TTL = 7.days.to_i

  def self.chave(inbox_id, physical_id)
    "whatsapp_hybrid:in:#{inbox_id}:#{physical_id}"
  end

  # Só o número do aparelho, para nada do número de telefone ir para a fila.
  def self.aparelho(sender)
    usuario = sender.to_s.split('@').first.to_s
    return if usuario.blank?

    usuario.include?(':') ? usuario.split(':').last : CELULAR_PRINCIPAL
  end

  def self.indexar(message)
    return unless indexavel?(message)

    physical_id = WhatsappHybrid::Wamid.message_id(message.source_id.to_s)
    ::Redis::Alfred.setex(chave(message.inbox_id, physical_id), message.id, INDICE_TTL) if physical_id.present?
  end

  def self.indexavel?(message)
    message&.persisted? && message.incoming? && ConversaCanal::VistaNoCelular.enabled?(message.account) &&
      WhatsappHybrid::Config.hybrid_inbox?(message.inbox_id)
  end

  def initialize(connection)
    @connection = connection
  end

  # -> true quando o "visto" andou.
  def aplicar(payload)
    return false unless leitura_do_celular?(payload)

    mensagem = recebida(payload['id'].to_s.split('_').last)
    return false if mensagem.nil? || ConversaCanal::LeituraDoSistema.recente?(mensagem.conversation)

    ConversaCanal::VistaNoCelular.marcar!(mensagem)
  end

  private

  def leitura_do_celular?(payload)
    ConversaCanal::VistaNoCelular.enabled?(@connection.account) && payload['from_me'] == false &&
      ACKS_DE_LEITURA.include?(payload['ack'].to_i) && payload['aparelho'] == CELULAR_PRINCIPAL
  end

  def recebida(physical_id)
    return if physical_id.blank?

    message_id = ::Redis::Alfred.get(self.class.chave(@connection.inbox_id, physical_id))
    Message.incoming.find_by(id: message_id, inbox_id: @connection.inbox_id) if message_id.present?
  end
end
