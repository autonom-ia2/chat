# O Guia PLANEJANDO um trabalho grande (#936): "arruma os 512 nomes de contato".
#
# Não executa nada. Monta a tarefa com a receita, congela a lista e prepara a amostra de 10 (antes e
# depois, custo, tempo e classificações do Jev). A tela mostra o cartão com o botão Começar, e só o
# clique da pessoa solta o primeiro lote (`comecar` está em `Acoes::SEM_DESFAZER`).
class Autonomia::Agents::Tools::Native::GuiaTarefa < Autonomia::Agents::Tools::Native::Base
  class << self
    def slug
      'planejar_tarefa'
    end

    def description
      'Planeja um trabalho grande na conta (mais de uns 20 registros, até 5.000): aplica a MESMA ação a ' \
        'cada registro de uma leitura, em lotes, com desfazer. NÃO muda nada agora: devolve a amostra de 10 ' \
        '(antes e depois), o custo e o tempo, e a tela mostra o botão Começar para a pessoa. Mensagem em ' \
        'massa não entra (é campanha). Só funciona para quem administra a conta.'
    end

    def params
      [
        { 'name' => 'receita_json', 'type' => 'string',
          'description' => 'A receita, como objeto JSON: {"descricao": frase curta do que muda, "alvo": {"recurso": ' \
                           'leitura do catálogo de ler_da_conta, "parametros": {}, "filtro": [{"campo", "op" ' \
                           '(igual, diferente, menor, maior, vazio, preenchido), "valor"}]}, "acao": UMA ação em ' \
                           'linguagem de rota, "caminho": {"id": {"$item": "id"}}, "corpo": montado pelo ' \
                           'formato_da_acao}. Valor que muda por registro: {"$item": "campo"} (o campo do registro), ' \
                           '{"$gerar": {"campo", "instrucao"}} (texto novo escrito a partir do campo) ou {"$jev": ' \
                           'true} (a escolha da classificação). Classificar antes de agir: "classificar": ' \
                           '{"pergunta", "opcoes": [{"chave", "descricao"}], "agir_quando": [chaves], ' \
                           '"certeza_minima": 0.8}.' }
      ]
    end
  end

  def call
    return 'Não consigo planejar agora porque não sei quem está pedindo.' if @operador.nil?

    receita = JSON.parse(@params['receita_json'].to_s)
    tarefa = ::Autonomia::Guide::Tarefas::Amostra.new(contexto: @operador, receita: receita).planejar
    planejada(tarefa)
  rescue JSON::ParserError
    'Não planejei: receita_json não é um objeto JSON. Monte de novo e chame uma vez.'
  rescue ::Autonomia::Guide::Tarefas::Recusada => e
    "Não planejei: #{e.message}"
  end

  private

  # A tarefa conta como lida: o Guia pode pausar ou cancelar pelo id no mesmo turno.
  def planejada(tarefa)
    @operador.tarefa_planejada(tarefa)
    dados = { id: tarefa.id, status: tarefa.status, total: tarefa.total, custo_estimado: tarefa.custo_estimado.to_f,
              tempo_estimado_segundos: tarefa.tempo_estimado, classificacoes_do_jev: tarefa.jev_estimado,
              amostra: tarefa.amostra }.to_json
    @operador.lido(dados)
    'Amostra pronta; NADA foi mudado ainda. A tela já mostra o cartão com o antes e depois, o custo e o botão ' \
      'Começar. Diga em uma ou duas frases o que vai mudar e em quantos registros, e que é só conferir e ' \
      "clicar em Começar. Não diga que já fez. #{dados}"
  end
end
