# As listas que a conta já trouxe (#2896), a mais nova primeiro, no formato da tela, de POR_PAGINA em POR_PAGINA
# (`pagina`, de 1 a ULTIMA_PAGINA; o que não é número vale 1). Recebe o escopo das importações de contatos da conta. O número de
# consultas não cresce com o número de listas: quem trouxe e o arquivo conferido vêm juntos, e as linhas das listas que
# ainda estão entrando (ou pararam) são contadas de uma vez.
#
# Cada lista diz de onde veio (`origem`, #3083): `trazer`, a planilha trazida por esta tela; `planilha_antiga`, a da tela
# antiga de Contatos; `automacao`, a do passo "para cada item" da automação. A da automação não tem arquivo: o nome que
# aparece é o dela. Só a desta tela oferece o Desfazer: a da automação é recusada por ele
# (Relacionamentos::Trazer::Desfazer.pode?), e a planilha antiga não tira ninguém (ela não anota o que preencheu). Na
# planilha antiga que já tinha um desfazer parado no meio, o "Continuar" fica, para ele chegar ao fim.
class Relacionamentos::Trazer::Historico
  PASSARAM = Relacionamentos::Trazer::Andamento::PASSARAM
  POR_PAGINA = 100
  # Um teto para a página pedida: o deslocamento da consulta não passa do que o banco aceita.
  ULTIMA_PAGINA = 100_000
  FALHOU = 'falhou'.freeze
  # "Desfazer" aparece na lista pronta e na que quebrou depois de pôr gente na base. Enquanto ela entra ou sai, não; a
  # não ser que o desfazer tenha parado no meio (Relacionamentos::Trazer::Desfazer.parado?).
  COM_DESFAZER = ['pronto', FALHOU].freeze
  DESFEITO = 'desfeito'.freeze
  TRAZER = 'trazer'.freeze
  PLANILHA_ANTIGA = 'planilha_antiga'.freeze
  AUTOMACAO = 'automacao'.freeze

  def initialize(importacoes, pagina: 1)
    @importacoes = importacoes
    @pagina = pagina.to_i.clamp(1, ULTIMA_PAGINA)
  end

  def call
    listas.map { |lista| item(lista, situacoes.fetch(lista.id)) }
  end

  private

  def listas
    @listas ||= Relacionamentos::Trazer::Situacao.no_historico(@importacoes).includes(:user, :normalized_csv_attachment)
                                                 .order(created_at: :desc, id: :desc)
                                                 .offset((@pagina - 1) * POR_PAGINA).limit(POR_PAGINA).to_a
  end

  def situacoes
    @situacoes ||= listas.to_h { |lista| [lista.id, Relacionamentos::Trazer::Situacao.de(lista)] }
  end

  def item(lista, situacao)
    de_onde = origem(lista)
    {
      id: lista.id, arquivo: de_onde == AUTOMACAO ? lista.name : lista.source_filename, origem: de_onde,
      quando: (lista.confirmed_at || lista.created_at).utc.iso8601, quem: lista.user&.name, total: lista.valid_rows, situacao: situacao,
      porcentagem: Relacionamentos::Trazer::Situacao.porcentagem(situacao, linhas_que_passaram.fetch(lista.id, 0), lista.valid_rows),
      pode_tentar: situacao == FALHOU && Relacionamentos::Trazer::Situacao.pode_tentar?(lista),
      pode_desfazer: pode_desfazer?(lista, situacao, de_onde)
    }.merge(ficaram(lista, situacao))
  end

  def origem(lista)
    return AUTOMACAO if lista.from_automation?

    lista.options.to_h.key?(TRAZER) ? TRAZER : PLANILHA_ANTIGA
  end

  # Só na lista desfeita em que alguém devia ter saído e ficou (Relacionamentos::Trazer::Desfazer): quantas pessoas.
  def ficaram(lista, situacao)
    quantas = situacao == DESFEITO ? Relacionamentos::Trazer::Desfazer.ficaram(lista) : 0
    quantas.positive? ? { ficaram: quantas } : {}
  end

  def pode_desfazer?(lista, situacao, origem)
    desfazer = Relacionamentos::Trazer::Desfazer
    return false unless desfazer.pode?(lista)
    return desfazer.parado?(lista) unless origem == TRAZER

    COM_DESFAZER.include?(situacao) || desfazer.parado?(lista)
  end

  # { id da importação => linhas gravadas ou que falharam }, só das listas que ainda não acabaram.
  def linhas_que_passaram
    @linhas_que_passaram ||= begin
      abertas = situacoes.reject { |_id, situacao| Relacionamentos::Trazer::Situacao::ACABOU.include?(situacao) }.keys
      abertas.empty? ? {} : CampaignImportRow.where(campaign_import_id: abertas, status: PASSARAM).group(:campaign_import_id).count
    end
  end
end
