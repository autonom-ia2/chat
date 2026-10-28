# Seus posts (#2302, F1 #2304): os posts de um perfil dos últimos HISTORICO_DIAS dias, com os números de cada um e o
# normal do perfil, para o veredito do post ("o dobro do normal"). Os números vêm junto com a lista, numa chamada por
# página de posts. A lista é a mesma para 7, 30 e 90 dias: SeusPosts::Leitura guarda uma vez e filtra pelo período.
#
# O normal tem janela fixa, que não muda com o período escolhido (rodada 9 do protótipo: em 7 dias a lista e o post
# divergiam): para cada número, os últimos NORMAL_POSTS posts com ele, sem o post que se sabe impulsionado. Número que
# a Meta não manda (post dentro de álbum, post apagado) é "sem número" (nil), e zero (post de hoje que ainda não
# apareceu) também fica fora: os dois puxariam a média para baixo e todo post pareceria acima do normal.
class SeusPosts::Posts < Crm::MetaAds::Organico::Lugar
  include SeusPosts::Orcamento

  HISTORICO_DIAS = 90
  NORMAL_POSTS = 30
  VIDA_TODA = 'lifetime'.freeze

  def self.para(canal, periodo:, prazo: nil)
    klass = canal.is_a?(Channel::Instagram) ? SeusPosts::PostsInstagram : SeusPosts::PostsPagina
    klass.new(channel: canal, periodo: periodo, prazo: prazo)
  end

  private

  def numeros
    @truncado = false
    todos = ler_posts(historico).sort_by { |post| post[:created_time].to_s }.reverse
    { status: 'ok', posts: todos, normal: normal(todos), truncated: @truncado }
  end

  def bloqueado
    { status: 'needs_permission' }
  end

  def historico
    ate = periodo.atual[:until]
    { since: ate - HISTORICO_DIAS.days.to_i, until: ate }
  end

  # Uma lista da Meta (organic_posts): os itens, e se ela parou no teto de posts lidos.
  def lista(result)
    dados = ler(result).to_h
    @truncado ||= dados['truncated'] == true
    Array(dados['data'])
  end

  def normal(todos)
    # O post que se sabe impulsionado (boosted true) fica fora; o que não se sabe (nil) entra.
    base = todos.reject { |post| post[:boosted] == true }
    self.class::COMPARAVEIS.index_with do |chave|
      valores = base.filter_map { |post| post[chave] if post[chave].to_i.positive? }.first(NORMAL_POSTS)
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
