require 'rails_helper'

# Teste-ouro LOCAL do painel de desempenho (#2251). Só roda na máquina de quem tem a leitura da conta de referência,
# que nunca entra no repositório: DESEMPENHO_OURO_DIR aponta para a pasta com g3.jsonl (as conversas exportadas),
# carga/esperado.json (a conta, o agente e o nome do arquivo da carga gerada por bin/carga_sql.py) e
# carga/referencia.json (o pacote do protótipo aprovado, de bin/contrato.py). Sem a pasta, o exemplo é pulado (no CI,
# sempre). Nenhum id da conta fica aqui: vem do esperado.json.
#
# Monta no banco de teste a conta, com o mesmo id, as mesmas conversas (id e número da caixa) e mensagens SEM texto, roda a
# carga e compara, período a período, o painel do servidor com o do protótipo, campo a campo. Só três campos podem
# diferir, e por definição: meta.fonte ('api'), meta.gerado_em (a hora do cálculo) e meta.dados_ate (a última
# mensagem lida, em vez da hora em que o protótipo foi gerado; o dia é o mesmo).
# O spec nunca imprime conteúdo: em falha, só os caminhos que diferem.
RSpec.describe Autonomia::Desempenho::Painel do
  pasta = ENV.fetch('DESEMPENHO_OURO_DIR', '')
  arquivos = %w[g3.jsonl carga/esperado.json carga/referencia.json].map { |nome| File.join(pasta, nome) }
  disponivel = pasta.present? && arquivos.all? { |caminho| File.exist?(caminho) }

  def semear_conversas(registros, conta)
    canal = Channel::Api.create!(account: conta)
    caixa = Inbox.create!(account: conta, channel: canal, name: 'Caixa')
    contato = Contact.create!(account: conta, name: 'Contato')
    agora = Time.current
    conversas = registros.map do |c|
      { id: c['id'], account_id: conta.id, inbox_id: caixa.id, contact_id: contato.id, status: 0, created_at: agora,
        updated_at: agora, last_activity_at: agora }
    end
    Conversation.insert_all!(conversas) # rubocop:disable Rails/SkipsModelValidations
    registros.each_slice(500) do |fatia|
      valores = fatia.map { |c| "(#{c['id'].to_i}, #{c['c'].to_i})" }.join(',')
      ActiveRecord::Base.connection.execute("UPDATE conversations c SET display_id = v.d FROM (VALUES #{valores}) v(id, d) WHERE c.id = v.id")
    end
    caixa
  end

  # Só quem mandou, quando e de que tipo: nenhum texto de mensagem entra no banco de teste.
  def semear_mensagens(registros, conta, caixa)
    linhas = registros.flat_map do |c|
      c['msgs'].map do |m|
        { account_id: conta.id, inbox_id: caixa.id, conversation_id: c['id'], message_type: m['t'], private: m['p'] == true,
          sender_type: m['s'], sender_id: m['sid'], created_at: m['at'], updated_at: m['at'], content_type: 0 }
      end
    end
    linhas.each_slice(5_000) { |fatia| Message.insert_all!(fatia) } # rubocop:disable Rails/SkipsModelValidations
  end

  # A carga roda como em produção, menos as linhas da transação dela (o exemplo já está numa).
  def rodar_carga(caminho)
    fora = ['BEGIN;', 'COMMIT;']
    sql = File.foreach(caminho).reject { |linha| fora.include?(linha.strip) || linha.start_with?('SET LOCAL ') }.join
    ActiveRecord::Base.connection.execute(sql)
  end

  def diferencas(esperado, obtido, caminho = '', out = []) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    if esperado.is_a?(Hash) && obtido.is_a?(Hash)
      (esperado.keys | obtido.keys).each { |chave| diferencas(esperado[chave], obtido[chave], "#{caminho}.#{chave}", out) }
    elsif esperado.is_a?(Array) && obtido.is_a?(Array) && esperado.size == obtido.size
      esperado.each_with_index { |item, i| diferencas(item, obtido[i], "#{caminho}[#{i}]", out) }
    elsif esperado != obtido
      out << caminho
    end
    out
  end

  it 'monta, para cada período, o mesmo painel do protótipo aprovado', skip: (disponivel ? false : 'sem DESEMPENHO_OURO_DIR (só local)') do
    g3 = File.foreach(arquivos[0]).map { |linha| JSON.parse(linha) }
    referencia = JSON.parse(File.read(arquivos[2]))
    alvo = JSON.parse(File.read(arquivos[1]))
    sujeito_type, sujeito_id = alvo['sujeito']
    conta = create(:account, id: alvo['conta'])
    AgentBot.create!(id: sujeito_id, name: 'Robô', account: conta)
    semear_mensagens(g3, conta, semear_conversas(g3, conta))
    rodar_carga(File.join(pasta, 'carga', alvo['carga']))
    # As tabelas acabaram de receber dezenas de milhares de linhas: sem estatística, o planejador do banco de teste
    # escolhe mal o plano das mensagens (em produção o autovacuum mantém as estatísticas).
    ActiveRecord::Base.connection.execute('ANALYZE messages, conversations, autonomia_desempenho_procuras')

    painel = described_class.new(account: conta, sujeito_type: sujeito_type, sujeito_id: sujeito_id)
    falhas = described_class::PERIODOS.to_h do |chave|
      esperado = Autonomia::Desempenho::Exportacao::Contrato.do_pacote(referencia, chave)
      obtido = JSON.parse(painel.call(chave).to_json)
      expect(obtido.dig('meta', 'dados_ate').first(10)).to eq(esperado.dig('meta', 'dados_ate').first(10))
      # As três da leitura automática (#2301) não existem no protótipo: a carga não tem rodada.
      fixos = { 'fonte' => nil, 'gerado_em' => nil, 'dados_ate' => nil, 'lido_ate' => nil, 'instrucao_mudou' => nil, 'recomendacoes_de' => nil }
      [chave, diferencas(esperado.merge('meta' => esperado['meta'].merge(fixos)), obtido.merge('meta' => obtido['meta'].merge(fixos)))]
    end

    expect(falhas.transform_values { |caminhos| caminhos.first(20) }).to eq(described_class::PERIODOS.index_with { [] })
  end
end
