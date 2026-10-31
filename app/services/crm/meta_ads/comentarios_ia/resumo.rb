# IA cuida dos comentários (#2212, A2): o bloco "O que tem nos comentários" do post e do anúncio. Conta, entre os
# comentários que esperam o dono (Fonte), quantos pedem informação (até 7 dias, que o privado ainda alcança, e mais
# velhos) e quantas são reclamações, para o dono decidir se liga a IA.
#
# - Quem decide é o Classificador, com um critério fixo no lugar do "para quem" do dono (ainda não há cuidado): pede
#   informação, preço ou como comprar o que o post mostra, com a legenda do post (Fonte#legenda, #2424). Nada de lista
#   de palavras.
# - Até LIMITE comentários, os mais recentes. Passou disso, `more: true`: a conta é "pelo menos".
# - A IA leva alguns segundos por comentário: a conta roda no ResumoJob e fica no cache só com os números (nunca o
#   texto), por CACHE. A chave leva os ids que esperam: quando a lista muda (alguém respondeu, chegou comentário), conta
#   de novo. Enquanto conta, `status: 'reading'`, e a tela pergunta de novo.
# - IA fora do ar não é "nenhum pedido": a conta para no primeiro erro, nada vai para o cache como pronto e a tela
#   recebe `ai_unavailable` uma vez (FALHOU); a pergunta seguinte conta de novo.
class Crm::MetaAds::ComentariosIa::Resumo
  LIMITE = 30
  CACHE = 1.hour
  # O teto do job: uma chamada à IA por comentário, sem nova tentativa, até o prazo do Classificador. A trava de um job
  # só por lista não pode vencer antes dele.
  POR_COMENTARIO = Crm::MetaAds::ComentariosIa::Classificador::PRAZO
  CONTANDO = ((LIMITE * POR_COMENTARIO) + 60).seconds
  # Quanto o aviso "IA fora do ar" espera a tela perguntar: lido uma vez, ele sai e a próxima pergunta conta de novo.
  FALHOU = 10.minutes
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
    Rails.cache.read(chave) || falhou(chave) || contar_depois(chave)
  end

  # No ResumoJob: lê de novo e grava a conta no cache.
  def contar!
    lido = @fonte&.ler || {}
    return unless lido[:status] == 'ready'

    linhas = recentes(lido[:linhas])
    chave = chave(linhas)
    Rails.cache.write(chave, contar(linhas, more: lido[:linhas].size > LIMITE), expires_in: CACHE)
  rescue Crm::MetaAds::ComentariosIa::Classificador::Erro => e
    Rails.logger.warn("[comentarios_ia] resumo account=#{@account.id} ia=#{e.code}")
    Rails.cache.write("#{chave}:falhou", 1, expires_in: FALHOU)
    Rails.cache.delete("#{chave}:contando")
  end

  private

  # O aviso sai na primeira leitura: a tela mostra a falha e o "tentar de novo" conta outra vez.
  def falhou(chave)
    return unless Rails.cache.delete("#{chave}:falhou")

    { status: 'ai_unavailable' }
  end

  def contar_depois(chave)
    # Um job só por lista: a tela pergunta de novo a cada poucos segundos enquanto conta.
    primeiro = Rails.cache.write("#{chave}:contando", 1, unless_exist: true, expires_in: CONTANDO)
    Crm::MetaAds::ComentariosIa::ResumoJob.perform_later(@account.id, @alvo) if primeiro
    { status: 'reading' }
  end

  def contar(linhas, more:)
    contagem = { status: 'ready', questions: 0, questions_old: 0, complaints: 0, read: linhas.size, more: more }
    linhas.each do |linha|
      decisao = classificador.decidir!(linha[:text])
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
      care: Crm::MetaAdsCommentCare.new(account: @account, para_quem: CRITERIO), legenda: @fonte.legenda, tela: true
    )
  end
end
