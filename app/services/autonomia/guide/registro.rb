# O que o Guia leu, chamou e decidiu num pedido (#861), para o time investigar.
#
# Até aqui isso era uma linha de log: quando a conta 18 relatou uma resposta
# errada, não havia como saber o que o Guia tinha lido nem por que respondeu
# aquilo. Agora cada pedido guarda o seu diagnóstico no turno.
#
# Acumula EM MEMÓRIA durante o turno e é gravado UMA vez, pelo `ChatJob`, depois
# de `Chat#perform`. Nunca dentro de `Diario.gravando`: lá, toda linha que o
# Rails escreve vira mudança do Guia, e o desfazer apagaria o próprio registro.
#
# Guarda o mínimo. Entram nomes de ferramenta, os argumentos que cada uma declara
# seguros (`args_registraveis`), tempos, tamanhos, custo e as decisões. NÃO
# entram instrução, catálogo, trecho da base, o conteúdo do que foi lido nem o
# valor que a pessoa mandou gravar — o corpo de uma ação pode ter telefone ou
# credencial.
#
# Best-effort, como o `UsageRecorder`: falhar aqui nunca derruba a resposta.
class Autonomia::Guide::Registro
  CHAVE = :autonomia_guide_registro
  EVENTO_DE_CUSTO = ::Crm::Ai::UsageRecorder::EVENT_NAME
  # O texto que o portão reteve: o bastante para entender o que o modelo quis
  # dizer, sem guardar uma resposta inteira que ninguém leu.
  MAX_RESPOSTA_RETIDA = 2_000
  MAX_TITULO = 120

  attr_reader :chamadas

  def initialize
    @chamadas = []
    @custos = []
    @decisoes = {}
  end

  # Executa o bloco com este registro ligado na thread: o custo de cada ida ao
  # modelo (`UsageRecorder`) entra nele. As notificações são globais; a
  # conferência da thread deixa de fora o que outros jobs fazem ao mesmo tempo.
  def ativo
    anterior = Thread.current[CHAVE]
    Thread.current[CHAVE] = self
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ouvinte = ActiveSupport::Notifications.subscribe(EVENTO_DE_CUSTO) do |*, payload|
      custo(payload) if Thread.current[CHAVE].equal?(self)
    end
    yield
  ensure
    @ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round if inicio
    ActiveSupport::Notifications.unsubscribe(ouvinte) if ouvinte
    Thread.current[CHAVE] = anterior
  end

  # Uma chamada de ferramenta. `call` é o pedido do modelo (nome e argumentos em
  # JSON); da saída fica só o tamanho, se era dado e, se foi recusa, o código.
  def registrar_chamada(call, output, milissegundos)
    nome = call['name'].to_s
    texto = output.to_s
    @chamadas << { 'ferramenta' => nome, **argumentos(nome, call['arguments']), 'ms' => milissegundos.to_i,
                   'saida_chars' => texto.length, 'dados' => texto.start_with?('[', '{'),
                   'recusa' => recusa(texto) }.compact
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][registro] chamada #{e.class}")
  end

  # O que o `Chat` decidiu no turno. Só id e título dos fluxos: o texto deles é
  # a base do Guia, não dado do pedido.
  def decidir(fluxos: [], check: nil, confianca: nil, grounded: nil, escalate: nil, retido: false, # rubocop:disable Metrics/ParameterLists
              resposta_retida: nil, telas: [], artigos: [], execution_id: nil)
    @decisoes = {
      'fluxos' => Array(fluxos).map { |fluxo| { 'id' => fluxo[:id], 'titulo' => fluxo[:source].to_s.truncate(MAX_TITULO) } },
      'check' => check, 'confianca' => confianca, 'grounded' => grounded, 'escalate' => escalate,
      'retido' => retido == true,
      'resposta_retida' => (resposta_retida.to_s.first(MAX_RESPOSTA_RETIDA).presence if retido),
      'telas' => Array(telas).pluck(:route_name), 'artigos' => Array(artigos).pluck(:ref),
      'execution_id' => execution_id
    }
  end

  # #934 — o que a pessoa estava vendo: rota, recurso, ids que ela enxerga e total. Sem resumo nem filtro.
  def ver_tela(tela)
    @tela = tela.presence
  end

  # O que vai para `Turno#diagnostico`. `erro` é só a classe: a mensagem pode
  # trazer o prompt ou dado da conta.
  def diagnostico(erro: nil)
    ultimo = @custos.last || {}
    { 'modelo' => ultimo[:model], 'effort' => ultimo[:effort], 'rodadas' => @custos.size, 'ms' => @ms,
      'custo_usd' => @custos.sum { |item| item[:cost].to_f }.round(6), 'tokens' => tokens,
      'chamadas' => @chamadas, **@decisoes, **({ 'tela' => @tela } if @tela).to_h, 'erro' => erro }
  end

  private

  def custo(payload)
    @custos << payload.slice(:model, :effort, :cost, :tokens)
  end

  def tokens
    %i[in cached out].index_with { |chave| @custos.sum { |item| item.dig(:tokens, chave).to_i } }.stringify_keys
  end

  # Os argumentos que a ferramenta declara seguros, com valor; dos outros, só o
  # nome. Ferramenta desconhecida (um especialista, por exemplo) fica só com nomes.
  def argumentos(nome, bruto)
    args = JSON.parse(bruto.presence || '{}')
    return { 'args_invalidos' => true } unless args.is_a?(Hash)

    ferramenta = ::Autonomia::Agents::Tools::Registry.find(nome)
    guardados = ferramenta ? ferramenta.args_para_registro(args) : {}
    { 'args' => guardados, 'omitidos' => args.keys.map(&:to_s) - guardados.keys }
  rescue JSON::ParserError
    { 'args_invalidos' => true }
  end

  # A recusa que o modelo leu vem como `{"error":"codigo: detalhe"}` (`Tools::Recusa`).
  # Só o código: o detalhe pode trazer dado.
  def recusa(texto)
    return nil unless texto.start_with?('{')

    corpo = JSON.parse(texto)
    corpo.is_a?(Hash) && corpo['error'].present? ? corpo['error'].to_s.split(':').first.strip : nil
  rescue JSON::ParserError
    nil
  end
end
