# O passo "prospecção" da Automação livre (#2414 G21, #2706; decisão A do Rodrigo na #2699, 08/11: o "buscar empresas"
# fica dentro da Automação). Duas coisas, escolhidas em `faz`:
#
# - `buscar`: repete uma busca do histórico da Prospecção (`busca_id`), com `quantas` empresas, e cria um card por
#   empresa que tem WhatsApp na etapa escolhida, com as etiquetas no contato (BuscaDaProspeccao). Só em gatilho da conta
#   (o recorrente da G7, `conta.recorrente`): num gatilho de conversa, card ou contato, cada execução faria uma busca
#   paga no Google. A Receita recusa ao salvar; a receita que chegar assim mesmo pula com `prospeccao_so_sem_alvo`.
# - `recusar`: o "Não quer ser contatado" da Prospecção, no lead do contato do alvo (ContactOptOutSync#refuse!, a mesma
#   porta do botão do lead). A recusa veta o número nas buscas e nas campanhas futuras (ConsentVeto).
#
# Age como quem ligou, conferido a cada rodada, com a régua das telas da Prospecção: o módulo ligado na conta e a chave
# dele (prospecting_manage); para buscar, também criar card (Crm::CardPolicy#create?), como o "Enviar ao CRM" da tela, e,
# com etiquetas, mudar contato (ContactPolicy#update?, contact_manage na função), como pôr etiqueta na tela do contato.
# Sem a chave, a automação pausa (`sem_acesso`), como nos outros passos. Por ser passo de funil (cria card, e o
# controller o põe em PASSOS_DE_FUNIL), pede também a chave de funis (RegraDoFunil.chave?), de quem salva e de quem
# ligou, como o "criar card" e o "para cada item": sem ela, pausa com `sem_chave_de_funis`. O lead segue o que quem ligou enxerga
# (Visibility): o agente só alcança as buscas e os leads dele. O funil é o do envio da tela (CrmCardBatch: só funil que
# quem ligou vê, com CardPolicy#create? como o Prospecting::BaseController#authorize_crm_card_create!).
#
# Chega pela porta da ação (PassoDeAcao.executar), porque usa o que a ação usa: a espera (`:esperar`, enquanto a
# conferência de WhatsApp roda) e a nova tentativa no erro passageiro do Google.
class Autonomia::Automacao::PassoDeProspeccao
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  CHAVE = 'prospecting_manage'.freeze

  # O que a Receita confere ao salvar e ao ligar. Sem conta (o catálogo das receitas prontas), só o alvo (`alvo`,
  # Receita#alvo: o tipo do registro em que o passo roda).
  def self.problemas_ao_salvar(passo, alvo, conta:, account_user:)
    id = passo['id']
    return [frase(:prospeccao_desligada, passo: id)] if conta && !::Autonomia::Prospecting::Config.enabled?(conta)

    buscar = passo['faz'] == 'buscar'
    lista = account_user && !pode?(account_user, passo) ? [frase(:prospeccao_sem_permissao, passo: id)] : []
    buscar ? lista + problemas_da_busca(passo, alvo, conta, account_user) : lista
  end

  def self.problemas_da_busca(passo, alvo, conta, account_user)
    id = passo['id']
    lista = ::Autonomia::Automacao::PassoDeCampanha.alvo_da_conta?(alvo) ? [] : [frase(:prospeccao_so_sem_alvo, passo: id)]
    return lista if conta.nil?

    etiquetas = Array(passo['etiquetas']) - conta.labels.where(id: passo['etiquetas']).pluck(:id)
    [*lista,
     *(frase(:prospeccao_busca_de_fora, passo: id, id: passo['busca_id']) unless busca(conta, account_user, passo['busca_id'])),
     *problema_da_etapa(passo, conta, account_user),
     *etiquetas.map { |etiqueta| frase(:campanha_etiqueta_de_fora, passo: id, id: etiqueta) }]
  end

  # A etapa é da conta e está num funil que quem salva enxerga (Crm::Access::VisiblePipelines, a mesma régua do envio ao
  # CRM da tela): sem isso, o passo salvaria e só falharia ao rodar (`etapa_fora_do_alcance`).
  def self.problema_da_etapa(passo, conta, account_user)
    id = passo['id']
    etapa = conta.crm_pipeline_stages.find_by(id: passo['etapa_id'])
    return [frase(:etapa_do_card_de_fora, passo: id, id: passo['etapa_id'])] if etapa.nil?
    return [] if account_user.nil?

    funis = ::Crm::Access::VisiblePipelines.new(user: account_user.user, account: conta, account_user: account_user)
    funis.visible?(etapa.pipeline_id) ? [] : [frase(:prospeccao_etapa_de_funil_fechado, passo: id, id: etapa.id)]
  end

  # A busca do histórico que quem salva (ou quem ligou) enxerga, como na tela da Prospecção.
  def self.busca(conta, account_user, id)
    escopo = ::Autonomia::Prospecting::Search.where(account: conta)
    escopo = ::Autonomia::Prospecting::Visibility.new(account_user).searches(escopo) if account_user
    escopo.find_by(id: id)
  end

  def self.pode?(account_user, passo)
    return false unless account_user&.permission_granted?(CHAVE) && ::Autonomia::Automacao::RegraDoFunil.chave?(account_user)
    return true unless passo['faz'] == 'buscar'

    ::Autonomia::Automacao::PassoDeCard.cria_card?(account_user) && (Array(passo['etiquetas']).empty? || muda_contato?(account_user))
  end

  # A pergunta da tela do contato para pôr etiqueta: não depende do contato (no EE, contact_manage para quem tem função).
  def self.muda_contato?(account_user)
    contexto = { user: account_user.user, account: account_user.account, account_user: account_user }
    ContactPolicy.new(contexto, ::Contact.new(account: account_user.account)).update?
  end

  def self.frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  # Pela porta da ação: `valores` não entra (o passo não lê valor do alvo).
  def initialize(execucao:, passo:, acesso:, **)
    @execucao = execucao
    @passo = passo
    @acesso = acesso
    @conta = execucao.account
  end

  def executar
    return pulado('prospeccao_desligada') unless ::Autonomia::Prospecting::Config.enabled?(@conta)
    return Resultado.new(tipo: :sem_acesso, motivo: 'sem_chave_de_funis', dados: {}) unless
      ::Autonomia::Automacao::RegraDoFunil.chave?(@acesso.account_user)

    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_permissao_prospeccao', dados: {}) unless
      self.class.pode?(@acesso.account_user, @passo)

    @passo['faz'] == 'buscar' ? buscar_empresas : recusar
  end

  private

  def buscar_empresas
    return pulado('prospeccao_so_sem_alvo') unless @execucao.alvo.is_a?(::Account)

    ::Autonomia::Automacao::BuscaDaProspeccao.new(execucao: @execucao, passo: @passo, account_user: @acesso.account_user).executar
  end

  # Todos os leads do contato que quem ligou enxerga: o mesmo número pode ter voltado em mais de uma busca.
  def recusar
    contato = ::Autonomia::Automacao::Contexto.de(@execucao.alvo).contato
    return pulado('sem_contato') if contato.nil?
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: {}) unless @acesso.alcanca?(contato)

    leads = leads_do(contato)
    return pulado('sem_lead_da_prospeccao', 'contato_id' => contato.id) if leads.empty?

    sincronia = ::Autonomia::Prospecting::ContactOptOutSync.new(account: @conta)
    # Todos ou nenhum: a recusa pela metade deixaria o mesmo número recusado num lead e livre no outro.
    ActiveRecord::Base.transaction { leads.each { |lead| sincronia.refuse!(lead, user: @acesso.usuario) } }
    ::Autonomia::Prospecting::SegmentRefusalSync.enqueue(account: @conta, leads: leads)
    Resultado.new(tipo: :ok, motivo: nil, dados: { 'contato_id' => contato.id, 'leads' => leads.map(&:id) })
  end

  def leads_do(contato)
    escopo = ::Autonomia::Prospecting::Lead.where(account: @conta, contact_id: contato.id)
    ::Autonomia::Prospecting::Visibility.new(@acesso.account_user).leads(escopo).order(:id).to_a
  end

  def pulado(motivo, dados = {}) = Resultado.new(tipo: :pulado, motivo: motivo, dados: dados)
end
