# O passo "campanha" (#2414 G14, #2630). Duas coisas, escolhidas em `faz`:
#
# - `disparar`: monta a campanha de WhatsApp oficial (caixa, modelo aprovado, público = etiquetas) pela mesma
#   `account.campaigns.create!` da API de campanhas e a põe na fila do disparo (Campaigns::TriggerOneoffCampaignJob, o
#   mesmo job do agendador). Quem manda é o Whatsapp::OneoffCampaignService (e o overlay do EE): ele lê o público no
#   disparo, relê a recusa de cada contato antes de mandar e manda o modelo. Nada sai por um caminho próprio daqui.
#   Só em gatilho da conta (o recorrente da G7, `conta.recorrente`, alvo = a própria Account): num gatilho de
#   conversa, card ou contato, cada execução criaria uma campanha
#   nova para o mesmo público, o mesmo envio N vezes. A Receita recusa ao salvar; a receita que chegar assim mesmo pula
#   com `campanha_so_sem_alvo`. Não é teto de uso, é a regra de não repetir o mesmo envio.
#   `publico: desta_execucao` (G58, #2779) troca as etiquetas pelos contatos que os passos anteriores desta execução
#   criaram (Autonomia::Automacao::CampanhaDaExecucao): a campanha da 2ª segunda não volta a quem recebeu na 1ª só por
#   ter a etiqueta do mês.
# - `nao_receber`: marca o contato do alvo como "não recebe" (a recusa das campanhas e mensagens ativas), como o botão
#   do contato (Contacts::OptOutsController): origem manual, feita por quem ligou, desfeita pelo mesmo botão.
#
# Pôr e tirar alguém de uma campanha é pôr e tirar a etiqueta do público dela, com o passo de etiqueta que já existe.
#
# Age como quem ligou, conferido a cada execução, com a pergunta da tela de cada coisa: disparar pede
# CampaignPolicy#send_campaign? (campaign_manage + campaign_send, #1898); não receber pede ContactPolicy#update?. Sem a
# permissão, a automação pausa (`sem_acesso`), como nos outros passos.
class Autonomia::Automacao::PassoDeCampanha
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  ModeloWhatsapp = ::Autonomia::Automacao::ModeloWhatsapp
  ROTA = ::Crm::BookingV2::Notices::Route
  # Utilidade e propaganda, aprovados, como a tela de campanhas (decisão do Rodrigo, 06/11: "Sim, com aviso"). O editor
  # avisa o custo do modelo de propaganda. Vale só aqui: o passo mensagem continua só com utilidade (ModeloWhatsapp).
  CATEGORIAS = %w[UTILITY MARKETING].freeze
  CANAL = ModeloWhatsapp::CANAL
  PROVEDOR = 'whatsapp_cloud'.freeze
  FLAG_DA_CAMPANHA = :whatsapp_campaign
  ALVO_DA_CONTA = 'Account'.freeze
  PUBLICO_DESTA_EXECUCAO = 'desta_execucao'.freeze

  # O que a Receita confere ao salvar (#2630). Sem conta (o catálogo das receitas prontas), só o que não depende dela.
  def self.problemas_ao_salvar(passo, receita, conta:, account_user:)
    id = passo['id']
    gatilho = receita.dig('gatilho', 'tipo')
    desligado = conta && !::Autonomia::Automacao::Motor.mensagens?(conta) ? [frase(:passo_desligado, passo: id)] : []
    return desligado unless passo['faz'] == 'disparar'

    desligado + problemas_do_disparo(passo, conta, gatilho, account_user) + problemas_do_publico(passo, receita)
  end

  # G58: o público desta execução precisa de um passo antes dele que crie card ou contato; sem ele, sairia sempre vazio.
  def self.problemas_do_publico(passo, receita)
    return [] unless desta_execucao?(passo)

    receita_obj = ::Autonomia::Automacao::Receita.new(receita, conta: nil, account_user: nil)
    antes = ::Autonomia::Automacao::TextoDaIaNaReceita.new(receita_obj, receita).rodam_antes(passo['id'])
    criam = ::Autonomia::Automacao::ContatosDaExecucao::TIPOS_QUE_CRIAM
    Array(antes).any? { |anterior| criam.include?(anterior['tipo']) } ? [] : [frase(:campanha_publico_sem_origem, passo: passo['id'])]
  end

  def self.desta_execucao?(passo) = passo['publico'] == PUBLICO_DESTA_EXECUCAO

  def self.problemas_do_disparo(passo, conta, gatilho, account_user)
    id = passo['id']
    lista = [*(frase(:campanha_so_sem_alvo, passo: id) unless gatilho_da_conta?(gatilho)),
             *(frase(:campanha_variavel_fixa, passo: id) unless variaveis_escritas?(passo['modelo']))]
    return lista if conta.nil?

    lista + problemas_de_acesso(passo['id'], conta, account_user) + problemas_da_campanha(passo, conta)
  end

  def self.problemas_de_acesso(id, conta, account_user)
    [*(frase(:campanha_sem_permissao, passo: id) if account_user && !pode_disparar?(account_user.user, conta)),
     *(frase(:campanha_desligada, passo: id) unless conta.feature_enabled?(FLAG_DA_CAMPANHA))]
  end

  def self.problemas_da_campanha(passo, conta)
    id = passo['id']
    caixa = caixa_da_campanha(conta, passo['caixa_id'])
    etiquetas = Array(passo['etiquetas']) - conta.labels.where(id: passo['etiquetas']).pluck(:id)
    modelo = caixa && modelo_pronto(caixa, passo['modelo'])
    [*(frase(:campanha_sem_caixa, passo: id) if caixa.nil?),
     *(frase(:campanha_modelo, passo: id, nome: passo.dig('modelo', 'nome')) if modelo.is_a?(String)),
     *etiquetas.map { |etiqueta| frase(:campanha_etiqueta_de_fora, passo: id, id: etiqueta) }]
  end

  # Cada variável com texto fixo de verdade: a campanha vai para muita gente (sem dado do contato), e só espaço
  # mandaria o parâmetro vazio para todo o público.
  def self.variaveis_escritas?(modelo)
    Array(modelo&.dig('variaveis')).all? do |partes|
      lista = Array(partes)
      lista.all?(String) && lista.join.split.any?
    end
  end

  def self.frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  # A campanha de WhatsApp da tela só sai pelo número oficial na Cloud API (Whatsapp::OneoffCampaignService).
  def self.caixa_da_campanha(conta, id)
    caixa = conta.inboxes.find_by(id: id, channel_type: CANAL)
    caixa if caixa&.channel.try(:provider) == PROVEDOR
  end

  # O gatilho que roda na conta inteira, não numa conversa, card ou contato. Contrato com a G7 (#2499): o
  # `conta.recorrente` entra em Gatilhos::LISTA com alvo 'Account'.
  def self.gatilho_da_conta?(tipo)
    ::Autonomia::Automacao::Gatilhos.alvo(tipo) == ALVO_DA_CONTA
  end

  def self.pode_disparar?(usuario, conta)
    account_user = usuario && conta.account_users.find_by(user_id: usuario.id)
    account_user.present? && CampaignPolicy.new({ user: usuario, account: conta, account_user: account_user }, Campaign).send_campaign?
  end

  # O modelo da caixa, pronto para a campanha: o template_params que a tela de campanhas grava, ou o motivo (texto).
  def self.modelo_pronto(caixa, modelo)
    item = caixa && ROTA.synced_template(caixa, ModeloWhatsapp.configurado(modelo))
    return 'modelo_fora_da_caixa' if item.nil?
    return 'modelo_nao_aprovado' unless ModeloWhatsapp.aprovado?(item)
    return 'modelo_de_categoria_fora' unless CATEGORIAS.include?(item['category'].to_s.upcase)

    variaveis = Array(modelo['variaveis'])
    return 'modelo_mudou' unless ModeloWhatsapp.encaixa?(item, variaveis.size)

    corpo = variaveis.each_with_index.to_h { |partes, indice| [(indice + 1).to_s, Array(partes).join.split.join(' ')] }
    { 'name' => item['name'], 'language' => item['language'], 'category' => item['category'], 'processed_params' => { 'body' => corpo } }
  end

  def self.texto_do_modelo(caixa, template_params)
    item = ROTA.synced_template(caixa, template_params.slice('name', 'language'))
    template_params.dig('processed_params', 'body').reduce(ROTA.native_body(item)) do |texto, (posicao, valor)|
      texto.gsub("{{#{posicao}}}") { valor }
    end
  end

  def initialize(execucao:, passo:, alvo:)
    @execucao = execucao
    @passo = passo
    @alvo = alvo
    @automacao = execucao.automacao
    @conta = execucao.account
    @quem = @automacao.ligada_por
  end

  def executar
    @passo['faz'] == 'disparar' ? disparar : nao_receber
  end

  private

  def disparar
    return pulado('campanha_so_sem_alvo') unless @alvo.is_a?(::Account)
    return sem_acesso('quem_ligou_sem_permissao_campanha') unless self.class.pode_disparar?(@quem, @conta)

    caixa = self.class.caixa_da_campanha(@conta, @passo['caixa_id'])
    return pulado('campanha_sem_caixa') if caixa.nil?
    return pulado('campanha_desligada') unless @conta.feature_enabled?(FLAG_DA_CAMPANHA)
    return pulado('campanha_variavel_vazia') unless self.class.variaveis_escritas?(@passo['modelo'])

    template_params = self.class.modelo_pronto(caixa, @passo['modelo'])
    return pulado("campanha_#{template_params}") if template_params.is_a?(String)

    publico_escolhido(caixa, template_params)
  end

  # Quem recebe: quem tem as etiquetas (G14) ou só quem os passos anteriores desta execução criaram (G58).
  def publico_escolhido(caixa, template_params)
    return criar_e_disparar(caixa, template_params) unless self.class.desta_execucao?(@passo)

    ::Autonomia::Automacao::CampanhaDaExecucao.new(execucao: @execucao, passo: @passo, caixa: caixa, template_params: template_params).disparar
  end

  def criar_e_disparar(caixa, template_params)
    etiquetas = @conta.labels.where(id: @passo['etiquetas']).pluck(:id)
    return pulado('campanha_sem_etiqueta') if etiquetas.empty?

    campanha = @conta.campaigns.create!(
      title: @passo['titulo'], inbox: caixa, sender: @quem, scheduled_at: Time.current, template_params: template_params,
      message: self.class.texto_do_modelo(caixa, template_params), audience: etiquetas.map { |id| { 'type' => 'Label', 'id' => id } }
    )
    ::Campaigns::TriggerOneoffCampaignJob.perform_later(campanha)
    Resultado.new(tipo: :ok, motivo: nil, dados: { 'campanha_id' => campanha.display_id, 'etiquetas' => etiquetas })
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.info("[automacao][campanha] recusada automacao=#{@automacao.id} erro=#{e.record.errors.attribute_names.join(',')}")
    pulado('campanha_recusada')
  end

  def nao_receber
    contato = ::Autonomia::Automacao::Contexto.de(@alvo).contato
    return pulado('sem_contato') if contato.nil?
    return sem_acesso('quem_ligou_sem_acesso') unless ::Autonomia::Automacao::Acesso.new(@automacao).alcanca?(contato)
    return pulado('contato_ja_nao_recebe', contato) if contato.opted_out?

    contato.opt_out!(source: 'manual', by: @quem)
    Resultado.new(tipo: :ok, motivo: nil, dados: { 'contato_id' => contato.id })
  end

  def pulado(motivo, contato = nil)
    Resultado.new(tipo: :pulado, motivo: motivo, dados: contato ? { 'contato_id' => contato.id } : {})
  end

  def sem_acesso(motivo) = Resultado.new(tipo: :sem_acesso, motivo: motivo, dados: {})
end
