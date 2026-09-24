import { NextResponse } from "next/server";

export async function GET() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  const secreto = process.env.TRADING_SERVER_SECRET ?? "";

  return NextResponse.json({
    ok: true,
    supabaseUrl: {
      largo: url.length,
      empieza: url.slice(0, 20),
      termina: url.slice(-5),
      esUrlValida: (() => {
        try {
          new URL(url);
          return true;
        } catch {
          return false;
        }
      })(),
    },
    anonKey: {
      largo: anon.length,
      empieza: anon.slice(0, 10),
      termina: anon.slice(-10),
    },
    tradingSecret: {
      largo: secreto.length,
      empieza: secreto.slice(0, 6),
    },
  });
}
