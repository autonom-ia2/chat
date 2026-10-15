# Liga e desliga a autorização do dono para o sistema criar modelos (#1586) e devolve o estado para a tela.
#
#   Whatsapp::Templates::Consentimento.new(account:, user:).mudar(acao: 'ligar', marcas: %w[utility marketing], versao:)
#   # => estado (o mesmo de #estado) | levanta Invalida(codigo)
#
# Regras (épico #1585):
# - Divulgação (marketing) só liga com o Aviso de serviço (utility) ligado, antes ou no mesmo pedido;
# - desligar o Aviso de serviço desliga as duas (uma linha por marca);
# - marca já no estado pedido não grava linha nova (nada mudou);
# - `versao` é a do aviso que a tela mostrou: outra (o preço mudou no meio) recusa com `aviso_mudou`.
# Uma trava na conta (linha de `accounts`, sem coluna nova) evita que dois pedidos ao mesmo tempo gravem fora de ordem.
class Whatsapp::Templates::Consentimento
  Aviso = Whatsapp::Templates::AvisoDeConsentimento
  UTILITY = 'utility'.freeze
  MARKETING = 'marketing'.freeze
  # A ação do pedido e a linha que ela grava.
  REGISTRO = { 'ligar' => WhatsappTemplateConsent::LIGOU, 'desligar' => WhatsappTemplateConsent::DESLIGOU }.freeze
  ACOES = REGISTRO.keys.freeze
  # O texto gravado é o da confirmação: com duas marcas no pedido, os dois parágrafos, como a tela mostra.
  SEPARADOR_DE_PARAGRAFO = "\n\n".freeze

  class Invalida < StandardError
    attr_reader :codigo

    def initialize(codigo)
      @codigo = codigo
      super
    end
  end

  def initialize(account:, user: nil)
    @account = account
    @user = user
  end

  def estado
    ultimas = WhatsappTemplateConsent::MARCAS.index_with { |marca| WhatsappTemplateConsent.ultima(@account, marca) }
    WhatsappTemplateConsent::MARCAS.index_with { |marca| estado_da_marca(ultimas[marca]) }.merge(
      'aviso' => {
        'versao' => Aviso::VERSAO, 'vigente_desde' => Aviso::VIGENTE_DESDE.iso8601, 'moeda' => Aviso::MOEDA_DA_TELA,
        'precos' => Aviso::PRECOS.transform_values { |preco| preco.fetch(Aviso::MOEDA_DA_TELA) },
        'textos' => ACOES.index_with { |acao| WhatsappTemplateConsent::MARCAS.index_with { |marca| Aviso.texto(marca, acao) } },
        'limites' => Aviso::LIMITES
      }
    )
  end

  def mudar(acao:, marcas:, versao:)
    marcas = conferir(acao, marcas, versao)
    @account.with_lock { acao == 'ligar' ? ligar(marcas) : desligar(marcas) }
    estado
  end

  private

  def conferir(acao, marcas, versao)
    raise Invalida, 'acao_invalida' unless ACOES.include?(acao.to_s)

    marcas = Array(marcas).map(&:to_s).uniq
    raise Invalida, 'marca_invalida' if marcas.empty? || (marcas - WhatsappTemplateConsent::MARCAS).any?
    raise Invalida, 'aviso_mudou' unless versao.to_s == Aviso::VERSAO

    marcas
  end

  def ligar(marcas)
    utility_ligada = marcas.include?(UTILITY) || WhatsappTemplateConsent.ativo?(@account, UTILITY)
    raise Invalida, 'utility_desligada' if marcas.include?(MARKETING) && !utility_ligada

    gravar_todas(marcas, 'ligar', texto_mostrado(marcas, 'ligar'))
  end

  # Desligar o Aviso de serviço leva a Divulgação junto. As duas linhas gravam o texto que o dono leu (o de desligar o
  # Aviso de serviço), não o de desligar só a Divulgação.
  def desligar(marcas)
    texto = texto_mostrado(marcas, 'desligar')
    marcas |= [MARKETING] if marcas.include?(UTILITY)
    gravar_todas(marcas, 'desligar', texto)
  end

  # O que a confirmação mostrou: o texto de cada marca pedida, na ordem da tela, um parágrafo por marca.
  def texto_mostrado(marcas, acao)
    WhatsappTemplateConsent::MARCAS.select { |marca| marcas.include?(marca) }
                                   .map { |marca| Aviso.texto(marca, acao) }.join(SEPARADOR_DE_PARAGRAFO)
  end

  def gravar_todas(marcas, acao, texto)
    WhatsappTemplateConsent::MARCAS.each { |marca| gravar(marca, acao, texto) if marcas.include?(marca) }
  end

  def gravar(marca, acao, texto)
    registro = REGISTRO.fetch(acao)
    return if (WhatsappTemplateConsent.ultima(@account, marca)&.acao || WhatsappTemplateConsent::DESLIGOU) == registro

    WhatsappTemplateConsent.create!(account: @account, user: @user, marca: marca, acao: registro, versao_aviso: Aviso::VERSAO,
                                    texto_aviso: texto, precos: Aviso.precos(marca))
  end

  # Quem mudou: o nome copiado na gravação (`user_name`); o usuário só para linha antiga sem cópia (NULL).
  def estado_da_marca(ultima)
    mudanca = ultima && { 'acao' => ultima.acao, 'por' => ultima.user_name || ultima.user&.name, 'em' => ultima.created_at.iso8601 }
    { 'ativo' => ultima&.acao == WhatsappTemplateConsent::LIGOU, 'mudanca' => mudanca }
  end
end
