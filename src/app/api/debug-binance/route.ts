import { NextResponse } from "next/server";

export async function GET() {
  const simbolo = "BTCUSDT";
  try {
    const res = await fetch(
      `https://api.binance.com/api/v3/ticker/24hr?symbol=${simbolo}`,
      { cache: "no-store", signal: AbortSignal.timeout(10_000) }
    );
    const texto = await res.text();
    return NextResponse.json({
      ok: true,
      status: res.status,
      statusText: res.statusText,
      headers: Object.fromEntries(res.headers.entries()),
      cuerpo: texto.slice(0, 1000),
    });
  } catch (e) {
    return NextResponse.json({
      ok: false,
      error: e instanceof Error ? e.message : String(e),
      nombre: e instanceof Error ? e.name : null,
      causa: e instanceof Error && e.cause ? String(e.cause) : null,
    });
  }
}
