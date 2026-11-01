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
# - Também `resposta` (#2454): a primeira resposta de outra pessoa dentro
#   de um dos comentários lidos, decidida com o de cima (como o motor faz), com o `kind` ('recebe' ou 'nao') e o
#   comentário de cima em `parent`. nil quando não há resposta ou a decisão não é nenhuma das duas. A tela não promete
#   o privado a ela: a Meta decide se aceita o privado em resposta. Cada exemplo leva também o `id` do
#   comentário: a tela põe a resposta dentro do cartão do comentário de cima quando ele é um dos exemplos.
# - #2458: o exemplo que recebe leva o que a IA escreveria para ele
#   (`written: { dm:, comment: }`, Escrita#textos, a mesma do motor; `comment` nil quando vale o preço do dono), ou
#   `kept_for_owner: true` quando o agente não saberia responder. Nas frases fixas (sem agente que possa escrever),
#   nenhum dos dois: a tela mostra a mensagem e a frase do dono. O assunto proibido do dono (`assunto_proibido`) dá o
#   exemplo `dono`: um comentário que ficaria com ele. O que o dono escreveu antes (ficha, nota, mensagem) vem do
#   cuidado gravado (`base`).
class Crm::MetaAds::ComentariosIa::Previa
  LIMITE = 10
  RECEBE = %w[private price].freeze
  NAO_SE_APLICA = %w[no_reply].freeze
  AMOSTRA = { sample: true }.freeze

  # base: o cuidado gravado (ou nil). escrita: { assunto_proibido:, tom: }, o que o dono escreveu agora no passo 2, só
  # com a escrita.
  def initialize(account:, fonte:, para_quem:, base: nil, escrita: {})
    @account = account
    @fonte = fonte
    @para_quem = para_quem.to_s.strip
    @base = base
    @escrita = escrita.slice(:assunto_proibido, :tom).transform_values { |valor| valor.to_s.strip.presence }
  end

  def call
    lido = @fonte.ler
    return { status: lido[:status] } unless lido[:status] == 'ready'

    linhas = lido[:linhas].first(LIMITE)
    previa = exemplos(linhas)
    previa.merge(resposta: resposta(linhas))
  rescue Crm::MetaAds::ComentariosIa::Classificador::Erro => e
    Rails.logger.warn("[comentarios_ia] previa account=#{@account.id} ia=#{e.code}")
    { status: 'ai_unavailable' }
  end

  private

  def exemplos(linhas)
    achados = {}
    linhas.each do |linha|
      break if completos?(achados)

      anotar(achados, linha)
    end
    previa = { status: 'ready', recebe: achados[:recebe] || AMOSTRA, nao: achados[:nao] }
    escreve? ? previa.merge(dono: achados[:dono]) : previa
  end

  # Com a escrita e o assunto proibido, a prévia também procura um comentário sobre ele, até o LIMITE.
  def completos?(achados)
    return false unless achados.key?(:recebe) && achados.key?(:nao)

    achados.key?(:dono) || !escreve? || care.assunto_proibido.blank?
  end

  # O primeiro comentário de cada tipo vira o exemplo.
  def anotar(achados, linha)
    decisao = classificador(linha).decidir!(linha[:text])
    tipo = tipo(decisao)
    return if tipo.nil? || achados.key?(tipo)

    achados[tipo] = tipo == :recebe ? com_a_escrita(exemplo(linha), linha, decisao) : exemplo(linha)
  end

  # #2458: o que a IA escreveria para o comentário que recebe, como o motor.
  def com_a_escrita(exemplo, linha, decisao)
    return exemplo unless escreve?

    textos = escrita(linha).textos(decisao, comentario: linha[:text])
    return exemplo.merge(kept_for_owner: true) if textos.key?(:dono)
    return exemplo if textos.empty?

    exemplo.merge(written: { dm: textos[:privado], comment: textos[:publico] })
  end

  def escrita(linha)
    Crm::MetaAds::ComentariosIa::Escrita.new(
      care: care, inbox: Inbox.find_by(id: linha[:inbox_id], account_id: @account.id), legenda: @fonte.legenda,
      foto: Crm::MetaAds::ComentariosIa::Foto.texto_para_ia(@account, linha[:network], linha[:post_id])
    )
  end

  def escreve?
    return @escreve if defined?(@escreve)

    @escreve = Crm::MetaAds::ComentariosIa::Escrita.ligada?(@account)
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
    return :dono if decisao == Crm::MetaAds::ComentariosIa::Classificador::DONO

    :nao if NAO_SE_APLICA.include?(decisao)
  end

  def exemplo(linha)
    { id: linha[:id].to_s, author: linha[:author], text: linha[:text], network: linha[:network] }
  end

  # Um por post (rede e id), para cada comentário decidir com a foto do próprio post.
  def classificador(linha)
    @classificadores ||= {}
    @classificadores[[linha[:network], linha[:post_id]]] ||= Crm::MetaAds::ComentariosIa::Classificador.new(
      care: care, legenda: @fonte.legenda, tela: true,
      foto: Crm::MetaAds::ComentariosIa::Foto.texto_para_ia(@account, linha[:network], linha[:post_id])
    )
  end

  # Com a escrita, o que o dono já escreveu (ficha, nota, mensagem, preço) e o que escreveu agora no passo 2.
  def care
    @care ||= Crm::MetaAdsCommentCare.new(account: @account, para_quem: @para_quem, **do_dono)
  end

  def do_dono
    return {} unless escreve?

    gravado = @base&.slice(:offer, :note, :message, :price_reply, :phrases).to_h.symbolize_keys
    gravado.merge(assunto_proibido: @escrita[:assunto_proibido], tom: @escrita[:tom])
  end
end
