# "Criar com IA" e "Melhorar com IA" da tela de Modelos do WhatsApp (#1333, épico #1320). Pede ao redator compartilhado
# (`Ai::Redacao::Escrever`, canal `whatsapp_modelo`) e devolve as opções que passaram na conferência dele. Nada é salvo
# nem enviado à Meta: a pessoa escolhe, a tela confere de novo (`regraEstrutural.js`/`conferirConteudo`) e o envio
# segue o caminho normal (`SubmitFormat` no `Manager`).
#
#   Whatsapp::Templates::Redacao.new(account:).criar(objetivo: 'lembrar do horário de amanhã', tom: 'simpatico')
#   Whatsapp::Templates::Redacao.new(account:).melhorar(texto: 'Oi, {{cliente.primeiro_nome}}! ...',
#                                                       melhorias: %w[mais_curto], tipo: 'aviso')
#   # => { status:, pergunta:, sugestoes:, opcoes: [{ texto:, categoria_prevista:, ..., whatsapp: { ... } }] }
#
# Campos que a IA pode usar: os que uma campanha com Público preenche sozinha (cliente, minha empresa) e os campos da
# tela (data, horário, valor, desconto, link, código), que a campanha liga a uma coluna da planilha: no catálogo,
# `publico.<campo>`, com o tipo de cada um. No "melhorar", os campos do catálogo que o texto já usa também valem.
# Entra só o que a pessoa escreveu (objetivo ou texto, como dado) e o catálogo com exemplo fictício: nunca dado de
# cliente. Erros da IA viram `Ai::Redacao::Escrever::Indisponivel`; entrada fora do formato, `Invalida`.
class Whatsapp::Templates::Redacao
  class Invalida < StandardError; end

  FEATURE = 'modelo_redacao'.freeze
  TONS = %w[curto simpatico formal].freeze
  # Tamanho do corpo por tom, o mesmo da bateria (escolha de produto, leitura no celular). O teto da Meta é 1024.
  MAX_CHARS = { 'curto' => 200, 'simpatico' => 350, 'formal' => 450 }.freeze
  MAX_CHARS_SEM_TOM = 450
  MELHORIAS = %w[mais_curto mais_claro manter_como_servico corrigir_recusa].freeze
  CATEGORIAS = { 'aviso' => 'servico', 'divulgacao' => 'divulgacao' }.freeze
  OPCOES = { criar: 3, melhorar: 2 }.freeze
  PROPOSITOS = { criar: 'criar um modelo de mensagem do WhatsApp', melhorar: 'melhorar um modelo de mensagem do WhatsApp' }.freeze
  OBJETIVO_MAXIMO = 300
  TEXTO_MAXIMO = 1024
  MOTIVO_MAXIMO = 120
  FIXAS = %w[cliente.primeiro_nome cliente.nome minha_empresa.nome minha_empresa.telefone minha_empresa.site].freeze
  # Os campos da tela e o tipo de cada um (o que vira formato e exemplo para a IA).
  COLUNAS = { 'data' => 'data', 'horario' => 'hora', 'valor' => 'moeda', 'desconto' => 'texto', 'link' => 'link',
              'codigo' => 'texto' }.freeze

  def initialize(account:)
    @account = account
  end

  def criar(objetivo:, tom: nil, tipo: nil)
    objetivo = objetivo.to_s.strip
    raise Invalida, 'objetivo' if objetivo.empty? || objetivo.length > OBJETIVO_MAXIMO

    escrever(pedido: objetivo, tom: tom, tipo: tipo, permitidas: permitidas)
  end

  def melhorar(texto:, melhorias:, tom: nil, tipo: nil, recusa: nil)
    texto = texto.to_s
    melhorias = Array(melhorias).map(&:to_s).uniq
    raise Invalida, 'melhorias' if melhorias.empty? || !(melhorias - MELHORIAS).empty?

    pedido = { melhorias: melhorias, observacao: nil, recusa_da_meta: recusa.present? ? { motivo: recusa.to_s.first(MOTIVO_MAXIMO) } : nil }
    escrever(pedido: pedido, base: texto, tom: tom, tipo: tipo, permitidas: permitidas | chaves_do_texto(texto))
  end

  private

  # `base` preenchida é o "melhorar".
  def escrever(pedido:, tom:, tipo:, permitidas:, base: nil)
    tom = TONS.include?(tom.to_s) ? tom.to_s : nil
    modo = base.nil? ? :criar : :melhorar
    Ai::Redacao::Escrever.call(
      account: @account, feature: FEATURE, canal: 'whatsapp_modelo', proposito: PROPOSITOS[modo], pedido: pedido, base: base,
      tom: tom, opcoes: OPCOES[modo], colunas: COLUNAS, chaves: { permitidas: permitidas, obrigatorias: [] },
      limites: { max_chars: MAX_CHARS.fetch(tom, MAX_CHARS_SEM_TOM), categoria_desejada: CATEGORIAS[tipo.to_s], sem_midia: true }
    )
  end

  def permitidas
    FIXAS + COLUNAS.keys.map { |coluna| TemplateFields::Catalog.audience_key(coluna) }
  end

  # O texto da pessoa: até 1024, chaves bem escritas e todas do catálogo (as da tela já chegam como chave).
  def chaves_do_texto(texto)
    raise Invalida, 'texto' if texto.strip.empty? || texto.length > TEXTO_MAXIMO || Ai::Redacao::Chaves.malformado?(texto)

    chaves = Ai::Redacao::Chaves.extrair(texto).uniq
    raise Invalida, 'texto' unless chaves.all? { |chave| TemplateFields::Catalog.known?(chave) && chave != TemplateFields::Catalog::FIXED }

    chaves
  end
end
