# O pedaço de uma conversa que a IA lê na revisão (#3158, B8b), portado do `Captain::Copilot::ReviewService`.
#
# Uma conversa longa é lida pelas pontas: as 3 primeiras mensagens dizem por que o cliente chamou, e as 5 últimas,
# como ficou. As 8 dividem 12 mil caracteres, da mais curta para a mais longa: um log colado não toma o espaço das
# outras, e a mensagem cortada guarda o começo e o fim.
#
# Entram as mensagens do cliente e da equipe (e do robô). Ficam de fora as notas privadas (decisão do desenho do
# B8b), as encaminhadas e as apagadas. E-mail e telefone saem pela `Revisoes::Mascara`.
class Autonomia::Guide::Revisoes::Leitor
  PRIMEIRAS = 3
  ULTIMAS = 5
  CARACTERES = 12_000
  PAPEIS = { 'Contact' => 'cliente', 'User' => 'equipe' }.freeze

  def initialize(conversa)
    @conversa = conversa
    contato = conversa.contact
    @mascara = ::Autonomia::Guide::Revisoes::Mascara.new(literais: [contato&.email, contato&.phone_number].compact)
  end

  def call
    mensagens, omitidas = janela
    textos = mensagens.map { |mensagem| @mascara.call(mensagem.content.to_s) }
    trechos = textos.zip(partes(textos.map(&:size))).map { |texto, parte| trecho(texto, parte) }
    { status: @conversa.status, mensagens_omitidas: omitidas,
      mensagens: mensagens.zip(trechos).map { |mensagem, texto| { id: mensagem.id, de: papel(mensagem), texto: texto } } }
  end

  def vazia?
    legiveis.none?
  end

  private

  def legiveis
    escopo = @conversa.messages.where(message_type: %w[incoming outgoing], private: false).not_forwarded
    escopo.respond_to?(:not_deleted) ? escopo.not_deleted : escopo
  end

  # `reorder`, porque o escopo padrão de Message já ordena da mais antiga.
  def janela
    primeiras = legiveis.reorder(created_at: :asc, id: :asc).limit(PRIMEIRAS).to_a
    ultimas = legiveis.reorder(created_at: :desc, id: :desc).limit(ULTIMAS).to_a.reverse
    mensagens = (primeiras + ultimas).uniq(&:id)
    [mensagens, legiveis.count - mensagens.size]
  end

  # Cada mensagem fica com o tamanho dela ou com a parte igual do que sobra, da mais curta para a mais longa.
  def partes(tamanhos)
    restante = CARACTERES
    partes = Array.new(tamanhos.size)
    tamanhos.each_with_index.sort_by(&:first).each_with_index do |(tamanho, indice), posicao|
      partes[indice] = [tamanho, restante / (tamanhos.size - posicao)].min
      restante -= partes[indice]
    end
    partes
  end

  def trecho(texto, limite)
    return texto if texto.size <= limite

    metade = limite / 2
    "#{texto.first(metade)}\n[... #{texto.size - (2 * metade)} caracteres cortados ...]\n#{texto.last(metade)}"
  end

  def papel(mensagem)
    PAPEIS.fetch(mensagem.sender_type.to_s) { mensagem.sender_type ? 'robô' : 'sistema' }
  end
end
