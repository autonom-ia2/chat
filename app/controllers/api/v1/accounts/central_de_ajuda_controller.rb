# Leitura da Central de Ajuda da plataforma, para qualquer pessoa da conta. Só leitura: o conteúdo vem do
# repositório pelo Publicador. Cada leitura garante que a versão embarcada já foi publicada.
class Api::V1::Accounts::CentralDeAjudaController < Api::V1::Accounts::BaseController
  before_action { ::Autonomia::CentralDeAjuda::Publicador.garantir_async }

  def index
    render json: { preparando: leitura.portal.nil?, capitulos: leitura.capitulos }
  end

  def show
    artigo = leitura.artigo(params[:id])
    return head :not_found if artigo.nil?

    anterior, proximo = leitura.vizinhos(artigo)
    render json: leitura.resumo(artigo).merge(
      conteudo: artigo.content,
      me_leve_ate_la: leitura.central(artigo)['me_leve_ate_la'],
      video: leitura.central(artigo)['video'],
      anterior: anterior, proximo: proximo,
      atualizado_em: artigo.updated_at
    )
  end

  def busca
    render json: { resultados: leitura.buscar(params[:termo]) }
  end

  private

  def leitura
    @leitura ||= ::Autonomia::CentralDeAjuda::Leitura.new(account: Current.account, account_user: Current.account_user)
  end
end
