# O que o agente sem função consegue fazer, por capacidade, gerado das policies (#2308).
#   bundle exec rails autonomia:funcoes:sem_funcao         # gera o JSON que a tela Funções da equipe lê
#   bundle exec rails autonomia:funcoes:sem_funcao:check   # falha se o versionado está fora de dia
namespace :autonomia do
  namespace :funcoes do
    desc 'Gera funcoesDaEquipe/semFuncaoCapacidades.json a partir das policies'
    task sem_funcao: :environment do
      CustomRoles::SemFuncaoCapacidades.escrever!
      puts "[funcoes:sem_funcao] escrito em #{CustomRoles::SemFuncaoCapacidades::ARQUIVO.relative_path_from(Rails.root)}"
    end

    namespace :sem_funcao do
      desc 'Falha se o JSON versionado do agente sem função não bate com as policies'
      task check: :environment do
        next puts('[funcoes:sem_funcao] em dia') if CustomRoles::SemFuncaoCapacidades.em_dia?

        puts "[funcoes:sem_funcao] fora de dia: #{CustomRoles::SemFuncaoCapacidades::ARQUIVO.relative_path_from(Rails.root)}"
        puts '  rode `bundle exec rails autonomia:funcoes:sem_funcao` e envie o resultado'
        exit(1)
      end
    end
  end
end
