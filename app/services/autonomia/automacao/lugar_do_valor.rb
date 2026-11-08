# Onde cada valor da receita existe (Autonomia::Automacao::Valores, que estende este módulo). Saiu do Valores para ele
# caber no tamanho.
#
# - a mensagem do gatilho, só no filtro do `mensagem.criada`;
# - a resposta durante a espera (G11), só na condição do "esperar até";
# - a reunião (G12), só nos gatilhos de reunião;
# - o responsável anterior (G9, #2707), só no gatilho da troca de responsável do card.
module Autonomia::Automacao::LugarDoValor
  def da_mensagem?(caminho) = ::Autonomia::Automacao::Valores::MENSAGEM.key?(caminho.to_s)

  def da_resposta?(caminho) = ::Autonomia::Automacao::Valores::RESPOSTA.key?(caminho.to_s)

  def da_reuniao?(caminho) = caminho.to_s.start_with?('reuniao.')

  def da_troca?(caminho) = caminho.to_s.start_with?('gatilho.responsavel_anterior')

  # Os gatilhos em que o caminho existe; nil quando vale em todos.
  def so_nos_gatilhos(caminho)
    return ::Autonomia::Automacao::Gatilhos::DE_REUNIAO if da_reuniao?(caminho)

    [::Autonomia::Automacao::Gatilhos::TROCA] if da_troca?(caminho)
  end

  # O valor fora do lugar dele: a mensagem fora do filtro do gatilho dela (`mensagem`: a receita está lá), a resposta
  # fora do "esperar até" (`na_espera`), a reunião e o responsável anterior em outro gatilho (`gatilho`). Devolve a chave
  # da frase do salvar, ou nil.
  def fora_do_lugar(caminho, mensagem:, na_espera:, gatilho: nil)
    return :mensagem_so_no_gatilho if da_mensagem?(caminho) && !mensagem
    return :resposta_so_na_espera if da_resposta?(caminho) && !na_espera

    so_no_gatilho(caminho, gatilho)
  end

  private

  def so_no_gatilho(caminho, gatilho)
    tipos = so_nos_gatilhos(caminho)
    return if tipos.nil? || tipos.include?(gatilho)

    da_reuniao?(caminho) ? :reuniao_so_no_gatilho : :troca_so_no_gatilho
  end
end
