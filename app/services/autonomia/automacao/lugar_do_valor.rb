# O valor que só existe num lugar da receita (saiu de Valores e da Receita para elas caberem no tamanho). A mensagem só
# no filtro do gatilho dela (`no_filtro`: a receita está lá); a resposta só no "esperar até" (`na_espera`); a reunião
# nos gatilhos de reunião e a mensagem que falhou no gatilho dela. A mensagem que falhou fica só nos passos: o "Só se"
# roda na Partida, antes de haver a execução de onde ela é lida, e leria sempre vazio. Os pedidos do RH (G22) só no
# contato.recorrente com `solicitante_de` na seleção. `gatilho`: o da receita (tipo e seleção).
module Autonomia::Automacao::LugarDoValor
  module_function

  # Devolve a chave da frase do salvar, ou nil.
  def fora(caminho, gatilho:, na_espera: false, no_filtro: false)
    gatilho = gatilho.to_h
    return :mensagem_so_no_gatilho if mensagem_fora?(caminho, gatilho, no_filtro)
    return :resposta_so_na_espera if ::Autonomia::Automacao::Valores.da_resposta?(caminho) && !na_espera

    fora_do_gatilho(caminho, gatilho) || falhou_no_filtro(caminho, no_filtro)
  end

  def mensagem_fora?(caminho, gatilho, no_filtro)
    valores = ::Autonomia::Automacao::Valores
    valores.da_mensagem?(caminho) && !(no_filtro && gatilho['tipo'] == valores::GATILHO_DA_MENSAGEM)
  end

  def falhou_no_filtro(caminho, no_filtro) = (:falhou_no_filtro if no_filtro && ::Autonomia::Automacao::Valores.da_falha?(caminho))

  # O valor que só existe em certos gatilhos: a reunião, a mensagem que falhou e os pedidos do RH.
  def fora_do_gatilho(caminho, gatilho)
    valores = ::Autonomia::Automacao::Valores
    return :reuniao_so_no_gatilho if valores.da_reuniao?(caminho) && !::Autonomia::Automacao::Gatilhos.de_reuniao?(gatilho['tipo'])
    return :falhou_so_no_gatilho if valores.da_falha?(caminho) && gatilho['tipo'] != ::Autonomia::Automacao::MensagemQueFalhou::TIPO

    :solicitados_so_no_recorrente if solicitados_fora?(caminho, gatilho)
  end

  def solicitados_fora?(caminho, gatilho)
    valores = ::Autonomia::Automacao::Valores
    caminho.to_s == valores::SOLICITADOS &&
      !(gatilho['tipo'].to_s == valores::GATILHO_DOS_SOLICITADOS && gatilho['selecao'].to_h.key?('solicitante_de'))
  end
end
