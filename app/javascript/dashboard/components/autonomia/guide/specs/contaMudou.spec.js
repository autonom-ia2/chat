import {
  avisarContaMudou,
  execucaoMudouConta,
  versaoDaConta,
} from '../contaMudou';

describe('contaMudou', () => {
  it('sobe a versão a cada mudança avisada', () => {
    const antes = versaoDaConta.value;
    avisarContaMudou();
    avisarContaMudou();
    expect(versaoDaConta.value).toBe(antes + 2);
  });

  it('considera que o turno mudou a conta quando ao menos um passo deu certo', () => {
    expect(execucaoMudouConta({ passos: [{ ok: true }, { ok: false }] })).toBe(
      true
    );
  });

  it('não remonta a tela quando nenhum passo deu certo ou não houve execução', () => {
    expect(execucaoMudouConta({ passos: [{ ok: false }] })).toBe(false);
    expect(execucaoMudouConta({ passos: [] })).toBe(false);
    expect(execucaoMudouConta(null)).toBe(false);
  });
});
