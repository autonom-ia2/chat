# Um lote de leitura da carteira (E6, #2899): os PDFs que a corretora enviou de uma vez, ou uma busca no conector (E7).
# É o que o Conferir mostra, o que o histórico lista e o que o Desfazer desfaz. Cada arquivo é um item
# (Carteira::LeituraItem); as apólices que o lote criou apontam para ele (`carteira_apolices.leitura_id`), e é por elas
# que o Desfazer acha o que desfazer, mesmo depois de os itens saírem.
#
# `totais` guarda só contagens (quantos lidos, quantos recusados): nome, documento, telefone e texto do PDF nunca entram
# ali. A validação recusa qualquer valor que não seja número inteiro.
#
# APAGAR LEITURA É SÓ COM `destroy` (ou `destroy!`), nunca com `delete` nem `delete_all`. O banco apaga os itens em
# cascata, mas a cascata não apaga arquivo: o PDF de cada item ficaria no armazenamento, sem dono. O `destroy` passa
# por cada item e tira o PDF junto. A limpeza dos itens vencidos (E6.2) apaga com `destroy`, em lote pequeno. A única
# exceção é a exclusão da conta (Autonomia::ExclusaoDaConta), que tira os itens e os anexos deles antes das leituras.
#
# O banco só lista as origens. Os estados crescem com quem grava (o anexar, o trazer por PDFs, a busca no conector) e
# são validados aqui.
#
# A busca no conector (E7, #2900) é a leitura de origem `conector`: cada registro que o conector devolveu é um item, e
# o primeiro item (`posicao` 0, estado `pedido`) guarda o andamento do pedido (Carteira::Conector::Pedido). `totais` diz
# se ela é a primeira busca (PRIMEIRA) ou a de todo dia (DIARIA).
#
# Três entradas gravam leitura de PDF, e o `totais` diz de qual ela é (é uma contagem, como tudo ali):
# - `anexar`: o PDF de UM seguro que já existe, anexado na gaveta para ver o que mudou (Carteira::Pdf::Ler). Um item só,
#   que já nasce com a apólice. Nunca é trazida nem aparece no histórico; sai quando o PDF é guardado;
# - `pdfs`: os PDFs que a corretora enviou em Trazer (Carteira::Trazer::Pdfs::Receber), com quantos foram. É o lote que
#   o Conferir mostra, o histórico lista e o Desfazer desfaz (`do_trazer`);
# - `de_fora`: o PDF de um seguro que a pessoa tem em OUTRA corretora (E6.5, Carteira::DeFora::Ler). Um item só, já com o
#   contato da tela e sem apólice. Nunca é trazida nem aparece no histórico; sai quando o seguro de fora é guardado.
class Carteira::Leitura < ApplicationRecord
  self.table_name = 'carteira_leituras'

  ORIGENS = %w[pdf conector].freeze
  # lendo: os itens ainda estão sendo lidos. lida: pronta para conferir. trazendo: gravando as apólices. trazida:
  # confirmada (`confirmada_em`). desfazendo: o Desfazer está rodando. desfeita: o Desfazer rodou (`desfeita_em`).
  # parou (E7, #2900): a busca no conector parou num erro (o login do Agger recusado, o Agger fora do ar); a pessoa
  # tenta de novo pela tela, e a busca continua de onde estava.
  ESTADOS = %w[lendo lida trazendo trazida desfazendo desfeita parou].freeze
  # As marcas de entrada, em `totais` (ver acima).
  DO_ANEXAR = 'anexar'.freeze
  DO_TRAZER = 'pdfs'.freeze
  DO_DE_FORA = 'de_fora'.freeze
  # E7 (#2900): a busca no conector é a primeira (36 meses, passa pelo Conferir) ou a de todo dia (7 dias, entra sozinha).
  PRIMEIRA = 'primeira'.freeze
  DIARIA = 'diaria'.freeze
  # Os itens guardam dado de cliente (o que foi lido e o PDF). Saem este tanto de dias depois de a leitura ser
  # confirmada; a que ninguém confirmou conta a partir da última vez em que foi mexida (abandonada).
  DIAS_DE_GUARDA_DOS_ITENS = 30

  belongs_to :account
  belongs_to :user, optional: true
  has_many :itens, class_name: 'Carteira::LeituraItem', inverse_of: :leitura, dependent: :destroy
  has_many :apolices, class_name: 'Carteira::Apolice', inverse_of: :leitura, dependent: :nullify

  validates :origem, inclusion: { in: ORIGENS }
  validates :estado, inclusion: { in: ESTADOS }
  validate :totais_so_com_contagens
  validate :pessoa_da_conta, if: :will_save_change_to_user_id?

  # As leituras do PDF anexado a um seguro.
  scope :do_anexar, -> { where(origem: 'pdf').where("carteira_leituras.totais ->> '#{DO_ANEXAR}' IS NOT NULL") }
  # Os lotes de Trazer por PDFs (nunca a leitura do anexar).
  scope :do_trazer, -> { where(origem: 'pdf').where("carteira_leituras.totais ->> '#{DO_TRAZER}' IS NOT NULL") }
  # As leituras do PDF de um seguro de outra corretora (E6.5).
  scope :do_de_fora, -> { where(origem: 'pdf').where("carteira_leituras.totais ->> '#{DO_DE_FORA}' IS NOT NULL") }
  # As buscas no conector (E7, #2900): a primeira e as de todo dia.
  scope :do_conector, -> { where(origem: 'conector') }
  # Os lotes que o histórico lista e o Desfazer desfaz: os de Trazer por PDFs e as buscas no conector.
  scope :do_lote, -> { do_trazer.or(do_conector) }

  # As leituras cujos itens já passaram do prazo de guarda.
  scope :com_a_guarda_vencida, lambda { |agora = Time.current|
    where('COALESCE(carteira_leituras.confirmada_em, carteira_leituras.updated_at) < ?', agora - DIAS_DE_GUARDA_DOS_ITENS.days)
  }

  private

  def totais_so_com_contagens
    errors.add(:totais, :invalid) unless totais.is_a?(Hash) && totais.values.all?(Integer)
  end

  # O banco só confere que a pessoa existe, não que ela é da conta.
  def pessoa_da_conta
    errors.add(:user, :invalid) if user && !AccountUser.exists?(account_id: account_id, user_id: user.id)
  end
end
