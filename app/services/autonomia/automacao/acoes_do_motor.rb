# O passo "ação da plataforma" (#2414 F3, D1, D2 e D3): a mesma execução do Guia, pela mesma porta (ChamadaInterna,
# com o token de quem ligou), com duas diferenças.
# - O que libera é a lista de ações permitidas (AcoesPermitidas) e a permissão de gerenciar automações, não o "só
#   administrador" do Guia. A caixa, o Pundit e a conta continuam valendo pelo endpoint.
# - A auditoria diz que foi a automação, com o id dela e o da execução (F3.9).
#
# Guarda o status HTTP da resposta: o executor decide por ele se o erro é permanente ou passageiro (F3.6).
class Autonomia::Automacao::AcoesDoMotor < Autonomia::Guide::Acoes
  AUDITORIA = 'automacao_action'.freeze

  # Quem ligou perdeu uma chave no meio da rodada: o executor pausa a automação, não só a execução. `motivo` é a chave
  # em autonomia.automacao.motivos.
  SemPermissao = Class.new(Recusada) do
    attr_reader :motivo

    def initialize(motivo)
      @motivo = motivo
      super(I18n.t("autonomia.automacao.motivos.#{motivo}"))
    end
  end

  attr_reader :codigo

  def initialize(execucao:, account_user:)
    @execucao = execucao
    super(account: execucao.account, user: execucao.automacao.ligada_por, account_user: account_user)
  end

  private

  # A lista já deixa de fora o que só se faz na tela; a conferência aqui é a rede, caso a lista erre.
  # Os dados da ação (#2446) não mudam a regra do motor: a lista, a chave de automações e, na ação de funil (crm/), a
  # chave de funis, a mesma pergunta do salvar, reconferida a cada execução (#2633).
  def garantir_permitida!(acao, _dados = nil)
    raise Recusada, so_na_tela(acao) if SO_NA_TELA.key?(acao.to_s)
    raise Recusada, I18n.t('autonomia.automacao.motivos.acao_fora') unless ::Autonomia::Automacao::AcoesPermitidas.permitida?(acao)
    raise SemPermissao, 'quem_ligou_sem_permissao' unless @account_user&.permission_granted?(::Autonomia::Automacao::Acesso::PERMISSAO)
    raise SemPermissao, 'sem_chave_de_funis' if de_funil?(acao) && !::Autonomia::Automacao::RegraDoFunil.chave?(@account_user)
  end

  def de_funil?(acao) = ::Autonomia::Automacao::AcoesPermitidas.recurso_de(acao).to_s.start_with?('crm/')

  # O que o pedido mudar sai assinado pela automação (Ato, #2568 P7), não só por quem a ligou.
  def requisitar(verbo, caminho, corpo)
    ::Autonomia::Automacao::Ato.da(@execucao.automacao_id) { super }.tap { |resposta| @codigo = resposta.codigo.to_i }
  end

  def trilha
    { 'automacao_id' => @execucao.automacao_id, 'execucao_id' => @execucao.id }
  end
end
