# Gera o .sql que grava a chave de leitura na ficha do painel de desempenho (#2301). Script LOCAL, em Ruby puro (sem
# Rails): em produção não se roda `rails runner`. Quem executa o .sql é a Orquestração, com psql.
#
#   ruby script/desempenho/chave.rb --chave <arquivo.md> --conta <id> --ficha <id> --versao <n> --saida <arquivo.sql>
#                                   [--instrucao <arquivo.txt> | --hash <sha256>] [--com-teste]
#
# - A chave é dado da conta: o arquivo dela e o .sql ficam fora do repositório. O script recusa --saida dentro deste
#   repositório e de qualquer working tree git (outra cópia, outra worktree), com os links simbólicos resolvidos.
# - O UPDATE só pega a ficha com o id, a conta e a versão dados, e só se ela for a vigente (a de maior versão daquele
#   agente). Se não atualizar exatamente uma linha, a transação é desfeita.
# - `instrucao_hash`: o SHA-256 da instrução que o agente usa hoje, para o painel avisar quando ela mudar. Com
#   --instrucao, o script calcula o hash do arquivo (o texto exato da instrução, em UTF-8); com --hash, usa o dado.
#   Sem nenhum dos dois (robô de outro sistema), o hash fica vazio.
# - --com-teste grava `configuracao.leitura.com_teste = true` no mesmo UPDATE (o leitor passa a pedir o campo `teste`).
#   A coluna é `json`, não `jsonb`: a ordem das chaves da ficha importa (desempata rankings), então o objeto é refeito
#   com json_each/json_object_agg na ordem de antes, sem passar por jsonb.
# - O .sql sai com permissão 0600 (só o dono lê): ele carrega a chave da conta.
# - A chave vai entre aspas de dólar com marcas aleatórias que o script confere não aparecerem no texto, então nada
#   no arquivo vira SQL.
# - Nunca imprime o conteúdo: só o tamanho da chave e onde gravou.
require 'digest'
require 'open3'
require 'optparse'
require 'securerandom'

