# O seguro que a pessoa tem em outra corretora vira lembrete (E6.5, #2899): os PDFs que já chegaram nas conversas dela,
# ler um PDF (enviado ou escolhido entre esses), perguntar pela leitura até ela sair de "lendo" e guardar o seguro com o
# que a pessoa conferiu. Tudo pede poder editar a pessoa: o que se lê aqui só serve a quem vai guardar.
#
# Conta sem a leitura liberada: tudo responde 422 `leitura_desligada` (decisão D4), sem ler nada. O resumo da carteira
# (`leituraDePdf`) já diz isso à tela, que nem mostra a entrada. Apagar o seguro de fora é o `DELETE seguros/:id`.
class Api::V1::Accounts::Relacionamentos::Pessoas::SegurosDeForaController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :sem_parametros, only: %i[arquivos leitura]
  before_action :achar_pessoa
  before_action :exigir_leitura

  # GET pessoas/:id/seguros_de_fora/arquivos
  def arquivos
    render json: ::Carteira::DeFora::Arquivos.new(@pessoa, user: Current.user).call
  end

  # POST pessoas/:id/seguros_de_fora/leitura (multipart `arquivo`, ou `anexoId` de um PDF da conversa)
  def ler
    pedido = params.key?(:anexoId) ? corpo(:anexoId) : corpo(:arquivo)
    leitura = ::Carteira::DeFora::Ler.new(@pessoa, user: Current.user).call(arquivo: pedido['arquivo'], anexo_id: pedido['anexoId'])
    render json: { leituraId: leitura.id }, status: :accepted
  end

  # GET pessoas/:id/seguros_de_fora/leitura/:leitura_id
  def leitura
    response.headers['Cache-Control'] = 'private, no-store'
    render json: ::Carteira::DeFora::Andamento.new(@pessoa, params[:leitura_id]).call
  end

  # POST pessoas/:id/seguros_de_fora { leituraId, querLembrete, campos: { tipo, seguradora, termina, corretora }, confirmados: [] }
  def create
    pedido = corpo(:leituraId, :querLembrete, campos: %i[tipo seguradora termina corretora], confirmados: [])
    seguro = ::Carteira::DeFora::Guardar.new(@pessoa, user: Current.user)
                                        .call(leitura_id: pedido['leituraId'], quer_lembrete: pedido['querLembrete'],
                                              campos: pedido.fetch('campos', {}), confirmados: pedido.fetch('confirmados', []))
    render json: apresentacao.de(seguro), status: :created
  end

  private

  def achar_pessoa
    @pessoa = Current.account.contacts.find(params[:id])
    authorize @pessoa, :update?
  end

  def exigir_leitura
    return if ::Carteira::Leitor::Liberado.para?(Current.account)

    raise CustomExceptions::CarteiraRecusa, ::Carteira::Leitor::Resultado::DESLIGADA
  end
end
