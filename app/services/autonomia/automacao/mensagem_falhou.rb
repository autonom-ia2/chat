# O gatilho "mensagem.falhou" (G8, #2637). A mensagem enviada ao cliente passou a falhar (o canal recusou depois, como
# a Meta faz) ou já nasceu falhada: cada automação ligada com esse gatilho começa na conversa dela. Quem chama é a
# Escuta, na mensagem criada e na situação atualizada, já sob o rescue dela.
#
# - Só a mensagem que ia ao cliente: a nota privada e a de entrada não "falham" para ele.
# - Uma execução por mensagem: a marca é a própria mensagem (Gatilhos.marca_da_falha), e o aviso repetido do canal não
#   abre outra.
# - A automação que mandou a mensagem não começa de novo por ela; o caminho dentro do fluxo é o ramo "se o envio
#   falhou" (`envio.situacao`). Outra automação começa. Sem isso, "falhou → manda de novo" giraria na mesma recusa.
# - A mensagem que uma execução deste gatilho mandou e falhou não começa nenhuma: a recusa vem do canal, fora da cadeia
#   (Cadeia), e duas automações "falhou → manda" girariam uma na outra.
# - Na execução, `envio.texto` e `envio.situacao` são os da mensagem que falhou até o primeiro envio dela
#   (Contexto#ultimo_envio).
module Autonomia::Automacao::MensagemFalhou
  module_function

  def comecar(mensagem)
    return unless mensagem.outgoing? && !mensagem.private? && ::Autonomia::Automacao::Motor.ligado?(mensagem.account)
    return if de_uma_falha?(mensagem)

    escuta = ::Autonomia::Automacao::Escuta
    tipo = ::Autonomia::Automacao::Gatilhos::FALHOU
    marca = ::Autonomia::Automacao::Gatilhos.marca_da_falha(mensagem)
    propria = mensagem.content_attributes.to_h.with_indifferent_access[:automacao_id].to_i
    escuta.cada_automacao(mensagem.conversation, tipo, {}) do |definicao|
      escuta.partir(definicao, mensagem.conversation, tipo, evento: marca) unless definicao.id == propria
    rescue StandardError => e
      escuta.registrar_erro("não começou automacao=#{definicao.id} mensagem=#{mensagem.id}", e)
    end
  end

  def de_uma_falha?(mensagem)
    execucao_id = mensagem.content_attributes.to_h.with_indifferent_access[:execucao_id]
    return false if execucao_id.blank?

    ::Autonomia::Automacao::Execucao.exists?(id: execucao_id, account_id: mensagem.account_id,
                                             chave_gatilho: ::Autonomia::Automacao::Gatilhos::FALHOU)
  end
end
