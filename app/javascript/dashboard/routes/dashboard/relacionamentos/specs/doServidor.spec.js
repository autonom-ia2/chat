import { doServidor } from '../fonte/doServidor';
import { SEM_ACESSO, ehSemAcesso } from '../lista/falhas';
import { SEM_ACESSO as SEM_ACESSO_DA_FICHA } from '../ficha/falhas';

// #2896 — a ida ao servidor que a lista e "Trazer minha lista" dividem: devolve
// o corpo da resposta e dá nome à recusa por falta de acesso (401 ou 403).
const erroHttp = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: {} },
  });

describe('doServidor', () => {
  it('devolve o corpo da resposta', async () => {
    expect(await doServidor(Promise.resolve({ data: { id: 812 } }))).toEqual({
      id: 812,
    });
  });

  it.each([401, 403])(
    '%s vira a falha SEM_ACESSO, com a causa guardada',
    async status => {
      const recusa = erroHttp(status);
      const falha = await doServidor(Promise.reject(recusa)).catch(
        erro => erro
      );
      expect(falha.name).toBe(SEM_ACESSO);
      expect(ehSemAcesso(falha)).toBe(true);
      expect(falha.cause).toBe(recusa);
    }
  );

  it.each([404, 422, 500])('%s sobe como veio', async status => {
    const caiu = erroHttp(status);
    await expect(doServidor(Promise.reject(caiu))).rejects.toBe(caiu);
  });

  it('erro sem resposta (rede) sobe como veio', async () => {
    const semRede = new Error('Network Error');
    await expect(doServidor(Promise.reject(semRede))).rejects.toBe(semRede);
  });
});

describe('uma constante só', () => {
  it('a ficha usa a mesma SEM_ACESSO da lista', () => {
    expect(SEM_ACESSO_DA_FICHA).toBe(SEM_ACESSO);
  });
});
