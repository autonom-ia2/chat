# A aba Pessoas da Lista nova de Relacionamentos (#2894): a página, o número de cada grupo e a consulta inteira. E as
# leituras da ficha da pessoa (#2895), cada uma no formato que a tela lê: a pessoa, as conversas, os cards, as notas, os
# arquivos e de onde ela veio.
class Api::V1::Accounts::Relacionamentos::PessoasController < Api::V1::Accounts::Relacionamentos::BaseController
  DA_LISTA = %i[index contagens todas].freeze

  before_action :sem_parametros, except: DA_LISTA
  before_action :achar_pessoa, except: DA_LISTA

  def index
    @consulta = consulta
  end

  def contagens
    render json: consulta.contagens
  end

  # Para "Marcar todas as N": sem página e sem teto.
  def todas
    itens = consulta.todos
    render json: { itens: itens, total: itens.size }
  end

  def show; end

  def conversas
    render json: ::Relacionamentos::Ficha::Conversas.new(conversas_legiveis_de(@pessoa.id)).call
  end

  def cards
    responder_cards { |cards| cards.where(contact_id: @pessoa.id) }
  end

  def notas
    render json: ::Relacionamentos::Ficha::Notas.new(@pessoa).call
  end

  def arquivos
    render json: ::Relacionamentos::Ficha::Arquivos.new(conversas_legiveis_de(@pessoa.id)).call
  end

  def origem
    render json: ::Relacionamentos::Ficha::Origem.new(@pessoa).call
  end

  private

  def consulta
    ::Relacionamentos::ConsultaDePessoas.new(Current.account, pedido)
  end

  def pedido
    conferido(params.permit(:grupo, :busca, :ordem, :pagina, filtros: [:empresa, :etiqueta, :cidade, :chegou_em]))
  end

  def achar_pessoa
    @pessoa = Current.account.contacts.find(params[:id])
  end
end
