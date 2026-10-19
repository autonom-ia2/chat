# #1426 (tema 4b) — a escolha da pessoa num problema. Nada se resolve sozinho: cada saída é um botão que ela apertou.
# - contradicao + id do material que vale: grava a escolha. Os DOIS materiais ficam (decisão do Rodrigo, 19/10); o agente
#   passa a usar o escolhido nesse assunto (PromptParts::DecisoesDoMaterial).
# - duplicado + 'um_so': tira o material repetido (o mais novo), pelo mesmo caminho do "Tirar" da gaveta.
# - duplicado + 'os_dois': os dois ficam e o par não volta a ser apontado.
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
    case @escolha.to_s
    when 'um_so'
      fonte = @agent.sources.find(@problema['tirar'])
      fonte.destroy!
      Autonomia::Agents::Knowledge::RecomputeOverallJob.perform_later(@agent.id)
    when 'os_dois'
      par = [@problema['manter'], @problema['tirar']]
      alterar_conferencia! { |base| base.merge('duplicados_mantidos' => (Array(base['duplicados_mantidos']) + [par]).uniq) }
    else raise Invalido, 'escolha_invalida'
    end
  end

  def confirmar!
    raise Invalido, 'escolha_invalida' unless @escolha.to_s == 'certa'

    rodada, indice = @problema['id'].delete_prefix('autoteste-').split('-')
    @agent.alterar_chave_do_material!(Autonomia::Agents::Material::Autoteste::CHAVE) do |atual|
      next unless atual.is_a?(Hash) && atual['rodada'] == rodada

      itens = Array(atual['itens']).each_with_index.map { |item, i| i == indice.to_i ? item.merge('confirmada' => true) : item }
      atual.merge('itens' => itens)
    end
  end

  def alterar_conferencia!(&)
    @agent.alterar_chave_do_material!(Autonomia::Agents::Material::Contradicoes::CHAVE) do |atual|
      yield(atual.is_a?(Hash) ? atual : {})
    end
  end
end
