# #2246 no Híbrido: a sessão auxiliar é um aparelho vinculado do mesmo número e recebe do motor (GOWS) o
# `message.ack` de "outro aparelho meu leu uma mensagem recebida": ack 3 (lido) ou 4 (ouvido) com fromMe=false, um por
# id físico lido. Antes, o WebhookEventJob só procurava o id entre as mensagens que SAÍRAM pelo WhatsApp API e
# descartava esse ack. Agora ele vira o "visto" do agente (ConversaCanal::VistaNoCelular).
#
# A mensagem do cliente chega pela Cloud, com o wamid no source_id; o id físico está dentro dele
# (WhatsappHybrid::Wamid.message_id). Na chegada, o id físico é guardado no Redis apontando para a mensagem
# (`indexar`, chamado por WhatsappHybrid::RecebidaIndexada), como o WebTransport faz com as que saem. O índice é gravado
# no fim do Webhooks::WhatsappEventsJob e o ack pode chegar antes (conversa aberta no celular): aí `aplicar` responde
# :sem_indice e o WebhookEventJob tenta de novo, algumas vezes, com espera.
#
# Quando conta como "pessoa leu no celular" (o resto é descartado, errando para "não lida"):
# - flag `leitura_no_celular` da conta;
# - fromMe=false e ack 3 ou 4;
# - o aparelho que leu é o 0, o celular principal (`_data.Sender` "<número>:<aparelho>@..."; sem ":", é o 0). Leitura
#   feita por aparelho vinculado (WhatsApp Web, a Cloud na coexistência, outra automação) não conta;
# - a mensagem lida não estava coberta por uma leitura que o próprio sistema mandou (ConversaCanal::LeituraDoSistema):
#   a lida pela Cloud de um robô respondendo volta ao motor como leitura de outro aparelho.
# Hipóteses ainda não medidas em produção (passo 0 da Issue): que o aparelho 0 é o celular, que a lida pela Cloud não
# chega como aparelho 0 e que o id físico do wamid da recebida é o do ack. Cada decisão vira uma linha de log (sem
# telefone e sem id de mensagem), para o piloto medir. Com a confirmação de leitura desligada no celular, o GOWS manda
# `read-self` e descarta: nada chega, e a bolinha fica como antes.
#
# Grupo: o id do WAHA é `false_<chat>_<ID>` e, em grupo, `false_<grupo>_<ID>_<participante>`; o id físico é sempre o
# terceiro pedaço (o JID não tem "_").
class WhatsappHybrid::LeituraNoCelular
  ACKS_DE_LEITURA = [3, 4].freeze
  CELULAR_PRINCIPAL = '0'.freeze
  INDICE_TTL = 7.days.to_i
  POSICAO_DO_ID_FISICO = 2

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

  # -> o motivo da decisão: :andou quando o "visto" andou; :sem_indice quando a mensagem lida ainda não foi achada.
  def aplicar(payload)
    return :flag_desligada unless ConversaCanal::VistaNoCelular.enabled?(@connection.account)

    motivo = decidir(payload)
    registrar_no_log(motivo, payload)
    motivo
  end

  private

  def decidir(payload)
    return :nao_e_leitura unless payload['from_me'] == false && ACKS_DE_LEITURA.include?(payload['ack'].to_i)
    return :aparelho_vinculado unless payload['aparelho'] == CELULAR_PRINCIPAL

    mensagem = recebida(payload['id'].to_s.split('_')[POSICAO_DO_ID_FISICO])
    return :sem_indice if mensagem.nil?
    return :marca_do_sistema if ConversaCanal::LeituraDoSistema.cobre?(mensagem)

    ConversaCanal::VistaNoCelular.marcar!(mensagem) ? :andou : :ja_visto
  end

  def recebida(physical_id)
    return if physical_id.blank?

    message_id = ::Redis::Alfred.get(self.class.chave(@connection.inbox_id, physical_id))
    Message.incoming.find_by(id: message_id, inbox_id: @connection.inbox_id) if message_id.present?
  end

  def registrar_no_log(motivo, payload)
    Rails.logger.info(
      "[whatsapp_hybrid][leitura_no_celular] connection=#{@connection.id} motivo=#{motivo} ack=#{payload['ack']} " \
      "aparelho=#{payload['aparelho'] || '-'} tentativa=#{payload['tentativa'].to_i}"
    )
  end
end
