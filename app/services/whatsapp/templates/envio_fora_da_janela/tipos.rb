# Os tipos de mensagem que o sistema manda sozinho fora da janela de 24 h (#1587, épico #1585): lista fixa, combinada com
# o Followup IA. Cada tipo tem a categoria pelo PROPÓSITO (pesquisa oficial no #1585): andamento, retorno e "deu certo?"
# são UTILITY porque falam de algo específico que o cliente já tem com a empresa, sem oferta; retomar contato é
# MARKETING sempre ("even if requested by users"). Forçar propaganda como utilidade tem punição em escada da Meta.
#
# A cobrança usa os prontos fixos de `Finalidades` (texto em produção desde o #1535, aprovado nas caixas): o momento vem
# daqui, o "com valor" de quem pede o plano. Os outros tipos a IA escreve para o negócio, um modelo por (caixa, tipo),
# com nome estável `c2y_<tipo>_<caixa>` (`_v2`, `_v3` depois de recusado). O `proposito` vai ao redator (o que escrever)
# e ao Jev (o que um modelo da conta precisa dizer para servir no lugar), sempre como dado.
module Whatsapp::Templates::EnvioForaDaJanela::Tipos
  class Desconhecido < ArgumentError; end

  UTILITY = 'UTILITY'.freeze
  MARKETING = 'MARKETING'.freeze
  DONO = 'fora_da_janela'.freeze
  PREFIXO = 'c2y_'.freeze
  SEPARADOR = '_'.freeze
  VERSAO = 'v'.freeze
  # O que o Followup preenche de qualquer card (`TemplateFields::Resolver.for_card`): nome do cliente, quem fala e o pedido.
  CAMPOS = %w[cliente.primeiro_nome minha_empresa.nome negocio.titulo].freeze
  OBRIGATORIOS = %w[negocio.titulo].freeze
  SEM_OFERTA = 'Sem oferta, desconto, urgência nem "aproveite".'.freeze

  Tipo = Data.define(:chave, :categoria, :amigavel, :proposito, :momento) do
    def cobranca?
      !momento.nil?
    end

    def propaganda?
      categoria == Whatsapp::Templates::EnvioForaDaJanela::Tipos::MARKETING
    end

    def campos
      Whatsapp::Templates::EnvioForaDaJanela::Tipos::CAMPOS
    end

    def obrigatorios
      Whatsapp::Templates::EnvioForaDaJanela::Tipos::OBRIGATORIOS
    end
  end

  CATALOGO = {
    'cobranca_antes' => { categoria: UTILITY, momento: :antes,
                          proposito: 'Lembrar o cliente de um pagamento que ainda vai vencer, com o assunto e a data.' },
    'cobranca_no_dia' => { categoria: UTILITY, momento: :no_dia,
                           proposito: 'Lembrar o cliente de um pagamento que vence hoje, com o assunto e a data.' },
    'cobranca_depois' => { categoria: UTILITY, momento: :depois,
                           proposito: 'Avisar o cliente de um pagamento vencido que ainda não consta como pago.' },
    'andamento' => { categoria: UTILITY, amigavel: 'Fora da janela: andamento do pedido',
                     proposito: 'Avisar o andamento de um pedido específico do cliente: cite o pedido, diga em que pé ele está ' \
                                "e qual é o próximo passo. #{SEM_OFERTA}" },
    'retorno' => { categoria: UTILITY, amigavel: 'Fora da janela: retorno combinado',
                   proposito: 'Retomar, no horário que o próprio cliente combinou, a conversa sobre o pedido dele, citando o ' \
                              "pedido e convidando a responder por aqui. #{SEM_OFERTA}" },
    'retomar_contato' => { categoria: MARKETING, amigavel: 'Fora da janela: retomar contato',
                           proposito: 'Retomar contato com um cliente que parou de responder sobre um pedido, perguntando se ' \
                                      'ainda tem interesse ou se ficou alguma dúvida. É divulgação mesmo que o cliente tenha pedido.' },
    'deu_certo' => { categoria: UTILITY, amigavel: 'Fora da janela: deu certo?',
                     proposito: 'Depois do serviço feito, perguntar se deu tudo certo com o pedido específico do cliente, ' \
                                "para resolver o que tiver ficado pendente. Sem pedir avaliação genérica. #{SEM_OFERTA}" }
  }.freeze

  module_function

  def buscar(chave)
    definicao = CATALOGO[chave.to_s] || raise(Desconhecido, "tipo #{chave}")
    Tipo.new(chave: chave.to_s, categoria: definicao[:categoria], amigavel: definicao[:amigavel], proposito: definicao[:proposito],
             momento: definicao[:momento])
  end

  def todos
    CATALOGO.keys.map { |chave| buscar(chave) }
  end

  # `c2y_andamento_42`, `c2y_andamento_42_v2`.
  def nome(inbox, tipo, versao)
    base = "#{PREFIXO}#{tipo.chave}#{SEPARADOR}#{inbox.id}"
    versao.to_i > 1 ? "#{base}#{SEPARADOR}#{VERSAO}#{versao}" : base
  end

  # O dono (selo "Usado pelo sistema") de um nome criado aqui, ou nil. Lido por partes, sem regex: prefixo, um tipo da
  # lista, o número da caixa e, opcional, a versão.
  def dono_de(nome)
    nome = nome.to_s
    return unless nome.start_with?(PREFIXO)

    resto = nome.delete_prefix(PREFIXO)
    criado_aqui = CATALOGO.keys.any? do |chave|
      inicio = "#{chave}#{SEPARADOR}"
      resto.start_with?(inicio) && caixa_e_versao?(resto.delete_prefix(inicio))
    end
    DONO if criado_aqui
  end

  def caixa_e_versao?(resto)
    caixa, versao, *sobra = resto.split(SEPARADOR)
    return false unless sobra.empty? && digitos?(caixa)

    versao.nil? || (versao.start_with?(VERSAO) && digitos?(versao.delete_prefix(VERSAO)))
  end

  def digitos?(texto)
    texto.present? && texto.each_char.all? { |char| char.between?('0', '9') }
  end
end
