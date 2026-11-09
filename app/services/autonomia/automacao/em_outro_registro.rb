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

  # A ligação lê cards do CRM: pede a chave de funis, como o gatilho de card e a ação de funil (controller#de_funil?).
  def de_funil?(passo, receita) = do_tipo?(passo) && alvo_do_ramo(passo, receita) == 'Crm::Card'

  def marca(mae, registro, passo_id) = [MARCA, mae.id, BASES.fetch(registro.class.name), registro.id, passo_id].join(':')

  # [id da mãe, id do passo] da filha; nil na execução que não é filha. O id do passo vai por último: ele pode ter ":".
  def da(execucao)
    prefixo, mae_id, _base, _id, passo_id = execucao&.evento.to_s.split(':', 5)
    [mae_id.to_i, passo_id] if prefixo == MARCA && passo_id.present?
  end

  # A conversa em que a filha num card age (decisão da Automação, 07/11): a da mãe, quando o card é do mesmo contato
  # do alvo dela (a resposta do exemplo 16 sai na conversa em que o cliente escreveu); senão nil, e vale a do card.
  def conversa_da_mae(execucao, card)
    mae_id, = da(execucao)
    mae = mae_id && ::Autonomia::Automacao::Execucao.find_by(id: mae_id, account_id: card.account_id)
    return unless mae&.alvo

    contexto = ::Autonomia::Automacao::Contexto.de(mae.alvo)
    contexto.conversa if contexto.contato && contexto.contato.id == card.contact_id
  end

  # Frases do salvar. `dentro`: o passo está no ramo de outro "em outro registro". O ramo é conferido como uma receita
  # cujo alvo é o registro (Receita com `alvo:`); o valor da âncora, pela régua do alvo da mãe (o bloco).
  # `receita`: a receita inteira, de onde sai o tipo do registro criado (G49).
  def problemas_ao_salvar(passo, conta:, account_user:, dentro:, receita:, &)
    id = passo['id']
    return [texto(:aninhado, passo: id)] if dentro

    ligacao = da_ligacao(id, passo['registro'].to_h, conta, account_user, &)
    alvo = alvo_do_ramo(passo, receita)
    return ligacao if alvo.nil?

    ramo = { 'gatilho' => {}, 'passos' => passo['passos'] }
    [*ligacao, *::Autonomia::Automacao::Receita.new(ramo, conta: conta, account_user: account_user, alvo: alvo).problemas]
  end

  # O campo do contato só aceita o contato criado (G49); o `criado_no_passo` é conferido como o valor `criado.<passo>`.
  def da_ligacao(id, registro, conta, account_user, &)
    criado = ::Autonomia::Automacao::RegistroCriado
    return [*yield(registro.dig('campo', '$valor'), tipo: criado::CONTATO)] if registro['de'] == 'contato_do_campo'
    return [*yield("#{criado::PREFIXO}#{registro['passo']}")] if registro['de'] == CRIADO

    chave = account_user && !::Autonomia::Automacao::RegraDoFunil.chave?(account_user) ? [texto(:sem_chave_de_funis, passo: id)] : []
    chave + do_funil(id, registro, conta)
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
