# Grava a gaveta "Metas do mês" (#1991, F4 do #1871): a meta de cada funil (crm_pipelines.metadata['goals'], a mesma do
# painel e da barra da equipe) e a meta do mês de cada pessoa (crm_person_goals), em reais inteiros na moeda do funil.
# Vazio ou zero tira a meta; campo que não veio não muda. Tudo ou nada: um valor inválido, um funil fora do alcance de
# quem grava, uma pessoa fora do funil ou a gaveta aberta num mês que já virou recusa o pedido inteiro.
class Crm::Metas::Salvar
  class Invalido < StandardError; end
  class ForaDoAlcance < StandardError; end
  class MesMudou < StandardError; end

  MAXIMO = 1_000_000_000

  # mes: a chave "AAAA-MM" do mês que a gaveta mostrou; vazio = o de hoje.
  def initialize(account:, user:, account_user:, funis:, mes: nil)
    @account = account
    @funis = Array(funis)
    @mes = Crm::Numeros::Mes.new(account: account)
    @mes_da_gaveta = mes
    @escopo = Crm::Metas::Escopo.new(account: account, user: user, account_user: account_user, mes: @mes)
  end

  def perform
    raise MesMudou if @mes_da_gaveta.present? && @mes_da_gaveta != @mes.info[:chave]

    pedidos = @funis.map { |pedido| conferir(pedido) }
    ActiveRecord::Base.transaction { pedidos.each { |funil, pedido| gravar(funil, pedido) } }
  end

  private

  def conferir(pedido)
    funil = @escopo.funis.find { |permitido| permitido.id == pedido[:id].to_i }
    raise ForaDoAlcance if funil.nil?

    validar!(pedido[:metaFunil]) if pedido.key?(:metaFunil)
    conferir_pessoas(funil, Array(pedido[:pessoas]))
    [funil, pedido]
  end

  def conferir_pessoas(funil, pessoas)
    permitidas = @escopo.pessoas_de(funil).map(&:id)
    pessoas.each do |pessoa|
      raise ForaDoAlcance unless permitidas.include?(pessoa[:id].to_i)

      validar!(pessoa[:meta]) if pessoa.key?(:meta)
    end
  end

  def validar!(valor)
    return if valor.nil?
    raise Invalido unless valor.is_a?(Integer) && valor.between?(0, MAXIMO)
  end

  def gravar(funil, pedido)
    moeda = Crm::Metas::Escopo.moeda_de(funil)
    gravar_funil(funil, pedido[:metaFunil], moeda) if pedido.key?(:metaFunil)
    Array(pedido[:pessoas]).each do |pessoa|
      gravar_pessoa(funil, pessoa[:id].to_i, pessoa[:meta], moeda) if pessoa.key?(:meta)
    end
  end

  # Como o PipelinesController#update_goal!: só metadata['goals']. O lock relê o funil, para não apagar o que outra
  # tela gravou no metadata (IA, desfechos, modelo) depois que a gaveta abriu.
  def gravar_funil(funil, valor, moeda)
    funil.lock!
    metadata = (funil.metadata || {}).deep_dup
    if valor.to_i.positive?
      metadata['goals'] = { 'monthly_target_cents' => valor * 100, 'currency' => moeda }
    else
      metadata.delete('goals')
    end
    funil.update!(metadata: metadata) if metadata != funil.metadata
  end

  def gravar_pessoa(funil, user_id, valor, moeda)
    chave = { account_id: @account.id, pipeline_id: funil.id, user_id: user_id, month: @escopo.mes_do_banco }
    return Crm::PersonGoal.where(chave).delete_all unless valor.to_i.positive?

    meta = Crm::PersonGoal.find_or_initialize_by(chave)
    meta.update!(target_cents: valor * 100, currency: moeda)
  end
end
