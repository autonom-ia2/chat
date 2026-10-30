# IA cuida dos comentários (#2212, A2): o bloco "O que tem nos comentários" do post e do anúncio. Conta, entre os
# comentários que esperam o dono (Fonte), quantos pedem informação (até 7 dias, que o privado ainda alcança, e mais
# velhos) e quantas são reclamações, para o dono decidir se liga a IA.
#
# - Quem decide é o Classificador, com um critério fixo no lugar do "para quem" do dono (ainda não há cuidado): pede
#   informação, preço ou como comprar o que o post mostra. Nada de lista de palavras.
# - Até LIMITE comentários, os mais recentes. Passou disso, `more: true`: a conta é "pelo menos".
# - O Jev leva alguns segundos por lista: a conta roda no ResumoJob e fica no cache só com os números (nunca o texto),
#   por CACHE. A chave leva os ids que esperam: quando a lista muda (alguém respondeu, chegou comentário), conta de novo.
#   Enquanto conta, `status: 'reading'`, e a tela pergunta de novo.
class Crm::MetaAds::ComentariosIa::Resumo
  LIMITE = 30
  CACHE = 1.hour
  CONTANDO = 2.minutes
  CRITERIO = 'Anyone who asks for information about what the post shows, its price, or how to get or buy it.'.freeze
  PEDIDOS = %w[private price].freeze

  # alvo: os ids que o ResumoJob precisa para ler de novo, sem nada do comentário (Fonte.do_alvo).
  def initialize(account:, alvo:, fonte: nil)
    @account = account
    @alvo = alvo.to_h.stringify_keys
    @fonte = fonte || Crm::MetaAds::ComentariosIa::Fonte.do_alvo(account, @alvo)
  end

  def call
    return { status: 'not_found' } if @fonte.nil?

    lido = @fonte.ler
    return { status: lido[:status] } unless lido[:status] == 'ready'

    linhas = recentes(lido[:linhas])
    chave = chave(linhas)
    Rails.cache.read(chave) || contar_depois(chave)
  end

  # No ResumoJob: lê de novo e grava a conta no cache.
  def contar!
    lido = @fonte&.ler || {}
    return unless lido[:status] == 'ready'

    linhas = recentes(lido[:linhas])
    Rails.cache.write(chave(linhas), contar(linhas, more: lido[:linhas].size > LIMITE), expires_in: CACHE)
  end

  private

  def contar_depois(chave)
    # Um job só por lista: a tela pergunta de novo a cada poucos segundos enquanto conta.
    primeiro = Rails.cache.write("#{chave}:contando", 1, unless_exist: true, expires_in: CONTANDO)
    Crm::MetaAds::ComentariosIa::ResumoJob.perform_later(@account.id, @alvo) if primeiro
    { status: 'reading' }
  end

  def contar(linhas, more:)
    contagem = { status: 'ready', questions: 0, questions_old: 0, complaints: 0, read: linhas.size, more: more }
    linhas.each do |linha|
      decisao = classificador.decidir(linha[:text])
      if PEDIDOS.include?(decisao)
        contagem[recente?(linha) ? :questions : :questions_old] += 1
      elsif decisao == 'to_you'
        contagem[:complaints] += 1
      end
    end
    contagem
  end

  # A Fonte já entrega do mais novo para o mais velho.
  def recentes(linhas)
    linhas.first(LIMITE)
  end

  def recente?(linha)
    linha[:momento]&.>=(Crm::MetaAds::ComentariosIa::Cuidar::JANELA.ago)
  end

  def chave(linhas)
    ids = linhas.map { |linha| "#{linha[:network]}:#{linha[:id]}" }.sort.join(',')
    "comentarios_ia:resumo:#{@account.id}:#{@alvo.values.flatten.join(':')}:#{Digest::SHA256.hexdigest(ids)}"
  end

  def classificador
    @classificador ||= Crm::MetaAds::ComentariosIa::Classificador.new(
      care: Crm::MetaAdsCommentCare.new(account: @account, para_quem: CRITERIO)
    )
  end
end
