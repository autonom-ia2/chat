# IA cuida dos comentários (#2212): o que fazer com um comentário, perguntado ao Jev (o mesmo do Decisor, #858) com as
# cinco decisões da tela — mandar no privado, responder o preço, passar para a pessoa, esconder ou não responder.
#
# O Jev lê a ficha que a pessoa aprovou e a correção dela (instruções) e o comentário como texto solto: o Estado manda o
# modelo tratar o texto como dado, nunca como ordem. Nada é guardado como exemplo. O custo é nosso e fica em
# Crm::AiUsageEvent com a feature própria, para o teto medido no eval.
#
# Sem certeza suficiente, ou com o Jev fora do ar, não decide: o comentário fica para a pessoa, sem resposta da IA.
class Crm::MetaAds::ComentariosIa::Classificador
  FEATURE = 'meta_ads_comentarios_ia'.freeze
  CERTEZA_MINIMA = 0.7
  DECISOES = {
    'private' => 'The person asks for information about what the post offers (details, how to buy, availability, ' \
                 'interest). They should get a private message.',
    'price' => 'The person asks the price or how much it costs.',
    'to_you' => 'A complaint, a problem with a purchase or service, an angry customer, or anything a person on the team ' \
                'must answer. Never answered automatically.',
    'hide' => 'Spam, scam or advertising of something else. Never hide criticism, rudeness or a complaint about the ' \
              'business: that is to_you.',
    'no_reply' => 'Tagging a friend, praise, an emoji or anything that needs no reply.'
  }.freeze
  PERGUNTA = 'What should be done with this comment left on a social media post?'.freeze

  def initialize(care:, jev: TypesafeAi::Decisor.new(feature: FEATURE))
    @care = care
    @jev = jev
  end

  # A chave da decisão ('private', 'price', 'to_you', 'hide', 'no_reply') ou nil.
  def decidir(texto)
    return if texto.to_s.strip.empty?

    resultado = @jev.decidir(decisor: decisor, estado: Autonomia::Decisores::Estado.new(texto: texto, leituras: []))
    resultado.resposta if resultado.certeza >= CERTEZA_MINIMA
  rescue TypesafeAi::Decisor::Error => e
    Rails.logger.warn("[comentarios_ia] care=#{@care.id} jev=#{e.code}")
    nil
  end

  private

  def decisor
    @decisor ||= Autonomia::Decisor.new(account: @care.account, nome: FEATURE, pergunta: PERGUNTA, instrucoes: instrucoes,
                                        respostas: DECISOES.map { |chave, descricao| { 'chave' => chave, 'descricao' => descricao } })
  end

  def instrucoes
    [ficha, @care.note.presence && "The owner also said: #{@care.note}"].compact.join("\n")
  end

  def ficha
    return 'This post does not offer a product: never choose private or price.' unless @care.offer?

    oferta = @care.offer
    ["The post offers: #{oferta['offer']}.", oferta['price'].presence && "Price: #{oferta['price']}.",
     oferta['how'].presence && "How to buy: #{oferta['how']}."].compact.join(' ')
  end
end
