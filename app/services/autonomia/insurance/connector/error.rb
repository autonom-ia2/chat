# Erro do connector com categoria estável (`kind`): auth_required | unavailable | timeout |
# protocol | validation. Quem chama decide pela categoria, nunca pelo texto (que vem do portal).
#
# `causa` DIZ QUAL PORTA FALHOU, e existe porque sem ela o diagnóstico acabava no rótulo. Em
# 20/09/2026 uma cotação real morreu com `motivo=unavailable` no log e mais nada: o adapter não
# tinha registrado erro nenhum, e não havia como saber se a invocação foi recusada, se a resposta
# veio ilegível ou se o handler explodiu. Um dia de investigação para descobrir que a informação
# existia e tinha sido jogada fora.
#
# É um símbolo NOSSO, de lista fechada, e nunca texto do portal ou do fornecedor: pode ir para o
# log sem risco de carregar credencial ou requisição assinada.
#
#   :invoke_recusado  — o serviço de invocação respondeu != 200 (throttle, permissão, 5xx dele).
#                       O handler NÃO rodou, então nada foi cotado no portal.
#   :resposta_ilegivel— invocação aceita, corpo que não se lê. O handler pode ter rodado.
#   :handler_quebrou  — o handler rodou e levantou (`errorType` na resposta).
#   :status_do_handler— o handler respondeu com status de erro (é aqui que mora a recusa de negócio).
#   :excecao_local    — exceção antes ou durante a chamada, do nosso lado (rede, DNS, credencial).
#   :timeout          — estourou o tempo de leitura ou de conexão.
class Autonomia::Insurance::Connector::Error < StandardError
  # A invocação foi recusada pelo próprio serviço: o código do adapter não chegou a rodar, então
  # nenhuma cotação foi criada no portal. É o que separa "não fez" de "pode ter feito".
  NAO_CHEGOU_A_RODAR = %i[invoke_recusado].freeze

  attr_reader :kind, :details, :causa

  def initialize(kind, message, details = {}, causa: nil)
    super(message)
    @kind = kind
    @details = details
    @causa = causa
  end

  def nao_chegou_a_rodar?
    NAO_CHEGOU_A_RODAR.include?(causa)
  end

  # Rótulo curto para log e para o motivo do envio incerto: categoria e porta, ambos nossos.
  def etiqueta
    causa.present? ? "#{kind}/#{causa}" : kind.to_s
  end
end
