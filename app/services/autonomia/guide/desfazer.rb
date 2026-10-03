# Põe a conta de volta como estava antes do Guia agir (#855).
#
# Lê as mudanças da execução de trás para frente: o que o Guia criou é
# apagado, o que ele alterou volta ao valor de antes, o que ele apagou é
# recriado com o mesmo id e os mesmos valores. Tudo numa transação: ou volta
# tudo, ou nada muda.
#
# Conflito não é erro. Se alguém mexeu no mesmo campo depois do Guia, o valor
# dessa pessoa fica — desfazer não pode apagar trabalho de outra pessoa — e o
# relatório diz o que não voltou e por quê.
class Autonomia::Guide::Desfazer
  class Recusado < StandardError; end

  # Mudam sozinhas a cada toque no registro; não contam como "alguém mexeu".
  CARIMBOS = %w[updated_at last_activity_at].freeze

  def initialize(execucao:, user:)
    @execucao = execucao
    @user = user
    @relatorio = { 'desfeitas' => 0, 'conflitos' => [] }
  end

  def perform
    raise Recusado, I18n.t('autonomia.guide.undo.already_undone') if @execucao.desfeita?
    raise Recusado, I18n.t('autonomia.guide.undo.expired') if @execucao.vencida?

    ActiveRecord::Base.transaction do
      @execucao.mudancas.reorder(ordem: :desc).each { |mudanca| voltar(mudanca) }
      @execucao.update!(desfeita_em: Time.current, desfeita_por: @user, relatorio_desfazer: @relatorio)
    end
    @relatorio
  end

  private

  def voltar(mudanca)
    case mudanca.operacao
    when 'create' then apagar_criado(mudanca)
    when 'update' then restaurar_alterado(mudanca)
    when 'destroy' then recriar_apagado(mudanca)
    end
  end

  # Apaga pelo próprio model, para os filhos e os efeitos irem junto, como na
  # tela. Já sumiu? Então já está como estava.
  def apagar_criado(mudanca)
    classe = mudanca.record_type.safe_constantize
    return conflito(mudanca, 'unknown_type') if classe.nil?

    classe.unscoped.find_by(classe.primary_key => mudanca.record_id)&.destroy!
    @relatorio['desfeitas'] += 1
  end

  def restaurar_alterado(mudanca)
    atual = linha(mudanca)
    return conflito(mudanca, 'missing') if atual.nil?

    mexidos = (mudanca.depois.keys - CARIMBOS).reject { |coluna| atual[coluna] == mudanca.depois[coluna] }
    return conflito(mudanca, 'changed_after', mexidos) if mexidos.any?

    escrever(mudanca, mudanca.antes)
    @relatorio['desfeitas'] += 1
  end

  def recriar_apagado(mudanca)
    return conflito(mudanca, 'exists') if linha(mudanca)

    inserir(mudanca.tabela, mudanca.antes)
    @relatorio['desfeitas'] += 1
  end

  def conflito(mudanca, motivo, colunas = [])
    @relatorio['conflitos'] << { 'tipo' => mudanca.record_type, 'id' => mudanca.record_id,
                                 'motivo' => motivo, 'campos' => colunas }
  end

  def conexao
    ActiveRecord::Base.connection
  end

  def tabela(nome)
    conexao.quote_table_name(nome)
  end

  # A chave é a do model, como o caderno a usou para ler (`Diario#linha`).
  def onde(mudanca)
    chave = mudanca.record_type.safe_constantize&.primary_key || 'id'
    "#{conexao.quote_column_name(chave)} = #{conexao.quote(mudanca.record_id)}"
  end

  def linha(mudanca)
    texto = conexao.select_value("SELECT row_to_json(t) FROM #{tabela(mudanca.tabela)} t WHERE #{onde(mudanca)}")
    texto && JSON.parse(texto)
  end

  # O valor volta pelo próprio Postgres (json_populate_record), coluna a
  # coluna: nada passa pelo tipo do Rails, então campo cifrado volta cifrado.
  def escrever(mudanca, valores)
    nome = mudanca.tabela
    colunas = valores.keys.map { |coluna| conexao.quote_column_name(coluna) }.join(', ')
    conexao.execute(
      "UPDATE #{tabela(nome)} SET (#{colunas}) = (SELECT #{colunas} FROM " \
      "json_populate_record(NULL::#{tabela(nome)}, #{conexao.quote(valores.to_json)})) " \
      "WHERE #{onde(mudanca)}"
    )
  end

  # Coluna gerada pelo banco não aceita valor: fica de fora e o Postgres a
  # recalcula.
  def inserir(nome, valores)
    gravaveis = conexao.columns(nome).reject(&:virtual?).map(&:name) & valores.keys
    colunas = gravaveis.map { |coluna| conexao.quote_column_name(coluna) }.join(', ')
    conexao.execute(
      "INSERT INTO #{tabela(nome)} (#{colunas}) SELECT #{colunas} FROM " \
      "json_populate_record(NULL::#{tabela(nome)}, #{conexao.quote(valores.to_json)})"
    )
  end
end
