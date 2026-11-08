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
# dele (prospecting_manage); para buscar, também criar card (Crm::CardPolicy#create?), como o "Enviar ao CRM" da tela.
# Sem a chave, a automação pausa (`sem_acesso`), como nos outros passos. O lead segue o que quem ligou enxerga
# (Visibility): o agente só alcança as buscas e os leads dele. O funil é o do envio da tela (CrmCardBatch: só funil que
# quem ligou vê, com CardPolicy#create? como o Prospecting::BaseController#authorize_crm_card_create!).
#
# Chega pela porta da ação (PassoDeAcao.executar), porque usa o que a ação usa: a espera (`:esperar`, enquanto a
# conferência de WhatsApp roda) e a nova tentativa no erro passageiro do Google.
class Autonomia::Automacao::PassoDeProspeccao
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  CHAVE = 'prospecting_manage'.freeze

  # O que a Receita confere ao salvar e ao ligar. Sem conta (o catálogo das receitas prontas), só o gatilho.
  def self.problemas_ao_salvar(passo, receita, conta:, account_user:)
    id = passo['id']
    return [frase(:prospeccao_desligada, passo: id)] if conta && !::Autonomia::Prospecting::Config.enabled?(conta)

    buscar = passo['faz'] == 'buscar'
    lista = account_user && !pode?(account_user, buscar: buscar) ? [frase(:prospeccao_sem_permissao, passo: id)] : []
    buscar ? lista + problemas_da_busca(passo, receita.dig('gatilho', 'tipo'), conta, account_user) : lista
  end

  def self.problemas_da_busca(passo, gatilho, conta, account_user)
    id = passo['id']
    lista = ::Autonomia::Automacao::PassoDeCampanha.gatilho_da_conta?(gatilho) ? [] : [frase(:prospeccao_so_sem_alvo, passo: id)]
    return lista if conta.nil?

    etiquetas = Array(passo['etiquetas']) - conta.labels.where(id: passo['etiquetas']).pluck(:id)
    [*lista,
     *(frase(:prospeccao_busca_de_fora, passo: id, id: passo['busca_id']) unless busca(conta, account_user, passo['busca_id'])),
     *(frase(:etapa_do_card_de_fora, passo: id, id: passo['etapa_id']) unless conta.crm_pipeline_stages.exists?(id: passo['etapa_id'])),
     *etiquetas.map { |etiqueta| frase(:campanha_etiqueta_de_fora, passo: id, id: etiqueta) }]
  end

  # A busca do histórico que quem salva (ou quem ligou) enxerga, como na tela da Prospecção.
  def self.busca(conta, account_user, id)
    escopo = ::Autonomia::Prospecting::Search.where(account: conta)
    escopo = ::Autonomia::Prospecting::Visibility.new(account_user).searches(escopo) if account_user
    escopo.find_by(id: id)
  end

  def self.pode?(account_user, buscar:)
    return false unless account_user&.permission_granted?(CHAVE)

    !buscar || ::Autonomia::Automacao::PassoDeCard.cria_card?(account_user)
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

    buscar = @passo['faz'] == 'buscar'
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_permissao_prospeccao', dados: {}) unless
      self.class.pode?(@acesso.account_user, buscar: buscar)

    buscar ? buscar_empresas : recusar
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
