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

  # Rotas que recusam o pedido sem a chave `Idempotency-Key` (Crm::IdempotentRequests). Só estas levam a chave: nas
  # outras rotas do CRM ela é opcional, e mandá-la mudaria o que já roda (o pedido que falha no meio deixa a chave
  # "em andamento", e a repetição do passo levaria 409).
  PEDEM_CHAVE = ['POST crm/cards/:card_id/contact'].freeze

  attr_reader :codigo

  def initialize(execucao:, account_user:)
    @execucao = execucao
    super(account: execucao.account, user: execucao.dona.ligada_por, account_user: account_user)
  end

  def executar(acao, dados)
    @acao = acao.to_s
    super
  end

  # A mesma conferência do executar, antes de montar o pedido: a chave que falta pausa a automação mesmo quando o passo
  # pularia por falta de valor. Relê quem ligou (e a função dele): a chave tirada no meio da rodada vale já no passo
  # seguinte, não só na próxima execução. Quem saiu da conta no meio da rodada pausa, como no começo dela.
  def conferir!(acao)
    @account_user&.reload
    garantir_permitida!(acao)
  rescue ActiveRecord::RecordNotFound
    raise SemPermissao, 'quem_ligou_saiu_da_conta'
  end

  private

  # A lista já deixa de fora o que só se faz na tela; a conferência aqui é a rede, caso a lista erre.
  # Os dados da ação (#2446) não mudam a regra do motor: a lista, a chave de automações e, na ação de funil (crm/), a
  # chave de funis, a mesma pergunta do salvar, reconferida a cada execução (#2633).
  def garantir_permitida!(acao, _dados = nil)
    raise Recusada, so_na_tela(acao) if SO_NA_TELA.key?(acao.to_s)
    raise Recusada, I18n.t('autonomia.automacao.motivos.acao_fora') unless ::Autonomia::Automacao::AcoesPermitidas.permitida?(acao)
    raise SemPermissao, 'quem_ligou_sem_permissao' unless @account_user&.permission_granted?(::Autonomia::Automacao::Acesso::PERMISSAO)
    return unless ::Autonomia::Automacao::AcoesPermitidas.de_funil?(acao)
    raise SemPermissao, 'sem_chave_de_funis' unless ::Autonomia::Automacao::RegraDoFunil.chave?(@account_user)
  end

  # O `proibe` da lista vale também na hora de rodar, e não só ao salvar (G15): a versão salva antes da regra, ou montada
  # fora do editor, com um campo proibido (o `assignee_type` que passaria a conversa ao robô sem a Atribuição) não passa.
  def conferir_corpo!(acao, dados)
    super.tap do |conferencia|
      next if ::Autonomia::Automacao::AcoesPermitidas.proibidos(acao, conferencia.valores).empty?

      raise Recusada, I18n.t('autonomia.automacao.motivos.campo_proibido')
    end
  end

  # O que o pedido mudar sai assinado pela automação (Ato, #2568 P7), não só por quem a ligou.
  def requisitar(verbo, caminho, corpo)
    chamada = ::Autonomia::Guide::ChamadaInterna.new(user: @user)
    resposta = ::Autonomia::Automacao::Ato.da(@execucao.automacao_id) do
      chamada.chamar(verbo, caminho, corpo: corpo, cabecalhos: cabecalhos(caminho, corpo))
    end
    resposta.tap { @codigo = resposta.codigo.to_i }
  end

  # A chave é a mesma para a mesma execução, rota e corpo (D7, #2660): o passo repetido pelo executor recebe a resposta
  # guardada da primeira vez, e o contato não sai em dobro.
  def cabecalhos(caminho, corpo)
    return {} unless PEDEM_CHAVE.include?(@acao)

    pedido = Digest::SHA256.hexdigest(JSON.generate([caminho, corpo]))
    { ::Crm::IdempotentRequests::IDEMPOTENCY_HEADER => "automacao:#{@execucao.id}:#{pedido}" }
  end

  def trilha
    { 'automacao_id' => @execucao.automacao_id, 'execucao_id' => @execucao.id }
  end
end
