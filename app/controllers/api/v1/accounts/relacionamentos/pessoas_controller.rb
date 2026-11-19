# A aba Pessoas da Lista nova de Relacionamentos (#2894): a página, o número de cada grupo e a consulta inteira. E as
# leituras da ficha da pessoa (#2895), cada uma no formato que a tela lê: a pessoa, as conversas, os cards, as notas, os
# arquivos e de onde ela veio.
# #3062 — e "Baixar planilha": a mesma consulta da tela (grupo, busca, filtros e ordem) vira o arquivo que a lista de
# contatos de hoje já manda por e-mail (Account::ContactsExportJob), para quem pode exportar contatos.
#
# Uma planilha por pessoa e conta a cada poucos minutos: cada pedido é uma consulta inteira e um e-mail. A trava fica no
# Redis com prazo, e o pedido repetido nesse tempo responde 429 com quantos segundos faltam.
class Api::V1::Accounts::Relacionamentos::PessoasController < Api::V1::Accounts::Relacionamentos::BaseController
  DA_LISTA = %i[index contagens todas exportar].freeze
  TRAVA_DA_PLANILHA = 'RELACIONAMENTOS_PLANILHA::%<account_id>d::%<user_id>d'.freeze
  ESPERA_DA_PLANILHA = 5.minutes

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
    return planilha_pedida_ha_pouco unless travar_planilha

    Account::ContactsExportJob.perform_later(Current.account.id, Current.user.id, nil, { relacionamentos: pedido_da_planilha })
    render json: { email: Current.user.email, espera: ESPERA_DA_PLANILHA.to_i }, status: :accepted
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

  def trava_da_planilha
    format(TRAVA_DA_PLANILHA, account_id: Current.account.id, user_id: Current.user.id)
  end

  def planilha_pedida_ha_pouco
    render json: { error: 'planilha_pedida_ha_pouco', espera: Redis::Alfred.ttl(trava_da_planilha) }, status: :too_many_requests
  end

  # Verdadeiro só para quem pegou a trava agora (SET NX): o pedido seguinte, no prazo, fica de fora.
  def travar_planilha
    Redis::Alfred.set(trava_da_planilha, 1, nx: true, ex: ESPERA_DA_PLANILHA.to_i)
  end

  def achar_pessoa
    @pessoa = Current.account.contacts.find(params[:id])
  end
end
