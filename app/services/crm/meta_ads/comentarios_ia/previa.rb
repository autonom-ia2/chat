# IA cuida dos comentários (#2212, A2): os exemplos do passo "como fica" da tela do dono (CuidarDono). Com o "para
# quem" que o dono escreveu, a IA lê alguns comentários do post que esperam resposta e mostra um que receberia o
# privado e um em que "aqui não se aplica". É a mesma decisão que o motor vai tomar depois (Classificador), não um
# palpite da tela.
#
# - Lê até LIMITE comentários, os mais recentes (a Fonte já os ordena), e para assim que tem os dois exemplos.
# - Sem comentário que receberia, `recebe: { sample: true }`: a tela mostra um exemplo dito como exemplo, nunca um
#   comentário inventado como real. Sem exemplo de "não se aplica", `nao: nil`.
# - O texto dos exemplos vai só na resposta à tela (dado de terceiro, lido ao vivo); nada é gravado.
# - A legenda do post (#2424), lida pela Fonte, vai ao Classificador como no motor.
# - A foto (#2454) é a leitura do post da rede de cada comentário, como no motor: no anúncio que roda no Instagram e no
#   Facebook, cada comentário decide com a foto do post da própria rede (nil quando aquela rede ainda não tem leitura).
# - IA fora do ar: `status: 'ai_unavailable'`, nunca uma prévia vazia que pareceria "ninguém recebe".
# - Com a flag meta_ads_comentarios_ia_conversa (#2454), também `resposta`: a primeira resposta de outra pessoa dentro
#   de um dos comentários lidos, decidida com o de cima (como o motor faz), com o `kind` ('recebe' ou 'nao') e o
#   comentário de cima em `parent`. nil quando não há resposta ou a decisão não é nenhuma das duas. A tela não promete
#   o privado a ela: a Meta decide se aceita o privado em resposta.
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

    linhas = lido[:linhas].first(LIMITE)
    previa = exemplos(linhas)
    conversa? ? previa.merge(resposta: resposta(linhas)) : previa
  rescue Crm::MetaAds::ComentariosIa::Classificador::Erro => e
    Rails.logger.warn("[comentarios_ia] previa account=#{@account.id} ia=#{e.code}")
    { status: 'ai_unavailable' }
  end

  private

  def exemplos(linhas)
    achados = {}
    linhas.each do |linha|
      break if achados.key?(:recebe) && achados.key?(:nao)

      tipo = tipo(classificador(linha).decidir!(linha[:text]))
      achados[tipo] ||= exemplo(linha) if tipo
    end
    { status: 'ready', recebe: achados[:recebe] || AMOSTRA, nao: achados[:nao] }
  end

  def conversa?
    @account.feature_enabled?(Crm::MetaAds::ComentariosIa::Cuidar::CONVERSA)
  end

  def resposta(linhas)
    linha = linhas.find { |candidata| candidata[:respostas].present? }
    return if linha.nil?

    resposta = linha[:respostas].first
    tipo = tipo(classificador(linha).decidir!(resposta[:text], pai: linha[:text]))
    tipo && { author: resposta[:author], text: resposta[:text], network: linha[:network], kind: tipo.to_s, parent: exemplo(linha) }
  end

  def tipo(decisao)
    return :recebe if RECEBE.include?(decisao)

    :nao if NAO_SE_APLICA.include?(decisao)
  end

  def exemplo(linha)
    { author: linha[:author], text: linha[:text], network: linha[:network] }
  end

  # Um por post (rede e id), para cada comentário decidir com a foto do próprio post.
  def classificador(linha)
    @classificadores ||= {}
    @classificadores[[linha[:network], linha[:post_id]]] ||= Crm::MetaAds::ComentariosIa::Classificador.new(
      care: care, legenda: @fonte.legenda, tela: true,
      foto: Crm::MetaAds::ComentariosIa::Foto.texto_para_ia(@account, linha[:network], linha[:post_id])
    )
  end

  def care
    @care ||= Crm::MetaAdsCommentCare.new(account: @account, para_quem: @para_quem)
  end
end
