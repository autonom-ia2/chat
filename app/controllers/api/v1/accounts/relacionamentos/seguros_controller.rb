# A aba Seguros de Relacionamentos e a gaveta de um seguro (E4, #2897). Leituras: a página, o número de cada grupo, a
# consulta inteira ("Marcar todas"), a frase do topo, as opções de filtro, um seguro e a história dele. Escritas da
# gaveta: corrigir, marcar como cancelado e voltar a ativo; cada uma devolve o seguro como ficou. O PDF fica em
# seguros/pdf_controller.rb.
class Api::V1::Accounts::Relacionamentos::SegurosController < Api::V1::Accounts::Relacionamentos::CarteiraController
  DA_LISTA = %i[index todos contagens].freeze
  LEITURAS_DE_UM = %i[show historia].freeze
  ESCRITAS = %i[update cancelar voltar_a_ativo].freeze
  CAMPOS = ::Carteira::Campos::COLUNAS.keys.freeze

  before_action :sem_parametros, except: DA_LISTA + ESCRITAS
  before_action :achar_seguro, only: LEITURAS_DE_UM + ESCRITAS
  before_action :poder_ver, only: LEITURAS_DE_UM
  before_action :poder_editar, only: ESCRITAS

  def index
    seguros = consulta
    render json: { itens: apresentacao.de_cada(seguros.itens), total: seguros.total, temMais: seguros.tem_mais? }
  end

  # Para "Marcar todas as N": sem página e sem teto.
  def todos
    itens = consulta.todos
    render json: { itens: itens, total: itens.size }
  end

  def contagens
    render json: consulta.contagens
  end

  def resumo
    render json: ::Carteira::Resumo.new(Current.account).call
  end

  def opcoes_de_filtro
    render json: ::Carteira::OpcoesDeFiltro.new(Current.account).call
  end

  def show
    responder_seguro
  end

  def historia
    render json: ::Carteira::Historia.new(@seguro).call
  end

  def update
    responder_seguro(::Carteira::Corrigir.new(@seguro, corpo(*CAMPOS), user: Current.user).call)
  end

  def cancelar
    corpo
    responder_seguro(cancelamento.cancelar)
  end

  def voltar_a_ativo
    corpo
    responder_seguro(cancelamento.voltar_a_ativo)
  end

  private

  def cancelamento
    ::Carteira::Cancelamento.new(@seguro, user: Current.user)
  end

  def consulta
    ::Carteira::Consulta.new(Current.account, conferido(params.permit(:grupo, :busca, :ordem, :pagina, filtros: [:tipo, :seguradora, :cuida])))
  end
end
