# O alvo de uma execução e as pontes dele (#2499, F6): a conversa, o card ou o contato em que a automação roda, e os
# outros dois quando há caminho até eles. O Valores, os passos e o Spam leem por aqui, nunca supondo a conversa.
#
# | alvo     | conversa                             | card | contato           |
# | conversa | ela (ou a do número novo, G43)       | —    | conversa.contact  |
# | card     | card.primary_conversation (pode faltar) | ele | card.contact, senão o da conversa |
# | contato  | — (a da conversa nova, #2680, ou a do número novo) | — | ele    |
# | conta    | —                                    | —    | —                 |
#
# A conta (#2635, G7) é o alvo do conta.recorrente: a execução da ocorrência, sem conversa, card nem contato. Nenhum
# caminho do Valores começa nela; o salvar só deixa nesse gatilho os passos que não pedem alvo.
#
# Contrato com a F2 (#2498, histórico e ensaio): `rotulo`, `link` e `visivel_para?(usuario)`. O rótulo sai do i18n e do
# registro na hora, nunca é gravado.
class Autonomia::Automacao::Contexto
  TIPOS = %w[Conversation Crm::Card Contact Account].freeze
  BASES = { ::Conversation => 'conversa', ::Crm::Card => 'card', ::Contact => 'contato', ::Account => 'conta' }.freeze

  attr_reader :alvo, :execucao

  # `execucao`: a execução em que o passo roda, quando há uma. A reunião do gatilho (G12), o texto da IA (#2679) e o
  # "gatilho repetiu" (lote 4) leem dela.
  # `textos`: no ensaio, que não tem execução, o texto que cada passo de IA produziria (só para mostrar).
  # `evento`: na partida, que ainda não tem execução, a marca do fato que disparou (G9: o filtro lê quem cuidava antes).
  # `fato`: no ensaio, que não tem a marca da execução, o registro que o gatilho traria: a última mensagem recusada da
  # conversa (G53), que o Ensaio acha pela régua do gatilho, ou a reunião do card que o gatilho de reunião leria (#2631,
  # CardsDoEnsaio).
  def self.de(alvo, **) = new(alvo, **)

  # Os `textos` do ensaio (#2679): ele não chama a IA, e no lugar do texto de cada passo que escreve vai a marca de onde
  # ele entraria. Do "para cada item" (G24), uma marca por valor (`<id>.quantos`, `<id>.nomes`).
  # Do "buscar em outro sistema" (#2934), que o ensaio não chama sem a pessoa pedir, a marca de cada dado guardado.
  def self.marcas_da_ia(receita, conta)
    passos = ::Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: nil).passos
    passos.flat_map { |passo| chaves_da_ia(passo) }
          .index_with { |chave| I18n.t('autonomia.automacao.ensaio.texto_da_ia', passo: chave) }
          .merge(marcas_da_consulta(passos))
  end

  def self.marcas_da_consulta(passos)
    passos.select { |passo| passo['tipo'] == 'consultar' }.to_h do |passo|
      marcas = Array(passo['guardar']).to_h do |dado|
        [::Autonomia::Automacao::PassoConsultar.chave(dado['nome']), I18n.t('autonomia.automacao.ensaio.dado_buscado', nome: dado['nome'])]
      end
      ["#{::Autonomia::Automacao::PassoConsultar::CHAVE}#{passo['id']}", marcas]
    end
  end

  def self.chaves_da_ia(passo)
    return [passo['id']] if ::Autonomia::Automacao::Valores::PASSOS_QUE_ESCREVEM.include?(passo['tipo'])
    return [] unless passo['tipo'] == 'para_cada'

    ::Autonomia::Automacao::PassoParaCada::VALORES.map { |valor| "#{passo['id']}.#{valor}" }
  end

  def initialize(alvo, execucao: nil, textos: nil, evento: nil, fato: nil)
    @alvo = alvo
    @execucao = execucao
    @textos = textos
    @evento = evento
    @mensagem_que_falhou = fato if fato.is_a?(::Message)
    @reuniao = fato if fato.is_a?(::Crm::Meeting)
  end

  # A marca do fato que disparou: a da partida ou a da execução. No ensaio, nil.
  def evento = @evento || @execucao&.evento

  def conversa
    return numero_novo || @alvo if @alvo.is_a?(::Conversation)
    return conversa_do_card || conversa_nova if @alvo.is_a?(::Crm::Card)

    numero_novo || conversa_nova
  end

  # G43 (#2700): depois que o passo "mensagem" mandou no número novo do contato, os passos seguintes usam aquela
  # conversa, achada pelo registro dele. O card não precisa: a conversa do número novo já virou a principal. Guarda só a
  # achada: antes do passo "mensagem", a próxima pergunta procura de novo.
  def numero_novo
    return unless @execucao

    @numero_novo ||= begin
      registro = @execucao.registros.where(resultado: 'ok').where("dados ? 'numero_novo'").order(:id).last
      id = registro&.dados&.dig('conversa_aberta')
      id && ::Conversation.find_by(account_id: @execucao.account_id, display_id: id)
    end
  end

  # Quem não tem conversa (o card sem conversa principal, o contato) usa a que a receita abriu na caixa da conversa nova
  # (ConversaNova, #2680): a do contato nessa caixa. Sem execução (o ensaio, a partida) não há caixa escolhida. Guarda
  # só a achada: antes de o passo "mensagem" abrir, a próxima pergunta procura de novo.
  def conversa_nova
    return unless @execucao

    conversa_nova = ::Autonomia::Automacao::ConversaNova
    @conversa_nova ||= conversa_nova.existente(conversa_nova.da_execucao(@execucao), contato)
  end

  def card = (@alvo if @alvo.is_a?(::Crm::Card))

  # A filha do "em outro registro" (G18) num card do mesmo contato age na conversa da mãe; o resto, na principal do card.
  def conversa_do_card
    return @conversa_do_card if defined?(@conversa_do_card)

    @conversa_do_card = ::Autonomia::Automacao::EmOutroRegistro.conversa_da_mae(@execucao, @alvo) || @alvo.primary_conversation
  end

  # A seleção do gatilho recorrente na versão desta execução (G22: a condição `solicitante_de`). Sem execução, nil.
  def selecao = @execucao&.versao&.receita.to_h.dig('gatilho', 'selecao')

  # G65 (#2842): na filha do "em outro registro", o Contexto do alvo da mãe (o registro de origem), com as pontes dela;
  # fora da filha, nil. Só com quem ligou ainda alcançando esse registro (a mesma pergunta do impedimento,
  # Acesso#alcanca?): quem perdeu o funil do João entre a mãe e a filha não manda os dados dele à Maria. Fora do alcance,
  # nil (lê vazio), e o Executor pula o passo que lê a origem com o motivo próprio (`origem_fora_do_alcance?`).
  def origem
    return @origem if defined?(@origem)

    mae = mae_com_alvo
    @origem = mae && origem_ao_alcance?(mae) ? self.class.de(mae.alvo, execucao: mae) : nil
  end

  # A filha tem registro de origem, e quem ligou deixou de alcançá-lo.
  def origem_fora_do_alcance?
    mae = mae_com_alvo
    mae.present? && !origem_ao_alcance?(mae)
  end

  # A conta do alvo; no conta.recorrente, a própria.
  def conta = (@alvo.is_a?(::Account) ? @alvo : @alvo.account)

  def conta_id = (@alvo.is_a?(::Account) ? @alvo.id : @alvo.account_id)

  def contato
    return @alvo if @alvo.is_a?(::Contact)
    return @alvo.contact if @alvo.is_a?(::Conversation)

    @alvo.contact || @alvo.primary_conversation&.contact if @alvo.is_a?(::Crm::Card)
  end

  # A reunião do gatilho de reunião (G12): a da atividade que disparou, achada pela marca da execução e sempre presa ao
  # card e à conta do alvo (parecer do Funções), nunca só pelo id. Num passo que roda dias depois ela é relida: a
  # reunião remarcada de novo traz o horário novo. Fora do gatilho de reunião, ou sem a atividade, nil. No ensaio, a
  # que chegou em `fato`.
  def reuniao
    return @reuniao if defined?(@reuniao)

    @reuniao = (reuniao_da_atividade if card && @execucao && ::Autonomia::Automacao::Gatilhos.de_reuniao?(@execucao.chave_gatilho))
  end

  # G50: a etapa escolhida no gatilho da versão em que a execução entrou (`card.entrou_de_novo`). Sem execução, nil.
  def etapa_do_gatilho = @execucao&.versao&.receita.to_h.dig('gatilho', 'etapa_id')

  # A última mensagem que esta execução mandou ao cliente (#2680, `envio.*`), pelo `mensagem_id` dos registros dos
  # passos: o "mensagem", o "escrever" e o "email". A nota do "avisar" também leva o id, mas não é envio ao cliente.
  def ultimo_envio
    return unless @execucao

    ids = @execucao.registros.where(resultado: 'ok').where("dados ? 'mensagem_id'").pluck(Arel.sql("dados->>'mensagem_id'"))
    # reorder: a Message ordena por created_at no default_scope, e o order só desempataria.
    ::Message.where(account_id: @execucao.account_id, id: ids, private: false, message_type: :outgoing).reorder(id: :desc).first
  end

  # G53: a mensagem que disparou o gatilho "mensagem que falhou", achada pela marca da execução (o passo roda depois, sem
  # ela). Sempre presa à conta e à conversa do alvo, e só a que saiu para o cliente, nunca só pelo id (a mesma regra da
  # reunião). Fora desse gatilho, ou sem a mensagem, nil. No ensaio, a que chegou em `fato`.
  # A conversa é a do alvo (a do gatilho), nunca `conversa`: depois do envio ao número novo (G43), `conversa` passa a
  # ser a do número novo, e a mensagem que falhou ficou na antiga.
  def mensagem_que_falhou
    return @mensagem_que_falhou if defined?(@mensagem_que_falhou)

    @mensagem_que_falhou = (buscar_mensagem_que_falhou if @execucao && @alvo.is_a?(::Conversation) &&
                                                          @execucao.chave_gatilho == ::Autonomia::Automacao::MensagemQueFalhou::TIPO)
  end

  # #2679: o texto que o passo de IA `passo_id` produziu nesta execução (Execucao#guardar_texto!). Antes do passo rodar,
  # nil.
  def texto_da_ia(passo_id) = (@textos || @execucao&.textos).to_h[passo_id.to_s]

  # #2934: o dado que o "buscar em outro sistema" guardou nesta execução (PassoConsultar). No ensaio, a marca do dado.
  def consulta(passo_id, chave) = (@textos || @execucao&.textos).to_h["#{::Autonomia::Automacao::PassoConsultar::CHAVE}#{passo_id}"].to_h[chave]

  # G49: o id do registro que o passo `passo_id` criou nesta execução; sem execução (o ensaio) ou antes do passo, nil.
  def criado(passo_id) = ::Autonomia::Automacao::RegistroCriado.da_execucao(@execucao, passo_id)&.dig('id')

  # "conversa", "card" ou "contato": a base dos caminhos do Valores que o alvo tem sem ponte.
  def base
    BASES.find { |classe, _| @alvo.is_a?(classe) }&.last
  end

  # O Spam (F3.5) vale para a conversa, para a conversa principal do card e para o contato cuja única conversa está lá.
  def no_spam?
    return ::ConversaCanal::PastaDoEmail.no_spam?(conversa) if conversa
    return false unless @alvo.is_a?(::Contact)

    conversas = ::Conversation.where(account_id: @alvo.account_id, contact_id: @alvo.id).limit(2).to_a
    conversas.one? && ::ConversaCanal::PastaDoEmail.no_spam?(conversas.first)
  end

  def rotulo
    case @alvo
    when ::Conversation then I18n.t('autonomia.automacao.alvo.conversa', id: @alvo.display_id)
    when ::Crm::Card then I18n.t('autonomia.automacao.alvo.card', id: @alvo.id, titulo: @alvo.title)
    when ::Contact then I18n.t('autonomia.automacao.alvo.contato', nome: @alvo.name.presence || @alvo.id)
    when ::Account then I18n.t('autonomia.automacao.alvo.conta')
    end
  end

  def link
    conta = conta_id
    case @alvo
    when ::Conversation then "accounts/#{conta}/conversations/#{@alvo.display_id}"
    when ::Crm::Card then "accounts/#{conta}/crm?pipeline_id=#{@alvo.pipeline_id}&card_id=#{@alvo.id}"
    when ::Contact then "accounts/#{conta}/contacts/#{@alvo.id}"
    when ::Account then "accounts/#{conta}/automacoes"
    end
  end

  # A mesma pergunta que a leitura faria: a política da conversa (view?, que no EE também deixa quem só lê,
  # conversation_view), a do card ou a do contato. Para agir no alvo, a pergunta é a do Acesso#alcanca?.
  def visivel_para?(usuario)
    account_user = usuario && conta.account_users.find_by(user_id: usuario.id)
    return false unless account_user
    # A execução da conta mostra o que a automação fez (a campanha, os passos): só quem vê as automações.
    return account_user.permission_granted?('automation_view') if @alvo.is_a?(::Account)

    contexto = { user: usuario, account: conta, account_user: account_user }
    case @alvo
    when ::Conversation then ConversationPolicy.new(contexto, @alvo).view?
    when ::Crm::Card then ::Crm::CardPolicy.new(contexto, @alvo).show?
    when ::Contact then ContactPolicy.new(contexto, @alvo).show?
    else false
    end
  end

  private

  def mae_com_alvo
    return @mae_com_alvo if defined?(@mae_com_alvo)

    mae = ::Autonomia::Automacao::EmOutroRegistro.mae(@execucao)
    @mae_com_alvo = (mae if mae&.alvo)
  end

  # Quem ligou é o da dona da mãe (#2933): no "em outro registro" dentro de um bloco, a mãe é a execução do bloco, que
  # age como quem ligou a automação de cima.
  def origem_ao_alcance?(mae)
    return @origem_ao_alcance if defined?(@origem_ao_alcance)

    @origem_ao_alcance = ::Autonomia::Automacao::Acesso.new(mae.dona, chave_gatilho: mae.chave_gatilho).alcanca?(mae.alvo, mae)
  end

  def buscar_mensagem_que_falhou
    id = ::Autonomia::Automacao::MensagemQueFalhou.id_da_marca(@execucao.evento)
    id && ::Message.find_by(account_id: conta_id, conversation_id: @alvo.id, id: id, message_type: :outgoing, private: false)
  end

  def reuniao_da_atividade
    reuniao = ::Autonomia::Automacao::ReuniaoDaAtividade
    gatilhos = ::Autonomia::Automacao::Gatilhos
    return reuniao.do_lembrete(card, @execucao.evento) if @execucao.chave_gatilho == gatilhos::LEMBRETE

    reuniao.de(card, gatilhos.atividade_da_marca(@execucao.evento))
  end
end
