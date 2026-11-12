# O passo "fazer para cada um de uma lista" (#2932): ao salvar, a lista é da conta e quem salva pode lê-la; o galho
# `cada` é conferido como uma receita própria, no tipo do item (card ou contato). Ao rodar, entrega a lista ao
# RepetirListaJob e segue (ver RepetirLista).
#
# O resultado de `executar` segue o do PassoDeAcao:
# - :ok com a lista nos dados (as filhas ficam com o job, que deixa a conta delas no histórico da mãe);
# - :pulado `receita_com_problema` numa filha, ou num bloco chamado por uma filha (o salvar já recusa "para cada" dentro
#   de outro galho de filha, também pelo bloco; a rodada confere de novo, porque o bloco muda depois);
# - :sem_acesso `sem_chave_de_funis` na lista de cards, quando quem ligou perdeu a chave de funis: pausa.
class Autonomia::Automacao::PassoRepetirLista
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  # `conferencia`: PassosNovos::Conferencia.
  def self.problemas_ao_salvar(passo, conferencia)
    id = passo['id']
    return [texto(:aninhado, passo: id)] if conferencia.dentro

    [*da_lista(id, passo['lista'].to_h, conferencia), *do_ramo(passo, conferencia)]
  end

  def self.da_lista(id, lista, conferencia)
    conta = conferencia.conta
    case lista['de']
    when 'etapa' then da_etapa(id, lista, conferencia)
    when 'etiqueta' then conta.labels.exists?(title: lista['etiqueta']) ? [] : [texto(:etiqueta_de_fora, passo: id)]
    else do_publico(id, ::Autonomia::Automacao::ItensDaLista.publico(conta, lista['publico_id']), conferencia.account_user)
    end
  end

  # Os cards da etapa pedem a chave de funis, como o "em outro registro" que lê cards.
  def self.da_etapa(id, lista, conferencia)
    sem_chave = conferencia.account_user && !::Autonomia::Automacao::RegraDoFunil.chave?(conferencia.account_user)
    return [texto(:sem_chave_de_funis, passo: id)] if sem_chave

    conferencia.conta.crm_pipeline_stages.exists?(id: lista['etapa_id']) ? [] : [texto(:etapa_de_fora, passo: id)]
  end

  # O público é lido como na tela de Públicos (CampaignImportPolicy#show?).
  def self.do_publico(id, publico, account_user)
    return [texto(:publico_de_fora, passo: id)] unless publico
    return [] if account_user.nil?

    contexto = { user: account_user.user, account: account_user.account, account_user: account_user }
    ::CampaignImportPolicy.new(contexto, publico).show? ? [] : [texto(:publico_sem_permissao, passo: id)]
  end

  # O galho roda numa execução filha, no item: é conferido como uma receita cujo alvo é o item.
  def self.do_ramo(passo, conferencia)
    ramo = { 'gatilho' => {}, 'passos' => passo[::Autonomia::Automacao::RepetirLista::RAMO] }
    alvo = ::Autonomia::Automacao::ItensDaLista.alvo(passo['lista'])
    ::Autonomia::Automacao::Receita.new(ramo, conta: conferencia.conta, account_user: conferencia.account_user, alvo: alvo).problemas
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.lista.#{chave}", **valores)

  def initialize(execucao:, passo:, valores:, acesso:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
  end

  def executar
    return Resultado.new(tipo: :pulado, motivo: 'receita_com_problema', dados: {}) if ::Autonomia::Automacao::RepetirLista.dentro_de_filha?(@execucao)
    return Resultado.new(tipo: :sem_acesso, motivo: 'sem_chave_de_funis', dados: {}) if sem_chave?

    ::Autonomia::Automacao::RepetirListaJob.perform_later(@execucao.account_id, @execucao.id, @passo['id'])
    Resultado.new(tipo: :ok, motivo: nil, dados: { 'lista' => @passo.dig('lista', 'de') })
  end

  private

  def sem_chave? = @passo.dig('lista', 'de') == 'etapa' && !::Autonomia::Automacao::RegraDoFunil.chave?(@acesso.account_user)
end
