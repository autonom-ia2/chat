// #2414 G23 (#2737) — o "ausente até" da pessoa. O campo da tela é o datetime-local do navegador (hora local, sem
// fuso); a API guarda e devolve o instante em ISO. Vazio é "não está ausente".

const doisDigitos = numero => String(numero).padStart(2, '0');

// ISO da API → valor do campo ("2026-11-20T18:00"), na hora local de quem vê.
export const paraCampo = iso => {
  if (!iso) return '';
  const data = new Date(iso);
  if (Number.isNaN(data.getTime())) return '';
  return `${data.getFullYear()}-${doisDigitos(data.getMonth() + 1)}-${doisDigitos(
    data.getDate()
  )}T${doisDigitos(data.getHours())}:${doisDigitos(data.getMinutes())}`;
};

// Valor do campo → ISO para a API, ou null para limpar a ausência.
export const paraEnvio = valor => {
  if (!valor) return null;
  const data = new Date(valor);
  return Number.isNaN(data.getTime()) ? null : data.toISOString();
};