module ChaveDeLeitura
  HEX = '0123456789abcdef'.freeze
  # configuracao com leitura.com_teste = true, nas posições de antes (o que é novo vai para o fim de cada objeto).
  # Ruby puro (sem o squish do Rails): os espaços viram um só com split/join.
  COM_TESTE = <<~CONSULTA.split.join(' ').freeze
    (SELECT json_object_agg(c.k, c.v ORDER BY c.n)
       FROM (SELECT json_object_agg(x.k, x.v ORDER BY x.n) AS leitura
               FROM (SELECT k, v, n FROM json_each(COALESCE(f.configuracao -> 'leitura', '{}'::json)) WITH ORDINALITY AS t(k, v, n)
                      WHERE k <> 'com_teste'
                     UNION ALL
                     SELECT 'com_teste', 'true'::json, 1000000) x) l
      CROSS JOIN LATERAL (
        SELECT k, CASE WHEN k = 'leitura' THEN l.leitura ELSE v END AS v, n
          FROM json_each(f.configuracao) WITH ORDINALITY AS e(k, v, n)
        UNION ALL
        SELECT 'leitura', l.leitura, 1000000 WHERE f.configuracao -> 'leitura' IS NULL) c)
  CONSULTA
  REPOSITORIO = File.realpath(File.expand_path('../..', __dir__))

  module_function

  def rodar(argumentos)
    opcoes = ler_opcoes(argumentos)
    chave = File.read(opcoes.fetch(:chave), encoding: 'UTF-8')
    abort('o arquivo da chave está vazio') if chave.strip.empty?

    gravar(opcoes.fetch(:saida), sql(chave, opcoes))
    puts "#{opcoes[:saida]}: chave com #{chave.size} caracteres; hash da instrução #{hash_da_instrucao(opcoes) ? 'incluído' : 'vazio'}"
  rescue KeyError, OptionParser::ParseError => e
    abort("#{e.class.name}: #{e.message}")
  rescue Errno::ENOENT
    abort('arquivo não encontrado')
  rescue SystemCallError => e
    abort("não deu para ler ou gravar os arquivos: #{e.class.name}")
  end

  # Só o dono lê o arquivo: 0600 ao criar e, se ele já existia com outra permissão, 0600 ANTES de escrever a chave.
  def gravar(caminho, conteudo)
    File.chmod(0o600, caminho) if File.exist?(caminho)
    File.open(caminho, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |arquivo| arquivo.write(conteudo) }
  end

  def ler_opcoes(argumentos)
    opcoes = {}
    OptionParser.new do |o|
      o.on('--com-teste') { opcoes[:com_teste] = true }
      %i[chave saida instrucao hash].each { |nome| o.on("--#{nome} VALOR", String) { |valor| opcoes[nome] = valor } }
      %i[conta ficha versao].each { |nome| o.on("--#{nome} N", Integer) { |valor| opcoes[nome] = valor } }
    end.parse!(argumentos.dup)
    conferir!(opcoes)
  end

  def conferir!(opcoes)
    %i[chave conta ficha versao saida].each { |nome| abort("falta --#{nome}") if opcoes[nome].nil? }
    abort('--saida precisa ficar fora do repositório') if no_repositorio?(opcoes[:saida])
    conferir_hash!(opcoes)
  end

  def conferir_hash!(opcoes)
    abort('use --instrucao ou --hash, não os dois') if opcoes[:instrucao] && opcoes[:hash]
    abort('--hash precisa ter 64 caracteres hexadecimais') if opcoes[:hash] && !hash_valido?(opcoes[:hash])
    opcoes
  end

  # A pasta real do destino (links simbólicos resolvidos) dentro deste repositório ou de QUALQUER working tree git
  # (outra cópia, outra worktree): o repositório é público e um `git add` publicaria a chave da conta.
  def no_repositorio?(caminho)
    pasta = File.realpath(File.dirname(destino_real(File.expand_path(caminho))))
    pasta == REPOSITORIO || pasta.start_with?("#{REPOSITORIO}/") || dentro_de_git?(pasta)
  rescue Errno::ENOENT
    abort('a pasta de --saida não existe')
  rescue SystemCallError => e
    abort("não deu para conferir a pasta de --saida: #{e.class.name}")
  end

  # O arquivo de destino que já existe como link simbólico grava onde o link aponta.
  def destino_real(caminho) = File.symlink?(caminho) ? File.realpath(caminho) : caminho

  def dentro_de_git?(pasta)
    saida, _erro, _status = Open3.capture3('git', '-C', pasta, 'rev-parse', '--is-inside-work-tree')
    saida.strip == 'true'
  rescue Errno::ENOENT
    abort('sem o git para conferir a pasta de --saida')
  end

  def hash_valido?(valor) = valor.size == 64 && valor.each_char.all? { |letra| HEX.include?(letra) }

  def hash_da_instrucao(opcoes)
    return opcoes[:hash] if opcoes[:hash]

    Digest::SHA256.hexdigest(File.read(opcoes[:instrucao], encoding: 'UTF-8')) if opcoes[:instrucao]
  end

  # Uma marca de aspas de dólar que não aparece no texto.
  def marca(prefixo, texto)
    nova = "#{prefixo}_#{SecureRandom.hex(8)}"
    nova = "#{prefixo}_#{SecureRandom.hex(8)}" while texto.include?(nova)
    nova
  end

  def sql(chave, opcoes)
    corpo = marca('leitura', chave)
    <<~SQL
      -- Grava a chave de leitura na ficha #{opcoes[:ficha]} (conta #{opcoes[:conta]}, versão #{opcoes[:versao]}). #2301
      BEGIN;
      DO $#{corpo}$
      DECLARE linhas integer;
      BEGIN
      #{update(chave, opcoes)}
        GET DIAGNOSTICS linhas = ROW_COUNT;
        IF linhas <> 1 THEN
          RAISE EXCEPTION 'esperava 1 ficha vigente, achou %', linhas;
        END IF;
      END
      $#{corpo}$;
      COMMIT;
    SQL
  end

  # Só a ficha com o id, a conta e a versão dados, e só se ela for a de maior versão daquele agente. Linhas juntas à
  # mão, sem heredoc: a chave entra exatamente como está no arquivo, com as quebras de linha dela.
  def update(chave, opcoes)
    texto = marca('chave', chave)
    instrucao = hash_da_instrucao(opcoes)
    ['UPDATE autonomia_desempenho_fichas f',
     "   SET chave_de_leitura = $#{texto}$#{chave}$#{texto}$,",
     "       instrucao_hash = #{instrucao ? "'#{instrucao}'" : 'NULL'}, updated_at = now()#{opcoes[:com_teste] ? ',' : ''}",
     *(opcoes[:com_teste] ? ["       configuracao = #{COM_TESTE}"] : []),
     " WHERE f.id = #{opcoes[:ficha]} AND f.account_id = #{opcoes[:conta]} AND f.versao = #{opcoes[:versao]}",
     '   AND f.versao = (SELECT max(v.versao) FROM autonomia_desempenho_fichas v',
     '                    WHERE v.account_id = f.account_id AND v.sujeito_type = f.sujeito_type AND v.sujeito_id = f.sujeito_id);'].join("\n")
  end
end

ChaveDeLeitura.rodar(ARGV) if $PROGRAM_NAME == __FILE__
