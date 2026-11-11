# #2889: as regras do Guia para as automações do motor novo (autonomia/automacoes), num lugar só.
#
# - Sem a porta da Automação (automacao_porta e automacao_editor), o Guia não toca nelas: segue em automation_rules.
#   A recusa vale no servidor, não só na instrução.
# - Ajustar uma automação LIGADA muda o que ela faz: se quem confirma é quem ligou, vale na hora; de outra pessoa, ela
#   pausa até alguém ligar de novo (Definicao#salvar_versao!). Por isso o ajuste dela não tem desfazer e passa pela
#   confirmação da pessoa (`Acoes#desfazivel?`), como o Decisor ligado, com o aviso do que vai acontecer.
# - Ligar e desligar não têm desfazer (Acoes::SEM_DESFAZER): o Guia só faz pelo cartão de confirmação, com o aviso.
#   Ligar é "assumir": ela age com os direitos de quem confirmou, na versão que a pessoa viu (versao_id). O Guia liga
#   só quando a pessoa pede, nunca por conta própria. Se a versão a ligar foi salva por outra pessoa, o aviso diz quem
#   e quando: quem liga assume passos que não montou.
class Autonomia::Guide::MotorNovo
  RECURSO = 'autonomia/automacoes'.freeze
  AJUSTES = ['PATCH autonomia/automacoes/:id', 'PUT autonomia/automacoes/:id'].freeze
  DESLIGAR = 'POST autonomia/automacoes/:id/desligar'.freeze
  LIGAR = 'POST autonomia/automacoes/:id/ligar'.freeze
  AVISOS = { DESLIGAR => 'automacao_desligar_sem_desfazer', LIGAR => 'automacao_ligar_vale_agora' }.freeze

  FORMATO_DA_HORA = '%d/%m/%Y %H:%M'.freeze

  # `user` é quem vai confirmar; só o aviso usa.
  def initialize(account, user = nil)
    @account = account
    @user = user
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

    automacao(dados)&.ativa == true
  end

  # O que a confirmação mostra além da frase, ou nil.
  def aviso(acao, dados)
    return aviso_do_ajuste(dados) if ajusta_ligada?(acao, dados)
    return aviso_de_ligar(dados) if dados && acao.to_s == LIGAR

    chave = AVISOS[acao.to_s]
    I18n.t("autonomia.guide.#{chave}") if chave
  end

  private

  def automacao(dados)
    id = (dados[:caminho] || {}).to_h.with_indifferent_access[:id]
    Autonomia::Automacao::Definicao.find_by(account_id: @account.id, id: id)
  end

  # Só quem ligou mantém a automação ligada ao salvar; de outra pessoa, ela pausa (Definicao#salvar_versao!).
  def aviso_do_ajuste(dados)
    quem_ligou = @user.present? && automacao(dados)&.ligada_por_id == @user.id
    I18n.t(quem_ligou ? 'autonomia.guide.automacao_ligada_vale_na_hora' : 'autonomia.guide.automacao_ligada_ajuste_pausa')
  end

  def aviso_de_ligar(dados)
    [I18n.t("autonomia.guide.#{AVISOS[LIGAR]}"), salva_por_outra_pessoa(dados)].compact.join(' ')
  end

  # A versão a ligar (a do versao_id, ou a ativa) salva por outra pessoa: quem e quando, no fuso da conta.
  def salva_por_outra_pessoa(dados)
    versao = versao_a_ligar(dados)
    autor = versao&.autor
    return if autor.nil? || autor.id == @user&.id

    quando = I18n.l(versao.created_at.in_time_zone(Autonomia::Automacao::Tempo.fuso(@account)), format: FORMATO_DA_HORA)
    I18n.t('autonomia.guide.automacao_versao_de_outra_pessoa', nome: autor.name, quando: quando)
  end

  def versao_a_ligar(dados)
    dona = automacao(dados)
    return if dona.nil?

    versao_id = (dados[:corpo] || {}).to_h.with_indifferent_access[:versao_id]
    (versao_id.present? && dona.versoes.find_by(id: versao_id)) || dona.versao_ativa
  end
end
