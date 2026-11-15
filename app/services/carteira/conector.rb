# Trazer os seguros pelo Agger (E7, #2900): a corretora conecta uma vez e a carteira se mantém sozinha. O chat não conhece
# a plataforma: fala com o conector (Autonomia::Insurance::Connector) pelas quatro operações da carteira, com a mesma
# conexão e a mesma sessão da Cotação (uma conexão por conta; decisão do Rodrigo de 13/11, "Agger sem Cotação").
#
# - `disponivel?`: a conta tem a carteira (Carteira::Acesso) e a instalação fala com o conector de verdade. O conector
#   de mentira (`mock`, o padrão sem configuração) só serve fora de produção: em produção ele gravaria seguros
#   fictícios na carteira de um cliente. Sem isso, a tela não mostra o caminho e as rotas recusam `agger_desligado`.
# - `ligado?`: além disso, o login do Agger da conta deu certo (`pronta?`).
#
# Quem faz o quê: Carteira::Conector::Sincronizar (a busca, um passo por vez, num job que se reagenda), Ler (cada
# registro vira um item da leitura), Gravar (os itens viram seguros pelo gravador único), BaixarPdf (o PDF de cada
# seguro), Conferir e Historico (o que a tela lê) e BuscaDiaria (o interruptor e a rotina de todo dia).
module Carteira::Conector
  PROVIDER = 'agger'.freeze
  MODO_DE_VERDADE = 'http'.freeze
  DESCOBRINDO = 'discovering'.freeze
  # O Guia não busca no Agger, não liga a busca de todo dia e não busca de novo por ninguém (`Guide::Acoes::SO_NA_TELA`):
  # a busca chama a plataforma da corretora com o login dela, traz pessoas e seguros em lote, e a de todo dia passa a
  # gravar sozinha. O trazer e o desfazer são as rotas do lote, já só na tela (Carteira::Pdf::SO_NA_TELA_DO_GUIA).
  SO_NA_TELA_DO_GUIA = {
    'POST relacionamentos/trazer/seguros/busca' => 'seguros_do_agger',
    'PUT relacionamentos/trazer/seguros/busca_diaria' => 'seguros_do_agger',
    'POST relacionamentos/trazer/seguros/leituras/:id/de_novo' => 'seguros_do_agger'
  }.freeze

  def self.disponivel?(account)
    Carteira::Acesso.liberada?(account) && conector_de_verdade?
  end

  def self.conector_de_verdade?
    ENV.fetch('INSURANCE_CONNECTOR_MODE', 'mock') == MODO_DE_VERDADE || !Rails.env.production?
  end

  def self.conexao(account)
    Autonomia::Insurance::Connection.for_account(account).find_by(provider: PROVIDER)
  end

  def self.ligado?(account)
    disponivel?(account) && pronta?(conexao(account))
  end

  # A conexão serve à carteira quando o login dela deu certo: pronta (`usable?`) ou varrendo os produtos da Cotação
  # (`discovering`, que só vem depois de um login aceito). A carteira não usa a varredura: sem isso, a corretora que
  # acabou de conectar esperaria a varredura inteira (perto de 25 s) para começar a busca.
  def self.pronta?(conexao)
    return false unless conexao&.credentials_present?

    conexao.usable? || conexao.status == DESCOBRINDO
  end
end
