# Bloque 0 — Auditoría de Calidad de Datos

> Prompt de IA usado: *"Carga los 6 CSV con pandas y para cada dimensión de calidad (completitud, consistencia, unicidad, validez, integridad referencial, frescura, integridad temporal, integridad del A/B test) calcula el hallazgo con evidencia numérica: conteos, ejemplos y % afectado."* Yo definí las reglas de negocio de cada chequeo y las decisiones; la IA generó el código de cálculo, que validé revisando manualmente los ejemplos devueltos.

---

## 1. Completitud

**Hallazgo:** 104,632 de 174,880 transacciones (**59.83%**) no tienen `customer_id`.

Es perfectamente consistente con `loyalty_card`: el cruce es 1:1 exacto —
`customer_id` nulo ⟺ `loyalty_card = False` (104,632 casos) y `customer_id` presente ⟺ `loyalty_card = True` (70,248 casos), sin ninguna excepción en ninguna dirección.

**Decisión:** No es un error de datos, es un patrón esperado (cliente sin tarjeta de lealtad = compra anónima). Para Cohortes (Query 3) y cualquier análisis a nivel cliente, se filtra explícitamente `loyalty_card = True`. No se imputa `customer_id`.

---

## 2. Consistencia (`total_amount` vs Σ unit_price × quantity)

**Hallazgo:** 1,745 transacciones (**1.00%**) tienen `total_amount` distinto a la suma de sus líneas (tolerancia ±0.01). La diferencia mediana es 0 pero el máximo llega a **$202.68**. En el 100% de los casos discrepantes, `total_amount` es **menor** que la suma de líneas (nunca mayor) — es decir, se aplicó un descuento adicional a nivel de transacción no reflejado en `unit_price`. La tasa de items en promo en estas transacciones (45.3%) es similar a la tasa general (44.0%), así que no explica por sí sola el patrón — probablemente cupones o descuentos de canasta completa fuera del dataset de promos.

**Decisión:** Para KPIs de GMV se usará `total_amount` como fuente de verdad (es lo que el POS reportó como cobrado), no la suma de líneas. Se documenta como *alerta*: el 1% de transacciones tiene un componente de descuento que el dataset actual no explica — recomendación para el equipo de datos es capturar el descuento a nivel de transacción como campo explícito.

---

## 3. Unicidad

**Hallazgo:** 0 `transaction_id` duplicados, 0 `transaction_item_id` duplicados.

**Decisión:** Sin acción — ambas claves primarias son únicas.

---

## 4. Validez

- **`total_amount` ≤ 0:** 3 transacciones con `total_amount = 0.00`, todas con `status = COMPLETED`.
- **`unit_price = 0` con `was_on_promo = False`:** 231 líneas, **las 231 pertenecen al mismo SKU** (`ITEM_089`, categoría Bebidas) — no es ruido disperso, es un producto con precio 0 sistemático.
- `quantity ≤ 0`: 0 casos.

**Decisión:**
- Las 3 transacciones de $0 se excluyen de KPIs de GMV/ticket promedio pero se dejan en el conteo de tráfico/transacciones (podrían ser canjes 100% con puntos).
- `ITEM_089` (precio unitario, no total_amount) se marca para excluir de análisis de precio/margen hasta confirmar con el equipo de producto si es un ítem promocional mal etiquetado (`was_on_promo` debería ser `True`) o un error de carga de precio — el hecho de que sea un único SKU y no ruido disperso apunta más a un error sistemático de carga que a 231 casos aislados.

---

## 5. Integridad referencial

- `transactions.store_id` → `stores`: **0 huérfanos**.
- `transaction_items.item_id` → `products`: **0 huérfanos**.
- `transaction_items.transaction_id` → `transactions`: **0 huérfanos**.
- `store_promotions.store_id` → `stores`: **0 huérfanos**.
- `products.vendor_id` → `vendors`: **5 huérfanos** (`ITEM_045`, `ITEM_078`, `ITEM_112`, `ITEM_156`, `ITEM_189`) — referencian un `vendor_id` que no existe en `vendors.csv`.

