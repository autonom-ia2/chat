# O que o "para cada item" (#2414 G24, #2771) confere ao salvar e ao ligar (ProblemasDoProprioPasso). O `maximo` de 1 a
# 50 e a forma dos campos o esquema já confere.
#
# - a flag dos passos de IA (automacao_ia) e a do "criar card" com o CRM ligado (PassoDeCard.ligado?);
# - as chaves dos campos não ficam em branco, não repetem, e uma delas é `nome`. A chave só de espaços passa no esquema
#   (minLength 1), mas vira um atributo do contato sem nome, que a conta recusa criar na hora de rodar;
# - a etapa é da conta e está num funil que quem salva enxerga (a mesma régua da prospecção);
# - quem salva pode criar card e importar contatos (a pergunta da tela de Contatos). A chave de funis o controller já
#   confere (PASSOS_DE_FUNIL). Sem pessoa (`account_user` nil: o catálogo), só a conta.
class Autonomia::Automacao::ProblemasDoParaCada
  def initialize(conta, passo, account_user)
    @conta = conta
    @passo = passo
    @account_user = account_user
  end

  def problemas
    [*ia_desligada, *chaves_em_branco, *campos_repetidos, *sem_nome, *etapa, *sem_importar]
  end

  private

  def id = @passo['id']

  def chaves = Array(@passo['campos']).pluck('chave')

  def ia_desligada = ::Autonomia::Automacao::Motor.ia?(@conta) ? [] : [texto(:ia_desligada)]

  def chaves_em_branco = chaves.any? { |chave| chave.to_s.strip.empty? } ? [texto(:para_cada_chave_em_branco)] : []

  def campos_repetidos
    chaves.tally.select { |_chave, vezes| vezes > 1 }.keys.map { |chave| texto(:campo_repetido, chave: chave) }
  end

  def sem_nome = chaves.include?(::Autonomia::Automacao::PassoParaCada::NOME) ? [] : [texto(:para_cada_sem_nome)]

  def etapa
    do_card = ::Autonomia::Automacao::PassoDeCard.problemas_ao_salvar(@conta, @passo, @account_user)
    return do_card if do_card.any?

    ::Autonomia::Automacao::PassoDeProspeccao.problema_da_etapa(@passo, @conta, @account_user)
  end

  def sem_importar
    return [] if @account_user.nil? || ::CampaignImports::ContactRow.allowed?(@account_user)

    [texto(:para_cada_sem_importar)]
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", passo: id, **valores)
end
