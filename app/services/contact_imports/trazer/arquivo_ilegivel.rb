# "Trazer minha lista" (#2896): um arquivo da conferência (as linhas com problema ou os consertos) tem um trecho que
# não dá para ler. A mensagem leva só o nome do arquivo e o erro não guarda a causa: o erro do leitor de JSON cita o
# trecho que não leu, e esse trecho é valor de planilha.
class ContactImports::Trazer::ArquivoIlegivel < StandardError
end
