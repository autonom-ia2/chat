# O limite de mensagens por cliente e o horário de envio da conta (#3063, item 2) nos passos que mandam mensagem ao
# cliente por iniciativa da empresa. Combinado com a Automação Ultra em 19/11:
# - onde: "mensagem" e "email" (passo_nativo), o "escrever" que fala com o cliente (passo_de_ia, antes de pagar a IA) e a
#   primeira pergunta da reunião e da pesquisa. A pergunta que sai depois que o cliente respondeu ao modelo vem na
#   retomada, por outro caminho, e não passa aqui;
# - consulta antes, contagem depois: o porteiro só conta o passo que mandou de fato (`mensagem_id` no resultado);
# - isenta a resposta a quem acabou de escrever: gatilho de entrada do cliente (a mensagem nova que ENTROU, ou a conversa
#   nova que o cliente começou), com o passo na primeira rodada, antes de qualquer espera. "Mensagem nova" seguida de
#   "esperar 3 dias" e mensagem é iniciativa da empresa e passa pelo porteiro;
# - fora do limite ou do horário: a execução espera até a hora (sem contar tentativa) e o histórico diz por quê.
module Autonomia::Automacao::RitmoNoExecutor
  PASSOS_QUE_PERGUNTAM_AO_CLIENTE = %w[reuniao pesquisa].freeze
  ORIGEM_POR_PASSO = Hash.new('automacao_mensagem').merge('email' => 'automacao_email').freeze
  MOTIVO = 'adiado_pelo_ritmo'.freeze
  EVENTO_DA_MENSAGEM = 'mensagem:'.freeze

  private

  # O envio de um passo pelo ritmo: no passo ao cliente, adiado nada roda; senão `envio` manda, a mensagem que saiu conta,
  # e o bloco segue com o resultado. Nos outros passos, só manda e segue.
  def pelo_ritmo(passo, envio)
    return yield(envio.call) unless ao_cliente?(passo)
    return if adiado_pelo_ritmo?(passo)

    resultado = envio.call
    contar_no_ritmo(passo, resultado)
    yield resultado
  end

  # true quando adiou: a rodada parou e o passo roda de novo na hora.
  def adiado_pelo_ritmo?(passo)
    return false if isento_do_ritmo?

    ate = ::Autonomia::RitmoDeEnvio::Porteiro.quando(account: @account, contact: contato_do_ritmo)
    return false unless ate

    registrar(passo['id'], 'ok', MOTIVO, 'ate' => ate.iso8601)
    aguardar(passo, ate, registrar: false)
    true
  end

  # O passo voltou da espera do ritmo, não de uma pergunta que saiu: o último registro dele é o do adiamento. A reunião e
  # a pesquisa perguntam de novo em vez de conferir a resposta.
  def voltou_do_ritmo?(passo)
    ::Autonomia::Automacao::Registro.where(execucao: @execucao, passo: passo['id']).order(:id).last&.motivo == MOTIVO
  end

  def contar_no_ritmo(passo, resultado)
    return if resultado.dados.to_h['mensagem_id'].blank? || isento_do_ritmo?

    ::Autonomia::RitmoDeEnvio::Porteiro.contar!(account: @account, contact_id: contato_do_ritmo&.id,
                                                origem: ORIGEM_POR_PASSO[passo['tipo']])
  end

  # O passo manda mensagem ao cliente: "avisar", o resumo que avisa a equipe e a aprovação ficam fora.
  def ao_cliente?(passo)
    case passo['tipo']
    when 'mensagem', 'email', *PASSOS_QUE_PERGUNTAM_AO_CLIENTE then true
    when 'escrever' then ::Autonomia::Automacao::PassoDeEscrever.fala_com_gente?(passo)
    else false
    end
  end

  def contato_do_ritmo = ::Autonomia::Automacao::Contexto.de(alvo).contato

  def isento_do_ritmo?
    return @isento_do_ritmo if defined?(@isento_do_ritmo)

    @isento_do_ritmo = @primeira_rodada == true && cliente_puxou_a_conversa?
  end

  def cliente_puxou_a_conversa?
    case @execucao.versao.receita.to_h.dig('gatilho', 'tipo')
    when 'mensagem.criada' then mensagem_do_gatilho&.incoming?
    when 'conversa.criada' then primeira_mensagem_da_conversa&.incoming?
    else false
    end
  end

  # A Partida guarda em `evento` a marca "mensagem:<id>" da mensagem que disparou.
  def mensagem_do_gatilho
    evento = @execucao.evento.to_s
    return unless evento.start_with?(EVENTO_DA_MENSAGEM)

    @account.messages.find_by(id: evento.delete_prefix(EVENTO_DA_MENSAGEM))
  end

  def primeira_mensagem_da_conversa
    conversa = @execucao.alvo
    return unless conversa.is_a?(Conversation)

    conversa.messages.where(message_type: %i[incoming outgoing]).order(:id).first
  end
end
