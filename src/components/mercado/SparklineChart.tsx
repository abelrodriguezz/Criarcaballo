"use client";

import { useId } from "react";
import { AreaChart, Area, ResponsiveContainer, YAxis } from "recharts";

/** Mini-gráfico de tendencia (sin ejes ni tooltip) para el fondo de una tarjeta de precio. */
export function SparklineChart({
  data,
  subiendo,
}: {
  data: number[];
  subiendo: boolean;
}) {
  const gradId = useId().replace(/:/g, "");

  if (data.length < 2) return null;

  const puntos = data.map((v, i) => ({ i, v }));
  const color = subiendo ? "var(--gain)" : "var(--loss)";

  return (
    <ResponsiveContainer width="100%" height={48}>
      <AreaChart data={puntos} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.35} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <YAxis domain={["dataMin", "dataMax"]} hide />
        <Area
          type="monotone"
          dataKey="v"
          stroke={color}
          strokeWidth={2}
          fill={`url(#${gradId})`}
          isAnimationActive={false}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
