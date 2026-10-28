# Seus posts (#2302, F1 #2304): os posts de um perfil com os números de cada um e o normal do perfil, para o veredito
# do post ("o dobro do normal"). Os números vêm junto com a lista, numa chamada por página de posts.
#
# O normal tem janela fixa, que não muda com o período escolhido (rodada 9 do protótipo: em 7 dias a lista e o post
# divergiam): os últimos NORMAL_POSTS posts dos últimos HISTORICO_DIAS dias, sem o post impulsionado. Número que a
# Meta não manda (post dentro de álbum, post apagado) é "sem número" (nil), nunca 0: um 0 puxaria a média para baixo e
# todo post pareceria acima do normal.
class SeusPosts::Posts < Crm::MetaAds::Organico::Lugar
  HISTORICO_DIAS = 90
  NORMAL_POSTS = 30
  VIDA_TODA = 'lifetime'.freeze

  def self.para(canal, periodo:)
    klass = canal.is_a?(Channel::Instagram) ? SeusPosts::PostsInstagram : SeusPosts::PostsPagina
    klass.new(channel: canal, periodo: periodo)
  end

  private

  def numeros
    todos = ler_posts(historico).sort_by { |post| post[:created_time].to_s }.reverse
    inicio = periodo.atual[:since]
    { status: 'ok', posts: todos.select { |post| Time.zone.parse(post[:created_time].to_s).to_i >= inicio },
      normal: normal(todos) }
  end

  def bloqueado
    { status: 'needs_permission' }
  end

  def historico
    ate = periodo.atual[:until]
    { since: ate - HISTORICO_DIAS.days.to_i, until: ate }
  end

  def normal(todos)
    # Só o post que se sabe sem anúncio (boosted false); o que não se sabe (nil) também fica fora.
    base = todos.select { |post| post[:boosted] == false }.first(NORMAL_POSTS)
    self.class::COMPARAVEIS.index_with do |chave|
      valores = base.filter_map { |post| post[chave] }
      valores.empty? ? nil : (valores.sum.to_f / valores.size).round
    end
  end

  # Os números de um post (insights.data), só os da vida toda do post: { 'views' => 120, ... }.
  def da_vida_toda(insights)
    Array(insights.to_h['data']).each_with_object({}) do |metrica, numeros|
      next unless metrica['period'] == VIDA_TODA

      valor = Array(metrica['values']).first&.dig('value')
      numeros[metrica['name']] = valor if valor.is_a?(Numeric)
    end
  end
end
