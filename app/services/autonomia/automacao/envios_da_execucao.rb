# G42 (#2721, exemplo 1, passo 12): o que a própria execução mandou ao cliente, para o "resumir" contar tudo o que foi
# tentado: o modelo no WhatsApp, o e-mail (que abre uma conversa própria, G34) e as respostas que vieram nessas conversas.
#
# - Os envios saem dos registros da execução (`mensagem_id`, a mesma ponte do histórico): só mensagem ao cliente, de
#   saída e não privada. A nota do "avisar" fica de fora.
# - Só entra conversa que quem ligou a automação vê (Acesso.alcanca?, a política da conversa, só leitura). Outras
#   conversas do contato, que a execução não tocou, não entram.
# - O envio que o canal recusou (status failed) vai marcado `not_delivered`.
# - A conversa do alvo já vai na leitura do passo. Das outras, a mesma leitura de mensagens do passo (o Estado).
class Autonomia::Automacao::EnviosDaExecucao
  LEITURAS_DE_MENSAGEM = %w[mensagens_recentes mensagens_com_respostas ultima_mensagem].freeze
  MAX_CARACTERES = ::Autonomia::Decisores::Estado::MAX_CARACTERES

  def initialize(execucao:, conversa:, leituras:)
    @execucao = execucao
    @conversa = conversa
    @leituras = Array(leituras) & LEITURAS_DE_MENSAGEM
  end

  # O que vai à IA junto da leitura do passo. Vazio quando a execução ainda não mandou nada.
  def dados
    @dados ||= { automation_sends: envios.map { |mensagem| envio(mensagem) },
                 other_conversations: outras.map { |conversa| leitura(conversa) }.compact_blank }.compact_blank
  end

  private

  def mensagens
    @mensagens ||= begin
      ids = @execucao.registros.where(resultado: 'ok').pluck(:dados).filter_map { |dados| dados.to_h['mensagem_id'] }
      Message.where(id: ids, account_id: @execucao.account_id, private: false, message_type: :outgoing)
             .includes(conversation: :inbox).reorder(:id).to_a
    end
  end

  def visiveis
    @visiveis ||= mensagens.map(&:conversation).uniq.select { |conversa| conversa == @conversa || ve?(conversa) }
  end

  def ve?(conversa)
    quem = @execucao.automacao.ligada_por
    quem.present? && ::Autonomia::Automacao::Acesso.alcanca?(quem, conversa)
  end

  def envios = mensagens.select { |mensagem| visiveis.include?(mensagem.conversation) }

  def outras = visiveis - [@conversa]

  def envio(mensagem)
    conversa = mensagem.conversation
    { channel: conversa.inbox&.channel_type.to_s.demodulize.underscore.presence,
      subject: conversa.additional_attributes.to_h['mail_subject'].to_s.strip.first(300).presence,
      text: mensagem.content.to_s.strip.first(MAX_CARACTERES), not_delivered: (true if mensagem.failed?) }.compact
  end

  def leitura(conversa)
    leituras = @leituras.presence || ::Autonomia::Decisor::LEITURAS_PADRAO
    ::Autonomia::Decisores::Estado.new(conversation: conversa, leituras: leituras).conversa
  end
end
