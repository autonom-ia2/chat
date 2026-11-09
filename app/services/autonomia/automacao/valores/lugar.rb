# Onde a receita pode ler cada valor (#2414): o que só existe num lugar dela. Saiu de `Valores`, que segue sendo a
# porta dos caminhos (`Valores.fora_do_lugar`).
module Autonomia::Automacao::Valores::Lugar
  module_function

  def valores = ::Autonomia::Automacao::Valores

  # O valor que só existe num lugar da receita: a mensagem no filtro do gatilho dela (`mensagem`: a receita está lá);
  # a resposta e a nova entrada na etapa (G50) no "esperar até" (`na_espera`); a reunião nos gatilhos de reunião e a
  # mensagem que falhou no gatilho dela (`gatilho`). A mensagem que falhou fica só nos passos (`no_filtro`): o "Só se"
  # roda na Partida, antes de haver a execução de onde ela é lida, e leria sempre vazio. Devolve a chave da frase do
  # salvar, ou nil.
  def fora_do_lugar(caminho, mensagem:, na_espera:, gatilho: nil, no_filtro: false)
    return :mensagem_so_no_gatilho if valores.da_mensagem?(caminho) && !mensagem

    fora_da_espera(caminho, na_espera, gatilho) || fora_do_gatilho(caminho, gatilho) || falhou_no_filtro(caminho, no_filtro)
  end

  # A resposta (G11) e a nova entrada na etapa (G50) só na condição do "esperar até"; a entrada, só no gatilho de etapa.
  def fora_da_espera(caminho, na_espera, gatilho)
    return :entrada_so_na_espera if valores.da_entrada?(caminho) && !(na_espera && gatilho == ::Autonomia::Automacao::EsperaDaEntrada::GATILHO)

    :resposta_so_na_espera if valores.da_resposta?(caminho) && !na_espera
  end

  def falhou_no_filtro(caminho, no_filtro) = (:falhou_no_filtro if no_filtro && valores.da_falha?(caminho))

  # O valor que só existe em certos gatilhos: a reunião e a mensagem que falhou.
  def fora_do_gatilho(caminho, gatilho)
    return :reuniao_so_no_gatilho if valores.da_reuniao?(caminho) && !::Autonomia::Automacao::Gatilhos.de_reuniao?(gatilho)

    :falhou_so_no_gatilho if valores.da_falha?(caminho) && gatilho != ::Autonomia::Automacao::MensagemQueFalhou::TIPO
  end
end
