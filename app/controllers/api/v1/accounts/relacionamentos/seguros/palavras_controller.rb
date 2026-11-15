# "Seu seguro em palavras simples" na gaveta do seguro (E6.6, #2899): o texto guardado e por onde ele sai, escrever o
# texto (chamada paga), guardar o texto ajustado e mandar ao cliente. Ler pede poder ver a pessoa; o resto, poder
# editá-la. Mandar ainda pede poder escrever numa conversa do contato (Carteira::Palavras::Conversa).
#
# Conta sem a leitura liberada: tudo responde 422 `leitura_desligada` (a mesma chave da E6, decisão D4); a tela nem mostra
# a parte de palavras simples.
class Api::V1::Accounts::Relacionamentos::Seguros::PalavrasController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :sem_parametros, only: :show
  before_action :achar_seguro
  before_action :poder_ver, only: :show
  before_action :poder_editar, except: :show
  before_action :exigir_leitura

  # GET seguros/:id/palavras
  def show
    response.headers['Cache-Control'] = 'private, no-store'
    render json: conversa.para_a_tela
  end

  # POST seguros/:id/palavras/escrever
  def escrever
    corpo
    ::Carteira::Palavras::Escrever.new(@seguro).call
    render json: conversa.para_a_tela
  end

  # PUT seguros/:id/palavras { texto }
  def update
    ::Carteira::Palavras::Salvar.new(@seguro).call(corpo(:texto)['texto'])
    render json: conversa.para_a_tela
  end

  # POST seguros/:id/palavras/enviar
  def enviar
    corpo
    ::Carteira::Palavras::Enviar.new(@seguro, user: Current.user).call
    render json: conversa.para_a_tela
  end

  private

  def conversa
    ::Carteira::Palavras::Conversa.new(@seguro, user: Current.user)
  end

  def exigir_leitura
    return if ::Carteira::Leitor::Liberado.para?(Current.account)

    raise CustomExceptions::CarteiraRecusa, ::Carteira::Leitor::Resultado::DESLIGADA
  end
end
