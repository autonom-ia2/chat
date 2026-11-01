# A posição de uma flag na coluna dela (#2454, revisão da Agentes IA). A posição é o índice da flag entre as da mesma
# coluna no config/features.yml, e o bit gravado na conta é 1 << (posição - 1). Mudar a posição de uma flag já gravada
# liga ou desliga outra coisa nas contas: este check prova a posição combinada antes do merge.
#   bundle exec rails "autonomia:flags:conferir_posicao[meta_ads_comentarios_ia_conversa,feature_flags_ext_2,24]"
# Falha (saída 1) quando a flag não está na posição esperada. Ainda fora da suíte: no merge final com a main, vira spec.
namespace :autonomia do
  namespace :flags do
    desc 'Falha se a flag não está na posição esperada da coluna (índice no config/features.yml)'
    task :conferir_posicao, %i[nome coluna posicao] => :environment do |_task, args|
      nome, coluna = args.values_at(:nome, :coluna).map(&:to_s)
      esperada = Integer(args[:posicao])
      da_coluna = Featurable::FEATURE_LIST.select { |item| (item['column'].presence || Featurable::DEFAULT_FEATURE_FLAG_COLUMN) == coluna }
      indice = da_coluna.index { |item| item['name'] == nome }
      abort("[flags] #{nome} não está em #{coluna}") if indice.nil?

      posicao = indice + 1
      # A mesma posição que a conta usa (Featurable::FEATURES_BY_COLUMN), para o check não divergir do bit gravado.
      mapeada = Featurable::FEATURES_BY_COLUMN.fetch(coluna).key(:"feature_#{nome}")
      abort("[flags] #{nome}: features.yml diz #{posicao}, Featurable diz #{mapeada}") unless mapeada == posicao

      puts "[flags] #{nome} em #{coluna}: posição #{posicao} de #{da_coluna.size}, bit 1 << #{posicao - 1} = #{1 << (posicao - 1)}"
      next puts('[flags] na posição esperada') if posicao == esperada

      puts "[flags] FORA da posição: esperada #{esperada}, bit 1 << #{esperada - 1} = #{1 << (esperada - 1)}"
      exit(1)
    end
  end
end
