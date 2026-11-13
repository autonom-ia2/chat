# As listas que a conta já trouxe (#2896), a mais nova primeiro, no formato da tela: as TETO mais recentes. Recebe o
# escopo das importações de contatos por arquivo da conta. O número de consultas não cresce com o número de listas: quem
# trouxe e o arquivo conferido vêm juntos, e as linhas das listas que ainda estão entrando (ou pararam) são contadas de
# uma vez.
class Relacionamentos::Trazer::Historico
  PASSARAM = Relacionamentos::Trazer::Andamento::PASSARAM
  TETO = 100
  FALHOU = 'falhou'.freeze
  # "Desfazer" aparece na lista pronta e na que quebrou depois de pôr gente na base. Enquanto ela entra ou sai, não; a
  # não ser que o desfazer tenha parado no meio (Relacionamentos::Trazer::Desfazer.parado?).
  COM_DESFAZER = ['pronto', FALHOU].freeze
  DESFEITO = 'desfeito'.freeze

  def initialize(importacoes)
    @importacoes = importacoes
  end

  def call
    listas.map { |lista| item(lista, situacoes.fetch(lista.id)) }
  end

  private

  def listas
    @listas ||= Relacionamentos::Trazer::Situacao.no_historico(@importacoes).includes(:user, :normalized_csv_attachment)
                                                 .order(created_at: :desc, id: :desc).limit(TETO).to_a
  end

  def situacoes
    @situacoes ||= listas.to_h { |lista| [lista.id, Relacionamentos::Trazer::Situacao.de(lista)] }
  end

  def item(lista, situacao)
    {
      id: lista.id, arquivo: lista.source_filename, quando: (lista.confirmed_at || lista.created_at).utc.iso8601, quem: lista.user&.name,
      total: lista.valid_rows, situacao: situacao,
      porcentagem: Relacionamentos::Trazer::Situacao.porcentagem(situacao, linhas_que_passaram.fetch(lista.id, 0), lista.valid_rows),
      pode_tentar: situacao == FALHOU && Relacionamentos::Trazer::Situacao.pode_tentar?(lista),
      pode_desfazer: pode_desfazer?(lista, situacao)
    }.merge(ficaram(lista, situacao))
  end

  # Só na lista desfeita em que alguém devia ter saído e ficou (Relacionamentos::Trazer::Desfazer): quantas pessoas.
  def ficaram(lista, situacao)
    quantas = situacao == DESFEITO ? Relacionamentos::Trazer::Desfazer.ficaram(lista) : 0
    quantas.positive? ? { ficaram: quantas } : {}
  end

  def pode_desfazer?(lista, situacao)
    desfazer = Relacionamentos::Trazer::Desfazer
    desfazer.pode?(lista) && (COM_DESFAZER.include?(situacao) || desfazer.parado?(lista))
  end

  # { id da importação => linhas gravadas ou que falharam }, só das listas que ainda não acabaram.
  def linhas_que_passaram
    @linhas_que_passaram ||= begin
      abertas = situacoes.reject { |_id, situacao| Relacionamentos::Trazer::Situacao::ACABOU.include?(situacao) }.keys
      abertas.empty? ? {} : CampaignImportRow.where(campaign_import_id: abertas, status: PASSARAM).group(:campaign_import_id).count
    end
  end
end
