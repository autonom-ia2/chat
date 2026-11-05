# Uma automação de etapa do CRM (`Crm::StageAutomation`) lida como receita do motor novo (#2568, F9). Só leitura.
#
# O gatilho vira o de card da F6 (`card.entrou_na_etapa`/`card.saiu_da_etapa` com a etapa). Os passos de hoje são
# todos da F6 (retorno, responsável, mover) ou da F7 (Decisor), então a receita sai só com o gatilho, e cada passo vai
# para as faltas com a fase. Quando a F6 e a F7 chegarem, este arquivo ganha os passos e as faltas somem.
class Autonomia::Automacao::Conversao::DaEtapa
  Mapa = Autonomia::Automacao::Conversao::Mapa

  FALTA_DO_PASSO = {
    'create_follow_up' => 'passo_retorno', 'assign_owner' => 'passo_de_card', 'move_stage' => 'passo_de_card',
    'perguntar_ao_decisor' => 'passo_decidir'
  }.freeze

  def initialize(automacao)
    @automacao = automacao
  end

  def resultado
    faltas = [falta('gatilho_de_card', @automacao.trigger_event)]
    faltas.concat(@automacao.steps.ordered.map { |passo| falta(FALTA_DO_PASSO.fetch(passo.action_type), passo.action_type) })

    Autonomia::Automacao::Conversao::Resultado.new(
      origem: 'etapa', id: @automacao.id, ligada: @automacao.enabled, autor_conhecido: @automacao.created_by_id.present?,
      receita: receita, faltas: faltas, ressalvas: ressalvas
    )
  end

  private

  def receita
    { 'gatilho' => { 'tipo' => Mapa::GATILHO_DA_ETAPA.fetch(@automacao.trigger_event), 'etapa_id' => @automacao.stage_id },
      'passos' => [] }
  end

  # Diferenças que a conversão precisa tratar para o comportamento ficar igual (F9.2).
  def ressalvas
    lista = []
    lista << 'nasce_na_etapa: o novo também dispara quando o card é criado na etapa; o antigo não' if @automacao.on_enter?
    if @automacao.steps.any? { |passo| !passo.create_follow_up? && passo.delay_seconds.positive? }
      lista << 'atraso_sem_reconferir: o atraso antigo não reconfere se a automação segue ligada; o esperar novo reconfere'
    end
    lista
  end

  def falta(chave, detalhe)
    { chave: chave, fase: Mapa::FALTA.fetch(chave), detalhe: detalhe.to_s }
  end
end
