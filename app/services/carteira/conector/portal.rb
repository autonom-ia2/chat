# As quatro operações da carteira no conector (E7, #2900), com a sessão da conexão da conta. Cada chamada passa pela
# sessão compartilhada (Autonomia::Insurance::Connections::Session#with_fresh_session): sem login a mais, e se a
# plataforma recusar a sessão guardada, ela é renovada UMA vez por operação, nunca em laço. A segunda recusa sobe.
#
# Erros sobem como Autonomia::Insurance::Connector::Error, com `kind` estável; quem chama decide pela categoria. Nada daqui
# vai para o log: o `pdf_ref`, a `url` e os itens levam dado de cliente.
class Carteira::Conector::Portal
  # O que vem da sessão quando a conta não tem conexão pronta.
  SemConexao = Class.new(StandardError)

  def initialize(account, connector: Autonomia::Insurance::Connector.client)
    @account = account
    @connector = connector
  end

  def pedir(desde:, ate:)
    com_sessao { |sessao| @connector.portfolio_sync_start(provider: provider, session: sessao, desde: desde, ate: ate) }
  end

  def andamento(sync_id)
    com_sessao { |sessao| @connector.portfolio_sync_status(provider: provider, session: sessao, sync_id: sync_id) }
  end

  def apolices(sync_id, cursor)
    com_sessao { |sessao| @connector.portfolio_policies(provider: provider, session: sessao, sync_id: sync_id, cursor: cursor) }
  end

  def documento(ref)
    com_sessao { |sessao| @connector.portfolio_document(provider: provider, session: sessao, ref: ref) }
  end

  private

  def com_sessao(&)
    resposta = Autonomia::Insurance::Connections::Session.new(conexao, connector: @connector).with_fresh_session(&)
    raise Autonomia::Insurance::Connector::Error.new(:protocol, 'resposta da carteira fora do formato') unless resposta.is_a?(Hash)

    resposta
  end

  def conexao
    @conexao ||= Carteira::Conector.conexao(@account)
    raise SemConexao unless Carteira::Conector.pronta?(@conexao)

    @conexao
  end

  def provider
    Carteira::Conector::PROVIDER
  end
end
