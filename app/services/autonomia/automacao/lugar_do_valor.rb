# Onde cada valor da receita existe (Autonomia::Automacao::Valores, que estende este módulo). Saiu do Valores e da
# Receita para elas caberem no tamanho.
#
# - a mensagem do gatilho, só no filtro do `mensagem.criada`;
# - a resposta durante a espera (G11), só na condição do "esperar até";
# - a nova entrada na etapa (G50), só na condição do "esperar até" do gatilho card.entrou_na_etapa (EsperaDaEntrada);
# - a reunião (G12), só nos gatilhos de reunião;
# - quem cuidava do card e o time de antes (G9, #2707), só no gatilho da troca (TrocaNoCard);
# - a mensagem que falhou (G53), só no gatilho dela e só nos passos: o "Só se" roda na Partida, antes de haver a
#   execução de onde ela é lida, e leria sempre vazio;
# - os pedidos do RH (G22), só no contato.recorrente com `solicitante_de` na seleção.
module Autonomia::Automacao::LugarDoValor
  extend self

  def da_mensagem?(caminho) = ::Autonomia::Automacao::Valores::MENSAGEM.key?(caminho.to_s)

  def da_resposta?(caminho) = ::Autonomia::Automacao::Valores::RESPOSTA.key?(caminho.to_s)

  def da_entrada?(caminho) = ::Autonomia::Automacao::Valores::ENTRADA.key?(caminho.to_s)

  def da_reuniao?(caminho) = caminho.to_s.start_with?('reuniao.')

  def da_falha?(caminho) = ::Autonomia::Automacao::Valores::FALHOU.key?(caminho.to_s)

  def dos_solicitados?(caminho) = caminho.to_s == ::Autonomia::Automacao::Solicitados::CAMINHO

  # Os gatilhos em que o caminho existe; nil quando vale em todos.
  def so_nos_gatilhos(caminho)
    return ::Autonomia::Automacao::Gatilhos::DE_REUNIAO if da_reuniao?(caminho)
    return [::Autonomia::Automacao::MensagemQueFalhou::TIPO] if da_falha?(caminho)
    return [::Autonomia::Automacao::EsperaDaEntrada::GATILHO] if da_entrada?(caminho)
    return [::Autonomia::Automacao::Solicitados::GATILHO] if dos_solicitados?(caminho)

    troca = ::Autonomia::Automacao::TrocaNoCard::DO_GATILHO[caminho.to_s]
    [troca] if troca
  end

  # O valor fora do lugar dele: a mensagem fora do filtro do gatilho dela (`no_filtro`: a receita está lá), a resposta
  # e a nova entrada (G50) fora do "esperar até" (`na_espera`; a entrada, também fora do gatilho de etapa), a reunião,
  # o que era antes da troca, a mensagem que falhou e os pedidos do RH em outro gatilho, e a mensagem que falhou no
  # "Só se" do gatilho. `gatilho`: o da receita (tipo e seleção). Devolve a chave da frase do salvar, ou nil.
  def fora(caminho, gatilho:, na_espera: false, no_filtro: false)
    gatilho = gatilho.to_h
    return :mensagem_so_no_gatilho if mensagem_fora?(caminho, gatilho, no_filtro)
    return :resposta_so_na_espera if da_resposta?(caminho) && !na_espera
    return :entrada_so_na_espera if entrada_fora?(caminho, gatilho, na_espera)

    so_no_gatilho(caminho, gatilho) || falhou_no_filtro(caminho, no_filtro)
  end

  private

  def mensagem_fora?(caminho, gatilho, no_filtro)
    da_mensagem?(caminho) && !(no_filtro && gatilho['tipo'] == ::Autonomia::Automacao::Valores::GATILHO_DA_MENSAGEM)
  end

  def entrada_fora?(caminho, gatilho, na_espera)
    da_entrada?(caminho) && !(na_espera && gatilho['tipo'].to_s == ::Autonomia::Automacao::EsperaDaEntrada::GATILHO)
  end

  def falhou_no_filtro(caminho, no_filtro) = (:falhou_no_filtro if no_filtro && da_falha?(caminho))

  def so_no_gatilho(caminho, gatilho)
    tipos = so_nos_gatilhos(caminho)
    return if tipos.nil? || (tipos.include?(gatilho['tipo'].to_s) && !solicitados_sem_condicao?(caminho, gatilho))
    return :reuniao_so_no_gatilho if da_reuniao?(caminho)
    return :falhou_so_no_gatilho if da_falha?(caminho)

    dos_solicitados?(caminho) ? :solicitados_so_no_recorrente : :troca_so_no_gatilho
  end

  # Os pedidos do RH pedem, além do contato.recorrente, a condição `solicitante_de` na seleção.
  def solicitados_sem_condicao?(caminho, gatilho)
    dos_solicitados?(caminho) && !gatilho['selecao'].to_h.key?('solicitante_de')
  end
end
