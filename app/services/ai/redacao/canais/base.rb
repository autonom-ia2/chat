# O que todo canal do redator tem (#1354): o bloco comum do prompt, o núcleo do schema e a conferência estrutural
# que vale para qualquer texto com chaves do catálogo. Um canal novo herda daqui e soma o que for só dele
# (`campos_da_opcao`, `defs`, `problema_do_canal`, `normalizar_opcao`).
#
# Interface de um canal: `prompt`, `schema(permitidas:, opcoes:)`, `limites_aceitos`, `validar_saida(saida, base:)`
# (antes de separar as opções; aqui não faz nada), `validar(opcao, chaves:, limites:, base:, pedido:)` (nil ou o motivo
# do descarte), `textos_com_chaves(opcao)` (os textos da opção que levam chave; aqui só o corpo) e `normalizar(saida)`.
# Modo melhorar (`base` preenchida): os campos da base continuam na opção, e "mais_curto" não traz campo novo.
# A conferência é só de estrutura, sem regex e sem ler linguagem: as chaves saem do `Ai::Redacao::Chaves`, e "tem
# palavra antes/depois do campo" é "tem letra" (caractere com maiúscula e minúscula diferentes).
class Ai::Redacao::Canais::Base
  PROMPTS = Rails.root.join('app/services/ai/redacao/prompts').freeze
  COMUM = 'comum.md'.freeze
  STATUS = %w[ok precisa_mais_info nao_se_aplica].freeze
  MAX_OPCOES = 3
  LIMITES = %i[max_chars categoria_desejada sem_midia].freeze
  MAIS_CURTO = 'mais_curto'.freeze
  # Os mesmos do schema que passou na bateria da Modelos (#1333).
  PROBLEMAS = %w[promocional_em_servico campo_no_inicio_ou_fim campos_colados muitos_campos vago pede_dado_sensivel
                 tom_ameacador promessa_que_o_sistema_nao_cumpre longo_demais confuso outro].freeze

  class << self
    def nome
      raise NotImplementedError
    end

    def prompt
      @prompt ||= [COMUM, "#{nome}.md"].map { |file| File.read(PROMPTS.join(file)) }.join("\n\n").freeze
    end

    def schema(permitidas:, opcoes:)
      { name: "redacao_#{nome}", strict: true, schema: nucleo(permitidas, opcoes) }
    end

    # Os limites que este canal entende (o que vai à IA em "limites"). O canal restringe ou soma.
    def limites_aceitos
      LIMITES
    end

    # Conferência da resposta inteira, antes de separar as opções. Devolve a saída (já normalizada) a usar.
    def validar_saida(saida, **)
      saida
    end

    # Os textos da opção que levam chave. O canal com cabeçalho e botões soma os dele.
    def textos_com_chaves(opcao)
      [opcao['texto'].to_s]
    end

    # nil quando a opção serve; senão o motivo (símbolo) do descarte.
    def validar(opcao, chaves:, limites:, base: nil, pedido: nil)
      texto = opcao['texto'].to_s
      textos = textos_com_chaves(opcao)
      problema = problema_de_forma(texto, textos, limites)
      return problema if problema

      usadas = textos.flat_map { |item| Ai::Redacao::Chaves.extrair(item) }
      problema_das_chaves(usadas, chaves) || problema_das_pontas(texto) || problema_da_base(usadas, chaves, base, pedido) ||
        problema_do_canal(opcao, chaves: chaves, limites: limites, base: base, pedido: pedido)
    end

    # A saída do modelo no formato do contrato. O que o comum não conhece fica de fora; o canal soma o seu.
    def normalizar(saida)
      saida = saida.to_h
      status = STATUS.include?(saida['status']) ? saida['status'] : 'nao_se_aplica'
      {
        status: status, pergunta: saida['pergunta'].presence, sugestoes: Array(saida['sugestoes']).map(&:to_s).first(MAX_OPCOES),
        opcoes: status == 'ok' ? Array(saida['opcoes']).select { |opcao| opcao.is_a?(Hash) } : []
      }
    end

    def normalizar_opcao(opcao)
      texto = opcao['texto'].to_s.strip
      { texto: texto, chaves_usadas: Ai::Redacao::Chaves.extrair(texto).uniq, categoria_prevista: opcao['categoria_prevista'],
        motivo_categoria: opcao['motivo_categoria'].presence, o_que_mudou: opcao['o_que_mudou'].presence }
    end

    private

    def problema_do_canal(_opcao, **)
      nil
    end

    def problema_de_forma(texto, textos, limites)
      return :vazio if texto.strip.empty?
      return :longo if limites[:max_chars].present? && texto.length > limites[:max_chars].to_i

      :malformado if textos.any? { |item| Ai::Redacao::Chaves.malformado?(item) }
    end

    # `usadas`: as chaves da UNIÃO dos textos da opção (corpo e, no canal que tem, cabeçalho e botões).
    def problema_das_chaves(usadas, chaves)
      return :chave_fora_da_lista unless (usadas - Array(chaves[:permitidas])).empty?

      :obrigatoria_ausente unless (Array(chaves[:obrigatorias]) - usadas).empty?
    end

    # Modo melhorar: os campos da base (que a lista permite) continuam; "mais_curto" não traz campo novo.
    def problema_da_base(usadas, chaves, base, pedido)
      return if base.blank?

      da_base = chaves_da_base(base) & Array(chaves[:permitidas])
      return :campo_da_base_removido unless (da_base - usadas).empty?

      :campo_novo_no_mais_curto if mais_curto?(pedido) && !(usadas - da_base).empty?
    end

    # `base` é o texto atual, ou `{ texto:, ... }` no canal que estende a base.
    def chaves_da_base(base)
      texto = base.is_a?(Hash) ? base.to_h.stringify_keys['texto'] : base
      Ai::Redacao::Chaves.extrair(texto.to_s)
    end

    def mais_curto?(pedido)
      melhorias = pedido.is_a?(Hash) ? pedido.to_h.stringify_keys['melhorias'] : nil
      Array(melhorias).map(&:to_s).include?(MAIS_CURTO)
    end

    # Palavras antes do primeiro campo e depois do último (o comum pede "feche com uma frase sem campo").
    def problema_das_pontas(texto)
      partes = Ai::Redacao::Chaves.partes(texto)
      return if partes.none?(&:chave?)
      return :campo_no_inicio unless texto_com_letra?(partes.first)

      :campo_no_fim unless texto_com_letra?(partes.last)
    end

    def texto_com_letra?(parte)
      !parte.chave? && parte.valor.each_char.any? { |char| char.upcase != char.downcase }
    end

    def nucleo(permitidas, opcoes)
      { type: 'object', additionalProperties: false, required: %w[status pergunta sugestoes problemas_encontrados opcoes],
        properties: {
          status: { type: 'string', enum: STATUS }, pergunta: { type: %w[string null] },
          sugestoes: { type: 'array', maxItems: MAX_OPCOES, items: { type: 'string' } },
          problemas_encontrados: { type: 'array', items: problema_schema },
          opcoes: { type: 'array', maxItems: opcoes.to_i.clamp(1, MAX_OPCOES), items: { '$ref': '#/$defs/opcao' } }
        },
        '$defs': defs.merge(opcao: opcao_schema(permitidas)) }
    end

    def opcao_schema(permitidas)
      properties = {
        texto: { type: 'string' }, chaves_usadas: { type: 'array', items: { type: 'string', enum: permitidas } },
        o_que_mudou: { type: %w[string null] }, categoria_prevista: { type: %w[string null], enum: ['servico', 'divulgacao', nil] },
        certeza_categoria: { type: %w[string null], enum: ['alta', 'media', 'baixa', nil] }, motivo_categoria: { type: %w[string null] }
      }.merge(campos_da_opcao(permitidas))
      { type: 'object', additionalProperties: false, required: properties.keys.map(&:to_s), properties: properties }
    end

    def problema_schema
      { type: 'object', additionalProperties: false, required: %w[trecho problema explicacao],
        properties: { trecho: { type: 'string' }, problema: { type: 'string', enum: PROBLEMAS }, explicacao: { type: 'string' } } }
    end

    def campos_da_opcao(_permitidas)
      {}
    end

    def defs
      {}
    end
  end
end
