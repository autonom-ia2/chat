# O passo "criar card" da Automação livre (#2414 G4): `{ id, tipo: "card", etapa_id }`. Abre um card na etapa
# escolhida, ligado à conversa da execução; no card, à conversa principal dele; no contato (e no card sem conversa), só
# ao contato. Serve ao "abrir card de retenção" e ao "card no quadro X".
#
# A criação é a das Regras (CardNovo), com o contrato do POST crm/cards: o card aberto no funil escolhido já é o card
# desta conversa (pula com `card_ja_existe`, sem duplicar); funil diferente é outro assunto, card novo. Contato fora do
# funil (#2084) não vira card. Nunca move card: mover é a ação `POST crm/cards/:id/move`. O card novo não vira o assunto
# atual da conversa nem desliga o card que ela já tem ("Convive" do termo): o card do pedido continua o principal.
#
# G49: com `contato` (um valor, `{"$valor": "criado.<passo>"}`), o card nasce nesse contato, sem conversa: o card do
# João, que o passo anterior criou (exemplo 11). Valor vazio pula com `faltou_valor`; o contato que quem ligou não
# alcança (ContactPolicy#update?, como o alvo contato) pausa a automação.
#
# Age como quem ligou (D1), conferido a cada execução, com as perguntas da API de cards: criar card (CardPolicy#create?,
# no EE `crm_manage_cards`) e o funil da etapa nas caixas dele (CardGuard#create_allowed?). Por ser passo de funil, pede
# também a chave de funis, a mesma das ações de funil (RegraDoFunil.chave?, #2633: `crm_manage_pipelines` ou `crm_admin`;
# sem ela, `sem_chave_de_funis`). Faltou uma, a automação pausa. Ver a conversa (ou mudar o contato) o executor já conferiu no alvo.
class Autonomia::Automacao::PassoDeCard
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  ORIGEM = 'livre'.freeze

  # Passo de funil, com a flag da F6 (a dos gatilhos de card) e o CRM ligado.
  def self.ligado?(conta) = ::Autonomia::Automacao::Motor.gatilhos?(conta)

  # Ao salvar e ao ligar (Receita): a flag, a etapa da conta e, com a pessoa, poder criar card (CardPolicy#create?). A
  # chave de funis o controller já confere (de_funil?). `account_user` nil (o catálogo) não confere a pessoa.
  def self.problemas_ao_salvar(conta, passo, account_user)
    id = passo['id']
    return [I18n.t('autonomia.automacao.receita.card_desligado', passo: id)] unless ligado?(conta)
    return [I18n.t('autonomia.automacao.receita.etapa_do_card_de_fora', passo: id, id: passo['etapa_id'])] unless
      conta.crm_pipeline_stages.exists?(id: passo['etapa_id'])
    return [] if account_user.nil? || cria_card?(account_user)

    [I18n.t('autonomia.automacao.receita.sem_criar_card', passo: id)]
  end

  def self.cria_card?(account_user)
    contexto = { user: account_user.user, account: account_user.account, account_user: account_user }
    ::Crm::CardPolicy.new(contexto, ::Crm::Card).create?
  end

  # `valores`: para ler o `contato` (G49).
  def initialize(execucao:, passo:, alvo:, acesso:, valores: nil)
    @execucao = execucao
    @passo = passo
    @acesso = acesso
    @conta = execucao.account
    @valores = valores
    no_alvo(alvo) unless @passo['contato']
  end

  def executar
    etapa = @conta.crm_pipeline_stages.find_by(id: @passo['etapa_id'])
    return pulado('etapa_sumiu') if etapa.nil?
    return sem_acesso('sem_chave_de_funis') unless ::Autonomia::Automacao::RegraDoFunil.chave?(@acesso.account_user)
    return sem_acesso('quem_ligou_sem_permissao_card') unless pode_criar?(etapa)
    return do_valor(etapa) if @passo['contato']
    return pulado('sem_contato') if @contato.nil?
    return pulado('fora_do_funil') if Crm::Relacao.fora_do_funil?(@contato)

    criar(etapa)
  end

  private

  # O contato em que o card nasce: o da conversa, quando há (CardNovo grava esse), senão o do alvo.
  def no_alvo(alvo)
    contexto = ::Autonomia::Automacao::Contexto.de(alvo)
    @conversa = contexto.conversa
    @contato = @conversa&.contact || contexto.contato
  end

  # G49: o card no contato do valor, sempre da conta. O id lido que não é número inteiro (ou de outra conta) não acha
  # contato e pula como o valor vazio.
  def do_valor(etapa)
    id = Integer(@valores.ler(@passo.dig('contato', '$valor')).to_s, 10, exception: false)
    @contato = id && @conta.contacts.find_by(id: id)
    return pulado('faltou_valor') if @contato.nil?
    return sem_acesso('quem_ligou_sem_acesso') unless @acesso.alcanca?(@contato)
    return pulado('fora_do_funil') if Crm::Relacao.fora_do_funil?(@contato)

    criar(etapa)
  end

  def criar(etapa)
    card = ::Autonomia::Automacao::CardNovo.new(stage: etapa, conversation: @conversa, contact: @contato, actor: @acesso.usuario,
                                                automacao: { origem: ORIGEM, id: @execucao.automacao_id }, foco: false)
                                           .criar { aberto(etapa).exists? }
    return pulado('card_ja_existe', 'card_id' => aberto(etapa).pick(:id)) if card.nil?

    criado = { 'tipo' => ::Autonomia::Automacao::RegistroCriado::CARD, 'id' => card.id }
    Resultado.new(tipo: :ok, dados: { 'card_id' => card.id, 'etapa_id' => etapa.id, 'criado' => criado })
  end

  # O card aberto do funil da etapa nesta conversa (pela regra do ConversationCardFinder) ou, sem conversa, do contato.
  def aberto(etapa)
    cards = if @conversa
              Crm::Cards::ConversationCardFinder.new(account: @conta).all(@conversa)
            else
              @conta.crm_cards.where(contact_id: @contato.id)
            end
    cards.where(pipeline_id: etapa.pipeline_id, status: :open)
  end

  def pode_criar?(etapa)
    self.class.cria_card?(@acesso.account_user) &&
      ::Crm::Access::CardGuard.new(user: @acesso.usuario, account: @conta, account_user: @acesso.account_user)
                              .create_allowed?(etapa.pipeline_id, conversation: @conversa)
  end

  def pulado(motivo, dados = {}) = Resultado.new(tipo: :pulado, motivo: motivo, dados: dados)

  def sem_acesso(motivo) = Resultado.new(tipo: :sem_acesso, motivo: motivo, dados: {})
end
