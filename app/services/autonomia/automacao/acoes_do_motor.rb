# O passo "ação da plataforma" (#2414 F3, D1, D2 e D3): a mesma execução do Guia, pela mesma porta (ChamadaInterna,
# com o token de quem ligou), com duas diferenças.
# - O que libera é a lista de ações permitidas (AcoesPermitidas) e a permissão de gerenciar automações, não o "só
#   administrador" do Guia. A caixa, o Pundit e a conta continuam valendo pelo endpoint.
# - A auditoria diz que foi a automação, com o id dela e o da execução (F3.9).
#
# Guarda o status HTTP da resposta: o executor decide por ele se o erro é permanente ou passageiro (F3.6).
class Autonomia::Automacao::AcoesDoMotor < Autonomia::Guide::Acoes
  AUDITORIA = 'automacao_action'.freeze

  attr_reader :codigo

  def initialize(execucao:, account_user:)
    @execucao = execucao
    super(account: execucao.account, user: execucao.automacao.ligada_por, account_user: account_user)
  end

  private

  def garantir_permitida!(acao)
    raise Recusada, I18n.t('autonomia.automacao.motivos.acao_fora') unless ::Autonomia::Automacao::AcoesPermitidas.permitida?(acao)
    raise Recusada, I18n.t('autonomia.automacao.motivos.quem_ligou_sem_permissao') unless @account_user&.permission_granted?(
      ::Autonomia::Automacao::Acesso::PERMISSAO
    )
  end

  def requisitar(verbo, caminho, corpo)
    super.tap { |resposta| @codigo = resposta.codigo.to_i }
  end

  def trilha
    { 'automacao_id' => @execucao.automacao_id, 'execucao_id' => @execucao.id }
  end
end
