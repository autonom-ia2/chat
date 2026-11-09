# Onde cada valor da receita existe (Autonomia::Automacao::Valores, que estende este módulo). Saiu do Valores para ele
# caber no tamanho.
#
# - a mensagem do gatilho, só no filtro do `mensagem.criada`;
# - a resposta durante a espera (G11), só na condição do "esperar até";
# - a reunião (G12), só nos gatilhos de reunião;
# - quem cuidava do card e o time de antes (G9, #2707), só no gatilho da troca (TrocaNoCard);
# - a mensagem que falhou (G53), só no gatilho dela e só nos passos: o "Só se" roda na Partida, antes de haver a
#   execução de onde ela é lida, e leria sempre vazio.
module Autonomia::Automacao::LugarDoValor
  def da_mensagem?(caminho) = ::Autonomia::Automacao::Valores::MENSAGEM.key?(caminho.to_s)

  def da_resposta?(caminho) = ::Autonomia::Automacao::Valores::RESPOSTA.key?(caminho.to_s)

  def da_reuniao?(caminho) = caminho.to_s.start_with?('reuniao.')

  def da_falha?(caminho) = ::Autonomia::Automacao::Valores::FALHOU.key?(caminho.to_s)

  # Os gatilhos em que o caminho existe; nil quando vale em todos.
  def so_nos_gatilhos(caminho)
    return ::Autonomia::Automacao::Gatilhos::DE_REUNIAO if da_reuniao?(caminho)
    return [::Autonomia::Automacao::MensagemQueFalhou::TIPO] if da_falha?(caminho)

    troca = ::Autonomia::Automacao::TrocaNoCard::DO_GATILHO[caminho.to_s]
    [troca] if troca
  end

  # O valor fora do lugar dele: a mensagem fora do filtro do gatilho dela (`mensagem`: a receita está lá), a resposta
  # fora do "esperar até" (`na_espera`), a reunião, o que era antes da troca e a mensagem que falhou em outro gatilho
  # (`gatilho`), e a mensagem que falhou no filtro do gatilho (`no_filtro`). Devolve a chave da frase do salvar, ou nil.
  def fora_do_lugar(caminho, mensagem:, na_espera:, gatilho: nil, no_filtro: false)
    return :mensagem_so_no_gatilho if da_mensagem?(caminho) && !mensagem
    return :resposta_so_na_espera if da_resposta?(caminho) && !na_espera

    so_no_gatilho(caminho, gatilho) || falhou_no_filtro(caminho, no_filtro)
  end

  private

  def falhou_no_filtro(caminho, no_filtro) = (:falhou_no_filtro if no_filtro && da_falha?(caminho))

  def so_no_gatilho(caminho, gatilho)
    tipos = so_nos_gatilhos(caminho)
    return if tipos.nil? || tipos.include?(gatilho)
    return :reuniao_so_no_gatilho if da_reuniao?(caminho)

    da_falha?(caminho) ? :falhou_so_no_gatilho : :troca_so_no_gatilho
  end
end
