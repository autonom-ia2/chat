# As sondas da troca de quem cuida do card (G9) e do campo pessoa da equipe (G62), do exemplo 17: rodam o código de
# verdade e conferem o efeito. Ficam fora do FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS
# de lá chama as daqui.
module FechamentoAutomacao::SondasDaTroca
  extend CrmHelpers

  module_function

  # G9: a receita do exemplo 17 (o começo: muda quem cuida do card e quem cuidava antes está ausente) dispara na troca
  # do dono, e a execução lê quem cuidava antes e quem cuida agora. Roda na transação do exemplo, que desfaz tudo; o
  # EventoDoCardJob do card roda aqui, e o AvancarJob só fica na fila.
  def troca_de_responsavel_dispara?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account, paula, julia, renata = conta_da_cobertura_de_ferias
      funil, etapa = create_crm_pipeline(account: account, user: paula)
      card = account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Sonda G9', currency: 'BRL', owner: julia)
      automacao = cobertura_de_ferias(account, paula, funil)
      card.update!(owner: renata)
      rodar_evento_do_card(card)
      execucao = Autonomia::Automacao::Execucao.find_by(automacao: automacao, alvo: card)
      valores = execucao && Autonomia::Automacao::Valores.new(alvo: Autonomia::Automacao::Contexto.de(card, execucao: execucao), quem: paula)
      valores.present? && %w[gatilho.responsavel_anterior_nome card.responsavel_nome].map { |caminho| valores.ler(caminho) } == %w[Júlia Renata]
    end
  end

  # A Júlia está de férias ("ausente até", G23); a Renata a cobre.
  def conta_da_cobertura_de_ferias
    account = FactoryBot.create(:account)
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
    pessoas = [[:administrator, 'Paula'], [:agent, 'Júlia'], [:agent, 'Renata']].map do |papel, nome|
      FactoryBot.create(:user, account: account, role: papel, name: nome)
    end
    AccountUser.find_by!(account: account, user: pessoas[1]).update!(ausente_ate: 15.days.from_now)
    [account, *pessoas]
  end

  # O gatilho do exemplo 17, com o filtro "quem cuidava antes está ausente", ligado pela Paula.
  def cobertura_de_ferias(account, paula, funil)
    filtro = { 'campo' => { '$valor' => 'gatilho.responsavel_anterior_ausente' }, 'op' => 'igual', 'valor' => true }
    gatilho = { 'tipo' => 'card.responsavel_mudou', 'funil_id' => funil.id, 'filtros' => [filtro] }
    espera = { 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }
    automacao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: paula)
    automacao.salvar_versao!(receita: { 'gatilho' => gatilho, 'passos' => [espera] }, autor: paula)
    automacao.tap { |definicao| definicao.update!(ativa: true) }
  end

  # O EventoDoCardJob do card, tirado da fila e rodado como o Sidekiq rodaria.
  def rodar_evento_do_card(card)
    fila = ActiveJob::Base.queue_adapter.enqueued_jobs
    fila.select { |job| job[:job] == Autonomia::Automacao::EventoDoCardJob }.each do |job|
      argumentos = ActiveJob::Arguments.deserialize(job[:args])
      next unless argumentos.first['card_id'] == card.id

      fila.delete(job)
      job[:job].perform_now(*argumentos)
    end
  end

  # G62: o campo do card do tipo pessoa da equipe. A pessoa da conta lê o nome e a ausência; o id de quem é de outra conta
  # (gravado por baixo, sem a validação do card) lê vazio: a pessoa é achada na conta do card, nunca só pelo id.
  def campo_pessoa_le_na_conta?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account, paula, julia, = conta_da_cobertura_de_ferias
      FactoryBot.create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'original',
                                                      attribute_display_name: 'Responsável original', attribute_display_type: :pessoa)
      funil, etapa = create_crm_pipeline(account: account, user: paula)
      da_conta = card_com_original(account, [funil, etapa], julia.id)
      de_fora = card_com_original(account, [funil, etapa], nil)
      de_fora.update_column(:custom_attributes, { 'original' => FactoryBot.create(:user, account: FactoryBot.create(:account)).id }) # rubocop:disable Rails/SkipsModelValidations
      [pessoa_do_campo(da_conta, paula), pessoa_do_campo(de_fora, paula)] == [['Júlia', true], [nil, false]]
    end
  end

  def card_com_original(account, (funil, etapa), pessoa_id)
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Sonda G62', currency: 'BRL', custom_attributes: { 'original' => pessoa_id })
  end

  def pessoa_do_campo(card, quem)
    valores = Autonomia::Automacao::Valores.new(alvo: card.reload, quem: quem)
    %w[nome ausente].map { |sufixo| valores.ler("card.atributos.original.#{sufixo}") }
  end
end
