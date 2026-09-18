const FORMATO_ERC20 = /^0x[a-fA-F0-9]{40}$/;

export function esWalletErc20Valida(direccion: string): boolean {
  return FORMATO_ERC20.test(direccion.trim());
}
