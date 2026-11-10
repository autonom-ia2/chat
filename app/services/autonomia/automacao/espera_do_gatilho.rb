# Quem o gatilho que aconteceu de novo acorda (lote 4, #2682; revisão do #2816): só o "esperar até" cuja condição lê
# `gatilho.repetiu`, no mesmo padrão do card (EsperaDoCard.le_o_card?) e da reunião (EsperaDaReuniao.le_reuniao?). A
# mensagem nova numa conversa com a execução aberta repete o gatilho "mensagem criada" a cada mensagem: sem espera que
# leia a repetição, ela não grava nada nem reserva a execução.
module Autonomia::Automacao::EsperaDoGatilho
  VALOR = 'gatilho.repetiu'.freeze

  module_function

  # O passo é um "esperar até" que lê `gatilho.repetiu`? O caminho fica em `{"$valor": "..."}` dentro da condição.
  def le_repetiu?(passo)
    passo.to_h['tipo'] == 'esperar_ate' && ::Autonomia::Automacao::EsperaDaReuniao.caminhos_da(passo['condicao']).include?(VALOR)
  end

  # A execução espera agora num passo que lê a repetição.
  def esperando_a_repeticao?(execucao)
    le_repetiu?(::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(execucao.cursor))
  end

  # Algum passo da receita lê a repetição. A hora fica gravada também antes de a execução chegar à espera: a rodada que
  # acabou de ler a condição e ainda não gravou a espera reconfere com ela (EsperaNoExecutor#reconferir_a_espera).
  def na_receita?(receita)
    ::Autonomia::Automacao::Receita.new(receita, conta: nil, account_user: nil).passos.any? { |passo| le_repetiu?(passo) }
  end
end
