"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { esWalletErc20Valida } from "@/lib/wallet";
import { IconoWallet } from "@/components/ui/Iconos";
import type { Diccionario } from "@/lib/i18n";

export function WalletForm({
  usuarioId,
  walletActual,
  t,
}: {
  usuarioId: string;
  walletActual: string | null;
  t: Diccionario;
}) {
  const router = useRouter();
  const [editando, setEditando] = useState(false);
  const [valor, setValor] = useState(walletActual ?? "");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const limpio = valor.trim();
    if (limpio && !esWalletErc20Valida(limpio)) {
      setError(t.wallet.formatoInvalido);
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("usuarios")
      .update({ wallet_usdt_erc20: limpio || null })
      .eq("id", usuarioId);
    setGuardando(false);

    if (error) {
      setError(t.wallet.errorGuardar);
      return;
    }

    setEditando(false);
    router.refresh();
  }

  if (!editando) {
    return (
      <button
        onClick={() => setEditando(true)}
        className="w-full text-left border border-[var(--border)] rounded-2xl p-4 mb-3 flex items-center gap-3.5 hover:bg-surface-hover hover:border-brand-primary/40 transition-colors"
      >
        <div className="shrink-0 w-10 h-10 rounded-[4px] bg-brand-primary/10 text-brand-primary flex items-center justify-center">
          <IconoWallet />
        </div>
        <div className="min-w-0 flex-1">
          <div className="font-medium text-sm">{t.wallet.titulo}</div>
          {walletActual ? (
            <div className="text-[13px] text-foreground-muted font-mono truncate">
              {walletActual}
            </div>
          ) : (
            <div className="text-[13px] text-foreground-muted">
              {t.wallet.sinWallet}
            </div>
          )}
        </div>
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
          className="w-4 h-4 shrink-0 text-foreground-muted"
        >
          <polyline points="9 18 15 12 9 6" />
        </svg>
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-4"
    >
      <div className="flex justify-between items-center mb-2.5">
        <div className="font-medium text-sm">{t.wallet.titulo}</div>
        <button
          type="button"
          onClick={() => {
            setEditando(false);
            setValor(walletActual ?? "");
            setError(null);
          }}
          className="text-xs text-foreground-muted"
        >
          {t.wallet.cancelar}
        </button>
      </div>

      <input
        value={valor}
        onChange={(e) => setValor(e.target.value)}
        placeholder="0x..."
        className="w-full px-3.5 py-2.5 mb-1.5 rounded-lg border border-[var(--border)] bg-background text-sm font-mono"
      />
      <p className="text-[12px] text-foreground-muted mb-3">
        {t.wallet.descripcion}
      </p>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? t.wallet.guardando : t.wallet.guardar}
      </button>
    </form>
  );
}
