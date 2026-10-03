# Decisor (#858): uma pergunta de múltipla escolha que a conta faz sobre cada conversa
# ("Este e-mail é um lead?"), respondida pelo Jev com uma certeza.
#
# A automação usa o Decisor como um passo (`perguntar_ao_decisor`): os passos seguintes só rodam
# quando ele responde a chave combinada com certeza suficiente. Os `campos` opcionais dizem o que
# tirar do texto e onde gravar (contato, empresa, card) quando a resposta é a que segue.
#
# Toda conferência de chave e de destino é por igualdade (`include?`, `start_with?`), nunca por
# expressão regular: quem entende o texto é o modelo, e aqui só se confere a lista fechada.
class Autonomia::Decisor < ApplicationRecord
  self.table_name = 'autonomia_decisores'

  RESPOSTAS = (2..8)
  MAX_EXEMPLOS = 30
  CERTEZA = (0.50..0.99)
  CERTEZA_PADRAO = 0.80
  MAX_CAMPOS = 10
  ORIGENS = %w[pessoa guia].freeze
  ATRIBUTO_DE_CONTATO = 'contato.atributo:'.freeze
  DESTINOS = %w[contato.nome contato.telefone contato.email empresa.nome card.titulo card.descricao].freeze
  # O que o Decisor guarda de cada exemplo: o bastante para o Jev reconhecer o caso, nunca a conversa inteira.
  MAX_TEXTO_DO_EXEMPLO = 1_500

  belongs_to :account
  has_many :decisoes, class_name: 'Autonomia::DecisorDecisao', inverse_of: :decisor, dependent: :delete_all

  before_validation :normalizar_listas

  validates :nome, presence: true, length: { maximum: 120 }, uniqueness: { scope: :account_id }
  validates :pergunta, presence: true, length: { maximum: 1_000 }
  validates :instrucoes, length: { maximum: 4_000 }
  validates :certeza_minima, numericality: { greater_than_or_equal_to: CERTEZA.min, less_than_or_equal_to: CERTEZA.max }
  validate :respostas_validas
  validate :exemplos_validos
  validate :campos_validos

  def chaves
    Array(respostas).map { |resposta| resposta['chave'].to_s }
  end

  def resposta?(chave)
    chaves.include?(chave.to_s)
  end

  # Guarda um exemplo confirmado. Os mais novos ficam: o teto de 30 descarta os mais antigos.
  def guardar_exemplo!(texto:, resposta:, origem:, decisao_id: nil)
    novo = { 'texto' => texto.to_s.first(MAX_TEXTO_DO_EXEMPLO), 'resposta' => resposta.to_s, 'origem' => origem.to_s,
             'decisao_id' => decisao_id, 'criado_em' => Time.current.iso8601 }.compact
    update!(exemplos: (Array(exemplos) + [novo]).last(MAX_EXEMPLOS))
  end

  def contadores
    { perguntas: perguntas_count, duvidas: duvidas_count, correcoes: correcoes_count, ultima_pergunta_em: ultima_pergunta_em }
  end

  private

  # Os campos jsonb chegam da API como hash de chave simbólica ou de texto; aqui viram sempre texto.
  def normalizar_listas
    self.respostas = textos(respostas)
    self.exemplos = textos(exemplos)
    self.campos = textos(campos)
  end

  def textos(lista)
    Array(lista).map { |item| item.is_a?(Hash) ? item.to_h.deep_stringify_keys : item }
  end

  def respostas_validas
    lista = Array(respostas)
    return errors.add(:respostas, "must have between #{RESPOSTAS.min} and #{RESPOSTAS.max} answers") unless RESPOSTAS.cover?(lista.size)
    return errors.add(:respostas, 'each answer needs chave and descricao') unless lista.all? { |item| item_completo?(item, %w[chave descricao]) }
    return if chaves.uniq.size == chaves.size

    errors.add(:respostas, 'chave must be unique')
  end

  def exemplos_validos
    lista = Array(exemplos)
    return errors.add(:exemplos, "must have at most #{MAX_EXEMPLOS} examples") if lista.size > MAX_EXEMPLOS
    return if lista.all? { |item| exemplo_valido?(item) }

    errors.add(:exemplos, "each example needs texto, a resposta from respostas and origem in #{ORIGENS.join(', ')}")
  end

  def exemplo_valido?(item)
    item_completo?(item, %w[texto resposta origem]) && resposta?(item['resposta']) && ORIGENS.include?(item['origem'].to_s)
  end

  def campos_validos
    lista = Array(campos)
    return errors.add(:campos, "must have at most #{MAX_CAMPOS} fields") if lista.size > MAX_CAMPOS
    return errors.add(:campos, 'each field needs chave, descricao and destino') unless lista.all? { |item| campo_completo?(item) }

    nomes = lista.map { |item| item['chave'].to_s }
    errors.add(:campos, 'chave must be unique') if nomes.uniq.size != nomes.size
    destinos_validos(lista)
  end

  def campo_completo?(item)
    item_completo?(item, %w[chave descricao destino])
  end

  def destinos_validos(lista)
    invalidos = lista.map { |item| item['destino'].to_s }.reject { |destino| destino_valido?(destino) }
    return if invalidos.empty?

    errors.add(:campos, "destino #{invalidos.join(', ')} not supported. Use one of: #{destinos_aceitos.join(', ')}")
  end

  def destino_valido?(destino)
    return DESTINOS.include?(destino) unless destino.start_with?(ATRIBUTO_DE_CONTATO)

    atributos_de_contato.include?(destino.delete_prefix(ATRIBUTO_DE_CONTATO))
  end

  def destinos_aceitos
    DESTINOS + atributos_de_contato.map { |chave| "#{ATRIBUTO_DE_CONTATO}#{chave}" }
  end

  def atributos_de_contato
    return [] if account.blank?

    @atributos_de_contato ||= account.custom_attribute_definitions.where(attribute_model: 'contact_attribute').pluck(:attribute_key)
  end

  def item_completo?(item, chaves_obrigatorias)
    item.is_a?(Hash) && chaves_obrigatorias.all? { |chave| item[chave].to_s.strip.present? }
  end
end
