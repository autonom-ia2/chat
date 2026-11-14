# "Trazer minha lista" (#2896): quem entra como cliente. O código não interpreta o que está escrito na célula: quem diz
# quais valores querem dizer cliente é a pessoa, na pergunta "Quais destes querem dizer cliente?"
# (Relacionamentos::Trazer::Perguntas). Sem a escolha dela ninguém é marcado.
#
# - "sim, todas": todo mundo da lista;
# - modo `preenchidas`: toda linha com algo escrito na coluna que diz quem é cliente;
# - modo `valores`: a linha cuja célula tem um dos valores escolhidos.
#
# A escolha fica guardada só com o modo e as chaves (options['trazer']['respostas']['valores_cliente']), nunca com o
# texto da célula. A `chave` de um valor é o resumo dele com um segredo derivado do `secret_key_base`: não dá para
# voltar dela ao texto nem para refazê-la sem o segredo. O resumo leva junto o id da importação e o índice da coluna:
# o mesmo texto tem outra chave noutra importação e noutra coluna, então nenhuma conta serve de dicionário para outra
# e a chave de uma coluna não vale em outra. Antes do resumo o valor é agrupado: sem espaço nas pontas, com um espaço
# só entre as palavras (o espaço que não quebra linha, comum no que vem do Excel, é espaço) e sem diferença de
# maiúscula. Isso é formato, não interpretação: acento e qualquer palavra a mais fazem outro valor.
#
# A mesma regra serve à gravação (ContactImports::Trazer::DestinosDaLinha), aos exemplos da tela e à conta de quantas
# pessoas entram como clientes (`quantas`).
class ContactImports::Trazer::Cliente
  PREENCHIDAS = 'preenchidas'.freeze
  VALORES = 'valores'.freeze
  MODOS = [PREENCHIDAS, VALORES].freeze
  RESPOSTA = 'valores_cliente'.freeze
  DESTINO = 'cliente'.freeze
  SAL = 'contact_imports/trazer/valores_cliente'.freeze
  # Entre o id da importação, o índice da coluna e o valor: os dois primeiros são números inteiros, e o valor vem por
  # último, então nenhuma combinação se confunde com outra.
  SEPARADOR = "\0".freeze

  def self.agrupado(valor)
    valor.to_s.unicode_normalize(:nfc).squish.downcase
  end

  # coluna: o índice da coluna na planilha.
  def self.chave(importacao_id, coluna, valor)
    OpenSSL::HMAC.hexdigest('SHA256', segredo, [Integer(importacao_id), Integer(coluna), agrupado(valor)].join(SEPARADOR))
  end

  def self.segredo
    @segredo ||= Rails.application.key_generator.generate_key(SAL, 32)
  end

  def initialize(importacao)
    @importacao_id = importacao.id
    respostas = ContactImports::Trazer::Conferencia.new(importacao).respostas
    @todas = respostas['clientes'] == Relacionamentos::Trazer::Perguntas::SIM_TODAS
    @escolha = respostas[RESPOSTA].to_h
    colunas = Relacionamentos::Trazer::Colunas.new(importacao)
    @coluna = colunas.chaves_do_destino(DESTINO).first
    @indice = colunas.indices_do_destino(DESTINO).first
  end

  # valores: as outras colunas da linha, pela chave de cada uma (extra_values).
  def marca?(valores)
    @todas || escolhido?(valores[@coluna])
  end

  # Quantas das linhas que entram (ContactImports::Trazer::QuemEntra) viram cliente.
  def quantas(quem_entra)
    return quem_entra.quantas if @todas
    return 0 if @escolha.empty?

    quem_entra.por_valor(@coluna).sum { |valor, linhas| escolhido?(valor) ? linhas : 0 }
  end

  private

  def escolhido?(valor)
    return false if valor.blank?
    return true if @escolha['modo'] == PREENCHIDAS

    @escolha['modo'] == VALORES && @escolha['chaves'].include?(self.class.chave(@importacao_id, @indice, valor))
  end
end
