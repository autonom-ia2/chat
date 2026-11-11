# A aba Empresas da Lista nova de Relacionamentos (#2894): a página e o número de cada grupo. Vale o mesmo que a lista
# de empresas de hoje: Empresas ligado na conta (403 sem) e permissão de ver empresas. E as leituras da ficha da empresa
# (#2895), no formato que a tela lê: a empresa, as pessoas, as conversas e os cards dela.
class Api::V1::Accounts::Relacionamentos::EmpresasController < Api::V1::Accounts::Relacionamentos::BaseController
  # A regra de "card da empresa" do quadro e do perfil de hoje (Crm::CompanyOpportunitiesController).
  include ::Crm::Cards::CompanyFilters

  DA_LISTA = %i[index contagens].freeze
  # A tela mostra as pessoas da empresa numa lista só, sem "mostrar mais"; o perfil da empresa de hoje traz 15 por vez.
  PESSOAS_NA_FICHA = 100

  self.registro_da_permissao = Company

  before_action :exigir_empresas
  before_action :sem_parametros, except: DA_LISTA
  before_action :achar_empresa, except: DA_LISTA

  def index
    @consulta = consulta
  end

  def contagens
    render json: consulta.contagens
  end

  def show; end

  def pessoas
    por_nome = Arel.sql(::Relacionamentos::Consulta.por_nome('contacts'))
    @pessoas = pessoas_da_empresa.order(por_nome).limit(PESSOAS_NA_FICHA).preload(::Relacionamentos::ConsultaDePessoas::O_QUE_A_LINHA_USA)
  end

  def conversas
    render json: ::Relacionamentos::Ficha::Conversas.new(conversas_legiveis_de(pessoas_da_empresa.select(:id)), com_pessoa: true).call
  end

  # A empresa de prospecção do card vale primeiro; senão, a empresa da pessoa do card.
  def cards
    responder_cards(com_pessoa: true) { |cards| cards.where(resolved_company_match_sql, @empresa.id, @empresa.id) }
  end

  private

  def exigir_empresas
    return if Current.account.feature_enabled?('companies')

    render json: { error: 'Companies are not enabled for this account' }, status: :forbidden
  end

  def consulta
    ::Relacionamentos::ConsultaDeEmpresas.new(Current.account, conferido(params.permit(:grupo, :busca, :ordem, :pagina)))
  end

  def achar_empresa
    @empresa = ::Relacionamentos::ConsultaDeEmpresas.com_clientes_contados(Current.account.companies).find(params[:id])
  end

  # Só gente da mesma conta da empresa, como a lista conta os clientes dela.
  def pessoas_da_empresa
    Current.account.contacts.where(company_id: @empresa.id)
  end
end
