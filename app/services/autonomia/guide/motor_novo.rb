# #2889: as regras do Guia para as automações do motor novo (autonomia/automacoes), num lugar só.
#
# - Sem a porta da Automação (automacao_porta e automacao_editor), o Guia não toca nelas: segue em automation_rules.
#   A recusa vale no servidor, não só na instrução.
# - Ajustar uma automação LIGADA vale na hora (quem salva segue sendo quem ligou, Definicao#salvar_versao!). Por isso
#   o ajuste dela não tem desfazer e passa pela confirmação da pessoa (`Acoes#desfazivel?`), como o Decisor ligado.
# - Ligar e desligar não têm desfazer (Acoes::SEM_DESFAZER): o Guia só faz pelo cartão de confirmação, com o aviso.
#   Ligar é "assumir": ela age com os direitos de quem confirmou, na versão que a pessoa viu (versao_id). O Guia liga
#   só quando a pessoa pede, nunca por conta própria.
class Autonomia::Guide::MotorNovo
  RECURSO = 'autonomia/automacoes'.freeze
  AJUSTES = ['PATCH autonomia/automacoes/:id', 'PUT autonomia/automacoes/:id'].freeze
  DESLIGAR = 'POST autonomia/automacoes/:id/desligar'.freeze
  LIGAR = 'POST autonomia/automacoes/:id/ligar'.freeze
  AVISOS = { DESLIGAR => 'automacao_desligar_sem_desfazer', LIGAR => 'automacao_ligar_vale_agora' }.freeze

  def initialize(account)
    @account = account
  end

  def self.do_motor?(acao)
    recurso = acao.to_s.split(' ', 2).last.to_s
    recurso == RECURSO || recurso.start_with?("#{RECURSO}/")
  end

  # A chave i18n (autonomia.guide.*) da recusa, ou nil quando pode.
  def recusa(acao)
    'automacao_sem_porta' if self.class.do_motor?(acao) && !Autonomia::Automacao.porta?(@account)
  end

  def ajusta_ligada?(acao, dados)
    return false unless dados && AJUSTES.include?(acao.to_s)

    id = (dados[:caminho] || {}).to_h.with_indifferent_access[:id]
    Autonomia::Automacao::Definicao.where(account_id: @account.id, id: id).pick(:ativa) == true
  end

  # O que a confirmação mostra além da frase, ou nil.
  def aviso(acao, dados)
    return I18n.t('autonomia.guide.automacao_ligada_vale_na_hora') if ajusta_ligada?(acao, dados)

    chave = AVISOS[acao.to_s]
    I18n.t("autonomia.guide.#{chave}") if chave
  end
end
