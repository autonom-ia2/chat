# O passo "campanha" (#2414 G14, #2630). Duas coisas, escolhidas em `faz`:
#
# - `disparar`: monta a campanha de WhatsApp oficial (caixa, modelo aprovado, público = etiquetas) pela mesma
#   `account.campaigns.create!` da API de campanhas e a põe na fila do disparo (Campaigns::TriggerOneoffCampaignJob, o
#   mesmo job do agendador). Quem manda é o Whatsapp::OneoffCampaignService (e o overlay do EE): ele lê o público no
#   disparo, relê a recusa de cada contato antes de mandar e manda o modelo. Nada sai por um caminho próprio daqui.
#   `sem_etiquetas` (lote 5, #2681) deixa de fora quem tem uma delas, mesmo com etiqueta do público
#   (Autonomia::Automacao::CampanhaSemEtiquetas). `publico: todos` (exemplo 7, passo 2: "a mesma campanha para todos os
#   outros contatos") manda para todos os contatos da conta, sem etiqueta de público, menos os de `sem_etiquetas`. A
#   recusa de cada contato (quem pediu para não receber) continua valendo no envio, como em toda campanha.
#   Só em gatilho recorrente (G7). No `conta.recorrente` (alvo = a própria Account) a execução é uma por vez e cria a
#   campanha na hora. No `card.recorrente` e no `contato.recorrente` (G55, exemplo 16) há uma execução por card ou
#   contato da vez, e a campanha é uma só para a vez inteira (Autonomia::Automacao::CampanhaDaOcorrencia). Num gatilho
#   de evento (conversa, card ou contato que muda), cada execução criaria uma campanha nova para o mesmo público, o
#   mesmo envio N vezes, e não há "vez" que as junte. A Receita recusa ao salvar; a receita que chegar assim mesmo pula
#   com `campanha_so_sem_alvo`. Não é teto de uso, é a regra de não repetir o mesmo envio.
#   `publico: desta_execucao` (G58, #2779) troca as etiquetas pelos contatos que os passos anteriores desta execução
#   criaram (Autonomia::Automacao::CampanhaDaExecucao): a campanha da 2ª segunda não volta a quem recebeu na 1ª só por
#   ter a etiqueta do mês. Só no `conta.recorrente`, em que a execução é a vez inteira: no recorrente de card ou contato
#   cada execução é um card, e a campanha "desta execução" sairia uma por card, fora da campanha da vez (G55). A Receita
#   recusa ao salvar (`campanha_desta_execucao_so_na_conta`) e a receita que chegar assim mesmo pula, também ao fechar a
#   vez (o registro da vez diz por quê).
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
  # Utilidade e propaganda, aprovados, como a tela de campanhas (decisão do Rodrigo, 06/11: "Sim, com aviso"); as mesmas
  # do passo mensagem desde o lote 5 (#2681). O editor avisa o custo do modelo de propaganda.
  CATEGORIAS = ModeloWhatsapp::CATEGORIAS
  CANAL = ModeloWhatsapp::CANAL
  PROVEDOR = 'whatsapp_cloud'.freeze
  FLAG_DA_CAMPANHA = :whatsapp_campaign
  ALVO_DA_CONTA = 'Account'.freeze
  PUBLICO_DESTA_EXECUCAO = 'desta_execucao'.freeze
  PARA_TODOS = 'todos'.freeze

  # O que a Receita confere ao salvar (#2630). Sem conta (o catálogo das receitas prontas), só o que não depende dela.
  # `alvo`: o tipo do registro em que o passo roda (Receita#alvo); o ramo do "em outro registro" nunca roda na conta.
  def self.problemas_ao_salvar(passo, receita, alvo:, conta:, account_user:)
    id = passo['id']
    desligado = conta && !::Autonomia::Automacao::Motor.mensagens?(conta) ? [frase(:passo_desligado, passo: id)] : []
    return desligado unless passo['faz'] == 'disparar'

    desligado + problemas_do_disparo(passo, receita, conta, alvo, account_user) + problemas_do_publico(passo, receita, alvo)
  end

  # G58: o público desta execução precisa de um passo antes dele que crie card ou contato; sem ele, sairia sempre vazio.
  # E só vale no gatilho da conta (a execução é a vez inteira).
  def self.problemas_do_publico(passo, receita, alvo)
    return [] unless desta_execucao?(passo)
    return [frase(:campanha_desta_execucao_so_na_conta, passo: passo['id'])] unless alvo_da_conta?(alvo)

    receita_obj = ::Autonomia::Automacao::Receita.new(receita, conta: nil, account_user: nil)
    antes = ::Autonomia::Automacao::TextoDaIaNaReceita.new(receita_obj, receita).rodam_antes(passo['id'])
    criam = ::Autonomia::Automacao::ContatosDaExecucao::TIPOS_QUE_CRIAM
    Array(antes).any? { |anterior| criam.include?(anterior['tipo']) } ? [] : [frase(:campanha_publico_sem_origem, passo: passo['id'])]
  end

  def self.desta_execucao?(passo) = passo['publico'] == PUBLICO_DESTA_EXECUCAO

  def self.problemas_do_disparo(passo, receita, conta, alvo, account_user)
    id = passo['id']
    lista = [*(frase(:campanha_so_sem_alvo, passo: id) unless roda_por_vez?(alvo, receita)),
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
    pedidas = Array(passo['etiquetas']) + Array(passo['sem_etiquetas'])
    etiquetas = pedidas - conta.labels.where(id: pedidas).pluck(:id)
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

  # O passo roda na conta inteira, não numa conversa, card ou contato. Contrato com a G7 (#2499): o `conta.recorrente`
  # entra em Gatilhos::LISTA com alvo 'Account'. `alvo`: Receita#alvo.
  def self.alvo_da_conta?(alvo) = alvo == ALVO_DA_CONTA

  # O passo que roda por vez (G7): na conta e, desde a G55, no recorrente de card ou contato, em que a campanha é uma
  # só para a vez inteira. O ramo do "em outro registro" não tem gatilho próprio (EmOutroRegistro): fica de fora.
  def self.roda_por_vez?(alvo, receita)
    alvo_da_conta?(alvo) || ::Autonomia::Automacao::Gatilhos.recorrente?(receita.to_h.dig('gatilho', 'tipo'))
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
    @automacao = execucao.dona
    @conta = execucao.account
    @quem = @automacao.ligada_por
  end

  def executar
    @passo['faz'] == 'disparar' ? disparar : nao_receber
  end

  # G55: a campanha da vez que fechou, montada pelo caminho da conta (alvo = a conta) sem pôr na fila do disparo. Quem
  # chama (CampanhaDaOcorrencia) cria a campanha e fecha a vez na mesma transação e enfileira depois do commit.
  # [Resultado, a campanha criada ou nil].
  def montar
    @so_montar = true
    [disparar, @campanha]
  end

  private

  def disparar
    return pulado('campanha_so_sem_alvo') unless da_vez?
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
    # A execução da conta, não a do alvo em que o passo roda: ao fechar a vez (montar), o alvo é a conta, mas a execução
    # é a de um card.
    return pulado('campanha_desta_execucao_so_na_conta') unless self.class.alvo_da_conta?(@execucao.alvo_type)

    ::Autonomia::Automacao::CampanhaDaExecucao.new(execucao: @execucao, passo: @passo, caixa: caixa, template_params: template_params).disparar
  end

  def criar_e_disparar(caixa, template_params)
    todos = @passo['publico'] == PARA_TODOS
    etiquetas = todos ? [] : @conta.labels.where(id: @passo['etiquetas']).pluck(:id)
    return pulado('campanha_sem_etiqueta') if etiquetas.empty? && !todos

    sem = excluidas_existentes
    return pulado('campanha_exclusao_apagada') if sem.nil?

    publicar(caixa, template_params, todos, etiquetas, sem)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.info("[automacao][campanha] recusada automacao=#{@automacao.id} erro=#{e.record.errors.attribute_names.join(',')}")
    pulado('campanha_recusada')
  end

  # Na conta, a campanha sai agora; no card ou contato do recorrente, a execução entra na campanha da vez (G55).
  def publicar(caixa, template_params, todos, etiquetas, sem)
    dados = { 'publico' => todos ? PARA_TODOS : 'etiquetas', 'etiquetas' => etiquetas, 'sem_etiquetas' => sem }
    return campanha_da_vez(dados) unless da_conta?

    campanha_da_conta(caixa, template_params, audiencia(todos, etiquetas, sem), dados)
  end

  # As etiquetas excluídas, ou nil quando alguma sumiu. Falha fechada (#2686): a que sumiu não pode cair da exclusão,
  # senão a campanha "para todos menos X" iria também para X.
  def excluidas_existentes
    pedidas = Array(@passo['sem_etiquetas']).map(&:to_i).uniq
    existentes = @conta.labels.where(id: pedidas).pluck(:id)
    existentes if (pedidas - existentes).empty?
  end

  def criar_campanha(caixa, template_params, audiencia)
    @conta.campaigns.create!(
      title: @passo['titulo'], inbox: caixa, sender: @quem, scheduled_at: Time.current, template_params: template_params,
      message: self.class.texto_do_modelo(caixa, template_params), audience: audiencia
    )
  end

  # O conta.recorrente: uma execução por vez, a campanha sai na hora.
  def campanha_da_conta(caixa, template_params, audiencia, dados)
    campanha = @campanha = criar_campanha(caixa, template_params, audiencia)
    ::Campaigns::TriggerOneoffCampaignJob.perform_later(campanha) unless @so_montar
    Resultado.new(tipo: :ok, motivo: nil, dados: { 'campanha_id' => campanha.display_id, **dados })
  end

  def da_conta? = @alvo.is_a?(::Account)

  # Roda por vez: na conta (conta.recorrente) ou num card ou contato do recorrente (G55).
  def da_vez? = da_conta? || ocorrencia.present?

  # G55: no card.recorrente e no contato.recorrente, a execução chega à campanha da vez e segue. A campanha sai quando a
  # vez fecha (CampanhaDaOcorrencia, conferida pelo Executor depois de gravar este registro). Na vez já fechada: "já
  # saiu" só se a campanha saiu de fato; senão, "não saiu".
  def campanha_da_vez(dados)
    vez = ::Autonomia::Automacao::CampanhaDaOcorrencia.chegada(@execucao, @passo['id'])
    marca = { 'campanha_da_vez' => vez.id, **dados }
    return Resultado.new(tipo: :ok, motivo: 'campanha_da_vez_aguardando', dados: marca) unless vez.fechada_em
    return Resultado.new(tipo: :pulado, motivo: 'campanha_da_vez_fechou_sem_enviar', dados: marca) unless vez.campanha_display_id

    Resultado.new(tipo: :pulado, motivo: 'campanha_da_vez_ja_saiu', dados: marca.merge('campanha_id' => vez.campanha_display_id))
  end

  # A vez do recorrente de card ou contato desta execução, ou nil fora dele.
  def ocorrencia = (@ocorrencia ||= ::Autonomia::Automacao::CampanhaDaOcorrencia.vez_da(@execucao))

  # As etiquetas do público (ou todos os contatos) e as excluídas (lote 5, #2681: ExcludeLabel e AllContacts, lidos pelo
  # CampanhaSemEtiquetas no envio).
  def audiencia(todos, etiquetas, sem)
    publico = todos ? ::Autonomia::Automacao::CampanhaSemEtiquetas.todos : etiquetas.map { |id| { 'type' => 'Label', 'id' => id } }
    publico + ::Autonomia::Automacao::CampanhaSemEtiquetas.audiencia(sem)
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
