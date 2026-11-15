# "Seu seguro em palavras simples" (E6.6, #2899): na gaveta do seguro, a plataforma escreve um resumo curto, em palavras
# simples, do seguro e de quando ele vence, a partir dos campos guardados (nunca do texto do PDF). A pessoa lê, ajusta e
# manda ao cliente pela conversa. Nada sai para o cliente sem um clique de gente (decisão P1): não há envio sozinho.
#
# - Carteira::Palavras::Escrever: a chamada paga que escreve o texto e o guarda em `palavras_texto`;
# - Carteira::Palavras::Salvar: guarda o texto que a pessoa ajustou;
# - Carteira::Palavras::Conversa: a conversa por onde o texto sai, e se ele pode sair agora;
# - Carteira::Palavras::Enviar: manda o texto guardado na conversa e marca `palavras_enviadas_em`.
#
# Só no seguro da carteira da corretora que não está cancelado: o seguro de outra corretora não ganha palavras simples.
# Só na conta com a leitura liberada (a mesma chave da E6, decisão D4): sem ela nada disto aparece.
module Carteira::Palavras
  TEXTO_MAXIMO = 1000
  # O Guia não escreve (é chamada paga) nem manda o texto ao cliente por ninguém: os dois só na tela.
  SO_NA_TELA_DO_GUIA = {
    'POST relacionamentos/seguros/:id/palavras/escrever' => 'seguro_palavras',
    'POST relacionamentos/seguros/:id/palavras/enviar' => 'seguro_palavras'
  }.freeze

  def self.cabe?(apolice)
    !apolice.de_fora && apolice.cancelado_em.nil?
  end

  # A frase do fim, que vai sempre e não entra no que se ajusta.
  def self.vale(account)
    I18n.t('carteira.palavras.vale', locale: locale(account))
  end

  def self.locale(account)
    account.locale.presence || I18n.default_locale
  end
end
