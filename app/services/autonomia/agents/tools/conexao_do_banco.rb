# #1430: DEVOLVER A CONEXÃO DO BANCO ENQUANTO SE ESPERA A REDE. A consulta HTTP em segundo plano espera em dois lugares —
# o job, durante a chamada, e o turno, entre duas leituras do estado —, e nenhum dos dois precisa de conexão parada
# enquanto isso. A próxima leitura pega outra do pool, sozinha.
#
# Nunca no meio de uma transação aberta pelo código: devolver a conexão ali a entregaria a outra thread com a transação
# pela metade. A transação do teste (a das fixtures, que não aceita junção) não conta.
module Autonomia::Agents::Tools::ConexaoDoBanco
  module_function

  # -> true quando devolveu.
  def soltar
    pool = ActiveRecord::Base.connection_pool
    conexao = pool.active_connection?
    return false if conexao.blank? || conexao.current_transaction.joinable?

    pool.release_connection
  end
end
