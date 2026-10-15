# O aviso que o dono lê antes de autorizar o sistema a criar modelos (#1586): ÚNICA fonte dos preços, da versão e do
# texto. A tela mostra o texto daqui e o registro (`WhatsappTemplateConsent`) grava o mesmo texto, a versão e os preços.
#
# Preços: tabela oficial da Meta, mercado Brasil, em vigor desde 01/10/2026, sem desconto de volume (decisão do
# Rodrigo no #1586). Preço da Meta mudou: troque PRECOS e VIGENTE_DESDE e suba VERSAO. Aceite antigo continua valendo
# (sem reaceite, decisão do épico #1585); a tela passa a mostrar o preço novo. Mudou o texto (`consent.*` em
# config/locales/whatsapp_templates.*.yml): suba VERSAO também.
# Limites: 250 modelos por conta do WhatsApp (6.000 com empresa verificada) e 100 criados por hora (templates/overview).
module Whatsapp::Templates::AvisoDeConsentimento
  VERSAO = '2026-10-01'.freeze
  VIGENTE_DESDE = Date.new(2026, 10, 1)
  PRECOS = {
    'utility' => { 'BRL' => '0.0350', 'USD' => '0.0068' }.freeze,
    'marketing' => { 'BRL' => '0.3217', 'USD' => '0.0625' }.freeze
  }.freeze
  LIMITES = { 'modelos' => 250, 'modelos_verificada' => 6000, 'por_hora' => 100 }.freeze
  MOEDA_DA_TELA = 'BRL'.freeze
  SIMBOLO_DA_MOEDA = 'R$'.freeze
  EXEMPLO_DE_ENVIOS = 1000
  MARCA_PADRAO = 'Chat2You'.freeze

  module_function

  # O texto que a tela mostra na confirmação (`acao`: ligar | desligar) e o registro grava, no idioma de quem lê.
  def texto(marca, acao)
    I18n.t("whatsapp_templates.consent.#{acao}.#{marca}",
           marca: nome_da_marca, preco: dinheiro(preco(marca), casas: 4, sem_zeros: true),
           vigencia: VIGENTE_DESDE.strftime(I18n.t('whatsapp_templates.consent.formato_da_data')),
           envios: ActiveSupport::NumberHelper.number_to_delimited(EXEMPLO_DE_ENVIOS, delimiter: separador('milhar')),
           exemplo: dinheiro(preco(marca) * EXEMPLO_DE_ENVIOS, casas: 2, sem_zeros: false))
  end

  # O que foi mostrado, para o registro: os dois preços da marca e a data da tabela.
  def precos(marca)
    PRECOS.fetch(marca.to_s).merge('vigente_desde' => VIGENTE_DESDE.iso8601)
  end

  def nome_da_marca
    GlobalConfig.get_value('INSTALLATION_NAME').presence || MARCA_PADRAO
  end

  def preco(marca)
    BigDecimal(PRECOS.fetch(marca.to_s).fetch(MOEDA_DA_TELA))
  end

  def dinheiro(valor, casas:, sem_zeros:)
    numero = ActiveSupport::NumberHelper.number_to_rounded(valor, precision: casas, strip_insignificant_zeros: sem_zeros,
                                                                  separator: separador('decimal'), delimiter: separador('milhar'))
    "#{SIMBOLO_DA_MOEDA} #{numero}"
  end

  def separador(tipo)
    I18n.t("whatsapp_templates.consent.separador_#{tipo}")
  end
end
