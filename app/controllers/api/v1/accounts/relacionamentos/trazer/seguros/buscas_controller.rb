# Trazer os seguros pelo Agger (E7, #2900): começar a busca e o interruptor "Buscar novos seguros todo dia". Acompanhar,
# conferir, trazer, buscar de novo, o histórico e o desfazer são as rotas das leituras (LeiturasController), as mesmas
# dos PDFs. Pede a carteira, a chave de Relacionamentos e a permissão de trazer contatos (BaseController), e a conta
# precisa poder trazer pelo Agger (Carteira::Conector.disponivel?): sem isso, `agger_desligado`. O login do Agger não
# passa por aqui: é a conexão da Cotação (POST autonomia/insurance/connection), uma só por conta.
class Api::V1::Accounts::Relacionamentos::Trazer::Seguros::BuscasController < Api::V1::Accounts::Relacionamentos::Trazer::Seguros::BaseController
  before_action :exigir_agger

  # POST trazer/seguros/busca → { leituraId }. Enquanto uma busca da conta anda, devolve a mesma.
  def create
    corpo
    busca = ::Carteira::Conector::Sincronizar.primeira(Current.account, user: Current.user)
    render json: { leituraId: busca.id }, status: :created
  end

  # GET trazer/seguros/busca_diaria → { ligado, jaTrouxe }. `jaTrouxe`: a conta já trouxe uma busca do Agger; antes disso
  # a tela não mostra o interruptor.
  def busca_diaria
    sem_parametros
    diaria = ::Carteira::Conector::BuscaDiaria.new(Current.account)
    render json: { ligado: diaria.ligada?, jaTrouxe: diaria.ja_trouxe? }
  end

  # PUT trazer/seguros/busca_diaria { ligado } → { ligado }
  def mudar_busca_diaria
    ligado = corpo(:ligado)['ligado']
    recusar('ligado') unless [true, false].include?(ligado)

    render json: { ligado: ::Carteira::Conector::BuscaDiaria.new(Current.account).mudar!(ligado) }
  end

  private

  def exigir_agger
    raise CustomExceptions::CarteiraRecusa, ::Carteira::Conector::Sincronizar::DESLIGADO unless ::Carteira::Conector.disponivel?(Current.account)
  end
end
