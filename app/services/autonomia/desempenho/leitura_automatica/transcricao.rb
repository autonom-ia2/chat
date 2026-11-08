# A conversa em texto para o leitor do painel de desempenho (#2301). O formato é o mesmo da prova cega de 27/10
# (o gerador `slim.py`, fora do repositório): a precisão de ~94% foi medida nele, então mudar uma vírgula aqui é
# mudar o que foi medido.
#
#   === CONVERSA <número> | criada AAAA-MM-DDTHH:MM | status <n> | etiquetas <a,b> | msgs <n>
#   [MM-DDTHH:MM] CLIENTE: texto
#   [MM-DDTHH:MM] <RÓTULO DO AGENTE>: texto
#   [MM-DDTHH:MM] NOTA_INTERNA HUMANO<id>: texto
#     (MM-DDTHH:MM evento: texto, até 160 caracteres)
#
# - Horários em UTC, como na prova (a chave de leitura converte quando precisa).
# - Autor: CLIENTE na mensagem que chega; o rótulo do agente para quem fala por ele (`remetentes_do_agente` da ficha);
#   HUMANO<id> para outra pessoa da equipe; tipo e id do remetente para o resto; SISTEMA quando não há remetente.
# - Mensagem sem texto vira `[anexo/sem texto]`; evento sem texto não aparece (mas conta em `msgs`, como na prova).
class Autonomia::Desempenho::LeituraAutomatica::Transcricao
  CLIENTE = 'CLIENTE'.freeze
  NOTA = 'NOTA_INTERNA '.freeze
  SEM_TEXTO = '[anexo/sem texto]'.freeze
  SEM_REMETENTE = 'SISTEMA'.freeze
  EVENTO_ATE = 160

  # `mensagens`: as da conversa até o corte, em ordem. `remetentes`: [[tipo, id]] de quem fala pelo agente.
  def initialize(conversa:, mensagens:, remetentes:, rotulo:)
    @conversa = conversa
    @mensagens = mensagens
    @remetentes = Array(remetentes).to_set { |tipo, id| [tipo.to_s, id.to_i] }
    @rotulo = rotulo
  end

  def texto
    [cabecalho, *@mensagens.filter_map { |mensagem| linha(mensagem) }].join("\n")
  end

  # 'MM-DDTHH:MM' em UTC, o horário que a leitura devolve em `inicio` e `fim` (com espaço no lugar do T).
  def self.minuto(momento) = momento.utc.strftime('%m-%dT%H:%M')

  private

  def cabecalho
    criada = @conversa.created_at.utc.strftime('%Y-%m-%dT%H:%M')
    etiquetas = @conversa.label_list.join(',')
    "=== CONVERSA #{@conversa.display_id} | criada #{criada} | status #{@conversa.status_before_type_cast} | " \
      "etiquetas #{etiquetas} | msgs #{@mensagens.size}"
  end

  def linha(mensagem)
    texto = mensagem.content.to_s.strip
    quando = self.class.minuto(mensagem.created_at)
    return evento(quando, texto) if mensagem.activity?

    autor = autor(mensagem)
    autor = "#{NOTA}#{autor}" if mensagem.private?
    "[#{quando}] #{autor}: #{texto.presence || SEM_TEXTO}"
  end

  def evento(quando, texto)
    "  (#{quando} evento: #{texto[0, EVENTO_ATE]})" if texto.present?
  end

  def autor(mensagem)
    return CLIENTE if mensagem.incoming?
    return @rotulo if @remetentes.include?([mensagem.sender_type.to_s, mensagem.sender_id.to_i])
    return "HUMANO#{mensagem.sender_id}" if mensagem.sender_type == 'User'

    "#{mensagem.sender_type}#{mensagem.sender_id}".presence || SEM_REMETENTE
  end
end
