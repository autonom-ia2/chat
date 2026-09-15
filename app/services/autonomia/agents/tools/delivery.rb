# CONTEXTO DE ENTREGA de um turno de atendimento (#313).
#
# É o que permite uma ferramenta assíncrona existir sem que o `Bound` — ou o `Registry`, ou a própria
# ferramenta — passe a conhecer conversa e mensagem. O Responder cria este objeto, ele desce até o
# ponto de execução da ferramenta, e volta carregando as execuções que foram aceitas no turno e os
# anexos do turno.
#
# Desce POR CHAMADA (`Bound#execute(call, delivery:)`), não pela construção da ferramenta. É
# deliberado: `Tools::Bound.for_agent` tem DOIS chamadores — o `Answerer` e o `Specialist#tools`,
# que memoiza o catálogo na instância do model. Pendurar contexto na construção quebraria o caminho
# do especialista, que é justamente onde a cotação vai morar (o `Answerer` REMOVE do principal todo
# slug reservado por um especialista habilitado).
#
# SEM contexto (Testar, Copiloto, playground) a ferramenta continua no catálogo e devolve erro
# nomeado. Sumir do catálogo faria o Testar mentir sobre o agente de produção.
class Autonomia::Agents::Tools::Delivery
  # ANEXO DO TURNO (fatia 2 do #420): texto escrito pelo CÓDIGO que o `Operate::Responder` entrega logo
  # depois da resposta do modelo, na mesma entrega. O modelo nunca recebe o texto do anexo. `dados` é o que
  # a ferramenta precisa para refazer o anexo quando é chamada de novo no mesmo turno.
  Anexo = Struct.new(:texto, :dados, keyword_init: true)

  attr_reader :conversation, :agent_inbox, :origin_message_id, :runs

  # `origin_message_id` é a mensagem do cliente que abriu o turno. Ela entra na execução no momento
  # da criação (e não na promoção) porque é a chave que distingue um PEDIDO NOVO de um RETRY do
  # mesmo turno: o `ReplyJob` pode reexecutar o settle e refazer a chamada ao modelo, e sem essa
  # chave a segunda passada abriria uma cotação nova no portal.
  def initialize(conversation:, agent_inbox:, origin_message_id: nil)
    @conversation = conversation
    @agent_inbox = agent_inbox
    @origin_message_id = origin_message_id
    @runs = []
    @anexos = {}
  end

  def register(run)
    @runs << run if run.present?
    run
  end

  def any_runs?
    @runs.any?
  end

  # UM ANEXO POR CHAVE: a ferramenta chamada duas vezes no mesmo turno troca o anexo dela no lugar em que
  # ele entrou, e o cliente recebe um só.
  def anexar(chave, texto, dados: nil)
    @anexos[chave.to_s] = Anexo.new(texto: texto.to_s, dados: dados)
  end

  # -> o anexo desta chave neste turno, ou nil.
  def anexo(chave)
    @anexos[chave.to_s]
  end

  # -> os textos a entregar depois da resposta, na ordem em que as chaves entraram.
  def anexos
    @anexos.values.map(&:texto).reject(&:blank?)
  end
end
