# O formato de cada ação de escrita do Guia, gerado do código (#900).
#   bundle exec rails autonomia:guia:formatos         # gera o JSON e o relatório
#   bundle exec rails autonomia:guia:formatos:check   # falha se o versionado está fora de dia
namespace :autonomia do
  namespace :guia do
    desc 'Gera lib/operator_guide/formatos-das-acoes.json e o relatório de cobertura a partir do código'
    task formatos: :environment do
      Autonomia::Guide::Formatos.escrever!
      puts "[guia:formatos] #{Autonomia::Guide::Formatos.todos.size} ações escritas em #{Autonomia::Guide::Formatos::ARQUIVO}"
    end

    namespace :formatos do
      desc 'Falha se o formato versionado das ações do Guia não bate com o código'
      task check: :environment do
        fora = Autonomia::Guide::Formatos.fora_de_dia
        next puts('[guia:formatos] em dia') if fora.empty?

        puts "[guia:formatos] fora de dia: #{fora.map { |arquivo| arquivo.relative_path_from(Rails.root) }.join(', ')}"
        puts '  rode `bundle exec rails autonomia:guia:formatos` e envie o resultado'
        exit(1)
      end
    end
  end
end
