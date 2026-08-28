# Bloque 4 — Framework de KPIs: Programa de Productividad de Tiendas

> **Prompt de IA usado:** *"Ayúdame a diseñar un framework de KPIs de retail cubriendo productividad de tienda, experiencia del cliente y desempeño de proveedor, con al menos un leading indicator y un KPI compuesto, usando como base las métricas ya calculadas en los Bloques 1 y 3 de este proyecto."* Yo elegí qué KPIs eran relevantes para este negocio específico (en vez de una lista genérica de retail), definí los targets con base en lo observado en los datos reales (Bloques 1 y 3), y decidí el North Star Metric y su justificación.

---

## Tabla de KPIs

> **Nota sobre "Valor actual":** 7 de los 9 KPIs ya tenían su cálculo hecho en bloques anteriores de este mismo proyecto (Bloque 1 SQL o Bloque 3 notebook) — la columna "Dónde se calculó" te dice exactamente en qué query o celda de código. Los KPIs 8 y 9 no existían antes; los calculé de cero para este bloque, reusando la misma lógica de detección de quiebres del Bloque 1 (Query 5).

| # | KPI | Definición exacta | Fórmula | Frecuencia | Fuente de datos | Target sugerido | ¿Cómo detectas si el dato está mal? | **Valor actual** | **Dónde se calculó** |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **GMV Neto por m²** | Ingresos netos (ventas completadas menos devoluciones) generados por cada metro cuadrado de área de venta de una tienda, en el periodo. | `SUM(total_amount COMPLETED − total_amount RETURNED) / size_sqm` | Semanal (vista mensual acumulada) | `fact_venta_linea` + `dim_tienda.size_sqm` | Percentil 50 de su propio formato, o +5% vs. mismo periodo del año anterior | `size_sqm` nulo o = 0; valor negativo; variación >3 desviaciones estándar vs. el histórico de la misma tienda | **$104.27/m²** (promedio de las 40 tiendas, último trimestre) | Bloque 1, Query 2 (por tienda) — promedio agregado aquí en Bloque 4 |
| 2 | **Comp Sales Growth %** | Crecimiento % de GMV año contra año, solo para tiendas con ≥13 meses operando en ambos periodos (evita distorsión por aperturas nuevas). | `(GMV_actual − GMV_año_anterior) / GMV_año_anterior × 100` | Mensual | `fact_venta_linea` + `dim_tienda.opening_date` + `dim_fecha` | +3% a +5% anual | Tiendas incluidas que no cumplen la regla de 13 meses; periodo actual y periodo comparado con distinto número de días | **+6.46%** (agregado, 36 tiendas elegibles) | Bloque 1, Query 1 (detalle por tienda/país/formato) — agregado aquí en Bloque 4 |
| 3 | **Transacciones por m²** *(leading indicator)* | Número de transacciones completadas por metro cuadrado — proxy de tráfico/conversión que se mueve **antes** de que el cambio se refleje en el GMV total. | `COUNT(transacciones COMPLETED) / size_sqm` | Semanal | `fact_venta_linea` + `dim_tienda` | +2% trimestre contra trimestre | Conteo en cero para una tienda operativa (posible caída de reporte, ver Bloque 0 #6); `transaction_id` duplicados | **0.38 tx/m²** (promedio, último trimestre) | Bloque 1, Query 2 (columna `transacciones_por_m2`) — promedio agregado aquí en Bloque 4 |
| 4 | **Tasa de quiebre de stock** *(leading indicator)* | % de combinaciones tienda-SKU con un gap de venta anómalo (ver Bloque 1 Query 5) sobre el total de combinaciones activas — anticipa pérdida de ventas y mala experiencia antes de que se note en el GMV. | `(# gaps anómalos detectados) / (# combinaciones tienda-item activas) × 100` | Semanal | `fact_venta_linea` (ventana de detección de gaps) | <5% de SKUs activos en quiebre en un momento dado | Gaps que coinciden con un cierre operativo total de la tienda (no es quiebre de un SKU, es la tienda cerrada — ver caso TIENDA_012 en Bloque 0); SKUs de rotación muy baja generando falsos positivos | ⚠️ **100%** (8,000 de 8,000 combinaciones tienda-item) | **Calculado de cero en Bloque 4**, reusando la lógica de Bloque 1 Query 5 / Bloque 3 P4 |
| 5 | **Retención de lealtad a 30-60 días (mes 1 de cohorte)** | % de clientes con tarjeta de lealtad cuya primera compra fue en un mes dado, y que vuelven a comprar dentro del mes 1 de esa cohorte. | Ver Query 3, Bloque 1 (`retencion_m1_pct`) | Mensual (por cohorte) | `fact_venta_linea` + `dim_cliente` | >70% | Cohortes con tamaño <10 clientes (alta varianza, no usar para decisiones — ver Bloque 3 P3); incluir por error a `customer_key = 'UNKNOWN'` | **65.3%** (ponderado, todas las cohortes) | Bloque 1, Query 3 (detalle por cohorte) — promedio ponderado aquí en Bloque 4 |
| 6 | **Tasa de devolución** | % de transacciones completadas que terminan en una devolución. | `COUNT(status='RETURNED') / COUNT(total transacciones) × 100` | Semanal | `fact_venta_linea` | <3% | Comparar diferencias entre tiendas con una prueba estadística (chi-cuadrado) antes de actuar — en este dataset la variación resultó ser ruido, no señal real (ver Bloque 3 P5) | **2.03%** (global) | Bloque 3, Pregunta 5 (hallazgo libre) |
| 7 | **GMROI por proveedor** | Margen bruto generado por cada $1 invertido en costo de inventario de un proveedor, en el periodo. | `(GMV − Costo total) / Costo total` | Mensual | `fact_venta_linea` + `dim_producto` + `dim_proveedor` | >1.0 (ideal >1.5 para proveedores Tier A) | Excluir `vendor_key = 'UNKNOWN'` (SKUs con proveedor huérfano, ver Bloque 0 #5); costo unitario en cero o negativo | **0.61** global ponderado (89.2% de combinaciones vendor-categoría por debajo de 1.0) | Bloque 1, Query 4 (detalle por vendor/categoría) — agregado aquí en Bloque 4 |
| 8 | **% SKUs de proveedor en quiebre** | Proporción de SKUs de un proveedor con al menos un quiebre anómalo en el periodo, sobre el total de SKUs activos de ese proveedor — mide confiabilidad de abastecimiento. | `(SKUs del proveedor con quiebre) / (SKUs activos del proveedor) × 100` | Mensual | `fact_venta_linea` + `dim_producto` + `dim_proveedor` | <10% | Mismos cuidados que el KPI 4 (excluir cierres de tienda completos, no solo del SKU) | ⚠️ **100%** (los 30 proveedores tienen el 100% de sus SKUs con al menos 1 quiebre) | **Calculado de cero en Bloque 4** |
| 9 | **Índice de Salud de Tienda (IST)** *(KPI compuesto)* | Score 0-100 que combina el desempeño relativo de una tienda en 3 KPIs normalizados dentro de su propio formato, para dar una vista única y priorizar intervención. | `IST = 0.4×percentil(KPI 1) + 0.3×percentil(KPI 2) + 0.3×percentil(KPI 5)`, cada uno normalizado 0-100 dentro del mismo formato de tienda | Mensual | Derivado de los KPIs 1, 2 y 5 | >60 | Si falta alguno de los 3 componentes o hay un outlier extremo en uno de ellos, el índice se distorsiona — validar que los 3 insumos existan y sean razonables antes de calcular | **54.4 promedio de cadena** (13 de 36 tiendas con dato completo superan 60) | **Calculado de cero en Bloque 4**, combinando resultados de Query 1, 2 y 3 del Bloque 1 |

---

## Cobertura por dimensión

- **Productividad de tienda:** KPI 1, 2, 3
- **Experiencia del cliente:** KPI 4, 5, 6
- **Desempeño de proveedor:** KPI 7, 8
- **Leading indicators:** KPI 3 (tráfico) y KPI 4 (quiebres) — ambos se mueven antes de que el efecto llegue al GMV total.
- **KPI compuesto:** KPI 9 (Índice de Salud de Tienda), construido a partir de los KPIs 1, 2 y 5.

---

## North Star Metric: GMV Neto por m² (KPI 1)

**¿Por qué este y no otro?**

El programa que se está lanzando es específicamente de **productividad de tienda** — no un programa general de crecimiento ni de satisfacción del cliente aislado. GMV/m² es la métrica estándar de la industria retail para esto porque:

1. **Ya viene normalizada por tamaño**, lo que la hace comparable directamente entre un EXPRESS de 400m² y un HIPERMERCADO de 4,000m² — algo que el GMV bruto no permite (una tienda grande siempre "gana" en GMV bruto sin decir nada de qué tan bien está usando su espacio).
2. **Es un resultado, no una causa aislada** — resume en un solo número el efecto combinado de tráfico (transacciones), conversión y ticket promedio, sin tener que mirar 3 métricas por separado para saber si "a la tienda le está yendo bien".
3. **Es accionable a nivel de tienda individual**, que es exactamente el nivel de decisión que el equipo directivo quiere operar (rankear tiendas, priorizar cuáles intervenir primero — tal como se pide en el Bloque 1 Query 2 y en el dashboard del Bloque 5).
4. Los demás KPIs de este framework (tráfico, quiebres, retención, GMROI) son bloques de construcción — **cada uno explica una parte del "por qué" del GMV/m²**, pero el North Star necesita ser el número único que el VP de Operaciones mira primero antes de bajar al detalle.

---

## Nota sobre los valores actuales de KPI 4 y KPI 8

Ambos dieron **100%** al calcularlos — es decir, con la definición literal del enunciado, absolutamente todos los SKUs y todos los proveedores tienen al menos un "quiebre" durante el periodo del dataset. Esto **no es un target razonable ni una alerta operativa real**: es el mismo hallazgo que documentamos en el Bloque 3 (Pregunta 4) — con la cadencia de venta tan dispersa de estos datos sintéticos (cada ítem vende en promedio 1 de cada 9 días por tienda), un gap de 3+ días es la norma estadística, no la excepción, así que termina afectando a todo el catálogo por igual.

**Esto no invalida el diseño del KPI** — la fórmula y el target (<5% / <10%) son correctos y quedarían bien calibrados con datos reales de un negocio real, donde los quiebres sí deberían ser un evento raro y concentrado en SKUs/proveedores específicos. Lo que muestra es que **este dataset en particular no es representativo para calibrar el target de este KPI en concreto** — es una limitación a comunicar junto con el número, no algo que se deba ocultar o "corregir" artificialmente en el reporte.
