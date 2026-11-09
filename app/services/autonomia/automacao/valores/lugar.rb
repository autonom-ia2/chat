# O valor que só existe num lugar da receita (#2496, G11, G12, G53): a mensagem no filtro do gatilho dela, a resposta no
# "esperar até", a reunião nos gatilhos de reunião e a mensagem que falhou nos passos do gatilho dela.
#
# Saiu de `Valores`, que segue sendo a porta dos caminhos (`Valores.fora_do_lugar`): o `extend` lá dentro põe estes
# métodos na própria classe, e as perguntas sobre o caminho (`da_mensagem?`, `da_falha?`…) continuam sendo dela.
module Autonomia::Automacao::Valores::Lugar
  # A mensagem no filtro do gatilho dela (`mensagem`: a receita está lá); a resposta no "esperar até" (`na_espera`); a
  # reunião nos gatilhos de reunião e a mensagem que falhou no gatilho dela (`gatilho`). A mensagem que falhou fica só
  # nos passos (`no_filtro`): o "Só se" roda na Partida, antes de haver a execução de onde ela é lida, e leria sempre
  # vazio. Devolve a chave da frase do salvar, ou nil.
  def fora_do_lugar(caminho, mensagem:, na_espera:, gatilho: nil, no_filtro: false)
    return :mensagem_so_no_gatilho if da_mensagem?(caminho) && !mensagem
    return :resposta_so_na_espera if da_resposta?(caminho) && !na_espera

    fora_do_gatilho(caminho, gatilho) || falhou_no_filtro(caminho, no_filtro)
  end

  def falhou_no_filtro(caminho, no_filtro) = (:falhou_no_filtro if no_filtro && da_falha?(caminho))

  # O valor que só existe em certos gatilhos: a reunião e a mensagem que falhou.
  def fora_do_gatilho(caminho, gatilho)
    return :reuniao_so_no_gatilho if da_reuniao?(caminho) && !::Autonomia::Automacao::Gatilhos.de_reuniao?(gatilho)

    :falhou_so_no_gatilho if da_falha?(caminho) && gatilho != ::Autonomia::Automacao::MensagemQueFalhou::TIPO
  end
end
