# G18 (#2671): o passo "em outro registro" age num registro ligado ao alvo, e não no próprio alvo. Exemplos 11 (o card
# do João, ganho, avisa a Maria, que o indicou) e 16 (a resposta lê o motivo da perda no card antigo do mesmo contato).
#
# A ligação vem de uma lista fechada, nunca de texto livre:
# - `contato_do_campo`: o contato cujo id está num valor do alvo (`card.atributos.indicado_por`). `usar` diz em que o
#   ramo roda: no contato, ou na conversa mais recente dele (onde a mensagem sai);
# - `cards_do_contato`: os cards do contato do alvo (menos o próprio alvo), filtrados por funil, etapa e situação, ou só
#   o mais recente deles.
# - `criado_no_passo` (G49): o registro que um passo anterior desta execução criou (`passo`: o id dele): o contato do
#   `POST contacts` ou o card do "criar card" (RegistroCriado). Exemplo 11, passo 5: a mensagem ao João sai no card dele.
#
# O ramo (`passos`) roda numa execução própria por registro achado: a "filha". A mãe só lê a âncora (o id do contato) e
# segue; quem procura os registros e abre as filhas é o EmOutroRegistroJob, fora da rodada da mãe. A filha:
# - é marcada pelo `evento` (`em:<mãe>:<base>:<id do registro>:<passo>`), e o índice único (automacao_id, evento)
#   garante uma execução só por registro;
# - herda a cadeia da mãe (D6): a mudança que ela faz não redispara a própria automação (:auto_disparo);
# - roda só o ramo (Roteiro.da) e passa por tudo que o alvo passa, a cada ação (Executor#impedimento): conta, quem
#   ligou, alcance e, no card, a chave de funis (Acesso#motivo_no).
# "Em outro registro" dentro do ramo de outro é recusado ao salvar: a filha nunca abre netas. Não há teto de registros
# (regra do Rodrigo, 31/10): todo registro que a ligação acha ganha a filha dele.
module Autonomia::Automacao::EmOutroRegistro
  TIPO = 'em_outro_registro'.freeze
  MARCA = 'em'.freeze
  # A base de cada alvo possível da filha, para a marca (o nome da classe tem "::", que a marca usa como separador).
  BASES = { 'Contact' => 'contato', 'Conversation' => 'conversa', 'Crm::Card' => 'card' }.freeze
  # Onde o `contato_do_campo` acha o id do contato: só um campo do card do tipo contato (decisão 16), que a equipe
  # preenche escolhendo um contato da conta numa lista, e o card recusa contato de fora (Crm::CardCampoContato). Campo
  # de número não serve: um engano (o número de um pedido, um protocolo) mandaria a mensagem a outro cliente da conta.
  CAMPOS_DO_CONTATO = %w[card.atributos].freeze

  module_function

  def do_tipo?(passo) = passo['tipo'] == TIPO

  # O tipo do registro em que o ramo roda: é contra ele que o salvar confere os valores lidos no ramo. No
  # `criado_no_passo` (G49), o do registro que o passo cria, achado na `receita` (nil se o passo não cria).
  def alvo_do_ramo(passo, receita)
    registro = passo['registro'].to_h
    return 'Crm::Card' if registro['de'] == 'cards_do_contato'
    return criado_pelo(registro['passo'], receita) if registro['de'] == CRIADO

    registro['usar'] == 'conversa' ? 'Conversation' : 'Contact'
  end

  CRIADO = 'criado_no_passo'.freeze

  def criado_pelo(passo_id, receita)
    ::Autonomia::Automacao::RegistroCriado.tipo_do_passo(::Autonomia::Automacao::Roteiro.new(receita.to_h).passo(passo_id))
  end

  # O tipo do registro criado de cada "em outro registro" com a ligação `criado_no_passo` (a conversa nova, G49). As
  # outras ligações acham registros que já existem, e a caixa da conversa nova continua só nos gatilhos de card e contato.
  def alvos_dos_criados(passos, receita)
    passos.filter_map { |passo| alvo_do_ramo(passo, receita) if do_tipo?(passo) && passo.dig('registro', 'de') == CRIADO }
  end

  # Pede a chave de funis, como o gatilho de card e a ação de funil (controller#de_funil?), ao salvar e a cada rodada
  # (PassoEmOutroRegistro): a ligação que lê cards do CRM, e o ramo que roda numa conversa e lê o card dela (#2716,
  # decisão 19: só para ler), qualquer que seja o gatilho. Sem ela, a filha leria o card sempre vazio.
  def de_funil?(passo, receita)
    return false unless do_tipo?(passo)

    alvo = alvo_do_ramo(passo, receita)
    alvo == 'Crm::Card' || (alvo == 'Conversation' && ::Autonomia::Automacao::CardDaConversa.le?(passo['passos']))
  end

  def marca(mae, registro, passo_id) = [MARCA, mae.id, BASES.fetch(registro.class.name), registro.id, passo_id].join(':')

  # [id da mãe, id do passo] da filha; nil na execução que não é filha. O id do passo vai por último: ele pode ter ":".
  def da(execucao)
    prefixo, mae_id, _base, _id, passo_id = execucao&.evento.to_s.split(':', 5)
    [mae_id.to_i, passo_id] if prefixo == MARCA && passo_id.present?
  end

  # A execução mãe da filha, sempre na conta dela; nil na execução que não é filha.
  def mae(execucao)
    mae_id, = da(execucao)
    mae_id && ::Autonomia::Automacao::Execucao.find_by(id: mae_id, account_id: execucao.account_id)
  end

  # A conversa em que a filha num card age (decisão da Automação, 07/11): a da mãe, quando o card é do mesmo contato
  # do alvo dela (a resposta do exemplo 16 sai na conversa em que o cliente escreveu); senão nil, e vale a do card.
  def conversa_da_mae(execucao, card)
    alvo_da_mae = mae(execucao)&.alvo
    return unless alvo_da_mae

    contexto = ::Autonomia::Automacao::Contexto.de(alvo_da_mae)
    contexto.conversa if contexto.contato && contexto.contato.id == card.contact_id
  end

  # Frases do salvar. `dentro`: o passo está no ramo de outro "em outro registro". O ramo é conferido como uma receita
  # cujo alvo é o registro (Receita com `alvo:`); o valor da âncora, pela régua do alvo da mãe (o bloco).
  # `receita`: a receita inteira, de onde sai o tipo do registro criado (G49) e o tipo do alvo do gatilho da mãe, onde o
  # ramo lê `origem.*` (G65).
  def problemas_ao_salvar(passo, conta:, account_user:, dentro:, receita:, &)
    id = passo['id']
    return [texto(:aninhado, passo: id)] if dentro

    ligacao = da_ligacao(id, passo['registro'].to_h, conta, account_user, &)
    alvo = alvo_do_ramo(passo, receita)
    return ligacao if alvo.nil?

    ramo = { 'gatilho' => {}, 'passos' => passo['passos'] }
    origem = ::Autonomia::Automacao::Gatilhos.alvo(receita.to_h.dig('gatilho', 'tipo'))
    [*ligacao, *::Autonomia::Automacao::Receita.new(ramo, conta: conta, account_user: account_user, alvo: alvo, origem: origem).problemas]
  end

  # O campo do contato só aceita campo do card do tipo Contato (decisão 16, do_campo); o `criado_no_passo` (G49) é
  # conferido como o valor `criado.<passo>`.
  def da_ligacao(id, registro, conta, account_user, &)
    return do_campo(id, registro.dig('campo', '$valor'), conta, &) if registro['de'] == 'contato_do_campo'
    return [*yield("#{::Autonomia::Automacao::RegistroCriado::PREFIXO}#{registro['passo']}")] if registro['de'] == CRIADO

    chave = account_user && !::Autonomia::Automacao::RegraDoFunil.chave?(account_user) ? [texto(:sem_chave_de_funis, passo: id)] : []
    chave + do_funil(id, registro, conta)
  end

  # O campo guarda o id do contato: só um campo do card do tipo contato (CAMPOS_DO_CONTATO), como a tela oferece. O resto
  # (um campo de número, o telefone, o nome, o próprio contato do alvo, o texto da IA) nunca é o contato ligado, e o
  # passo pularia sempre ou acharia outro contato.
  def do_campo(id, caminho, conta)
    lidos = [*yield(caminho)]
    return lidos if lidos.any?

    campo_do_contato?(caminho, conta) ? [] : [texto(:campo_sem_contato, passo: id)]
  end

  # As automações ligadas da conta cujo "em outro registro" acha o contato neste campo (`card.atributos.<chave>`). O campo
  # do tipo contato não troca de tipo nem é apagado enquanto alguma delas o lê (CampoContatoEmUso).
  def automacoes_que_leem(conta, caminho)
    ::Autonomia::Automacao::Definicao.where(account_id: conta.id, ativa: true).includes(:versao_ativa).select do |automacao|
      receita = automacao.versao_ativa&.receita
      receita && ::Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: nil).passos.any? do |passo|
        passo['tipo'] == TIPO && passo.dig('registro', 'campo', '$valor') == caminho
      end
    end
  end

  def campo_do_contato?(caminho, conta)
    atributos = ::Autonomia::Automacao::Valores::Atributos
    base, = atributos.do_caminho(caminho)
    CAMPOS_DO_CONTATO.include?(base) && atributos.contato?(caminho, conta)
  end

  def do_funil(id, registro, conta)
    funil = registro['funil_id'] && conta.crm_pipelines.find_by(id: registro['funil_id'])
    return [texto(:funil_de_fora, passo: id)] if registro['funil_id'] && funil.nil?
    return [] unless registro['etapa_id']

    etapas = funil ? funil.stages : ::Crm::PipelineStage.where(account_id: conta.id)
    etapas.exists?(id: registro['etapa_id']) ? [] : [texto(:etapa_de_fora, passo: id)]
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.em_outro_registro.#{chave}", **valores)
end
