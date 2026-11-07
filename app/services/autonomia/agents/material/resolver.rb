# #1426 (tema 4b) — a escolha da pessoa num problema. Nada se resolve sozinho: cada saída é um botão que ela apertou.
# - contradicao + id do material que vale: grava a escolha. Os DOIS materiais ficam (decisão do Rodrigo, 19/10); o agente
#   passa a usar o escolhido nesse assunto (PromptParts::DecisoesDoMaterial).
# - duplicado + 'os_dois': os dois ficam e o par não volta a ser apontado. "Ficar só com X" não passa por aqui: é o Tirar
#   da gaveta, com a confirmação de sempre (nada é apagado por este caminho).
# - autoteste/autoteste_fora + 'certa': a pessoa diz que a resposta está certa; o item conta como certo.
# Vazio, leitura ruim, tabela sem cabeçalho e páginas de fora não têm escolha aqui: as saídas deles são mandar outro
# arquivo, tirar ou explicar conversando, que a tela leva para os caminhos de sempre. Problema que não existe mais (já
# resolvido, material tirado) ou escolha fora das opções: Invalido (422).
class Autonomia::Agents::Material::Resolver
  class Invalido < StandardError; end

  def initialize(agent, problema_id, escolha)
    @agent = agent
    @problema = Autonomia::Agents::Material::Problemas.new(agent).lista.find { |item| item['id'] == problema_id.to_s }
    @escolha = escolha
  end

  def resolver!
    raise Invalido, 'problema_sumiu' if @problema.nil?

    case @problema['tipo']
    when 'contradicao' then escolher!
    when 'duplicado' then duplicado!
    when 'autoteste', 'autoteste_fora' then confirmar!
    when 'ocr' then usar_mesmo_assim!
    else raise Invalido, 'sem_escolha'
    end
  end

  private

  def escolher!
    valor = @escolha.to_i
    raise Invalido, 'escolha_invalida' unless @problema['fontes'].include?(valor)

    alterar_conferencia! do |base|
      base.merge('contradicoes' => Array(base['contradicoes']).map do |item|
        item['id'] == @problema['id'] ? item.merge('escolha' => valor, 'escolhida_em' => Time.current.iso8601) : item
      end)
    end
  end

  def duplicado!
    raise Invalido, 'escolha_invalida' unless @escolha.to_s == 'os_dois'

    par = [@problema['manter'], @problema['tirar']]
    alterar_conferencia! { |base| base.merge('duplicados_mantidos' => (Array(base['duplicados_mantidos']) + [par]).uniq) }
  end

  def confirmar!
    raise Invalido, 'escolha_invalida' unless @escolha.to_s == 'certa'

    rodada, indice = @problema['id'].delete_prefix('autoteste-').split('-')
    @agent.alterar_chave_do_material!(Autonomia::Agents::Material::Autoteste::CHAVE) do |atual|
      next unless atual.is_a?(Hash) && atual['rodada_dos_itens'] == rodada

      itens = Array(atual['itens']).each_with_index.map { |item, i| i == indice.to_i ? item.merge('confirmada' => true) : item }
      atual.merge('itens' => itens)
    end
  end

  # #2425 (protótipo) — leitura ruim + 'usar': a pessoa conferiu "o que eu li" com o arquivo e disse que está certo. O
  # material passa a valer; a conferência guarda que foi o dono que aceitou, e com que texto (o mesmo arquivo, com o mesmo
  # texto, não volta a ser reprovado pela leitura).
  def usar_mesmo_assim!
    raise Invalido, 'escolha_invalida' unless @escolha.to_s == 'usar'

    fonte = @agent.sources.find(@problema['fontes'].first)
    conferencia = fonte.metadata.to_h['conferencia'].to_h
    aceite = { 'em' => Time.current.iso8601, 'hash_do_texto' => fonte.metadata.to_h['hash_do_texto'] }
    fonte.update!(review_status: 'accepted',
                  metadata: fonte.metadata.to_h.merge('conferencia' => conferencia.merge('aceito_pelo_dono' => aceite)))
  end

  def alterar_conferencia!(&)
    @agent.alterar_chave_do_material!(Autonomia::Agents::Material::Contradicoes::CHAVE) do |atual|
      yield(atual.is_a?(Hash) ? atual : {})
    end
  end
end