**Decisión:** Se recomienda primero validar con el equipo de datos si es un error de extracción (ETL que truncó o desincronizó `vendors.csv`) o un vendor real dado de baja del maestro. Mientras se confirma, estos 5 productos se mantienen en el análisis de ventas (GMV, unidades), pero se excluyen de cualquier análisis por proveedor (GMROI Query 4). En el dashboard (Power BI) se les asigna la categoría `"Vendedor Desconocido"` en vez de excluirlos, para no perder GMV real ni ocultar el problema de calidad al usuario del reporte.

---

## 6. Frescura

**Hallazgo:** 39 de 40 tiendas tienen cobertura diaria completa (2024-01-01 a 2025-06-30, o desde su apertura). Una tienda, **TIENDA_012** (Escuintla, GT), tiene un gap de **7 días consecutivos sin ninguna transacción: 2024‑09‑10 a 2024‑09‑16**.

Este gap coincide con el arranque del experimento de exhibición (`Exhibicion_Q3_2024`, inicio 2024‑09‑01), lo que sugiere una posible interrupción operativa relacionada con el remodelado de punto de venta, no un fallo aleatorio de reporte.

**Decisión:** Se marca TIENDA_012 con alerta operativa. Para el A/B test (Bloque 3) se evalúa si excluirla o tratarla aparte, ya que un gap de datos dentro de la ventana del experimento puede sesgar su resultado si está en el grupo TREATMENT o CONTROL.

---

## 7. Integridad temporal

**Hallazgo:** 50 transacciones en **TIENDA_037** ocurren *antes* de su `opening_date` (2024‑06‑01) — las transacciones más tempranas son del 2024‑05‑15, es decir, hasta 17 días antes de la apertura oficial.

**Decisión:** Se excluyen estas 50 transacciones de cualquier análisis que dependa de `opening_date` (Comp Sales, antigüedad de tienda) y se marcan como alerta de calidad. Hipótesis a validar con el negocio: (a) apertura "soft"/preventa a empleados o clientes VIP antes de la inauguración oficial (práctica común en retail), en cuyo caso el dato es correcto y lo que está mal es `opening_date`; o (b) error de carga de la fecha de apertura en el maestro de tiendas. Se recomienda confirmar con la tienda antes de decidir cuál de las dos correcciones aplicar.

---

## 8. Integridad del A/B Test

**Hallazgo:** **2 tiendas están asignadas simultáneamente a `CONTROL` y `TREATMENT`** en `store_promotions.csv`: **TIENDA_008** y **TIENDA_037** (cada una tiene 2 filas, una por variante). El resto de las 40 tiendas tiene una asignación única y consistente (22 TREATMENT, 20 CONTROL antes de corregir).

Nota adicional: **TIENDA_037** es la misma tienda con transacciones previas a su apertura (hallazgo #7) — es una tienda con dos problemas de calidad independientes, lo que la hace especialmente poco confiable para el experimento.

**Decisión:** Estas 2 tiendas se **excluyen del análisis del A/B test** (Bloque 3, Parte B) por contaminación de asignación — no es posible saber a qué grupo pertenecen realmente. Universo final del experimento: 38 tiendas (21 TREATMENT, 19 CONTROL). Se documenta como hallazgo crítico de auditoría porque invalidaría el resultado del test si no se detecta.

---

## Resumen de decisiones para bloques siguientes

| # | Hallazgo | Filas afectadas | Decisión |
|---|---|---|---|
| 1 | `customer_id` nulo | 104,632 (59.8%) | Esperado; filtrar `loyalty_card=True` en análisis de cliente |
| 2 | `total_amount` ≠ Σ líneas | 1,745 (1.0%) | Usar `total_amount` como GMV oficial; marcar como alerta de descuentos no capturados |
| 3 | Duplicados | 0 | Sin acción |
| 4a | `total_amount = 0` | 3 | Excluir de GMV/ticket, mantener en conteo de tráfico |
| 4b | `unit_price=0`, sin promo | 231 (1 SKU: ITEM_089) | Excluir de análisis de precio/margen; alertar a producto |
| 5 | `vendor_id` huérfano | 5 SKUs | Excluir de análisis por proveedor, mantener en GMV total |
| 6 | Gap de 7 días TIENDA_012 | 1 tienda | Alerta operativa; revisar impacto en A/B test |
| 7 | Ventas antes de apertura TIENDA_037 | 50 | Excluir de Comp Sales / antigüedad |
| 8 | Doble asignación A/B (TIENDA_008, TIENDA_037) | 2 tiendas | **Excluir del A/B test**; universo final 38 tiendas |
