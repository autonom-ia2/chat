# A FALA DA LIA COM PREÇO SÓ SAI CONFERIDA (fatia 3 do #420).
#
# Decisão do CEO de 18/09/2026: quem escreve valor em reais e nome de seguradora ao cliente é a Lia, a partir do
# que `ver_resultado_da_cotacao` devolveu no turno; o código só confere. Este é o único lugar da conferência:
#
#   1. todo valor em reais da fala está no texto que a ferramenta devolveu neste turno, e toda seguradora da
#      cotação que a fala cita também está nele; e no trecho que cita seguradora, o valor é o DELA, com o
#      período dela (`trocados`);
#   2. se não bater, o modelo é chamado UMA vez para reescrever, e escreve junto uma versão sem valor nenhum;
#   3. se a reescrita não bater, sai a versão sem valores, conferida do mesmo jeito;
#   4. se nem ela passar, ou a chamada falhar, sai o recuo, registrado no log.
#
# A ideia vem do `Crm::Ai::QuoteVerifier`: comparar o que o modelo escreveu com o que ele recebeu, sem outro
# modelo no meio. Aqui a comparação é por valor em centavos e pelas palavras do nome da seguradora.
class Autonomia::Agents::ConferenciaDePrecos
  # O que a ferramenta devolveu ao modelo neste turno: `texto` é a saída dela, `seguradoras` o nome de toda
  # seguradora da cotação (é por eles que se acha a citação na fala), `comparativo` diz se o PDF já foi
  # entregue ao cliente. `coberturas` são as linhas do que cada seguradora cotou (chat#585): valores que a fala
  # pode citar, mas nunca como preço (`trocados`). Duas chamadas no mesmo turno somam (`+`).
  Dados = Struct.new(:texto, :seguradoras, :comparativo, :coberturas, keyword_init: true) do
    def +(other)
      return self if other.nil?

      Dados.new(texto: [texto, other.texto].compact.join("\n"), seguradoras: (seguradoras | other.seguradoras),
                comparativo: comparativo || other.comparativo, coberturas: Array(coberturas) + Array(other.coberturas))
    end
  end

  # O pedido de reescrita devolve as duas versões, em `strict`: as duas chaves em `required`.
  REESCRITA = {
    name: 'autonomia_reescrita_com_precos',
    schema: {
      type: 'object',
      properties: { reply: { type: 'string' }, reply_sem_valores: { type: 'string' } },
      required: %w[reply reply_sem_valores],
      additionalProperties: false
    }
  }.freeze

  # Valor com centavos ("1.321,25", com ou sem "R$"), fora de percentual.
  COM_CENTAVOS = /(?<![\d.,])(\d{1,3}(?:\.\d{3})+|\d+),(\d{2})(?!\d)(?!\s*%)/
  # Valor em reais sem centavos ("R$ 1.321"): só com o cifrão, para não confundir com contagem.
  SEM_CENTAVOS = /R\$\s*(\d{1,3}(?:\.\d{3})+|\d+)(?!\d|[.,]\d)/
  # O período que a fala ou a linha dos dados afirma (`PremiumText#resumo` escreve "no total" e "por mês").
  PERIODO_MES = /por m[eê]s|mensal/i
  PERIODO_TOTAL = /no total|[àa] vista|por ano|anual/i
  # Onde a fala se parte em trechos: quebra de linha, ou espaço depois de fim de frase ou de ponto e vírgula.
  TRECHOS = /\n|(?<=[.;!?])\s+/

  # OS RECUOS, quando nem a reescrita nem a versão sem valores passam. Sem valor e sem nome de seguradora.
  RECUO_COM_COMPARATIVO = 'Os valores de cada seguradora estão no comparativo em PDF que te mandei.'.freeze
  RECUO_SEM_COMPARATIVO = 'Não consegui escrever os valores por aqui agora. Se quiser, me peça de novo.'.freeze

  # -> os valores em centavos que o texto escreve.
  def self.valores(texto)
    texto = texto.to_s
    com = texto.scan(COM_CENTAVOS).map { |inteiro, centavos| (inteiro.delete('.').to_i * 100) + centavos.to_i }
    sem = texto.scan(SEM_CENTAVOS).map { |(inteiro)| inteiro.delete('.').to_i * 100 }
    com + sem
  end

  def initialize(dados, conversa: nil)
    @dados = dados
    @conversa = conversa
  end

  # -> o texto que pode sair ao cliente. O bloco recebe o pedido de reescrita e devolve o Hash do
  # `REESCRITA` (ou nil). Nunca levanta e nunca devolve vazio: o pior caso é o recuo.
  def publicavel(reply)
    divergencias = divergencias(reply)
    return reply if divergencias.empty?

    Rails.logger.warn("[autonomia][conferencia] reescrita pedida conversa=#{@conversa} divergencias=#{divergencias.size}")
    depois_da_reescrita(yield(pedido(divergencias)))
  rescue StandardError => e
    recuo("falha #{e.class}")
  end

  private

  def depois_da_reescrita(reescrita)
    reescrita = reescrita.is_a?(Hash) ? reescrita.stringify_keys : {}
    return reescrita['reply'] if reescrita['reply'].present? && divergencias(reescrita['reply']).empty?

    sem_valores = reescrita['reply_sem_valores']
    return sem_valores if sem_valores.present? && sem_valores?(sem_valores)

    recuo('reescrita divergente')
  end

  # -> o que a fala escreve e os dados não têm: valores (em centavos), nomes de seguradora e valores postos na
  # seguradora ou no período errados.
  def divergencias(texto)
    (self.class.valores(texto).uniq - permitidos) + (citadas(texto) - citadas(@dados.texto)) + trocados(texto)
  end

  # O VALOR É DAQUELA SEGURADORA (revisão da PR #454). Em cada trecho da fala que cita seguradora: com uma só,
  # cada valor do trecho está na linha dela nos dados, e o período do trecho não contradiz o dela; com várias,
  # cada valor está na linha de uma delas. -> os valores fora do lugar, e `:periodo` para o período trocado.
  def trocados(texto)
    texto.to_s.split(TRECHOS).flat_map do |trecho|
      nomes = citadas(trecho)
      valores = self.class.valores(trecho)
      next [] if nomes.empty? || valores.empty?

      linhas = linhas_de(nomes)
      fora = valores - linhas.flat_map { |linha| self.class.valores(linha) } - de_cobertura(trecho, nomes)
      nomes.one? && periodo_trocado?(trecho, linhas.join(' ')) ? fora + [:periodo] : fora
    end
  end

  # As linhas dos dados do turno que citam alguma destas seguradoras (uma linha por seguradora).
  def linhas_de(nomes)
    @dados.texto.to_s.lines.select { |linha| citadas(linha).intersect?(nomes) }
  end

  # O VALOR DE COBERTURA NÃO É PREÇO (revisão da chat#587). A franquia ou o limite de danos que a seguradora cotou
  # pode ser citado; no trecho que fala de período de preço ("no total", "por mês"), não: "a Suhai ficou em
  # R$ 500.000,00 no total" é o limite de danos materiais escrito como preço.
  def de_cobertura(trecho, nomes)
    return [] if trecho.match?(PERIODO_MES) || trecho.match?(PERIODO_TOTAL)

    Array(@dados.coberturas).select { |linha| citadas(linha).intersect?(nomes) }.flat_map { |linha| self.class.valores(linha) }
  end

  # O trecho diz "por mês" onde o dado é total, ou "no total" onde o dado é por mês.
  def periodo_trocado?(fala, dado)
    mes = ->(texto) { texto.match?(PERIODO_MES) && !texto.match?(PERIODO_TOTAL) }
    total = ->(texto) { texto.match?(PERIODO_TOTAL) && !texto.match?(PERIODO_MES) }
    (total.call(dado) && mes.call(fala)) || (mes.call(dado) && total.call(fala))
  end

  def sem_valores?(texto)
    self.class.valores(texto).empty? && (citadas(texto) - citadas(@dados.texto)).empty?
  end

  def permitidos
    @permitidos ||= self.class.valores([@dados.texto, *Array(@dados.coberturas)].join("\n"))
  end

  # As seguradoras da cotação que o texto cita: todas as palavras que distinguem o nome estão no texto
  # (`Insurance::ResultadoDaCotacao.palavras`, a mesma leitura da procura por nome da ferramenta).
  def citadas(texto)
    palavras = ::Autonomia::Insurance::ResultadoDaCotacao.palavras(texto)
    Array(@dados.seguradoras).select do |nome|
      do_nome = ::Autonomia::Insurance::ResultadoDaCotacao.palavras(nome)
      do_nome.any? && (do_nome - palavras).empty?
    end
  end

  def pedido(divergencias)
    lugar = if @dados.comparativo
              'diga que os valores estão no comparativo em PDF que o cliente já recebeu'
            else
              'diga que você não conseguiu escrever os valores agora e que ele pode pedir de novo'
            end
    "A sua resposta tem #{divergencias.size} valor(es) ou nome(s) de seguradora que não estão nos dados que " \
      "ver_resultado_da_cotacao devolveu neste turno. Os dados são estes:\n#{dados_por_extenso}\n\n" \
      'Reescreva a resposta ao cliente em reply, com cada valor e cada nome de seguradora exatamente como ' \
      'estão nos dados e o período junto de cada valor. Em reply_sem_valores, escreva a mesma resposta sem ' \
      "nenhum valor em reais: #{lugar}. Sem travessão."
  end

  def dados_por_extenso
    [@dados.texto, *Array(@dados.coberturas)].join("\n")
  end

  def recuo(motivo)
    papel = @dados.comparativo ? 'precos_com_comparativo' : 'precos_sem_comparativo'
    Rails.logger.warn("[autonomia][recuo] conversa=#{@conversa} papel=#{papel} motivo=#{motivo}")
    @dados.comparativo ? RECUO_COM_COMPARATIVO : RECUO_SEM_COMPARATIVO
  end
end
