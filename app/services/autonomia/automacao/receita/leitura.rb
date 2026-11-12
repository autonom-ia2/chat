# A régua dos valores que a receita lê (#2608, saiu da Receita): todo `$valor` do caminho, do corpo, do texto e das
# condições passa por aqui.
#
# Caminho que a automação não sabe ler, ou atributo que a conta não tem. O atributo apagado depois de salvar chega
# vazio no motor, com o motivo no registro. A resposta (G11) só existe na condição do "esperar até": fora dele não há
# o começo da espera, e ela leria sempre vazio. O texto da IA (#2679) só vem de um passo que escreve; o registro criado
# (G49), de um passo que cria, e do `tipo` pedido quando o lugar só aceita um (o contato do "criar card"). A mensagem
# que falhou (G53) não vale no "Só se" do gatilho (`no_gatilho`): a Partida filtra sem ela. `lugar`: `tipo` (G49) e
# `onde`: :caminho ou :corpo da ação, :texto (mensagem, aviso, e-mail, retorno); sem `onde` é o que decide (filtro e
# condição). Na ação, a automação de conversa não usa o card para agir (#2716): nenhum `card.*` no caminho e nenhum
# `card.id` no corpo; copiar um campo do card é ler. Vale também no ramo do "em outro registro" que roda numa conversa
# (alvo) e na origem que é uma conversa (decisão 19).
class Autonomia::Automacao::Receita::Leitura
  include ::Autonomia::Automacao::Receita::Frase

  # `travessia`: a Receita, por onde o texto da IA e o registro criado andam nos passos (do_alvo, ramos_do_alvo).
  # `contexto`: Receita::Contexto.
  def initialize(travessia, contexto)
    @travessia = travessia
    @receita = contexto.receita
    @conta = contexto.conta
    @account_user = contexto.account_user
    @alvo = contexto.alvo
    @origem = contexto.origem
  end

  def problemas(id, caminho, no_gatilho: false, na_espera: false, **lugar)
    valores = ::Autonomia::Automacao::Valores
    return [texto(:valor_desconhecido, passo: id, caminho: caminho)] unless valores.caminho_valido?(caminho)

    de_passo = de_outro_passo(id, caminho, no_gatilho, lugar[:tipo])
    return de_passo if de_passo
    return problemas_da_origem(id, caminho, lugar[:onde]) if valores.da_origem?(caminho)

    fora = ::Autonomia::Automacao::LugarDoValor.fora(caminho, gatilho: @receita['gatilho'], na_espera: na_espera, no_filtro: no_gatilho)
    return [texto(fora, passo: id, caminho: caminho)] if fora
    return [texto(:valor_fora_do_alvo, passo: id, caminho: caminho)] unless no_alvo_do_gatilho?(caminho)

    lido_no(id, caminho, caminho, lugar[:onde], alvo)
  end

  private

  attr_reader :alvo

  # G65: `origem.*` só no ramo do "em outro registro" (a filha lê o alvo da mãe), com o caminho que o alvo do gatilho da
  # mãe alcança e a régua de sempre (lido_no), no alvo da mãe.
  def problemas_da_origem(id, caminho, onde)
    lido = ::Autonomia::Automacao::Valores.caminho_da_origem(caminho)
    return [texto(:origem_fora_do_ramo, passo: id, caminho: caminho)] unless @origem
    return [texto(:valor_fora_do_alvo, passo: id, caminho: caminho)] unless ::Autonomia::Automacao::Valores.no_alvo?(lido, @origem)

    lido_no(id, caminho, lido, onde, @origem)
  end

  # O `lido` (sem o prefixo da origem) no registro `alvo_type`: o card da conversa só para ler (decisão 19), o atributo
  # da conta e a permissão de quem salva. A frase leva o `caminho` como a pessoa escreveu.
  def lido_no(id, caminho, lido, onde, alvo_type)
    no_lugar = ::Autonomia::Automacao::CardDaConversa.problema(lido, onde, alvo_type)
    return [texto(no_lugar, passo: id, caminho: caminho)] if no_lugar

    leitura = ::Autonomia::Automacao::Valores.problema_de_leitura(lido, conta: @conta, account_user: @account_user)
    Array(leitura).map { |chave| texto(chave, passo: id, caminho: caminho) }
  end

  # O valor que vem de outro passo desta execução: o texto da IA (#2679) ou o registro criado (G49); nil nos outros.
  def de_outro_passo(id, caminho, no_gatilho, tipo)
    if ::Autonomia::Automacao::Valores.da_ia?(caminho)
      ::Autonomia::Automacao::TextoDaIaNaReceita.new(@travessia, @receita).problemas(id, caminho, no_gatilho: no_gatilho)
    elsif ::Autonomia::Automacao::RegistroCriado.caminho?(caminho)
      ::Autonomia::Automacao::RegistroCriadoNaReceita.new(@travessia, @receita, tipo: tipo).problemas(id, caminho, no_gatilho: no_gatilho)
    end
  end

  # #2499: `card.*` num gatilho de conversa não tem de onde ler. Gatilho desconhecido o esquema já recusou.
  # A conversa nova (#2680) dá ao alvo sem conversa (o contato) a ponte para a que ela abre.
  def no_alvo_do_gatilho?(caminho)
    return true if alvo.nil? || ::Autonomia::Automacao::Valores.no_alvo?(caminho, alvo)

    ::Autonomia::Automacao::ConversaNova.caixa_id(@receita).present? && caminho.to_s.start_with?('conversa.')
  end
end
