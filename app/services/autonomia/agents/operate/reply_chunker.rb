module Autonomia
  module Agents
    module Operate
      # ENTREGA HUMANIZADA — QUEBRADOR + RITMO. Porta enxuta e fiel do script "splitResponse v3"
      # que o produto calibrou no n8n: pega a resposta ÚNICA do Answerer e devolve uma lista de
      # pedaços naturais, cada um com um delay (ms) calculado para imitar digitação humana.
      #
      # Decisões portadas do v3 (sem as heurísticas semânticas de link/CTA, desnecessárias p/ o v1):
      #   - quebra por parágrafo (\n\n) → sentença (. ! ? …) → empacota até soft_max, racha > hard_max;
      #   - URLs/preços/datas/SKUs/abreviações são PROTEGIDOS para não quebrar no meio;
      #   - pedaços < min_chunk são colados no vizinho; teto de max_chunks (cola os mais próximos);
      #   - delay = perChar(24–38ms)·len + pausas de pontuação/quebra/bullet + extra do 1º OU gap dos
      #     próximos + jitter; clamp [min,max] por chunk; teto total (escala p/ baixo se estourar).
      #
      # Determinístico fora do jitter (Random): mesma resposta → mesma quebra; só os delays variam.
      # 100% texto puro (sem rede/IO) → trivialmente testável e seguro (nunca levanta no caminho vivo).
      class ReplyChunker
        H = ::Autonomia::Agents::Config::HUMANIZE

        URL_REGEX = %r{https?://[^\s<>"]+}i
        # Tokens que NÃO podem ser cortados por um ponto final no meio (decimais, datas, SKUs, URLs, e-mails).
        PROTECT_PATTERNS = [
          URL_REGEX,
          /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
          %r{\b\d{2}/\d{2}/\d{4}\b},
          /\b\d{1,3}(?:\.\d{3})*,\d{2}\b/,          # 1.234,56
          /\b[A-Z]{2,}[- ]?\d[A-Z0-9-]*\b/i,        # SKU NB-15 / ST-045
          /\b\d+[.,]\d+\b/                           # 4.999 / 3,5
        ].freeze
        # Abreviações cujo ponto NÃO encerra frase. Casadas com o ponto e protegidas como token.
        ABBREVIATION_RE = /\b(?:Dr|Dra|Sr|Sra|Srta|etc|vs|aprox|obs|Ref|Ex)\./i

        # Item de lista: marcador (•, -, *) ou numeração (1. / 1)) seguido de espaço. Espelha o
        # mesmo formato que `text_delay` já reconhece para a pausa de bullet.
        # `*negrito*` do WhatsApp NÃO casa (exige espaço depois do marcador).
        LIST_ITEM_RE = /\A\s*(?:[-*•]\s+|\d+[.)]\s+)/

        # SENTINELAS de área privada Unicode (U+E000/E001) que envolvem o índice do token protegido.
        # Nunca aparecem em texto real, não casam pontuação de frase e sobrevivem ao split → colisão-proof.
        # (O esquema antigo " N " colidia com números soltos do texto: "3 parcelas" virava lixo no restore.)
        TOKEN_OPEN = [0xE000].pack('U').freeze
        TOKEN_CLOSE = [0xE001].pack('U').freeze
        TOKEN_RE = /#{[0xE000].pack('U')}(\d+)#{[0xE001].pack('U')}/.freeze

        # text:String -> Array<{ 'text'=>String, 'delay_ms'=>Integer, 'type'=>'text'|'url' }>
        def self.call(text)
          new(text).call
        end

        def initialize(text)
          @text = text.to_s
        end

        def call
          chunks = build_chunks(normalize(@text))
          return [] if chunks.empty?

          with_delays(chunks)
        end

        private

        # ---- Normalização (espelha normalizeText do v3) -------------------------------------------
        def normalize(text)
          text.gsub("\u00A0", ' ')                       # NBSP -> espaco normal
              .gsub(/[\u200B\u200C\u200D\uFEFF]/, '')   # zero-width / BOM
              .gsub("\r\n", "\n")
              .gsub('\\n', "\n")
              .gsub(/[ \t]+\n/, "\n")
              .gsub(/\n{3,}/, "\n\n")
              .gsub(/[ \t]{2,}/, ' ')
              .gsub(/\*\*(.+?)\*\*/m, '*\\1*')          # **negrito** -> *negrito* (WhatsApp)
              .strip
        end

        # ---- Construção dos pedaços ---------------------------------------------------------------
        def build_chunks(normalized)
          raw = []
          normalized.split(/\n{2,}/).map(&:strip).reject(&:empty?).each do |block|
            if url_only?(block)
              raw << { text: block, type: 'url' }
            else
              pack_block(block).each { |c| raw << { text: c, type: 'text' } }
            end
          end
          refine(raw)
        end

        def url_only?(text)
          t = text.strip
          t.match?(URL_REGEX) && t.sub(URL_REGEX, '').strip.empty?
        end

        # Empacota um bloco separando LISTAS (átomos) de PROSA (empacotada normalmente).
        # Defeito de produção (lista de 6 documentos entregue picotada em 4 mensagens): uma lista
        # partida no meio chega quebrada ao cliente. Uma corrida de 2+ linhas de item sai INTEIRA
        # num único pedaço — sem soft_max, sem hard_max, sem split_long.
        def pack_block(block)
          lines = block.split("\n").map(&:rstrip).reject { |line| line.strip.empty? }
          return [] if lines.empty?

          segments(lines).flat_map do |list, group|
            list ? [group.join("\n")] : pack_lines(group)
          end
        end

        # Fatia as linhas em segmentos [lista?, linhas]. Só uma corrida de 2+ itens conta como lista;
        # um bullet solto segue no segmento de prosa (mesmo empacotamento de sempre, zero regressão).
        def segments(lines)
          flags = list_run_flags(lines)
          lines.zip(flags)
               .slice_when { |(_, a), (_, b)| a != b }
               .map { |pairs| [pairs.first.last, pairs.map(&:first)] }
        end

        def list_run_flags(lines)
          marks = lines.map { |line| line.match?(LIST_ITEM_RE) }
          marks.each_with_index.map do |mark, i|
            neighbor = (i.positive? && marks[i - 1]) || marks[i + 1] == true
            mark && neighbor
          end
        end

        # PROSA: preserva as quebras de linha entre linhas curtas — junta linhas com "\n" até
        # soft_max; uma linha longa (> soft_max) é quebrada em sentenças e empacotada por espaço.
        def pack_lines(lines)
          chunks = []
          current = +''
          flush = lambda do
            chunks << current.strip unless current.strip.empty?
            current = +''
          end

          lines.each do |line|
            if line.length > H[:soft_max_chunk_chars]
              flush.call
              pack_sentences(split_sentences(line)).each { |c| chunks << c }
              next
            end

            candidate = current.empty? ? line : "#{current}\n#{line}"
            if candidate.length <= H[:soft_max_chunk_chars]
              current = candidate
            else
              flush.call
              current = line
            end
          end
          flush.call
          chunks.flat_map { |c| c.length <= H[:hard_max_chunk_chars] ? [c] : split_long(c) }
        end

        # Quebra em sentenças protegendo tokens (decimais/URLs/abreviações) de um ponto-final falso.
        def split_sentences(text)
          protected_text, restore = protect(text)
          out = []
          buffer = +''
          chars = protected_text.chars
          chars.each_with_index do |ch, i|
            buffer << ch
            nxt = chars[i + 1]
            boundary = ch == "\n" || (".!?…".include?(ch) && (nxt.nil? || nxt == ' ' || nxt == "\n"))
            next unless boundary

            piece = restore.call(buffer).strip
            out << piece unless piece.empty?
            buffer = +''
          end
          tail = restore.call(buffer).strip
          out << tail unless tail.empty?
          out
        end

        def pack_sentences(sentences)
          chunks = []
          current = +''
          sentences.each do |sentence|
            units = sentence.length > H[:hard_max_chunk_chars] ? split_long(sentence) : [sentence]
            units.each do |unit|
              candidate = current.empty? ? unit : "#{current} #{unit}"
              if candidate.length <= H[:soft_max_chunk_chars]
                current = candidate
              else
                chunks << current unless current.empty?
                current = unit
              end
            end
          end
          chunks << current unless current.empty?
          chunks
        end

        # Racha texto acima de hard_max por separadores naturais e, em último caso, por palavra.
        def split_long(text)
          clean = text.strip
          return [clean] if clean.length <= H[:hard_max_chunk_chars]

          ['; ', ': ', ', ', ' - ', ' — '].each do |sep|
            next unless clean.include?(sep)

            parts = pack_by(clean.split(sep), sep.strip)
            return parts if parts.all? { |p| p.length <= H[:hard_max_chunk_chars] }
          end
          pack_by(clean.split(/\s+/), nil)
        end

        def pack_by(parts, joiner)
          chunks = []
          current = +''
          parts.each_with_index do |part, i|
            piece = joiner && i < parts.size - 1 ? "#{part}#{joiner}" : part
            candidate = current.empty? ? piece : "#{current} #{piece}"
            if candidate.length <= H[:hard_max_chunk_chars]
              current = candidate
            else
              chunks << current.strip unless current.empty?
              current = part
            end
          end
          chunks << current.strip unless current.empty?
          chunks
        end

        # Protege tokens sensíveis (abreviações + URL/preço/data/SKU/decimais) trocando-os por
        # SENTINELAS de área privada (TOKEN_OPEN<idx>TOKEN_CLOSE) antes do split; restore() desfaz.
        # Números SOLTOS do texto ("3 parcelas") NÃO casam o restore (TOKEN_RE exige os sentinelas).
        def protect(text)
          tokens = []
          wrap = ->(match) { tokens << match; "#{TOKEN_OPEN}#{tokens.size - 1}#{TOKEN_CLOSE}" }
          protected_text = text.dup
          [ABBREVIATION_RE, *PROTECT_PATTERNS].each do |pattern|
            protected_text = protected_text.gsub(pattern, &wrap)
          end
          restore = ->(value) { value.gsub(TOKEN_RE) { tokens[Regexp.last_match(1).to_i].to_s } }
          [protected_text, restore]
        end

        # Cola pedaços curtos (< min_chunk) no vizinho e impõe o teto de max_chunks.
        def refine(chunks)
          refined = chunks.map { |c| { text: c[:text].strip, type: c[:type] } }.reject { |c| c[:text].empty? }

          merged = true
          while merged
            merged = false
            refined.each_with_index do |chunk, i|
              next if chunk[:text].length >= H[:min_chunk_chars]
              next if chunk[:type] == 'url' # URL isolada nunca cola

              target = best_merge_neighbor(refined, i)
              next if target.nil?

              a, b = target < i ? [target, i] : [i, target]
              refined[a..b] = [merge_two(refined[a], refined[b])]
              merged = true
              break
            end
          end

          while refined.size > H[:max_chunks]
            i = smallest_adjacent_pair(refined)
            break if i.nil?

            refined[i..i + 1] = [merge_two(refined[i], refined[i + 1])]
          end
          refined
        end

        def best_merge_neighbor(chunks, index)
          prev_i = index - 1
          next_i = index + 1
          prev_ok = prev_i >= 0 && chunks[prev_i][:type] != 'url'
          next_ok = next_i < chunks.size && chunks[next_i][:type] != 'url'
          return prev_i if prev_ok && !next_ok
          return next_i if next_ok && !prev_ok
          return nil unless prev_ok && next_ok

          # cola no vizinho que gera o menor chunk combinado (mantém pedaços equilibrados)
          chunks[prev_i][:text].length <= chunks[next_i][:text].length ? prev_i : next_i
        end

        def smallest_adjacent_pair(chunks)
          best = nil
          best_len = nil
          (0...chunks.size - 1).each do |i|
            next if chunks[i][:type] == 'url' || chunks[i + 1][:type] == 'url'

            len = chunks[i][:text].length + chunks[i + 1][:text].length
            if best_len.nil? || len < best_len
              best_len = len
              best = i
            end
          end
          # se só sobraram URLs adjacentes, força a cola do 1º par para respeitar o teto
          best.nil? ? 0 : best
        end

        # Cola com "\n" quando o pedaço da direita abre uma LISTA — colar com espaço grudaria o
        # preâmbulo no 1º item e destruiria a formatação que o átomo de lista acabou de preservar.
        def merge_two(a, b)
          joiner = a[:text].end_with?("\n") || b[:text].start_with?('-') || b[:text].match?(LIST_ITEM_RE) ? "\n" : ' '
          { text: "#{a[:text]}#{joiner}#{b[:text]}".gsub(/[ \t]{2,}/, ' ').strip,
            type: a[:type] == 'url' || b[:type] == 'url' ? 'text' : a[:type] }
        end

        # ---- Cálculo de delay (espelha computeChunkDelay do v3) -----------------------------------
        def with_delays(chunks)
          waits = chunks.each_with_index.map { |chunk, i| chunk_delay(chunk, i) }
          total = waits.sum
          if total > H[:max_total_delay_ms]
            scale = H[:max_total_delay_ms].to_f / total
            waits = waits.map { |w| [(w * scale).round, H[:min_chunk_delay_ms]].max }
          end
          chunks.each_with_index.map do |chunk, i|
            { 'text' => chunk[:text], 'type' => chunk[:type], 'delay_ms' => waits[i] }
          end
        end

        def chunk_delay(chunk, index)
          base = chunk[:type] == 'url' ? url_delay : text_delay(chunk[:text])
          base += index.zero? ? rand_int(H[:first_chunk_extra_min_ms], H[:first_chunk_extra_max_ms])
                              : rand_int(H[:next_chunk_gap_min_ms], H[:next_chunk_gap_max_ms])
          base.round.clamp(H[:min_chunk_delay_ms], H[:max_chunk_delay_ms])
        end

        def text_delay(text)
          compact = text.gsub(/\s+/, ' ').strip
          delay = compact.length * rand_int(H[:per_char_min_ms], H[:per_char_max_ms])
          delay += text.scan("\n").size * H[:newline_pause_ms]
          delay += text.scan(/(?:\A|\n)\s*(?:[-*•]\s+|\d+[.)]\s+)/).size * H[:bullet_pause_ms]
          H[:punctuation_pause_ms].each { |sym, pause| delay += text.count(sym) * pause }
          delay
        end

        def url_delay
          rand_int(H[:url_chunk_min_ms], H[:url_chunk_max_ms]) + H[:url_lead_pause_ms]
        end

        def rand_int(min, max)
          min + Kernel.rand(max - min + 1)
        end
      end
    end
  end
end
