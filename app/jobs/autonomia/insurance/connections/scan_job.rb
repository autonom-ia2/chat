# A DESCOBERTA de ramos e seguradoras, fora do caminho da requisição.
#
# Ela conversa com o portal seguradora por seguradora e leva perto de 25 segundos. Enquanto rodava
# dentro do clique de "Atualizar configuração", o proxy cortava a requisição antes do fim: o
# corretor via erro 500, a descoberta continuava rodando sem ninguém esperando por ela, e a conexão
# ficava parada em `discovering` — estado transitório, que desabilita os botões da tela. Medido em
# produção em 06/09/2026: 15,7 s até o 500, e a conexão presa depois disso.
#
# A cotação já resolvia isso do jeito certo, com job e consulta depois. A descoberta passa a seguir
# o mesmo caminho.
class Autonomia::Insurance::Connections::ScanJob < ApplicationJob
  queue_as :default

  def perform(connection_id)
    connection = ::Autonomia::Insurance::Connection.find_by(id: connection_id)
    return if connection.nil?
    return unless ::Autonomia::Insurance::Config.enabled?(connection.account)

    ::Autonomia::Insurance::Connections::Sync.new(connection).call
  rescue StandardError => e
    # `Sync` já não levanta; isto cobre o que estiver fora dele (o find, a config). Sem este resgate
    # a conexão ficaria em `discovering` para sempre — e é justamente disso que a rede de segurança
    # do healthcheck cuida, mas é melhor não precisar dela.
    Rails.logger.warn("[autonomia][insurance] scan job failed connection=#{connection_id} #{e.class}")
    connection&.update(status: 'degraded', last_error: "unexpected: #{e.class.name}")
  end
end
