# IA cuida dos comentários (#2212, A2): os exemplos do passo "como fica" da tela do dono (CuidarDono). Com o "para
# quem" que o dono escreveu, a IA lê alguns comentários do post que esperam resposta e mostra um que receberia o
# privado e um em que "aqui não se aplica". É a mesma decisão que o motor vai tomar depois (Classificador), não um
# palpite da tela.
#
# - Lê até LIMITE comentários, os mais recentes (a Fonte já os ordena), e para assim que tem os dois exemplos.
# - Sem comentário que receberia, `recebe: { sample: true }`: a tela mostra um exemplo dito como exemplo, nunca um
#   comentário inventado como real. Sem exemplo de "não se aplica", `nao: nil`.
# - O texto dos exemplos vai só na resposta à tela (dado de terceiro, lido ao vivo); nada é gravado.
# - Jev fora do ar: `status: 'ai_unavailable'`, nunca uma prévia vazia que pareceria "ninguém recebe".
class Crm::MetaAds::ComentariosIa::Previa
  LIMITE = 10
  RECEBE = %w[private price].freeze
  NAO_SE_APLICA = %w[no_reply].freeze
  AMOSTRA = { sample: true }.freeze

  def initialize(account:, fonte:, para_quem:)
    @account = account
    @fonte = fonte
    @para_quem = para_quem.to_s.strip
  end

  def call
    lido = @fonte.ler
    return { status: lido[:status] } unless lido[:status] == 'ready'

    exemplos(lido[:linhas].first(LIMITE))
  rescue TypesafeAi::Decisor::Error => e
    Rails.logger.warn("[comentarios_ia] previa account=#{@account.id} jev=#{e.code}")
    { status: 'ai_unavailable' }
  end

  private

  def exemplos(linhas)
    achados = {}
    linhas.each do |linha|
      break if achados.key?(:recebe) && achados.key?(:nao)

      tipo = tipo(classificador.decidir!(linha[:text]))
      achados[tipo] ||= exemplo(linha) if tipo
    end
    { status: 'ready', recebe: achados[:recebe] || AMOSTRA, nao: achados[:nao] }
  end

  def tipo(decisao)
    return :recebe if RECEBE.include?(decisao)

    :nao if NAO_SE_APLICA.include?(decisao)
  end

  def exemplo(linha)
    { author: linha[:author], text: linha[:text], network: linha[:network] }
  end

  def classificador
    @classificador ||= Crm::MetaAds::ComentariosIa::Classificador.new(
      care: Crm::MetaAdsCommentCare.new(account: @account, para_quem: @para_quem), tela: true
    )
  end
end
