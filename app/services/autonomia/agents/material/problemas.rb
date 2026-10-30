# #1426 (tema 4b) — a lista "um problema por vez": o que as conferências e o autoteste acharam, na ordem em que a tela
# mostra. Cada problema tem `id` estável, `tipo`, os materiais envolvidos (`fontes`) e o que o cartão precisa. O texto
# leigo é da tela (i18n); daqui saem só dados. Nada aqui chama IA: lê o que já foi gravado.
#
# Tipos: vazio · ocr · sem_cabecalho · duplicado · contradicao · paginas_de_fora · autoteste (resposta errada) ·
# autoteste_fora (inventou numa pergunta de fora do material).
class Autonomia::Agents::Material::Problemas
  ERRO_DE_VAZIO = 'empty_extraction'.freeze
  REPROVADOS = %w[ocr sem_cabecalho].freeze

  def initialize(agent)
    @agent = agent
    @fontes = agent.sources.knowledge_sources.order(:id).to_a
    @por_id = @fontes.index_by(&:id)
  end

  def lista
    return [] unless Autonomia::Agents::Material.conferir?(@agent)

    vazios + reprovados + duplicados + contradicoes + paginas_de_fora + do_autoteste
  end

  private

  def vazios
    @fontes.select { |fonte| fonte.failed? && fonte.error == ERRO_DE_VAZIO }
           .map { |fonte| { 'id' => "vazio-#{fonte.id}", 'tipo' => 'vazio', 'fontes' => [fonte.id], 'nome' => nome(fonte) } }
  end

  # Leitura ruim e tabela sem cabeçalho: só enquanto a reprovação for a da conferência vigente. #1426 (t4e): no material
  # grande, a tabela sem cabeçalho é aviso (`aviso` na conferência) e o material segue aceito; o cartão aparece do mesmo jeito.
  def reprovados
    @fontes.filter_map do |fonte|
      conferencia = fonte.metadata.to_h['conferencia'].to_h
      problema = conferencia['problema']
      next unless fonte.ready? && REPROVADOS.include?(problema)

      aviso = fonte.review_status == 'accepted' && conferencia['aviso'] == true
      next unless fonte.review_status == 'needs_resend' || aviso

      reprovado(fonte, problema, aviso)
    end
  end

  # No aviso, a tela troca o rodapé: o material continua em uso.
  def reprovado(fonte, problema, aviso)
    item = { 'id' => "#{problema}-#{fonte.id}", 'tipo' => problema, 'fontes' => [fonte.id], 'nome' => nome(fonte),
             'foto' => fonte.source_type == Autonomia::Agents::Source::FOTO,
             'amostra' => Array(fonte.metadata.to_h.dig('conferencia', 'amostra')) }
    aviso ? item.merge('aviso' => true) : item
  end

  # Mesmo texto (resumo exato do texto lido): fica o mais antigo, o outro é o candidato a sair.
  def duplicados
    lidos = @fontes.select { |fonte| fonte.ready? && fonte.metadata.to_h['hash_do_texto'].present? }
    lidos.group_by { |fonte| fonte.metadata['hash_do_texto'] }.values.flat_map do |grupo|
      manter, *outros = grupo
      outros.reject { |outro| mantidos.include?([manter.id, outro.id]) }.map { |outro| duplicado(manter, outro) }
    end
  end

  def duplicado(manter, outro)
    { 'id' => "duplicado-#{manter.id}-#{outro.id}", 'tipo' => 'duplicado', 'fontes' => [manter.id, outro.id],
      'nome' => nome(manter), 'outro' => nome(outro), 'manter' => manter.id, 'tirar' => outro.id }
  end

  def contradicoes
    Array(conferencia['contradicoes']).filter_map do |item|
      ids = item['opcoes'].to_a.pluck('fonte')
      next if item['escolha'].present? || ids.size != 2 || !ids.all? { |id| @por_id[id] }

      { 'id' => item['id'], 'tipo' => 'contradicao', 'fontes' => ids, 'assunto' => item['assunto'],
        'opcoes' => item['opcoes'].map { |opcao| { 'valor' => opcao['fonte'], 'onde' => nome(@por_id[opcao['fonte']]), 'diz' => opcao['diz'] } } }
    end
  end

  # O material vale com o que foi lido: o cartão só avisa o que ficou de fora e por quê.
  def paginas_de_fora
    @fontes.filter_map do |fonte|
      fora = fonte.metadata.to_h[Autonomia::Agents::Source::PAGINAS_DE_FORA]
      next unless fonte.ready? && fora.is_a?(Hash) && fora.any?

      { 'id' => "paginas-#{fonte.id}", 'tipo' => 'paginas_de_fora', 'fontes' => [fonte.id], 'nome' => nome(fonte) }
        .merge(Autonomia::Agents::Material::PaginasDeFora.resumo(fora))
    end
  end

  def do_autoteste
    estado = @agent.chave_do_material(Autonomia::Agents::Material::Autoteste::CHAVE).to_h
    Array(estado['itens']).each_with_index.filter_map do |item, indice|
      next if item['confirmada'] || %w[errado inventou].exclude?(item['veredito'])

      fonte = @por_id[item['fonte']]
      { 'id' => "autoteste-#{estado['rodada_dos_itens']}-#{indice}", 'tipo' => item['origem'] == 'fora' ? 'autoteste_fora' : 'autoteste',
        'fontes' => [], 'pergunta' => item['pergunta'], 'resposta' => item['resposta'], 'equipe' => item['equipe'] == true,
        'esperado' => item['esperado'], 'onde' => fonte && nome(fonte),
        'trechos' => Autonomia::Agents::Material::TrechosUsados.da_tela(item, @por_id) }.compact
    end
  end

  def conferencia
    @conferencia ||= @agent.chave_do_material(Autonomia::Agents::Material::Contradicoes::CHAVE).to_h
  end

  def mantidos
    @mantidos ||= Array(conferencia['duplicados_mantidos'])
  end

  def nome(fonte)
    Autonomia::Agents::Material.nome(fonte)
  end
end
