// O que a tela diz depois de encaminhar (#1702): o servidor devolve um resultado
// por destino ({ conversation_id, ok, erro }); a falha aparece com o nome da
// conversa escolhida ("Ana: Fora da janela de 24 h: use um modelo.").
export const resumoDoEnvio = (resultados, escolhidas) => {
  const lista = Array.isArray(resultados) ? resultados : [];
  const nomeDe = id =>
    escolhidas.find(item => item.id === id)?.nome || `#${id}`;
  return {
    algumEnviado: lista.some(item => item?.ok),
    falhas: lista
      .filter(item => item && !item.ok)
      .map(item => ({
        id: item.conversation_id,
        nome: nomeDe(item.conversation_id),
        erro: item.erro,
      })),
  };
};
