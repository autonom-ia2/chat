# As conversas em que o Ensaio roda um gatilho de conversa (#2498): as recentes que quem ensaia enxerga, pelo mesmo
# filtro da lista de conversas. Só lê. O par do gatilho de card é o CardsDoEnsaio (#2631), com a mesma interface.
class Autonomia::Automacao::ConversasDoEnsaio
  def initialize(gatilho:, conta:, usuario:)
    @tipo = gatilho['tipo']
    @conta = conta
    @usuario = usuario
  end

  def recentes(limite) = visiveis.includes(:contact).reorder(last_activity_at: :desc, id: :desc).limit(limite).to_a

  # Pelo número que a pessoa vê; fora do alcance de quem pede, é como se não existisse (RecordNotFound).
  def um(display_id) = visiveis.find_by!(display_id: display_id)

  def base(conversa) = { conversa_id: conversa.display_id, nome: conversa.contact&.name, ultima_atividade: conversa.last_activity_at }

  # A mensagem do gatilho e o fato que o Contexto do ensaio recebe: no "mensagem que falhou" (G53), a própria mensagem.
  def gatilho_de(conversa)
    mensagem = ::Autonomia::Automacao::MensagemDoGatilho.de(conversa, @tipo)
    [mensagem, (mensagem if ::Autonomia::Automacao::MensagemDoGatilho.falhou?(@tipo))]
  end

  # Sem a mensagem que o gatilho pede (no "mensagem criada", G53 no "mensagem que falhou") ou com a resposta automática
  # de e-mail (a régua da Escuta).
  def motivo(conversa, mensagem, _fato)
    faltando = ::Autonomia::Automacao::MensagemDoGatilho.faltando(@tipo, mensagem)
    return faltando if faltando

    'resposta_automatica' if ::Autonomia::Automacao::Escuta.resposta_automatica?(conversa, @tipo, mensagem)
  end

  private

  def visiveis
    ::Conversations::PermissionFilterService.new(@conta.conversations, @usuario, @conta, for_reading: true).perform
  end
end
