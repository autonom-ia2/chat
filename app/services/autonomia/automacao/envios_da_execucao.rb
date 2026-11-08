# G42 (#2721, exemplo 1, passo 12): o que a própria execução mandou ao cliente, para o "resumir" contar tudo o que foi
# tentado: o modelo no WhatsApp, o e-mail (que abre uma conversa própria, G34) e as respostas que vieram nessas conversas.
#
# - Os envios saem dos registros da execução (`mensagem_id`, a mesma ponte do histórico): só mensagem ao cliente, de
#   saída e não privada. A nota do "avisar" fica de fora. O texto do envio é o da receita e vai com a marca
#   `not_delivered` quando o canal recusou (status failed).
# - Só entra conversa que quem ligou a automação vê (Acesso.alcanca?, a política da conversa, só leitura). Outras
#   conversas do contato, que a execução não tocou, não entram.
# - As respostas das outras conversas (`other_conversations`) vão a quem lê o resumo, então também passam por ele
#   (parecer de Funções no #2763): no aviso (`publico`), a conversa só entra se todo destinatário a vê; na nota, que
#   todos da conversa do alvo leem, só entra conversa da mesma caixa do alvo. As que ficam de fora vão em `fora` (os ids).
# - A conversa do alvo já vai na leitura do passo. Das outras, a mesma leitura de mensagens do passo (o Estado).
class Autonomia::Automacao::EnviosDaExecucao
  LEITURAS_DE_MENSAGEM = %w[mensagens_recentes mensagens_com_respostas ultima_mensagem].freeze
  MAX_CARACTERES = ::Autonomia::Decisores::Estado::MAX_CARACTERES

  # `publico`: as pessoas que vão receber o resumo (o aviso). nil é a nota.
  def initialize(execucao:, conversa:, leituras:, publico: nil)
    @execucao = execucao
    @conversa = conversa
    @leituras = Array(leituras) & LEITURAS_DE_MENSAGEM
    @publico = publico
  end

  # O que vai à IA junto da leitura do passo. Vazio quando a execução ainda não mandou nada.
  def dados
    @dados ||= { automation_sends: envios.map { |mensagem| envio(mensagem) },
                 other_conversations: lidas.map { |conversa| leitura(conversa) }.compact_blank }.compact_blank
  end

  # Leu resposta de outra conversa: o resumo não serve para reuso (ia.<passo>) fora deste público.
  def outras_lidas? = dados.key?(:other_conversations)

  # Os ids das outras conversas que o público do resumo não vê, para o histórico.
  def fora = (outras - lidas).map(&:display_id)

  private

  def mensagens
    @mensagens ||= begin
      ids = @execucao.registros.where(resultado: 'ok').pluck(:dados).filter_map { |dados| dados.to_h['mensagem_id'] }
      Message.where(id: ids, account_id: @execucao.account_id, private: false, message_type: :outgoing)
             .includes(conversation: :inbox).reorder(:id).to_a
    end
  end

  def visiveis
    @visiveis ||= mensagens.map(&:conversation).uniq.select { |conversa| conversa == @conversa || ve?(quem_ligou, conversa) }
  end

  def quem_ligou = @execucao.automacao.ligada_por

  def ve?(pessoa, conversa) = pessoa.present? && ::Autonomia::Automacao::Acesso.alcanca?(pessoa, conversa)

  def envios = mensagens.select { |mensagem| visiveis.include?(mensagem.conversation) }

  def outras = visiveis - [@conversa]

  def lidas
    @lidas ||= outras.select do |conversa|
      @publico.nil? ? conversa.inbox_id == @conversa.inbox_id : @publico.all? { |pessoa| ve?(pessoa, conversa) }
    end
  end

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
