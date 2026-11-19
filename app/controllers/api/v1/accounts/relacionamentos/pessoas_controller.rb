# A aba Pessoas da Lista nova de Relacionamentos (#2894): a página, o número de cada grupo e a consulta inteira. E as
# leituras da ficha da pessoa (#2895), cada uma no formato que a tela lê: a pessoa, as conversas, os cards, as notas, os
# arquivos e de onde ela veio.
# #3062 — e "Baixar planilha": a mesma consulta da tela (grupo, busca, filtros e ordem) vira o arquivo que a lista de
# contatos de hoje já manda por e-mail (Account::ContactsExportJob), para quem pode exportar contatos.
class Api::V1::Accounts::Relacionamentos::PessoasController < Api::V1::Accounts::Relacionamentos::BaseController
  DA_LISTA = %i[index contagens todas exportar].freeze

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

  # A página não entra: a planilha leva a consulta inteira. O pedido é conferido aqui (422 para o que a lista não
  # conhece), antes de ir para a fila: um filtro perdido no caminho mandaria a base inteira.
  def exportar
    authorize Contact, :export?
    pedido_da_planilha = pedido.to_h.except('pagina')
    ::Relacionamentos::ConsultaDePessoas.new(Current.account, pedido_da_planilha)
    Account::ContactsExportJob.perform_later(Current.account.id, Current.user.id, nil, { relacionamentos: pedido_da_planilha })
    render json: { email: Current.user.email }, status: :accepted
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
